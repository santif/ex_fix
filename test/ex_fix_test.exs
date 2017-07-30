defmodule ExFix.ExFixTest do
  use ExUnit.Case

  defmodule TestTransport do
    def connect(_host, _port, options) do
      {:ok, options[:pid]}
    end
    def send(conn, data) do
      Process.send(conn, {:data, data}, [])
    end
    def receive(worker, data) do
      Process.send(worker, {:tcp, self(), data}, [])
    end
  end

  defmodule TestApplication do
    @behaviour ExFix.FixApplication
    def before_logon(_fix_session, _fields), do: :ok
    def on_logon(fix_session, pid) do
      send(pid, {:logon, fix_session})
    end
    def on_message(fix_session, msg_type, pid, msg) do
      send(pid, {:msg, fix_session, msg_type, msg})
    end
    def on_logout(_fix_session), do: :ok
  end

  test "Session initiator test" do
    ExFix.start_session_initiator("session1", "SENDER", "TARGET", TestApplication,
      transport_mod: TestTransport, transport_options: [pid: self()])
    assert_receive {:data, _}
    assert ExFix.SessionRegistry.get_status == %{"session1" => :connecting}
  end
end