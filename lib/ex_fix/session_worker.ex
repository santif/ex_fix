defmodule ExFix.SessionWorker do
  @moduledoc """
  FIX session worker
  """

  require Logger
  use GenServer
  alias ExFix.Session
  alias ExFix.SessionConfig
  alias ExFix.OutMessage
  alias ExFix.Serializer
  alias ExFix.SessionTimer

  @compile {:inline, handle_data: 2}

  @rx_heartbeat_tolerance Application.get_env(:ex_fix, :rx_heartbeat_tolerance, 1.2)
  @logout_timeout Application.get_env(:ex_fix, :logout_timeout, 2_000)

  defmodule State do
    @moduledoc false
    defstruct name: nil,
      mode: :initiator,
      transport: nil,
      client: nil,
      session_registry: nil,
      session: nil,
      log_outgoing_msg: true,
      rx_timer: nil,
      tx_timer: nil
  end

  def start_link(config, registry) do
    # name = {:via, ExFix.Registry, {:ex_fix_session, config.name}}
    name = :"ex_fix_session_#{config.name}"
    GenServer.start_link(__MODULE__, [config, registry], name: name)
  end

  def send_message!(fix_session, out_message) when is_binary(fix_session) do
    # name = {:via, ExFix.Registry, {:ex_fix_session, fix_session}}
    name = :"ex_fix_session_#{fix_session}"
    GenServer.call(name, {:send_message, out_message})
  end
  def send_message!(fix_session, out_message) when is_pid(fix_session) do
    GenServer.call(fix_session, {:send_message, out_message})
  end

  def stop(fix_session) do
    # name = {:via, ExFix.Registry, {:ex_fix_session, fix_session}}
    name = :"ex_fix_session_#{fix_session}"
    GenServer.call(name, :stop)
  end

  ##
  ## GenServer callbacks
  ##

  def init([config, session_registry]) do
    action = session_registry.session_on_init(config.name)
    send(self(), {:init, action, config})
    {:ok, %State{name: config.name, mode: config.mode,
      log_outgoing_msg: config.log_outgoing_msg, session_registry: session_registry}}
  end

  def handle_info({:timeout, timer_name}, %State{session: session} = state) do
    {:ok, msgs_to_send, session} = Session.handle_timeout(session, timer_name)
    do_send_messages(msgs_to_send, state)
    {:noreply, %State{state | session: session}}
  end

  def handle_info({:ssl, _socket, data}, %State{} = state) do
    handle_data(data, state)
  end

  def handle_info({:tcp, _socket, data}, %State{} = state) do
    handle_data(data, state)
  end

  def handle_info({:init, action, config}, state) do
    case action do
      :ok ->
        connect_and_send_logon(config, state)
      :wait_to_reconnect ->
        Logger.info fn  -> "Waiting #{config.reconnect_interval} seconds to reconnect..." end
        Process.sleep(config.reconnect_interval * 1_000)
        connect_and_send_logon(config, state)
      {:error, _reason} ->
        {:stop, :normal, state}
    end
  end

  def handle_info({:ssl_closed, _socket}, state) do
    {:stop, :closed, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :closed, state}
  end

  def handle_call({:send_message, %OutMessage{} = msg}, _from, %State{session: session} = state) do
    {:ok, msgs_to_send, session} = Session.send_message(session, msg)
    do_send_messages(msgs_to_send, state)
    {:reply, :ok, %State{state | session: session}}
  end

  def handle_call(:stop, _from, %State{transport: transport, client: client,
      session: session} = state) do
    state = case Session.session_stop(session) do
      {:logout_and_wait, msgs_to_send, session} ->
        do_send_messages(msgs_to_send, state)
        Process.sleep(@logout_timeout)
        %State{state | session: session}
      {:stop, session} ->
        %State{state | session: session}
    end
    transport.close(client)
    {:stop, :normal, :ok, state}
  end

  def terminate(:econnrefused, %State{name: fix_session_name,
      session_registry: session_registry} = _state) do
    session_registry.session_update_status(fix_session_name, :reconnecting)
    :ok
  end
  def terminate(:closed, %State{name: fix_session_name,
      session_registry: session_registry} = _state) do
    session_registry.session_update_status(fix_session_name, :reconnecting)
    :ok
  end
  def terminate(:normal, %State{name: fix_session_name,
      session_registry: session_registry} = _state) do
    session_registry.session_update_status(fix_session_name, :disconnected)
    :ok
  end
  def terminate(_reason, _state) do
    :ok
  end

  ##
  ## Private functions
  ##

  defp handle_data(data, %State{session: session, rx_timer: rx_timer} = state) do
    case Session.handle_incoming_data(session, data) do
      {:ok, [], session2} ->
        rx_timer = case rx_timer do
          nil ->
            setup_rx_timer(state.session_registry, session)
          value ->
            value
        end
        send(rx_timer, :msg)
        {:noreply, %State{state | session: session2, rx_timer: rx_timer}}
      {:ok, msgs_to_send, session2} ->
        send(rx_timer, :msg)
        do_send_messages(msgs_to_send, state)
        {:noreply, %State{state | session: session2}}
      {:continue, msgs_to_send, session2} ->
        send(rx_timer, :msg)
        do_send_messages(msgs_to_send, state)
        handle_data("", %State{state | session: session2})
      {:resend, msgs_to_send, session2} ->
        send(rx_timer, :msg)
        do_send_messages(msgs_to_send, state, true)
        {:noreply, %State{state | session: session2}}
      {:logout, msgs_to_send, session2} ->
        send(rx_timer, :msg)
        do_send_messages(msgs_to_send, state)
        Process.sleep(@logout_timeout)
        %State{transport: transport, client: client} = state
        transport.close(client)
        {:stop, :normal, %State{state | session: session2}}
    end
  end

  defp do_send_messages(msgs_to_send, %State{name: fix_session_name,
      transport: transport, client: client, log_outgoing_msg: log_outgoing_msg,
      tx_timer: tx_timer}, resend \\ false) do
    for msg <- msgs_to_send do
      data = Serializer.serialize(msg, DateTime.utc_now(), resend)
      if log_outgoing_msg do
        Logger.info fn -> "[fix.outgoing] [#{fix_session_name}] " <>
          :unicode.characters_to_binary(data, :latin1, :utf8) end
      end
      transport.send(client, data)
      send(tx_timer, :msg)
    end
    :ok
  end

  defp connect_and_send_logon(config, %State{name: fix_session_name} = state) do
    Logger.debug fn -> "Starting FIX session: [#{fix_session_name}]" end
    {:ok, session} = Session.init(config)
    {:ok, msgs_to_send, session} = Session.session_start(session)
    %Session{config: config} = session
    host = config.hostname
    port = config.port
    Logger.debug fn -> "[#{fix_session_name}] Trying to connect to #{host}:#{port}..." end
    str_host = String.to_charlist(host)
    options = [mode: :binary] ++ config.transport_options
    case config.transport_mod.connect(str_host, port, options) do
      {:ok, client} ->
        tx_timer = SessionTimer.setup_timer(:tx, session.config.heart_bt_int * 1_000)
        state = %State{state | transport: config.transport_mod, client: client,
          session: session, tx_timer: tx_timer}
        do_send_messages(msgs_to_send, state)
        {:noreply, state}
      {:error, reason} ->
        Logger.error "Cannot open socket: #{inspect reason}"
        {:stop, reason, state}
    end
  end

  defp setup_rx_timer(session_registry, %Session{config: config}) do
    %SessionConfig{name: name, heart_bt_int: heart_bt_int} = config
    interval = round(heart_bt_int * 1_000 * @rx_heartbeat_tolerance)
    rx_timer = SessionTimer.setup_timer(:rx, interval)
    session_registry.session_update_status(name, :connected)
    rx_timer
  end
end
