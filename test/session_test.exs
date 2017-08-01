defmodule ExFix.SessionTest do
  use ExUnit.Case
  import ExFix.TestHelper

  alias ExFix.Types.MessageToSend
  alias ExFix.Types.SessionConfig
  alias ExFix.Session
  alias ExFix.TestHelper.FixDummyApplication

  @msg_type_logon             "A"
  @msg_type_heartbeat         "0"
  @msg_type_test_request      "1"
  @msg_type_resend_request    "2"
  @msg_type_reject            "3"
  @msg_type_sequence_reset    "4"
  @msg_type_logout            "5"

  # Some application message types for testing
  @msg_type_new_order_single  "D"
  @msg_type_execution_report  "8"

  # App fields used in tests
  @field_account 1
  @field_last_px 31

  @t0        Calendar.DateTime.from_erl!({{2017, 6, 5}, {14, 1, 2}}, "Etc/UTC")
  @t_plus_1  Calendar.DateTime.from_erl!({{2017, 6, 5}, {14, 1, 3}}, "Etc/UTC")
  @t_plus_2  Calendar.DateTime.from_erl!({{2017, 6, 5}, {14, 1, 4}}, "Etc/UTC")

  setup do
    config = %SessionConfig{name: "test", mode: :initiator, sender_comp_id: "BUYSIDE",
      target_comp_id: "SELLSIDE", logon_username: "testuser", logon_password: "testpwd",
      fix_application: FixDummyApplication, dictionary: ExFix.DefaultDictionary,
      time_service: @t0}
    {:ok, config: config}
  end

  test "FIX session logon", %{config: cfg} do
    {:ok, session} = Session.init(cfg)
    session = Session.set_time(session, @t0)

    assert Session.get_status(session) == :offline

    {:ok, msgs_to_send, session} = Session.session_start(session)

    assert Session.get_status(session) == :connecting
    expected_fields = [{"98", "0"}, {"108", 60}, {"141", true},
      {"553", "testuser"}, {"554", "testpwd"}, {"1137", "9"}]
    assert msgs_to_send == [%MessageToSend{
      seqnum: 1, msg_type: @msg_type_logon, sender: "BUYSIDE",
      orig_sending_time: @t0, target: "SELLSIDE", body: expected_fields}]

    incoming_data = build_message(@msg_type_logon, 1, "SELLSIDE", "BUYSIDE",
      @t_plus_1, [{"Username", "testuser"}, {"Password", "testpwd"}, {"EncryptMethod", "0"},
        {"HeartBtInt", 120}, {"ResetSeqNumFlag", true}, {"DefaultApplVerID", "9"}])
    session = Session.set_time(session, @t_plus_1)
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :online
    assert msgs_to_send == []
  end

  test "Message received with MsgSeqNum higher than expected (p. 49)", %{config: cfg} do
    # Respond with Resend Message

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    incoming_data = build_message(@msg_type_new_order_single, 12, "SELLSIDE", "BUYSIDE",
      @t_plus_1, [{@field_account, "1234"}])
    session = Session.set_time(session, @t_plus_1)
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert msgs_to_send == [%MessageToSend{seqnum: 6, msg_type: @msg_type_resend_request,
      sender: "BUYSIDE", orig_sending_time: @t_plus_1, target: "SELLSIDE",
      body: [{"7", 11}, {"16", 11}]}]

    assert Session.get_in_queue_length(session) == 1
    assert Session.get_in_lastseq(session) == 10
    [queued_message] = Session.get_in_queue(session)

    assert queued_message.valid == true
    assert queued_message.error_reason == nil
    assert queued_message.seqnum == 12
    assert queued_message.msg_type == @msg_type_new_order_single
  end

  test "MsgSeqNum lower than expected without PossDupFlag set to Y (p. 49)", %{config: cfg} do
    # Respond with Logout with "MsgSeqNum too low, expecting X but received Y" (optional - wait for response)
    # Disconnect

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    seq = 9
    incoming_data = build_message(@msg_type_execution_report, seq, "SELLSIDE", "BUYSIDE",
      @t_plus_1, [{@field_account, "1234"}])
    session = Session.set_time(session, @t_plus_1)
    {:logout, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :disconnecting

    assert length(msgs_to_send) == 1
    [logout] = msgs_to_send

    assert logout.seqnum == 6
    assert logout.msg_type == @msg_type_logout
    assert logout.sender == "BUYSIDE"
    assert logout.target == "SELLSIDE"
    assert logout.orig_sending_time == @t_plus_1
    assert :lists.keyfind("58", 1, logout.body) ==
      {"58", "MsgSeqNum too low, expecting 11 but received 9"}
  end

  test "Garbled message received - 1 (p. 49)", %{config: cfg} do
    # Ignore message - don't increment expected MsgSeqNum
    # Warning condition

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    incoming_data = msg("8=FIXT.1.1|9=$$$|garbled|10=$$$|")
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :online
    assert length(msgs_to_send) == 0
  end

  test "Garbled message received - 2 (p. 49)", %{config: cfg} do
    # Ignore message - don't increment expected MsgSeqNum
    # Warning condition

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    incoming_data = msg("garbled_garbled_garbled_garbled_garbled")
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :online
    assert length(msgs_to_send) == 0
  end

  test "PossDupFlag=Y, OrigSendingTime<=SendingTime and MsgSeqNum<Expected (p. 50)", %{config: cfg} do
    # 1. Check to see if MsgSeqNum has already been received.
    # 2. If already received then ignore the message, otherwise accept and process the message.

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    seq = 9
    resend = true
    orig_sending_time = @t0
    incoming_data = build_message(@msg_type_execution_report, seq, "SELLSIDE", "BUYSIDE",
      @t_plus_1, [{@field_account, "1234"}], orig_sending_time, resend)
    session = Session.set_time(session, @t_plus_1)
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :online
    assert length(msgs_to_send) == 0
  end

  # test "PossDupFlag=Y, OrigSendingTime > SendingTime and MsgSeqNum=Expected (p. 50)", %{config: cfg} do
  #   # 1. Send Reject (session-level) message referencing inaccurate SendingTime: "SendingTime acccuracy problem")
  #   # 2. Increment inbound MsgSeqNum
  #   # 3. Optional flow - send Logout - p. 50

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   msg_seqnum = 11
  #   incoming_data = msg("8=FIXT.1.1|9=$$$|35=8|34=#{msg_seqnum}|49=SELLSIDE|" <>
  #     "43=Y|52=20170717-17:50:56.123|122=20170717-17:51:00.000|56=BUYSIDE|1=1234|10=$$$|")
  #   {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert Session.get_status(session) == :online
  #   assert Session.get_in_lastseq(session) == 11

  #   assert length(msgs_to_send) == 1
  #   [reject_msg] = msgs_to_send

  #   assert reject_msg.seqnum == 6
  #   assert reject_msg.msg_type == @msg_type_reject
  #   assert reject_msg.sender == "BUYSIDE"
  #   assert reject_msg.target == "SELLSIDE"
  #   assert reject_msg.orig_sending_time == @t0
  #   assert :lists.keyfind("373", 1, reject_msg.body) == {"373", "10"}
  #   assert :lists.keyfind("58", 1, reject_msg.body) == {"58", "SendingTime acccuracy problem"}
  # end

  # test "PossDupFlag=Y and OrigSendingTime not specified (p. 51)", %{config: cfg} do
  #   # 1. Send Reject (session-level) with SessionRejectReason = "Required tag missing")
  #   # 2. Increment inbound MsgSeqNum

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   msg_seqnum = 11
  #   incoming_data = msg("8=FIXT.1.1|9=$$$|35=8|34=#{msg_seqnum}|49=SELLSIDE|" <>
  #     "43=Y|52=20170717-17:50:56.123|56=BUYSIDE|1=1234|10=$$$|")
  #   {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert Session.get_status(session) == :online
  #   assert Session.get_in_lastseq(session) == 11

  #   assert length(msgs_to_send) == 1
  #   [reject_msg] = msgs_to_send

  #   assert reject_msg.seqnum == 6
  #   assert reject_msg.msg_type == @msg_type_reject
  #   assert reject_msg.sender == "BUYSIDE"
  #   assert reject_msg.target == "SELLSIDE"
  #   assert reject_msg.orig_sending_time == @t0
  #   assert :lists.keyfind("373", 1, reject_msg.body) == {"373", "1"}
  #   assert :lists.keyfind("58", 1, reject_msg.body) == {"58", "Required tag missing: OrigSendingTime"}
  # end

  # test "BeginString value received did not match value expected (p. 51)", %{config: cfg} do
  #   # 1. Send Logout message referencing incorrect BeginString value
  #   # 2. Optional - Wait for Logout message response (note likely will have incorrect BeginString)
  #   #    or wait 2 seconds whichever comes first
  #   # 3. Disconnect

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   msg_seqnum = 11
  #   incoming_data = msg("8=INCORRECT_BEGIN_STRING|9=$$$|35=8|34=#{msg_seqnum}|49=SELLSIDE|" <>
  #     "52=20170717-17:50:56.123|56=BUYSIDE|1=1234|10=$$$|")
  #   {:logout, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert Session.get_status(session) == :disconnecting

  #   assert length(msgs_to_send) == 1
  #   [logout] = msgs_to_send

  #   assert logout.seqnum == 6
  #   assert logout.msg_type == @msg_type_logout
  #   assert logout.sender == "BUYSIDE"
  #   assert logout.target == "SELLSIDE"
  #   assert logout.orig_sending_time == @t0
  #   assert :lists.keyfind("58", 1, logout.body) == {"58", "Incorrect BeginString value"}
  # end

  # test "Unexpected SenderCompID", %{config: cfg} do
  #   # 1. Send Reject (session-level) with SessionRejectReason = "CompID problem")
  #   # 2. Increment inbound MsgSeqNum
  #   # 3. Send Logout message referencing incorrect SenderCompID or TargetCompID value
  #   # 4. Optional - Wait for Logout message response (note likely will have incorrect SenderCompID or TargetCompID)
  #   #    or wait 2 seconds whichever comes first
  #   # 5. Disconnect
  #   # Error condition

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   msg_seqnum = 11
  #   incoming_data = msg("8=FIXT.1.1|9=$$$|35=8|34=#{msg_seqnum}|49=OTHER_BUYSIDE|" <>
  #     "52=20170717-17:50:56.123|56=SELLSIDE|1=1234|10=$$$|")
  #   {:logout, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert Session.get_status(session) == :disconnecting

  #   assert length(msgs_to_send) == 2
  #   [reject_msg, logout_msg] = msgs_to_send

  #   assert reject_msg.seqnum == 6
  #   assert reject_msg.msg_type == @msg_type_reject
  #   assert reject_msg.sender == "BUYSIDE"
  #   assert reject_msg.target == "SELLSIDE"
  #   assert reject_msg.orig_sending_time == @t0
  #   assert :lists.keyfind("373", 1, reject_msg.body) == {"373", "9"}
  #   assert :lists.keyfind("58", 1, reject_msg.body) == {"58", "CompID problem"}

  #   assert logout_msg.seqnum == 7
  #   assert logout_msg.msg_type == @msg_type_logout
  #   assert logout_msg.sender == "BUYSIDE"
  #   assert logout_msg.target == "SELLSIDE"
  #   assert logout_msg.orig_sending_time == @t0
  #   assert :lists.keyfind("58", 1, logout_msg.body) == {"58", "Incorrect SenderCompID value"}
  # end

  # test "Unexpected TargetCompID", %{config: cfg} do
  #   # 1. Send Reject (session-level) with SessionRejectReason = "CompID problem")
  #   # 2. Increment inbound MsgSeqNum
  #   # 3. Send Logout message referencing incorrect SenderCompID or TargetCompID value
  #   # 4. Optional - Wait for Logout message response (note likely will have incorrect SenderCompID or TargetCompID)
  #   #    or wait 2 seconds whichever comes first
  #   # 5. Disconnect
  #   # Error condition

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   msg_seqnum = 11
  #   incoming_data = msg("8=FIXT.1.1|9=$$$|35=8|34=#{msg_seqnum}|49=SELLSIDE|" <>
  #     "52=20170717-17:50:56.123|56=OTHER_BUYSIDE|1=1234|10=$$$|")
  #   {:logout, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert Session.get_status(session) == :disconnecting

  #   assert length(msgs_to_send) == 2
  #   [reject_msg, logout_msg] = msgs_to_send

  #   assert reject_msg.seqnum == 6
  #   assert reject_msg.msg_type == @msg_type_reject
  #   assert reject_msg.sender == "BUYSIDE"
  #   assert reject_msg.target == "SELLSIDE"
  #   assert reject_msg.orig_sending_time == @t0
  #   assert :lists.keyfind("373", 1, reject_msg.body) == {"373", "9"}
  #   assert :lists.keyfind("58", 1, reject_msg.body) == {"58", "CompID problem"}

  #   assert logout_msg.seqnum == 7
  #   assert logout_msg.msg_type == @msg_type_logout
  #   assert logout_msg.sender == "BUYSIDE"
  #   assert logout_msg.target == "SELLSIDE"
  #   assert logout_msg.orig_sending_time == @t0
  #   assert :lists.keyfind("58", 1, logout_msg.body) == {"58", "Incorrect TargetCompID value"}
  # end

  # test "BodyLength value received is not correct (p. 52)", %{config: cfg} do
  #   # Ignore message - don't increment expected MsgSeqNum
  #   # Warning condition

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   msg_seqnum = 11
  #   incorrect_body_length = 5
  #   incoming_data = msg("8=FIXT.1.1|9=#{incorrect_body_length}|35=8|34=#{msg_seqnum}|49=SELLSIDE|" <>
  #     "52=20170717-17:50:56.123|56=BUYSIDE|1=1234|10=$$$|")
  #   {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert Session.get_status(session) == :online

  #   assert length(msgs_to_send) == 0
  # end

  # test "Checksum error (p. 55)", %{config: cfg} do
  #   # > CheckSum error is not the last field of message, value doesn't have length of 3, or isn't delimited by SOH
  #   # Ignore message - don't increment expected MsgSeqNum
  #   # Warning condition

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   msg_seqnum = 11
  #   incoming_data = msg("8=FIXT.1.1|9=$$$|35=8|34=#{msg_seqnum}|49=SELLSIDE|" <>
  #     "52=20170717-17:50:56.123|56=BUYSIDE|10=ERR")
  #   {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert Session.get_status(session) == :online
  #   assert Session.get_in_lastseq(session) == 10
  #   assert length(msgs_to_send) == 0
  # end

  # test "A Test Request message is received (p. 55)", %{config: cfg} do
  #   # Send Hearbeat message with Test Request message's TestReqID
  #   # Warning condition

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   msg_seqnum = 11
  #   incoming_data = msg("8=FIXT.1.1|9=$$$|35=1|34=#{msg_seqnum}|49=SELLSIDE|" <>
  #     "52=20170717-17:50:56.123|56=BUYSIDE|10=$$$|")
  #   {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert Session.get_status(session) == :online

  #   assert length(msgs_to_send) == 1
  #   [hb_msg] = msgs_to_send

  #   assert hb_msg.seqnum == 6
  #   assert hb_msg.msg_type == @msg_type_heartbeat
  #   assert hb_msg.sender == "BUYSIDE"
  #   assert hb_msg.target == "SELLSIDE"
  #   assert hb_msg.orig_sending_time == @t0
  # end

  # test "No data received during (HeartBeatInt field + 20%) interval (p. 55)", %{config: cfg} do
  #   # Send Test Request message
  #   # Track and verify that a Heartbeat with the same TestReqID is received (may not be the next message received)

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   {:ok, msgs_to_send, session} = Session.handle_timeout(session, :rx)

  #   assert Session.get_status(session) == :online

  #   assert length(msgs_to_send) == 1
  #   [test_msg] = msgs_to_send

  #   assert test_msg.seqnum == 6
  #   assert test_msg.msg_type == @msg_type_test_request
  #   assert test_msg.sender == "BUYSIDE"
  #   assert test_msg.target == "SELLSIDE"
  #   assert test_msg.orig_sending_time == @t0
  #   {"112", test_req_id} = :lists.keyfind("112", 1, test_msg.body)

  #   assert Session.get_last_test_req_id(session) == test_req_id

  #   {:logout, [logout_msg], session} = Session.handle_timeout(session, :rx)

  #   assert Session.get_status(session) == :disconnecting
  #   assert logout_msg.seqnum == 7
  #   assert logout_msg.msg_type == @msg_type_logout

  #   assert Session.get_last_test_req_id(session) == nil
  # end

  # test "Valid Resend Request (p. 55)", %{config: cfg} do
  #   ## Respond with application level messages and SequenceReset-Gap-Fill for admin messages requested
  #   ## range according to "Message Recovery rules"

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 1, out_lastseq: 1}

  #   {:ok, _, session} = Session.send_message(session, "D",
  #     [{"1", 100}, {"55", "Symbol1"}, {"44", 4.56}]) # seqnum 2
  #   {:ok, _, session} = Session.send_message(session, "D",
  #     [{"1", 101}, {"55", "Symbol1"}, {"44", 4.56}]) # seqnum 3
  #   {:ok, _, session} = Session.send_message(session, "0",
  #     []) # seqnum 4 (heartbeat)
  #   {:ok, _, session} = Session.send_message(session, "D",
  #     [{"1", 103}, {"55", "Symbol1"}, {"44", 4.56}]) # seqnum 5

  #   msg_seqnum = 2
  #   tag_begin_seq_no = "7"
  #   tag_end_seq_no = "16"
  #   incoming_data = msg("8=FIXT.1.1|9=$$$|35=2|34=#{msg_seqnum}|49=BUYSIDE|" <>
  #     "52=20170717-17:50:56.123|56=SELLSIDE|#{tag_begin_seq_no}=2|#{tag_end_seq_no}=4|10=$$$|")

  #   {:resend, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert length(msgs_to_send) == 3
  #   assert Session.get_status(session) == :online
  #   ## TODO asserts
  # end

  # test "SeqResetGapFill with NewSeqNo>MsgSeqNum AND MsgSeqNum>Expected (p. 56)", %{config: cfg} do
  #   ## Issue Resend Request to fill gap between last expected MsgSeqNum and received MsgSeqNum

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   msg_seqnum = 13
  #   tag_new_seq_no = "36"
  #   incoming_data = msg("8=FIXT.1.1|9=$$$|35=#{@msg_type_sequence_reset}|34=#{msg_seqnum}|" <>
  #     "49=SELLSIDE|52=20170717-17:50:56.123|56=BUYSIDE|#{tag_new_seq_no}=14|" <>
  #     "123=Y|10=$$$|")
  #   {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert Session.get_status(session) == :online
  #   assert Session.get_in_lastseq(session) == 10

  #   assert length(msgs_to_send) == 1
  #   [resend_req] = msgs_to_send

  #   assert resend_req.seqnum == 6
  #   assert resend_req.msg_type == @msg_type_resend_request
  #   {"7", 11} = :lists.keyfind("7", 1, resend_req.body)
  #   {"16", 12} = :lists.keyfind("16", 1, resend_req.body)

  #   assert Session.get_in_queue_length(session) == 1
  #   [queued_message] = Session.get_in_queue(session)

  #   assert queued_message.valid == true
  #   assert queued_message.seqnum == 13
  #   assert queued_message.msg_type == @msg_type_sequence_reset
  # end

  # test "SeqResetGapFill with NewSeqNo>MsgSeqNum AND MsgSeqNum=Expected (p. 56)", %{config: cfg} do
  #   ## Set expected sequence number = NewSeqNo

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   msg_seqnum = 11
  #   tag_new_seq_no = "36"
  #   incoming_data = msg("8=FIXT.1.1|9=$$$|35=#{@msg_type_sequence_reset}|34=#{msg_seqnum}|" <>
  #     "49=SELLSIDE|52=20170717-17:50:56.123|56=BUYSIDE|#{tag_new_seq_no}=14|" <>
  #     "123=Y|10=$$$|")
  #   {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert Session.get_status(session) == :online
  #   assert Session.get_in_lastseq(session) == 14

  #   assert length(msgs_to_send) == 0
  # end

  # test "SeqResetGapFill w/NewSeqNo>MsgSeqNum AND MsgSeqNum<Expected AND PossDupFlag=Y (p. 56)", %{config: cfg} do
  #   ## Ignore message

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   msg_seqnum = 9
  #   tag_new_seq_no = "36"
  #   incoming_data = msg("8=FIXT.1.1|9=$$$|35=#{@msg_type_sequence_reset}|34=#{msg_seqnum}|" <>
  #     "49=SELLSIDE|43=Y|52=20170717-17:50:56.123|56=BUYSIDE|#{tag_new_seq_no}=14|" <>
  #     "123=Y|10=$$$|")
  #   {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert Session.get_status(session) == :online
  #   assert Session.get_in_lastseq(session) == 10

  #   assert length(msgs_to_send) == 0
  # end

  # test "SeqResetGapFill w/NewSeqNo>MsgSeqNum AND MsgSeqNum<Expected AND PossDupFlag!=Y (p. 56)", %{config: cfg} do
  #   # 1. Send Logout message with text "MsgSeqNum too low, expecting X received Y"
  #   # 2. Optional - Wait for Logout message response (note likely will have inaccurate MsgSeqNum)
  #   #    or wait 2 seconds whichever comes first
  #   # 3. Disconnect
  #   # Error condition

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   msg_seqnum = 9
  #   tag_new_seq_no = "36"
  #   incoming_data = msg("8=FIXT.1.1|9=$$$|35=#{@msg_type_sequence_reset}|34=#{msg_seqnum}|" <>
  #     "49=SELLSIDE|52=20170717-17:50:56.123|56=BUYSIDE|#{tag_new_seq_no}=14|" <>
  #     "123=Y|10=$$$|")
  #   {:logout, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert Session.get_status(session) == :disconnecting
  #   assert length(msgs_to_send) == 1
  #   [logout_msg] = msgs_to_send

  #   assert logout_msg.seqnum == 6
  #   assert logout_msg.msg_type == @msg_type_logout
  #   assert logout_msg.sender == "BUYSIDE"
  #   assert logout_msg.target == "SELLSIDE"
  #   assert logout_msg.orig_sending_time == @t0
  #   assert :lists.keyfind("58", 1, logout_msg.body) ==
  #     {"58", "MsgSeqNum too low, expecting 11 but received 9"}
  # end

  # @tag :try1
  # test "SeqResetGapFill with NewSeqNo<=MsgSeqNum AND MsgSeqNum=Expected (p. 57)", %{config: cfg} do
  #   ## Send Reject (session level) with message: " attempt to lower sequence number, invalid value NewSeqNum={x}"

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   msg_seqnum = 11
  #   tag_new_seq_no = "36"
  #   incoming_data = msg("8=FIXT.1.1|9=$$$|35=#{@msg_type_sequence_reset}|" <>
  #     "34=#{msg_seqnum}|49=SELLSIDE|52=20170717-17:50:56.123|56=BUYSIDE|" <>
  #     "#{tag_new_seq_no}=10|123=Y|10=$$$|")
  #   {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert Session.get_status(session) == :online
  #   assert Session.get_in_lastseq(session) == 10

  #   assert length(msgs_to_send) == 1
  #   [reject_msg] = msgs_to_send

  #   assert reject_msg.seqnum == 6
  #   assert reject_msg.msg_type == @msg_type_reject
  #   assert reject_msg.sender == "BUYSIDE"
  #   assert reject_msg.target == "SELLSIDE"
  #   assert reject_msg.orig_sending_time == @t0
  #   assert :lists.keyfind("58", 1, reject_msg.body) ==
  #     {"58", "Attempt to lower sequence number, invalid value NewSeqNum=10"}
  # end

  # test "Receive SeqReset (reset) with NewSeqNum > than expected seq num (p. 57)", %{config: cfg} do
  #   ## 1. Accept the Sequence Reset (Reset) msg without regards to its MsgSeqNum
  #   ## 2. Set the expected sequence number equal to NewSeqNo

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   msg_seqnum = 11
  #   tag_new_seq_no = "36"
  #   incoming_data = msg("8=FIXT.1.1|9=$$$|35=#{@msg_type_sequence_reset}|" <>
  #     "34=#{msg_seqnum}|49=SELLSIDE|52=20170717-17:50:56.123|56=BUYSIDE|" <>
  #     "#{tag_new_seq_no}=15|10=$$$|")
  #   {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert Session.get_status(session) == :online
  #   assert Session.get_in_lastseq(session) == 14
  #   assert length(msgs_to_send) == 0
  # end

  # test "Receive SeqReset (reset) with NewSeqNum = than expected seq num (p. 57)", %{config: cfg} do
  #   ## 1. Accept the Sequence Reset (Reset) msg without regards to its MsgSeqNum
  #   ## Warning condition

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   msg_seqnum = 11
  #   tag_new_seq_no = "36"
  #   incoming_data = msg("8=FIXT.1.1|9=$$$|35=#{@msg_type_sequence_reset}|" <>
  #     "34=#{msg_seqnum}|49=SELLSIDE|52=20170717-17:50:56.123|56=BUYSIDE|" <>
  #     "#{tag_new_seq_no}=11|10=$$$|")
  #   {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert Session.get_status(session) == :online
  #   assert Session.get_in_lastseq(session) == 10
  #   assert length(msgs_to_send) == 0
  # end

  # test "Receive SeqReset (reset) with NewSeqNum < than expected seq num (p. 57)", %{config: cfg} do
  #   ## 1. Accept the Sequence Reset (Reset) msg without regards to its MsgSeqNum
  #   ## 2. Send Reject (session level) msg with SessionRejectReason = "Value is incorrect (out of range) for this tag"
  #   ## 3. DO NOT increment inbound MsgSeqNum
  #   ## 4. Error condition
  #   ## 5. DO NOT lower expected sequence number

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   msg_seqnum = 11
  #   tag_new_seq_no = "36"
  #   incoming_data = msg("8=FIXT.1.1|9=$$$|35=#{@msg_type_sequence_reset}|" <>
  #     "34=#{msg_seqnum}|49=SELLSIDE|52=20170717-17:50:56.123|56=BUYSIDE|" <>
  #     "#{tag_new_seq_no}=9|10=$$$|")
  #   {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert Session.get_status(session) == :online
  #   assert Session.get_in_lastseq(session) == 10
  #   assert length(msgs_to_send) == 1

  #   [reject_msg] = msgs_to_send

  #   assert reject_msg.seqnum == 6
  #   assert reject_msg.msg_type == @msg_type_reject
  #   assert reject_msg.sender == "BUYSIDE"
  #   assert reject_msg.target == "SELLSIDE"
  #   assert reject_msg.orig_sending_time == @t0
  #   assert :lists.keyfind("58", 1, reject_msg.body) ==
  #     {"58", "Value is incorrect (out of range) for this tag"}
  # end

  # test "Initiate Logout (p. 58)", %{config: cfg} do
  #   ## 1. Send Logout message
  #   ## 2. Wait for Logout message response up to 10 seconds. If not received => Warning condition
  #   ## 3. Disconnect

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   {:logout_and_wait, msgs_to_send, session} = Session.session_stop(session)

  #   assert Session.get_status(session) == :disconnecting
  #   assert length(msgs_to_send) == 1

  #   [logout] = msgs_to_send

  #   assert logout.seqnum == 6
  #   assert logout.msg_type == @msg_type_logout
  #   assert logout.sender == "BUYSIDE"
  #   assert logout.target == "SELLSIDE"
  # end

  # test "Receive valid Logout message in response to a solicited logout process (p. 58)", %{config: cfg} do
  #   ## Disconnect without sending a message

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :disconnecting, in_lastseq: 10, out_lastseq: 5}

  #   msg_seqnum = 11
  #   incoming_data = msg("8=FIXT.1.1|9=$$$|35=#{@msg_type_logout}|" <>
  #     "34=#{msg_seqnum}|49=SELLSIDE|52=20170717-17:50:56.123|56=BUYSIDE|10=$$$|")
  #   {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert Session.get_status(session) == :offline
  #   assert length(msgs_to_send) == 0
  # end

  # test "Receive valid Logout message unsolicited (p. 58)", %{config: cfg} do
  #   ## 1. Send Logout response message
  #   ## 2. Wait for counterparty to disconnect up to 10 seconds. If max exceeded, disconnect and 'Error condition'

  #   {:ok, session} = Session.init(cfg)
  #   session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

  #   msg_seqnum = 11
  #   incoming_data = msg("8=FIXT.1.1|9=$$$|35=#{@msg_type_logout}|" <>
  #     "34=#{msg_seqnum}|49=SELLSIDE|52=20170717-17:50:56.123|56=BUYSIDE|10=$$$|")
  #   {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

  #   assert Session.get_status(session) == :disconnecting
  #   assert length(msgs_to_send) == 1

  #   [logout] = msgs_to_send

  #   assert logout.seqnum == 6
  #   assert logout.msg_type == @msg_type_logout
  #   assert logout.sender == "BUYSIDE"
  #   assert logout.target == "SELLSIDE"
  # end
end
