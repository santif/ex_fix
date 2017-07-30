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
      logon_username: "usr1", logon_password: "pwd1", log_incoming_msg: true,
      log_outgoing_msg: true, reset_on_logon: true, heart_bt_int: 10,
      reconnect_interval: 5, validate_incoming_message: true,
      time_service: nil, default_applverid: "9", logon_encrypt_method: "0",
      socket_connect_host: "host1", socket_connect_port: 0,
      transport_mod: TestTransport, transport_options: [test_pid: self()])

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
    Process.sleep(25)
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

    ## Receive Execution Report
    now = DateTime.utc_now()
    er_body = [
      {"1", 531},
      {"11", 99},
      {"14", 5},
      {"17", 872},
      {"31", 1.2},
      {"32", 5},
      {"37", 456},
      {"38", 5},
      {"39", 2},
      {"54", 1},
      {"55", "ABC"},
      {"150", "F"},
      {"151", 0},
    ]
    received_logon_msg = %MessageToSend{seqnum: 2, sender: "TARGET",
      orig_sending_time: now, target: "SENDER",
      msg_type: "8", body: er_body}
    |> Serializer.serialize(now)

    TestTransport.receive(:"ex_fix_session_session1", received_logon_msg)

    Process.sleep(25)
    assert SessionRegistry.get_status() == %{"session1" => :connected}

    ExFix.stop_session("session1")
    assert SessionRegistry.get_status() == %{}
  end
end