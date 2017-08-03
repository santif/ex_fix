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
  @field_begin_seq_no 7
  @field_end_seq_no 16
  @field_new_seq_no 36
  @field_gap_fill 123

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

  test "Execution Report received", %{config: cfg} do
    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}
    incoming_data = build_message(@msg_type_execution_report, 11, "SELLSIDE", "BUYSIDE",
      @t_plus_1, [{@field_account, "1234"}])
    session = Session.set_time(session, @t_plus_1)
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)
    assert Session.get_status(session) == :online
    assert Session.get_in_lastseq(session) == 11
    assert msgs_to_send == []
  end

  test "Execution Report - fragmented", %{config: cfg} do
    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}
    assert byte_size(Session.get_extra_bytes(session)) == 0

    seq = 11
    incoming_data = msg("8=FIXT.1.1|9=$$$|35=8|34=#{seq}|49=SELLSIDE|52=20161007-16:28:50.802|" <>
      "56=BUYSIDE|1=1557|6=18050.000|11=clordid12345|14=5|17=T3231110|31=18050|" <>
      "32=5|37=76733014|38=5|39=2|40=2|44=18050|54=1|55=Symbol1|58=Filled|59=0|" <>
      "60=20161007-16:28:50.796|150=F|151=0|207=MARKET|453=1|448=|447=D|452=11|10=$$$|")
    << seg1::binary-size(100), seg2::binary-size(100), seg3::binary() >> = incoming_data

    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, seg1)
    assert msgs_to_send == []
    assert Session.get_status(session) == :online
    assert byte_size(Session.get_extra_bytes(session)) == 100

    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, seg2)
    assert msgs_to_send == []
    assert Session.get_status(session) == :online
    assert byte_size(Session.get_extra_bytes(session)) == 200

    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, seg3)
    assert msgs_to_send == []
    assert Session.get_status(session) == :online
    assert Session.get_in_lastseq(session) == 11
    assert byte_size(Session.get_extra_bytes(session)) == 0
  end

  test "Receiving multiple messages in a single segment", %{config: cfg} do
    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}
    assert byte_size(Session.get_extra_bytes(session)) == 0

    seq = 11
    incoming_data1 = msg("8=FIXT.1.1|9=$$$|35=8|34=#{seq}|49=SELLSIDE|52=20161007-16:28:50.802|" <>
      "56=BUYSIDE|1=1557|6=18050.000|11=clordid12345|14=5|17=T3231110|31=18050|" <>
      "32=5|37=76733014|38=5|39=2|40=2|44=18050|54=1|55=Symbol1|58=Filled|59=0|" <>
      "60=20161007-16:28:50.796|150=F|151=0|207=MARKET|453=1|448=|447=D|452=11|10=$$$|")
    seq = 12
    incoming_data2 = msg("8=FIXT.1.1|9=$$$|35=8|34=#{seq}|49=SELLSIDE|52=20161007-16:28:50.803|" <>
      "56=BUYSIDE|1=1558|6=18050.000|11=clordid12345|14=5|17=T3231110|31=18050|" <>
      "32=5|37=76733014|38=5|39=2|40=2|44=18050|54=1|55=Symbol1|58=Filled|59=0|" <>
      "60=20161007-16:28:50.796|150=F|151=0|207=MARKET|453=1|448=|447=D|452=11|10=$$$|")
    incoming_data = << incoming_data1::binary(), incoming_data2::binary() >>

    {:continue, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)
    assert msgs_to_send == []
    assert Session.get_status(session) == :online
    assert Session.get_extra_bytes(session) != ""
    assert Session.get_in_lastseq(session) == 11

    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, "")
    assert msgs_to_send == []
    assert Session.get_status(session) == :online
    assert Session.get_extra_bytes(session) == ""
    assert Session.get_in_lastseq(session) == 12
  end

  test "Receiving 1.5 messages in a segment", %{config: cfg} do
    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}
    assert byte_size(Session.get_extra_bytes(session)) == 0

    seq = 11
    msg1 = msg("8=FIXT.1.1|9=$$$|35=8|34=#{seq}|49=SELLSIDE|52=20161007-16:28:50.802|" <>
      "56=BUYSIDE|1=1557|6=18050.000|11=clordid12345|14=5|17=T3231110|31=18050|" <>
      "32=5|37=76733014|38=5|39=2|40=2|44=18050|54=1|55=Symbol1|58=Filled|59=0|" <>
      "60=20161007-16:28:50.796|150=F|151=0|207=MARKET|453=1|448=|447=D|452=11|10=$$$|")
    seq = 12
    msg2 = msg("8=FIXT.1.1|9=$$$|35=8|34=#{seq}|49=SELLSIDE|52=20161007-16:28:50.803|" <>
      "56=BUYSIDE|1=1558|6=18050.000|11=clordid12345|14=5|17=T3231110|31=18050|" <>
      "32=5|37=76733014|38=5|39=2|40=2|44=18050|54=1|55=Symbol1|58=Filled|59=0|" <>
      "60=20161007-16:28:50.796|150=F|151=0|207=MARKET|453=1|448=|447=D|452=11|10=$$$|")

    << seg1::binary-size(100), incoming_data2::binary() >> = msg2
    incoming_data1 = << msg1::binary(), seg1::binary() >>

    {:continue, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data1)
    assert msgs_to_send == []
    assert Session.get_status(session) == :online
    assert Session.get_extra_bytes(session) != ""
    assert Session.get_in_lastseq(session) == 11

    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, "")
    assert msgs_to_send == []
    assert Session.get_status(session) == :online
    assert Session.get_extra_bytes(session) != ""
    assert Session.get_in_lastseq(session) == 11

    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data2)
    assert msgs_to_send == []
    assert Session.get_status(session) == :online
    assert Session.get_extra_bytes(session) == ""
    assert Session.get_in_lastseq(session) == 12
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

    incoming_data = "garbled_garbled_garbled_garbled_garbled"
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

  test "PossDupFlag=Y, OrigSendingTime > SendingTime and MsgSeqNum=Expected (p. 50)", %{config: cfg} do
    # 1. Send Reject (session-level) message referencing inaccurate SendingTime: "SendingTime acccuracy problem")
    # 2. Increment inbound MsgSeqNum
    # 3. Optional flow - send Logout - p. 50

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    seq = 11
    resend = true
    orig_sending_time = @t_plus_2
    incoming_data = build_message(@msg_type_execution_report, seq, "SELLSIDE", "BUYSIDE",
      @t_plus_1, [{@field_account, "1234"}], orig_sending_time, resend)
    session = Session.set_time(session, @t_plus_1)
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :online
    assert Session.get_in_lastseq(session) == 11

    assert length(msgs_to_send) == 1
    [reject_msg] = msgs_to_send

    assert reject_msg.seqnum == 6
    assert reject_msg.msg_type == @msg_type_reject
    assert reject_msg.sender == "BUYSIDE"
    assert reject_msg.target == "SELLSIDE"
    assert reject_msg.orig_sending_time == @t_plus_1
    assert :lists.keyfind("373", 1, reject_msg.body) == {"373", "10"}
    assert :lists.keyfind("58", 1, reject_msg.body) == {"58", "SendingTime acccuracy problem"}
  end

  test "PossDupFlag=Y and OrigSendingTime not specified (p. 51)", %{config: cfg} do
    # 1. Send Reject (session-level) with SessionRejectReason = "Required tag missing")
    # 2. Increment inbound MsgSeqNum

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    msg_seqnum = 11
    poss_dup_flag = "Y"
    ## TODO replace all hardcoded datetimes with DateUtil.serialize_date
    incoming_data = msg("8=FIXT.1.1|9=$$$|35=8|34=#{msg_seqnum}|49=SELLSIDE|" <>
      "43=#{poss_dup_flag}|52=20170717-17:50:56.123|56=BUYSIDE|1=1234|10=$$$|")
    session = Session.set_time(session, @t_plus_1)
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :online
    assert Session.get_in_lastseq(session) == 11

    assert length(msgs_to_send) == 1
    [reject_msg] = msgs_to_send

    assert reject_msg.seqnum == 6
    assert reject_msg.msg_type == @msg_type_reject
    assert reject_msg.sender == "BUYSIDE"
    assert reject_msg.target == "SELLSIDE"
    assert reject_msg.orig_sending_time == @t_plus_1
    assert :lists.keyfind("373", 1, reject_msg.body) == {"373", "1"}
    assert :lists.keyfind("58", 1, reject_msg.body) == {"58", "Required tag missing: OrigSendingTime"}
  end

  test "BeginString value received did not match value expected (p. 51)", %{config: cfg} do
    # 1. Send Logout message referencing incorrect BeginString value
    # 2. Optional - Wait for Logout message response (note likely will have incorrect BeginString)
    #    or wait 2 seconds whichever comes first
    # 3. Disconnect

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    msg_seqnum = 11
    incoming_data = msg("8=INCORRECT_BEGIN_STRING|9=$$$|35=8|34=#{msg_seqnum}|49=SELLSIDE|" <>
      "52=20170717-17:50:56.123|56=BUYSIDE|1=1234|10=$$$|")
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
    assert :lists.keyfind("58", 1, logout.body) == {"58", "Incorrect BeginString value"}
  end

  test "Unexpected SenderCompID", %{config: cfg} do
    # 1. Send Reject (session-level) with SessionRejectReason = "CompID problem")
    # 2. Increment inbound MsgSeqNum
    # 3. Send Logout message referencing incorrect SenderCompID or TargetCompID value
    # 4. Optional - Wait for Logout message response (note likely will have incorrect SenderCompID or TargetCompID)
    #    or wait 2 seconds whichever comes first
    # 5. Disconnect
    # Error condition

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    seq = 11
    incoming_data = build_message(@msg_type_execution_report, seq, "OTHER_SELLSIDE", "BUYSIDE",
      @t_plus_1, [{@field_account, "1234"}])
    session = Session.set_time(session, @t_plus_1)
    {:logout, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :disconnecting

    assert length(msgs_to_send) == 2
    [reject_msg, logout_msg] = msgs_to_send

    assert reject_msg.seqnum == 6
    assert reject_msg.msg_type == @msg_type_reject
    assert reject_msg.sender == "BUYSIDE"
    assert reject_msg.target == "SELLSIDE"
    assert reject_msg.orig_sending_time == @t_plus_1
    assert :lists.keyfind("373", 1, reject_msg.body) == {"373", "9"}
    assert :lists.keyfind("58", 1, reject_msg.body) == {"58", "CompID problem"}

    assert logout_msg.seqnum == 7
    assert logout_msg.msg_type == @msg_type_logout
    assert logout_msg.sender == "BUYSIDE"
    assert logout_msg.target == "SELLSIDE"
    assert logout_msg.orig_sending_time == @t_plus_1
    assert :lists.keyfind("58", 1, logout_msg.body) == {"58", "Incorrect SenderCompID value"}
  end

  test "Unexpected TargetCompID", %{config: cfg} do
    # 1. Send Reject (session-level) with SessionRejectReason = "CompID problem")
    # 2. Increment inbound MsgSeqNum
    # 3. Send Logout message referencing incorrect SenderCompID or TargetCompID value
    # 4. Optional - Wait for Logout message response (note likely will have incorrect SenderCompID or TargetCompID)
    #    or wait 2 seconds whichever comes first
    # 5. Disconnect
    # Error condition

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    seq = 11
    incoming_data = build_message(@msg_type_execution_report, seq, "SELLSIDE", "OTHER_BUYSIDE",
      @t_plus_1, [{@field_account, "1234"}])
    session = Session.set_time(session, @t_plus_1)
    {:logout, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :disconnecting

    assert length(msgs_to_send) == 2
    [reject_msg, logout_msg] = msgs_to_send

    assert reject_msg.seqnum == 6
    assert reject_msg.msg_type == @msg_type_reject
    assert reject_msg.sender == "BUYSIDE"
    assert reject_msg.target == "SELLSIDE"
    assert reject_msg.orig_sending_time == @t_plus_1
    assert :lists.keyfind("373", 1, reject_msg.body) == {"373", "9"}
    assert :lists.keyfind("58", 1, reject_msg.body) == {"58", "CompID problem"}

    assert logout_msg.seqnum == 7
    assert logout_msg.msg_type == @msg_type_logout
    assert logout_msg.sender == "BUYSIDE"
    assert logout_msg.target == "SELLSIDE"
    assert logout_msg.orig_sending_time == @t_plus_1
    assert :lists.keyfind("58", 1, logout_msg.body) == {"58", "Incorrect TargetCompID value"}
  end

  test "BodyLength value received is not correct (p. 52)", %{config: cfg} do
    # Ignore message - don't increment expected MsgSeqNum
    # Warning condition

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    msg_seqnum = 11
    incorrect_body_length = 5
    incoming_data = msg("8=FIXT.1.1|9=#{incorrect_body_length}|35=8|34=#{msg_seqnum}|49=SELLSIDE|" <>
      "52=20170717-17:50:56.123|56=BUYSIDE|1=1234|10=$$$|")
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :online

    assert length(msgs_to_send) == 0
  end

  test "Checksum error (p. 55)", %{config: cfg} do
    # > CheckSum error is not the last field of message, value doesn't have length of 3, or isn't delimited by SOH
    # Ignore message - don't increment expected MsgSeqNum
    # Warning condition

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    msg_seqnum = 11
    incoming_data = msg("8=FIXT.1.1|9=$$$|35=8|34=#{msg_seqnum}|49=SELLSIDE|" <>
      "52=20170717-17:50:56.123|56=BUYSIDE|10=ERR")
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :online
    assert Session.get_in_lastseq(session) == 10
    assert length(msgs_to_send) == 0
  end

  test "A Test Request message is received (p. 55)", %{config: cfg} do
    # Send Hearbeat message with Test Request message's TestReqID
    # Warning condition

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    seq = 11
    incoming_data = build_message(@msg_type_test_request, seq, "SELLSIDE", "BUYSIDE", @t_plus_1)
    session = Session.set_time(session, @t_plus_1)
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :online

    assert length(msgs_to_send) == 1
    [hb_msg] = msgs_to_send

    assert hb_msg.seqnum == 6
    assert hb_msg.msg_type == @msg_type_heartbeat
    assert hb_msg.sender == "BUYSIDE"
    assert hb_msg.target == "SELLSIDE"
    assert hb_msg.orig_sending_time == @t_plus_1
  end

  test "No data received during (HeartBeatInt field + 20%) interval (p. 55)", %{config: cfg} do
    # Send Test Request message
    # Track and verify that a Heartbeat with the same TestReqID is received (may not be the next message received)

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    {:ok, msgs_to_send, session} = Session.handle_timeout(session, :rx)

    assert Session.get_status(session) == :online

    assert length(msgs_to_send) == 1
    [test_msg] = msgs_to_send

    assert test_msg.seqnum == 6
    assert test_msg.msg_type == @msg_type_test_request
    assert test_msg.sender == "BUYSIDE"
    assert test_msg.target == "SELLSIDE"
    assert test_msg.orig_sending_time == @t0
    {"112", test_req_id} = :lists.keyfind("112", 1, test_msg.body)

    assert Session.get_last_test_req_id(session) == test_req_id

    {:logout, [logout_msg], session} = Session.handle_timeout(session, :rx)

    assert Session.get_status(session) == :disconnecting
    assert logout_msg.seqnum == 7
    assert logout_msg.msg_type == @msg_type_logout

    assert Session.get_last_test_req_id(session) == nil
  end

  test "Valid Resend Request (p. 55)", %{config: cfg} do
    ## Respond with application level messages and SequenceReset-Gap-Fill for admin messages requested
    ## range according to "Message Recovery rules"

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 1, out_lastseq: 1}

    fields = [{"1", 100}, {"55", "ABC1"}, {"44", 4.56}]
    {:ok, _, session} = Session.send_message(session, "D", [{1, "acc1"}] ++ fields) # seqnum 2
    {:ok, _, session} = Session.send_message(session, "D", [{1, "acc1"}] ++ fields) # seqnum 3
    {:ok, _, session} = Session.send_message(session, "0", []) # seqnum 4 (heartbeat)
    {:ok, _, session} = Session.send_message(session, "D", [{1, "acc1"}] ++ fields) # seqnum 5

    seq = 2
    incoming_data = build_message(@msg_type_resend_request, seq, "SELLSIDE", "BUYSIDE", @t_plus_1,
      [{@field_begin_seq_no, 2}, {@field_end_seq_no, 5}])
    session = Session.set_time(session, @t_plus_1)
    {:resend, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :online
    assert Session.get_in_lastseq(session) == 2

    assert length(msgs_to_send) == 4
    [msg1, msg2, msg3, msg4] = msgs_to_send

    assert msg1.msg_type == @msg_type_new_order_single
    assert msg1.seqnum == 2

    assert msg2.msg_type == @msg_type_new_order_single
    assert msg2.seqnum == 3

    assert msg3.msg_type == @msg_type_sequence_reset
    assert msg3.seqnum == 4
    {_, true} = :lists.keyfind("#{@field_gap_fill}", 1, msg3.body)
    {_, 4} = :lists.keyfind("#{@field_new_seq_no}", 1, msg3.body)

    assert msg4.msg_type == @msg_type_new_order_single
    assert msg4.seqnum == 5
  end

  test "SeqResetGapFill with NewSeqNo>MsgSeqNum AND MsgSeqNum>Expected (p. 56)", %{config: cfg} do
    ## Issue Resend Request to fill gap between last expected MsgSeqNum and received MsgSeqNum

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    seq = 13
    new_seq_no = 14
    gap_fill = true
    incoming_data = build_message(@msg_type_sequence_reset, seq, "SELLSIDE", "BUYSIDE", @t_plus_1,
      [{@field_new_seq_no, new_seq_no}, {@field_gap_fill, gap_fill}])
    session = Session.set_time(session, @t_plus_1)
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :online
    assert Session.get_in_lastseq(session) == 10

    assert length(msgs_to_send) == 1
    [resend_req] = msgs_to_send

    assert resend_req.seqnum == 6
    assert resend_req.msg_type == @msg_type_resend_request
    {"7", 11} = :lists.keyfind("7", 1, resend_req.body)
    {"16", 12} = :lists.keyfind("16", 1, resend_req.body)

    assert Session.get_in_queue_length(session) == 1
    [queued_message] = Session.get_in_queue(session)

    assert queued_message.valid == true
    assert queued_message.seqnum == 13
    assert queued_message.msg_type == @msg_type_sequence_reset
  end

  test "SeqResetGapFill with NewSeqNo>MsgSeqNum AND MsgSeqNum=Expected (p. 56)", %{config: cfg} do
    ## Set expected sequence number = NewSeqNo

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    seq = 11
    new_seq_no = 14
    gap_fill = true
    incoming_data = build_message(@msg_type_sequence_reset, seq, "SELLSIDE", "BUYSIDE", @t_plus_1,
      [{@field_new_seq_no, new_seq_no}, {@field_gap_fill, gap_fill}])
    session = Session.set_time(session, @t_plus_1)
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :online
    assert Session.get_in_lastseq(session) == 14

    assert length(msgs_to_send) == 0
  end

    test "SeqResetGapFill w/NewSeqNo>MsgSeqNum AND MsgSeqNum<Expected AND PossDupFlag=Y (p. 56)", %{config: cfg} do
      ## Ignore message

      {:ok, session} = Session.init(cfg)
      session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

      seq = 9
      new_seq_no = 14
      gap_fill = true
      resend = true
      incoming_data = build_message(@msg_type_sequence_reset, seq, "SELLSIDE", "BUYSIDE", @t_plus_1,
        [{@field_new_seq_no, new_seq_no}, {@field_gap_fill, gap_fill}], @t_plus_1, resend)
      session = Session.set_time(session, @t_plus_1)
      {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

      assert Session.get_status(session) == :online
      assert Session.get_in_lastseq(session) == 10

      assert length(msgs_to_send) == 0
    end

  test "SeqResetGapFill w/NewSeqNo>MsgSeqNum AND MsgSeqNum<Expected AND PossDupFlag!=Y (p. 56)", %{config: cfg} do
    # 1. Send Logout message with text "MsgSeqNum too low, expecting X received Y"
    # 2. Optional - Wait for Logout message response (note likely will have inaccurate MsgSeqNum)
    #    or wait 2 seconds whichever comes first
    # 3. Disconnect
    # Error condition

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    seq = 9
    new_seq_no = 14
    gap_fill = true
    incoming_data = build_message(@msg_type_sequence_reset, seq, "SELLSIDE", "BUYSIDE", @t0,
      [{@field_new_seq_no, new_seq_no}, {@field_gap_fill, gap_fill}])
    session = Session.set_time(session, @t_plus_1)
    {:logout, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :disconnecting
    assert length(msgs_to_send) == 1
    [logout_msg] = msgs_to_send

    assert logout_msg.seqnum == 6
    assert logout_msg.msg_type == @msg_type_logout
    assert logout_msg.sender == "BUYSIDE"
    assert logout_msg.target == "SELLSIDE"
    assert logout_msg.orig_sending_time == @t_plus_1
    assert :lists.keyfind("58", 1, logout_msg.body) ==
      {"58", "MsgSeqNum too low, expecting 11 but received 9"}
  end

  test "SeqResetGapFill with NewSeqNo<=MsgSeqNum AND MsgSeqNum=Expected (p. 57)", %{config: cfg} do
    ## Send Reject (session level) with message: " attempt to lower sequence number, invalid value NewSeqNum={x}"

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    seq = 11
    new_seq_no = 10
    gap_fill = true
    incoming_data = build_message(@msg_type_sequence_reset, seq, "SELLSIDE", "BUYSIDE", @t0,
      [{@field_new_seq_no, new_seq_no}, {@field_gap_fill, gap_fill}])
    session = Session.set_time(session, @t_plus_1)
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :online
    assert Session.get_in_lastseq(session) == 10

    assert length(msgs_to_send) == 1
    [reject_msg] = msgs_to_send

    assert reject_msg.seqnum == 6
    assert reject_msg.msg_type == @msg_type_reject
    assert reject_msg.sender == "BUYSIDE"
    assert reject_msg.target == "SELLSIDE"
    assert reject_msg.orig_sending_time == @t_plus_1
    assert :lists.keyfind("58", 1, reject_msg.body) ==
      {"58", "Attempt to lower sequence number, invalid value NewSeqNum=10"}
  end

  test "Receive SeqReset (reset) with NewSeqNum > than expected seq num (p. 57)", %{config: cfg} do
    ## 1. Accept the Sequence Reset (Reset) msg without regards to its MsgSeqNum
    ## 2. Set the expected sequence number equal to NewSeqNo

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    seq = 11
    new_seq_no = 15
    incoming_data = build_message(@msg_type_sequence_reset, seq, "SELLSIDE", "BUYSIDE", @t0,
      [{@field_new_seq_no, new_seq_no}])
    session = Session.set_time(session, @t_plus_1)
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :online
    assert Session.get_in_lastseq(session) == 14
    assert length(msgs_to_send) == 0
  end

  test "Receive SeqReset (reset) with NewSeqNum = than expected seq num (p. 57)", %{config: cfg} do
    ## 1. Accept the Sequence Reset (Reset) msg without regards to its MsgSeqNum
    ## Warning condition

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    seq = 11
    new_seq_no = 11
    incoming_data = build_message(@msg_type_sequence_reset, seq, "SELLSIDE", "BUYSIDE", @t0,
      [{@field_new_seq_no, new_seq_no}])
    session = Session.set_time(session, @t_plus_1)
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :online
    assert Session.get_in_lastseq(session) == 10
    assert length(msgs_to_send) == 0
  end

  test "Receive SeqReset (reset) with NewSeqNum < than expected seq num (p. 57)", %{config: cfg} do
    ## 1. Accept the Sequence Reset (Reset) msg without regards to its MsgSeqNum
    ## 2. Send Reject (session level) msg with SessionRejectReason = "Value is incorrect (out of range) for this tag"
    ## 3. DO NOT increment inbound MsgSeqNum
    ## 4. Error condition
    ## 5. DO NOT lower expected sequence number

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    seq = 11
    new_seq_no = 9
    incoming_data = build_message(@msg_type_sequence_reset, seq, "SELLSIDE", "BUYSIDE", @t0,
      [{@field_new_seq_no, new_seq_no}])
    session = Session.set_time(session, @t_plus_1)
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :online
    assert Session.get_in_lastseq(session) == 10
    assert length(msgs_to_send) == 1

    [reject_msg] = msgs_to_send

    assert reject_msg.seqnum == 6
    assert reject_msg.msg_type == @msg_type_reject
    assert reject_msg.sender == "BUYSIDE"
    assert reject_msg.target == "SELLSIDE"
    assert reject_msg.orig_sending_time == @t_plus_1
    assert :lists.keyfind("58", 1, reject_msg.body) ==
      {"58", "Value is incorrect (out of range) for this tag"}
  end

  test "Initiate Logout (p. 58)", %{config: cfg} do
    ## 1. Send Logout message
    ## 2. Wait for Logout message response up to 10 seconds. If not received => Warning condition
    ## 3. Disconnect

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    {:logout_and_wait, msgs_to_send, session} = Session.session_stop(session)

    assert Session.get_status(session) == :disconnecting
    assert length(msgs_to_send) == 1

    [logout] = msgs_to_send

    assert logout.seqnum == 6
    assert logout.msg_type == @msg_type_logout
    assert logout.sender == "BUYSIDE"
    assert logout.target == "SELLSIDE"
  end

  test "Receive valid Logout message in response to a solicited logout process (p. 58)", %{config: cfg} do
    ## Disconnect without sending a message

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :disconnecting, in_lastseq: 10, out_lastseq: 5}

    seq = 11
    incoming_data = build_message(@msg_type_logout, seq, "SELLSIDE", "BUYSIDE", @t_plus_1)
    session = Session.set_time(session, @t_plus_1)
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :offline
    assert length(msgs_to_send) == 0
  end

  test "Receive valid Logout message unsolicited (p. 58)", %{config: cfg} do
    ## 1. Send Logout response message
    ## 2. Wait for counterparty to disconnect up to 10 seconds. If max exceeded, disconnect and 'Error condition'

    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    seq = 11
    incoming_data = build_message(@msg_type_logout, seq, "SELLSIDE", "BUYSIDE", @t_plus_1)
    session = Session.set_time(session, @t_plus_1)
    {:ok, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :disconnecting
    assert length(msgs_to_send) == 1

    [logout] = msgs_to_send

    assert logout.seqnum == 6
    assert logout.msg_type == @msg_type_logout
    assert logout.sender == "BUYSIDE"
    assert logout.target == "SELLSIDE"
  end

  test "Resend messages: replace administrative messages with Sequence Reset messages (1)", %{config: cfg} do
    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 5}

    out_messages = [{1, %MessageToSend{seqnum: 1, msg_type: @msg_type_logon,
      sender: "BUYSIDE", target: "SELLSIDE", orig_sending_time: @t0, body: []}}]
    session = Session.set_out_queue(session, out_messages)

    seq = 11
    incoming_data = build_message(@msg_type_resend_request, seq, "SELLSIDE", "BUYSIDE", @t_plus_1,
      [{@field_begin_seq_no, 1}, {@field_end_seq_no, 0}])
    session = Session.set_time(session, @t_plus_1)
    {:resend, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :online
    assert Session.get_in_lastseq(session) == 11

    assert length(msgs_to_send) == 1
    [msg] = msgs_to_send

    assert msg.msg_type == @msg_type_sequence_reset
    assert msg.seqnum == 1
  end

  test "Resend messages: replace administrative messages with Sequence Reset messages (2)", %{config: cfg} do
    {:ok, session} = Session.init(cfg)
    session = %Session{session | status: :online, in_lastseq: 10, out_lastseq: 8}

    out_messages = [
      {3, %MessageToSend{seqnum: 3, msg_type: @msg_type_heartbeat}},
      {4, %MessageToSend{seqnum: 4, msg_type: @msg_type_reject}},
      {5, %MessageToSend{seqnum: 5, msg_type: @msg_type_test_request}},
      {6, %MessageToSend{seqnum: 6, msg_type: @msg_type_sequence_reset}},
      {7, %MessageToSend{seqnum: 7, msg_type: @msg_type_resend_request}},
      {8, %MessageToSend{seqnum: 8, msg_type: @msg_type_logout}},
    ]
    session = Session.set_out_queue(session, out_messages)

    seq = 11
    incoming_data = build_message(@msg_type_resend_request, seq, "SELLSIDE", "BUYSIDE", @t_plus_1,
      [{@field_begin_seq_no, 3}, {@field_end_seq_no, 0}])
    session = Session.set_time(session, @t_plus_1)
    {:resend, msgs_to_send, session} = Session.handle_incoming_data(session, incoming_data)

    assert Session.get_status(session) == :online
    assert Session.get_in_lastseq(session) == 11

    assert length(msgs_to_send) == 6
    [msg3, msg4, msg5, msg6, msg7, msg8] = msgs_to_send

    assert msg3.msg_type == @msg_type_sequence_reset
    assert msg3.seqnum == 3
    assert msg4.msg_type == @msg_type_sequence_reset
    assert msg4.seqnum == 4
    assert msg5.msg_type == @msg_type_sequence_reset
    assert msg5.seqnum == 5
    assert msg6.msg_type == @msg_type_sequence_reset
    assert msg6.seqnum == 6
    assert msg7.msg_type == @msg_type_sequence_reset
    assert msg7.seqnum == 7
    assert msg8.msg_type == @msg_type_sequence_reset
    assert msg8.seqnum == 8
  end
end
