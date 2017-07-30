defmodule ExFix.ExFixTest do
  use ExUnit.Case
  alias ExFix.SessionRegistry
  alias ExFix.{Parser, Serializer}
  alias ExFix.DefaultDictionary
  alias ExFix.Types.MessageToSend

  @tag_account       "1"
  @tag_cl_ord_id     "11"
  @tag_order_qty     "38"
  @tag_ord_type      "40"
  @tag_price         "44"
  @tag_side          "54"
  @tag_symbol        "55"
  @tag_time_in_force "59"
  @tag_transact_time "60"

  defmodule TestTransport do
    def connect(_host, _port, options) do
      {:ok, options[:test_pid]}
    end
    def send(conn, data) do
      Process.send(conn, {:data, data}, [])
    end
    def close(_conn), do: :ok
    def receive(worker, data) do
      Process.send(worker, {:tcp, self(), data}, [])
    end
  end

  defmodule TestApplication do
    @behaviour ExFix.FixApplication
    def before_logon(_fix_session, _fields), do: :ok
    def on_logon(_fix_session, _pid) do
    end
    def on_message(_fix_session, _msg_type, _pid, _msg) do
    end
    def on_logout(_fix_session), do: :ok
  end

  test "Session initiator simple test" do
    ExFix.start_session_initiator("session1", "SENDER", "TARGET", TestApplication,
      transport_mod: TestTransport, logon_username: "usr1", logon_password: "pwd1",
      transport_options: [test_pid: self()])
    assert_receive {:data, logon_msg}
    assert SessionRegistry.get_status() == %{"session1" => :connecting}
    assert "8=FIXT.1.1" <> _ = logon_msg
    msg = Parser.parse(logon_msg, DefaultDictionary, 1)
    assert msg.valid

    now = DateTime.utc_now()
    received_logon_msg = %MessageToSend{seqnum: 1, sender: "TARGET",
      orig_sending_time: now, target: "SENDER",
      msg_type: "A", body: [{"98", "0"}, {"108", 120},
      {"141", true}, {"553", "usr1"}, {"554", "pwd1"},
      {"1137", "9"}]}
    |> Serializer.serialize(now)

    TestTransport.receive(:"ex_fix_session_session1", received_logon_msg)
    Process.sleep(50)
    assert SessionRegistry.get_status() == %{"session1" => :connected}

    ## Send New Order Single
    now = DateTime.utc_now()
    body = [
      {@tag_account, 1234},
      {@tag_cl_ord_id, "cod12345"},
      {@tag_order_qty, 10},
      {@tag_ord_type, "2"},
      {@tag_price, 1.23},
      {@tag_side, "1"},
      {@tag_symbol, "SYM1"},
      {@tag_time_in_force, "0"},
      {@tag_transact_time, now},
    ]
    ExFix.send_message!("session1", "D", body)

    assert_receive {:data, new_order_single}
    assert "8=FIXT.1.1" <> _ = new_order_single

    SessionRegistry.stop_session("session1")
    assert SessionRegistry.get_status() == %{}
  end
end