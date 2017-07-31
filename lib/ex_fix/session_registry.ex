defmodule ExFix.SessionRegistry do
  @moduledoc """
  FIX Session registry - Tracks status of FIX sessions
  """

  use GenServer
  require Logger
  alias ExFix.SessionWorker

  @ets_table :"ex_fix_registry"

  defmodule State do
    @moduledoc false
    defstruct monitor_map: %{}
  end

  ##
  ## API
  ##

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get_session_status(session_name) do
    case :ets.lookup(@ets_table, session_name) do
      [{^session_name, status}] -> status
      [] -> :disconnected
    end
  end

  def start_session(fix_session_name, config) do
    :ets.insert(@ets_table, {fix_session_name, :connecting})
    Supervisor.start_child(ExFix.SessionSup, [config])
  end

  def stop_session(fix_session_name) do
    :ets.delete(@ets_table, fix_session_name)
    try do
      SessionWorker.stop(fix_session_name)
    rescue
      _ -> :ok
    end
  end

  ##
  ## Internal API (functions to use from FIX session genservers)
  ##

  @spec session_on_init(fix_session :: String.t) :: :ok
    | :wait_to_reconnect
    | {:error, reason :: term()}
  def session_on_init(fix_session_name) do
    GenServer.call(__MODULE__, {:session_on_init, fix_session_name, self()})
  end

  def session_update_status(fix_session_name, status) do
    Logger.info fn -> "session_update_status [#{fix_session_name}] - Status: #{inspect status}" end
    :ets.insert(@ets_table, {fix_session_name, status})
  end

  ##
  ## GenServer callbacks
  ##

  def init([]) do
    Logger.debug fn -> "Starting FIX Session Registry" end
    :ets.new(@ets_table, [:public, :named_table])
    {:ok, %State{}}
  end

  def handle_call({:session_on_init, fix_session_name, pid}, _from,
      %State{monitor_map: monitor_map} = state) do
    ref = Process.monitor(pid)

    monitor_map = Map.put(monitor_map, ref, fix_session_name)

    result = case :ets.lookup(@ets_table, fix_session_name) do
      [] ->
        {:error, :notfound}
      [{^fix_session_name, status}] ->
        case status do
          :disconnecting -> {:error, :disconnected}
          :connecting -> :ok
          _ -> :wait_to_reconnect
        end
    end
    {:reply, result, %State{state | monitor_map: monitor_map}}
  end

  def handle_info({:DOWN, monitor, :process, _pid, :normal}, %State{monitor_map:
      monitor_map} = state) do
    fix_session_name = monitor_map[monitor]
    :ets.delete(@ets_table, fix_session_name)
    {:noreply, %State{state | monitor_map: monitor_map}}
  end
  def handle_info({:DOWN, monitor, :process, _pid, _other}, %State{monitor_map:
      monitor_map} = state) do
    fix_session_name = monitor_map[monitor]
    monitor_map = Map.delete(monitor_map, monitor)
    :ets.insert(@ets_table, {fix_session_name, :reconnecting})
    {:noreply, %State{state | monitor_map: monitor_map}}
  end
end
