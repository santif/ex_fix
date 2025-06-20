defmodule ExFix.SessionWorkerFailureTest do
  use ExUnit.Case

  alias ExFix.SessionConfig
  alias ExFix.TestHelper.FixEmptySessionHandler

  defmodule FailTransport do
    def connect(_host, _port, _opts), do: {:error, :econnrefused}
    def send(_conn, _data), do: :ok
    def close(_conn), do: :ok
  end

  alias ExFix.TestHelper.TestSessionRegistry

  test "worker reports reconnecting on connection failure" do
    Process.flag(:trap_exit, true)
    {:ok, _} = TestSessionRegistry.start_link()
    config = %SessionConfig{
      name: "fail1",
      mode: :initiator,
      sender_comp_id: "S",
      target_comp_id: "T",
      session_handler: FixEmptySessionHandler,
      transport_mod: FailTransport,
      transport_options: [],
      log_incoming_msg: false,
      log_outgoing_msg: false,
      reconnect_interval: 0
    }

    {:ok, pid} = ExFix.SessionWorker.start_link(config, TestSessionRegistry)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :econnrefused}
    assert TestSessionRegistry.get_session_status("fail1") == :reconnecting
  end
end
