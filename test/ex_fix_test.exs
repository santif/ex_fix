defmodule ExFix.ExFixTest do
  use ExUnit.Case

  alias ExFix.Parser
  alias ExFix.Serializer
  alias ExFix.DefaultDictionary
  alias ExFix.Session.MessageToSend
  alias ExFix.OutMessage
  alias ExFix.TestHelper.FixEmptySessionHandler
  alias ExFix.TestHelper.TestTransport

  @session_registry Application.compile_env(:ex_fix, :session_registry, ExFix.DefaultSessionRegistry)

  @tag_account "1"
  @tag_cl_ord_id "11"
  @tag_order_qty "38"
  @tag_ord_type "40"
  @tag_price "44"
  @tag_side "54"
  @tag_symbol "55"
  @tag_time_in_force "59"
  @tag_transact_time "60"

  test "Session initiator simple test" do
    ExFix.start_session_initiator(
      "session1",
      "SENDER",
      "TARGET",
      FixEmptySessionHandler,
      username: "usr1",
      password: "pwd1",
      log_incoming_msg: true,
      log_outgoing_msg: true,
      reset_on_logon: true,
      heart_bt_int: 10,
      reconnect_interval: 5,
      validate_incoming_message: true,
      time_service: nil,
      default_applverid: "9",
      logon_encrypt_method: "0",
      hostname: "host1",
      port: 0,
      max_output_buf_count: 100,
      dictionary: ExFix.DefaultDictionary,
      time_service: nil,
      transport_mod: TestTransport,
      transport_options: [test_pid: self()]
    )

    assert_receive {:data, logon_msg}
    assert @session_registry.get_session_status("session1") == :connecting
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

    TestTransport.receive_data("session1", received_logon_msg)
    Process.sleep(20)
    assert @session_registry.get_session_status("session1") == :connected

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
    |> ExFix.send_message!("session1")

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

    TestTransport.receive_data("session1", received_logon_msg)

    Process.sleep(20)
    assert @session_registry.get_session_status("session1") == :connected

    ExFix.stop_session("session1")
    assert @session_registry.get_session_status("session1") == :disconnected
  end

  test "Session - data received over TCP" do
    ExFix.start_session_initiator(
      "session2",
      "SENDER",
      "TARGET",
      FixEmptySessionHandler,
      transport_mod: TestTransport,
      transport_options: [test_pid: self()]
    )

    assert_receive {:data, logon_msg}
    assert @session_registry.get_session_status("session2") == :connecting
    assert "8=FIXT.1.1" <> _ = logon_msg

    msg = Parser.parse(logon_msg, DefaultDictionary, 1)
    assert msg.valid

    now = DateTime.utc_now()

    rec_msg = %MessageToSend{
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

    received_logon_msg = Serializer.serialize(rec_msg, now)
    TestTransport.receive_data("session2", received_logon_msg, :tcp)

    Process.sleep(20)
    assert @session_registry.get_session_status("session2") == :connected
    ExFix.stop_session("session2")
  end

  test "Session - disconnection (TCP)" do
    ExFix.start_session_initiator(
      "session3",
      "SENDER",
      "TARGET",
      FixEmptySessionHandler,
      transport_mod: TestTransport,
      transport_options: [test_pid: self()]
    )

    assert_receive {:data, logon_msg}
    assert @session_registry.get_session_status("session3") == :connecting
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
    TestTransport.receive_data("session3", received_logon_msg, :tcp)

    Process.sleep(20)
    assert @session_registry.get_session_status("session3") == :connected

    TestTransport.disconnect("session3", :tcp)
    Process.sleep(20)
    assert @session_registry.get_session_status("session3") == :reconnecting
  end

  test "Session - disconnection (SSL)" do
    ExFix.start_session_initiator(
      "session4",
      "SENDER",
      "TARGET",
      FixEmptySessionHandler,
      transport_mod: TestTransport,
      transport_options: [test_pid: self()]
    )

    assert_receive {:data, logon_msg}
    assert @session_registry.get_session_status("session4") == :connecting
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
    TestTransport.receive_data("session4", received_logon_msg, :ssl)

    Process.sleep(20)
    assert @session_registry.get_session_status("session4") == :connected

    TestTransport.disconnect("session4", :ssl)
    Process.sleep(20)
    assert @session_registry.get_session_status("session4") == :reconnecting
  end

  test "Session - timeout" do
    ExFix.start_session_initiator(
      "session5",
      "SENDER",
      "TARGET",
      FixEmptySessionHandler,
      transport_mod: TestTransport,
      transport_options: [test_pid: self()]
    )

    assert_receive {:data, logon_msg}
    assert @session_registry.get_session_status("session5") == :connecting
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
    TestTransport.receive_data("session5", received_logon_msg, :tcp)

    Process.sleep(20)
    assert @session_registry.get_session_status("session5") == :connected

    TestTransport.receive_msg("session5", {:timeout, :tx})
    Process.sleep(20)

    assert_receive {:data, hb_msg}
    assert @session_registry.get_session_status("session5") == :connected

    msg = Parser.parse(hb_msg, DefaultDictionary)
    assert msg.msg_type == "0"
    ExFix.stop_session("session5")
  end
end
