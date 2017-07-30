defmodule ExFix.SessionTimer do

  @doc """
  Sends a message `{:timeout, name}` when no messages are received for a certain time in seconds.
  """
  @spec setup_timer(term(), non_neg_integer()) :: pid()
  def setup_timer(name, interval_seconds) do
    spawn_link(__MODULE__, :timer_loop, [name, interval_seconds * 1_000, self()])
  end

  @doc """
  Main loop of timer process
  """
  def timer_loop(name, interval_ms, process_pid) do
    receive do
      _ ->
        timer_loop(name, interval_ms, process_pid)
    after interval_ms ->
      send(process_pid, {:timeout, name})
      timer_loop(name, interval_ms, process_pid)
    end
  end
end