defmodule ExFix.ExFixTest do
  use ExUnit.Case
  alias ExFix.SessionRegistry
  alias ExFix.Parser
  alias ExFix.DefaultDictionary

  defmodule TestTransport do
    def connect(_host, _port, options) do
      {:ok, options[:test_pid]}
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
      transport_mod: TestTransport, transport_options: [test_pid: self()])
    assert_receive {:data, logon_msg}
    assert SessionRegistry.get_status == %{"session1" => :connecting}
    assert "8=FIXT.1.1" <> _ = logon_msg
    msg = Parser.parse(logon_msg, DefaultDictionary, 1)
    assert msg.valid
  end
end