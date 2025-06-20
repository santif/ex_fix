defmodule ExFix.SessionWorkerTest do
  use ExUnit.Case

  alias ExFix.Parser
  alias ExFix.Serializer
  alias ExFix.DefaultDictionary
  alias ExFix.SessionWorker
  alias ExFix.Session.MessageToSend
  alias ExFix.OutMessage
  alias ExFix.SessionConfig
  alias ExFix.TestHelper.FixEmptySessionHandler
  alias ExFix.TestHelper.TestTransport
  alias ExFix.TestHelper.TestSessionRegistry

  @tag_account "1"
  @tag_cl_ord_id "11"
  @tag_order_qty "38"
  @tag_ord_type "40"
  @tag_price "44"
  @tag_side "54"
  @tag_symbol "55"
  @tag_time_in_force "59"
  @tag_transact_time "60"

  setup do
    {:ok, _} = TestSessionRegistry.start_link()

    config = %SessionConfig{
      name: "sessiontest1",
      mode: :initiator,
      sender_comp_id: "SENDER",
      target_comp_id: "TARGET",
      session_handler: FixEmptySessionHandler,
      dictionary: DefaultDictionary,
      hostname: "localhost",
      port: 9876,
      username: nil,
      password: nil,
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
      env: %{}
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

    rec_logon = %MessageToSend{
      seqnum: 1,
      sender: "TARGET",
      orig_sending_time: now,
      target: "SENDER",
      msg_type: "A",
      body: [
        {"98", "0"},
        {"108", 120},
        {"141", true},
        {"553", "usr1"},
        {"554", "pwd1"},
        {"1137", "9"}
      ]
    }

    received_logon_msg = Serializer.serialize(rec_logon, now)

    TestTransport.receive_data("sessiontest1", received_logon_msg)
    Process.sleep(20)
    assert TestSessionRegistry.get_session_status("sessiontest1") == :connected

    ## Send New Order Single
    now = DateTime.utc_now()

    "D"
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
      {"151", 0}
    ]

    received_logon_msg =
      Serializer.serialize(
        %MessageToSend{
          seqnum: 2,
          sender: "TARGET",
          orig_sending_time: now,
          target: "SENDER",
          msg_type: "8",
          body: er_body
        },
        now
      )

    TestTransport.receive_data("sessiontest1", received_logon_msg)

    assert TestSessionRegistry.get_session_status("sessiontest1") == :connected

    SessionWorker.stop("sessiontest1")
    assert TestSessionRegistry.get_session_status("sessiontest1") == :disconnected
  end

  test "higher seqnum triggers resend request" do

    cfg = %SessionConfig{
      name: "resend_sess",
      mode: :initiator,
      sender_comp_id: "SENDER",
      target_comp_id: "TARGET",
      session_handler: FixEmptySessionHandler,
      dictionary: DefaultDictionary,
      transport_mod: TestTransport,
      transport_options: [test_pid: self()]
    }

    {:ok, _pid} = SessionWorker.start_link(cfg, TestSessionRegistry)
    assert_receive {:data, _logon_msg}

    now = DateTime.utc_now()
    logon = %MessageToSend{seqnum: 1, sender: "TARGET", orig_sending_time: now, target: "SENDER", msg_type: "A", body: []}
    TestTransport.receive_data("resend_sess", Serializer.serialize(logon, now))
    Process.sleep(20)

    msg = %MessageToSend{seqnum: 12, sender: "TARGET", orig_sending_time: now, target: "SENDER", msg_type: "8", body: []}
    TestTransport.receive_data("resend_sess", Serializer.serialize(msg, now))

    assert_receive {:data, resend}
    parsed = Parser.parse(resend, DefaultDictionary, 1)
    assert parsed.msg_type == "2"
    SessionWorker.stop("resend_sess")
  end

  test "invalid SenderCompID triggers logout" do
    cfg = %SessionConfig{
      name: "badcomp",
      mode: :initiator,
      sender_comp_id: "SENDER",
      target_comp_id: "TARGET",
      session_handler: FixEmptySessionHandler,
      dictionary: DefaultDictionary,
      transport_mod: TestTransport,
      transport_options: [test_pid: self()]
    }

    {:ok, pid} = SessionWorker.start_link(cfg, TestSessionRegistry)
    ref = Process.monitor(pid)
    assert_receive {:data, _}

    now = DateTime.utc_now()
    logon = %MessageToSend{seqnum: 1, sender: "TARGET", orig_sending_time: now, target: "SENDER", msg_type: "A", body: []}
    TestTransport.receive_data("badcomp", Serializer.serialize(logon, now))
    Process.sleep(20)

    msg = %MessageToSend{seqnum: 2, sender: "OTHER", orig_sending_time: now, target: "SENDER", msg_type: "8", body: []}
    TestTransport.receive_data("badcomp", Serializer.serialize(msg, now))

    assert_receive {:data, reject}
    assert_receive {:data, logout}
    assert Parser.parse(reject, DefaultDictionary, 1).msg_type == "3"
    assert Parser.parse(logout, DefaultDictionary, 1).msg_type == "5"
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
  end
end
