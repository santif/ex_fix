defmodule ExFix.SessionWorkerTest do
  use ExUnit.Case

  alias ExFix.Parser
  alias ExFix.Serializer
  alias ExFix.DefaultDictionary
  alias ExFix.SessionWorker
  alias ExFix.Session.MessageToSend
  alias ExFix.OutMessage
  alias ExFix.SessionConfig
  alias ExFix.TestHelper.FixEmptyApplication
  alias ExFix.TestHelper.TestTransport
  alias ExFix.TestHelper.TestSessionRegistry

  @tag_account         1
  @tag_cl_ord_id      11
  @tag_order_qty      38
  @tag_ord_type       40
  @tag_price          44
  @tag_side           54
  @tag_symbol         55
  @tag_time_in_force  59
  @tag_transact_time  60

  setup do
    {:ok, _} = TestSessionRegistry.start_link()
    config = %SessionConfig{
      name: "sessiontest1",
      mode: :initiator,
      sender_comp_id: "SENDER",
      target_comp_id: "TARGET",
      fix_application: FixEmptyApplication,
      dictionary: DefaultDictionary,
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
      transport_mod: TestTransport,
      transport_options: [test_pid: self()],
      time_service: nil,
    }
    %{config: config}
  end

  test "Session worker simple test", %{config: cfg} do
    {:ok, _session} = SessionWorker.start_link(cfg, TestSessionRegistry)
    assert_receive {:data, logon_msg}
    assert TestSessionRegistry.get_session_status("sessiontest1") == :connecting
    assert "8=FIXT.1.1" <> _ = logon_msg

    msg = Parser.parse(logon_msg, DefaultDictionary, 1)
    assert msg.valid

    now = DateTime.utc_now()
    rec_logon = %MessageToSend{seqnum: 1, sender: "TARGET",
      orig_sending_time: now, target: "SENDER",
      msg_type: "A", body: [{"98", "0"}, {"108", 120},
      {"141", true}, {"553", "usr1"}, {"554", "pwd1"},
      {"1137", "9"}]}
    received_logon_msg = Serializer.serialize(rec_logon, now)

    TestTransport.receive_data("sessiontest1", received_logon_msg)
    Process.sleep(20)
    assert TestSessionRegistry.get_session_status("sessiontest1") == :connected

    ## Send New Order Single
    now = DateTime.utc_now()
    out_msg = "D"
    |> OutMessage.new()
    |> OutMessage.set_field(@tag_account, 1234)
    |> OutMessage.set_field(@tag_cl_ord_id, "cod12345")
    |> OutMessage.set_field(@tag_order_qty, 10)
    |> OutMessage.set_field(@tag_ord_type, "2")
    |> OutMessage.set_field(@tag_price, 1.23)
    |> OutMessage.set_field(@tag_side, "1")
    |> OutMessage.set_field(@tag_symbol, "SYM1")
    |> OutMessage.set_field(@tag_time_in_force, "0")
    |> OutMessage.set_field(@tag_transact_time, now)
    |> ExFix.send_message!("sessiontest1")

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
    received_logon_msg = Serializer.serialize(%MessageToSend{seqnum: 2, sender: "TARGET",
      orig_sending_time: now, target: "SENDER", msg_type: "8", body: er_body}, now)
    TestTransport.receive_data("sessiontest1", received_logon_msg)

    assert TestSessionRegistry.get_session_status("sessiontest1") == :connected

    SessionWorker.stop("sessiontest1")
    assert TestSessionRegistry.get_session_status("sessiontest1") == :disconnected
  end
end
