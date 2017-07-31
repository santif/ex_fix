defmodule ExFix.SessionTimer do
  @moduledoc """
  Keeps track of sent and received messages. Triggers a message with the
  form `{:timeout, timer_name}` when no sent/received messages are registered
  for a certain time.
  """

  @doc """
  Sends a message `{:timeout, name}` when no messages are received for a certain time.
  """
  @spec setup_timer(term(), non_neg_integer()) :: pid()
  def setup_timer(name, interval_ms) do
    spawn_link(__MODULE__, :timer_loop, [name, interval_ms, self()])
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