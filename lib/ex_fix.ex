defmodule ExFix do
  @moduledoc """
  Elixir implementation of FIX Session Protocol FIXT.1.1.
  Currently only supports FIX session initiator (buy side).

  ## Usage

  ```
  defmodule MyFixApplication do
    @behaviour ExFix.FixApplication
    require Logger

    alias ExFix.InMessage
    alias ExFix.OutMessage
    alias ExFix.Parser

    @msg_new_order_single "D"

    @tag_account         1
    @tag_cl_ord_id      11
    @tag_order_qty      38
    @tag_ord_type       40
    @tag_price          44
    @tag_side           54
    @tag_symbol         55
    @tag_time_in_force  59
    @tag_transact_time  60

    @value_side_buy        "1"
    @value_ord_type_limit  "2"

    def on_logon(session_id, _env) do
      \#\# Buy 10 shares of SYM1 for $1.23 per share

      @msg_new_order_single
      |> OutMessage.new()
      |> OutMessage.set_field(@tag_account, 1234)
      |> OutMessage.set_field(@tag_cl_ord_id, "cod12345")
      |> OutMessage.set_field(@tag_order_qty, 10)
      |> OutMessage.set_field(@tag_ord_type, @value_ord_type_limit)
      |> OutMessage.set_field(@tag_price, 1.23)
      |> OutMessage.set_field(@tag_side, @value_side_buy)
      |> OutMessage.set_field(@tag_symbol, "SYM1")
      |> OutMessage.set_field(@tag_transact_time, DateTime.utc_now())
      |> ExFix.send_message!(session_id)
    end

    def on_message(session_id, msg_type, %InMessage{} = msg, _env) do
      Logger.info "App msg received: \#{inspect Parser.parse2(msg)}"
    end

    def on_admin_message(session_id, msg_type, %InMessage{} = msg, _env) do
      Logger.info "Admin msg received: \#{inspect Parser.parse2(msg)}"
    end

    def on_logout(_session_id, _env), do: :ok
  end

  ExFix.start_session_initiator("mysession", "SENDER", "TARGET", MyFixApplication,
    socket_connect_host: "localhost", socket_connect_port: 9876,
    logon_username: "user1", logon_password: "pwd1", transport_mod: :ssl)
  ```
  """

  alias ExFix.Session
  alias ExFix.SessionConfig
  alias ExFix.SessionRegistry
  alias ExFix.SessionWorker
  alias ExFix.OutMessage

  @default_dictionary Application.get_env(:ex_fix, :default_dictionary)
  @session_registry Application.get_env(:ex_fix, :session_registry, ExFix.DefaultSessionRegistry)

  @doc """
  Starts FIX session initiator
  """
  ## TODO spec
  def start_session_initiator(session_name, sender_comp_id, target_comp_id,
      fix_application, opts \\ []) do
    opts = Enum.into(opts, %{
      socket_connect_host: "localhost",
      socket_connect_port: 9876,
      logon_username: nil,
      logon_password: nil,
      log_incoming_msg: true,
      log_outgoing_msg: true,
      default_applverid: "9",
      logon_encrypt_method: "0",
      heart_bt_int: 60,
      max_output_buf_count: 1_000,
      reconnect_interval: 15,
      reset_on_logon: true,
      validate_incoming_message: true,
      transport_mod: :gen_tcp,
      transport_options: [],
      time_service: nil,
      env: %{}
    })
    config = struct(%SessionConfig{
      name: session_name,
      mode: :initiator,
      sender_comp_id: sender_comp_id,
      target_comp_id: target_comp_id,
      fix_application: fix_application,
      dictionary: @default_dictionary,
    }, opts)
    session_registry = opts[:session_registry] || @session_registry
    session_registry.start_session(session_name, config)
  end

  @doc """
  Send FIX message to a session
  """
  @spec send_message!(OutMessage.t, Session.session_id) :: :ok | no_return
  def send_message!(out_message, session_id) do
    SessionWorker.send_message!(session_id, out_message)
  end

  @doc """
  Stop FIX session
  """
  @spec stop_session(Session.session_id, SessionRegistry | nil) :: :ok | no_return
  def stop_session(session_id, registry \\ nil) do
    session_registry = registry || @session_registry
    session_registry.stop_session(session_id)
  end
end
