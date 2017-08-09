defmodule ExFix.Session do
  @moduledoc """
  FIX session protocol implementation
  """

  require Logger
  alias ExFix.Session
  alias ExFix.Parser
  alias ExFix.SessionConfig
  alias ExFix.InMessage
  alias ExFix.OutMessage
  alias ExFix.Session.MessageToSend

  @compile {:inline, process_valid_message: 4}

  @type session_name :: String.t
  @type fix_field :: {String.t, any()}
  @type session_status :: :offline | :connecting | :online | :disconnecting
  @type session_result :: {:ok, [MessageToSend.t], Session.t}
    | {:resend, [MessageToSend.t], Session.t}
    | {:logout, [MessageToSend.t], Session.t}
    | {:stop, Session.t}
  @type session_in_queue :: [InMessage.t]

  ##
  ## Type definitions
  ##

  @type t :: %Session{}
  defstruct config: nil,
    status: :offline,
    in_lastseq: 0,
    out_lastseq: 0,
    extra_bytes: "",
    in_queue: [],
    out_queue: nil,
    last_test_req_id_sent: nil

  defmodule MessageToSend do
    @moduledoc """
    Represents a FIX message sent to counterparty
    """

    defstruct seqnum: 0,
      msg_type: nil,
      sender: nil,
      orig_sending_time: nil,
      target: nil,
      extra_header: [],
      body: []

    @type t :: %__MODULE__{}
  end

  ##
  ## Constants
  ##

  # InMessage types
  @msg_type_logon                  "A"
  @msg_type_heartbeat              "0"
  @msg_type_test_request           "1"
  @msg_type_resend_request         "2"
  @msg_type_reject                 "3"
  @msg_type_sequence_reset         "4"
  @msg_type_logout                 "5"

  # Fields
  @field_poss_dup_flag            "43"
  @field_orig_sending_time       "122"
  @field_sending_time             "52"
  @field_sender_comp_id           "49"
  @field_target_comp_id           "56"
  @field_logon_encrypt_method     "98"
  @field_heart_bt_int            "108"
  @field_reset_on_logon          "141"
  @field_logon_username          "553"
  @field_logon_password          "554"
  @field_default_applverid      "1137"
  @field_begin_seq_no              "7"
  @field_end_seq_no               "16"
  @field_text                     "58"
  @field_session_reject_reason   "373"
  @field_gap_fill                "123"
  @field_new_seq_no               "36"

  ##
  ## API
  ##

  @doc """
  State initialization
  """
  @spec init(SessionConfig.t) :: {:ok, Session.t}
  def init(%SessionConfig{} = config) do
    out_queue_table = :ets.new(:out_queue, [:ordered_set, :private])
    {:ok, %Session{config: config, out_queue: out_queue_table}}
  end

  @doc """
  Returns session's current status (offline, online, connecting, disconnecting). `online` means "logged on".
  """
  @spec get_status(Session.t) :: session_status
  def get_status(%Session{status: status}), do: status

  @doc """
  Returns session's last sequence number accepted
  """
  @spec get_in_lastseq(Session.t) :: non_neg_integer()
  def get_in_lastseq(%Session{in_lastseq: in_lastseq}), do: in_lastseq

  @doc """
  Returns session's extra bytes to be processed with the next segment
  """
  @spec get_extra_bytes(Session.t) :: binary() | nil
  def get_extra_bytes(%Session{extra_bytes: extra_bytes}), do: extra_bytes

  @doc """
  Returns inbound message queue (messages received with high sequence number)
  """
  @spec get_in_queue(Session.t) :: session_in_queue
  def get_in_queue(%Session{in_queue: in_queue}), do: in_queue

  @doc """
  Returns length of inbound message queue
  """
  @spec get_in_queue_length(Session.t) :: non_neg_integer()
  def get_in_queue_length(%Session{in_queue: in_queue}), do: length(in_queue)

  @doc """
  Returns ID of last Test Request sent
  """
  @spec get_last_test_req_id(Session.t) :: String.t | nil
  def get_last_test_req_id(%Session{last_test_req_id_sent: value}), do: value

  @doc """
  Utility function for tests: simulates a certain point in time
  """
  def set_time(%Session{config: config} = session, date_time) do
    %Session{session | config: %SessionConfig{config | time_service: date_time}}
  end

  @doc """
  Utility function for tests: set out_queue to an arbitrary list of messages
  """
  def set_out_queue(%Session{out_queue: out_queue} = session, out_queue_messages) do
    :ets.delete_all_objects(out_queue)
    for {seq, msg} <- out_queue_messages do
      :ets.insert(out_queue, {seq, msg})
    end
    session
  end

  @doc """
  Session start: send Logon msg
  """
  @spec session_start(Session.t) :: session_result
  def session_start(%Session{config: config, out_lastseq: lastseq} = session) do
    %SessionConfig{
      logon_encrypt_method: logon_encrypt_method,
      heart_bt_int: heart_bt_int,
      reset_on_logon: reset_on_logon,
      username: username,
      password: password,
      default_applverid: default_applverid
    } = config
    seqnum = lastseq + 1
    fields = [{@field_logon_encrypt_method, logon_encrypt_method},
              {@field_heart_bt_int, heart_bt_int},
              {@field_reset_on_logon, reset_on_logon},
              {@field_logon_username, username},
              {@field_logon_password, password},
              {@field_default_applverid, default_applverid}]
    logon_msg = build_message(config, @msg_type_logon, seqnum, fields)
    {:ok, [logon_msg], %Session{session | status: :connecting, out_lastseq: seqnum}}
  end

  @doc """
  Session stop
  """
  def session_stop(%Session{config: config, out_lastseq: out_lastseq, status: :online} = session) do
    out_lastseq = out_lastseq + 1
    logout_msg = build_message(config, @msg_type_logout, out_lastseq, [])
    {:logout_and_wait, [logout_msg],
      %Session{session | status: :disconnecting, out_lastseq: out_lastseq}}
  end
  def session_stop(%Session{} = session) do
    {:stop, %Session{session | status: :disconnected}}
  end

  @doc """
  Send application message
  """
  @spec send_message(Session.t, OutMessage.t) :: session_result
  def send_message(%Session{config: config, out_lastseq: out_lastseq,
      out_queue: out_queue} = session, out_message) do
    out_lastseq = out_lastseq + 1
    msg = build_message(config, out_message.msg_type, out_lastseq, out_message.fields)
    :ets.insert(out_queue, {out_lastseq, msg})
    {:ok, [msg], %Session{session | out_lastseq: out_lastseq}}
  end

  @doc """
  Handle incoming binary data
  """
  @spec handle_incoming_data(Session.t, binary()) :: session_result
  def handle_incoming_data(%Session{config: %SessionConfig{name: session_name,
      validate_incoming_message: validate, log_incoming_msg: log_incoming_msg,
      dictionary: dictionary}, extra_bytes: extra_bytes,
      in_lastseq: in_lastseq} = session, data) do

    expected_seqnum = in_lastseq + 1

    msg = Parser.parse1(<< extra_bytes::binary(), data::binary() >>,
      dictionary, expected_seqnum, validate)

    case msg.valid do
      true ->
        if log_incoming_msg do
          Logger.info "[fix.incoming] [#{session_name}] " <>
            :unicode.characters_to_binary(msg.original_fix_msg, :latin1, :utf8)
        end
        process_valid_message(expected_seqnum, session_name, session, msg)
      false ->
        process_invalid_message(session, expected_seqnum, msg)
    end
  end

  @doc """
  Process incoming message
  """
  def process_incoming_message(expected_seqnum, @msg_type_logon = msg_type, session_name,
      %Session{config: config} = session, %InMessage{seqnum: _seqnum} = msg) do
    %SessionConfig{session_handler: session_handler, env: env} = config
    session_handler.on_session_message(session_name, msg_type, msg, env)
    session_handler.on_logon(session_name, env)
    {:ok, [], %Session{session | in_lastseq: expected_seqnum, status: :online,
      extra_bytes: msg.other_msgs}}
  end

  def process_incoming_message(_expected_seqnum, @msg_type_test_request = msg_type, session_name,
      %Session{config: config, out_lastseq: out_lastseq} = session,
      %InMessage{seqnum: seqnum} = msg) do
    %SessionConfig{session_handler: session_handler, env: env} = config
    session_handler.on_session_message(session_name, msg_type, msg, env)
    out_lastseq = out_lastseq + 1
    hb_msg = build_message(config, @msg_type_heartbeat, out_lastseq, [])
    {:ok, [hb_msg], %Session{session | in_lastseq: seqnum, out_lastseq: out_lastseq,
      extra_bytes: msg.other_msgs}}
  end

  def process_incoming_message(expected_seqnum, @msg_type_resend_request = msg_type, session_name,
      %Session{config: config, out_queue: out_queue} = session,
      %InMessage{seqnum: _seqnum, fields: fields} = msg) do
    %SessionConfig{session_handler: session_handler, env: env} = config
    session_handler.on_session_message(session_name, msg_type, msg, env)
    {@field_begin_seq_no, begin_seq} = :lists.keyfind(@field_begin_seq_no, 1, fields)
    {@field_end_seq_no, end_seq} = :lists.keyfind(@field_end_seq_no, 1, fields)
    {begin_seq, _} = Integer.parse(begin_seq)
    {end_seq, _} = Integer.parse(end_seq)
    msgs = resend_messages(out_queue, begin_seq, end_seq)
    {:resend, msgs, %Session{session | in_lastseq: expected_seqnum, extra_bytes: msg.other_msgs}}
  end

  def process_incoming_message(_expected_seqnum, @msg_type_reject = msg_type, session_name,
      %Session{config: config} = session, %InMessage{seqnum: seqnum} = msg) do
    %SessionConfig{session_handler: session_handler, env: env} = config
    session_handler.on_session_message(session_name, msg_type, msg, env)
    Logger.warn fn -> "[fix.warning] [#{session_name}] Reject received: " <>
      :unicode.characters_to_binary(msg.original_fix_msg, :latin1, :utf8) end
    {:ok, [], %Session{session | in_lastseq: seqnum, extra_bytes: msg.other_msgs}}
  end

  def process_incoming_message(expected_seqnum, @msg_type_sequence_reset = msg_type, session_name,
      %Session{config: config} = session, %InMessage{seqnum: seqnum, fields: fields} = msg) do
    %SessionConfig{session_handler: session_handler, env: env} = config
    session_handler.on_session_message(session_name, msg_type, msg, env)
    gap_fill = :lists.keyfind(@field_gap_fill, 1, fields) == {@field_gap_fill, "Y"}
    {@field_new_seq_no, new_seq_no_str} = :lists.keyfind(@field_new_seq_no, 1, fields)
    {new_seq_no, _} = Integer.parse(new_seq_no_str)
    if not gap_fill and new_seq_no == seqnum and expected_seqnum == new_seq_no do
      Logger.warn fn ->
        %Session{config: %SessionConfig{name: session_name}} = session
        "[fix.warning] [#{session_name}] " <>
          "SeqReset GapFill with new_seq_no == seqnum == expected_seqnum: " <>
          :unicode.characters_to_binary(msg.original_fix_msg, :latin1, :utf8)
      end
    end
    process_sequence_reset(gap_fill, new_seq_no, seqnum, expected_seqnum, session)
  end

  def process_incoming_message(_expected_seqnum, @msg_type_logout = msg_type, session_name,
      %Session{config: config, status: :online, out_lastseq: out_lastseq} = session,
      %InMessage{seqnum: seqnum} = msg) do
    %SessionConfig{session_handler: session_handler, env: env} = config
    session_handler.on_session_message(session_name, msg_type, msg, env)
    session_handler.on_logout(session_name, env)
    out_lastseq = out_lastseq + 1
    logout_msg = build_message(config, @msg_type_logout, out_lastseq, [])
    {:ok, [logout_msg], %Session{session | in_lastseq: seqnum,
      status: :disconnecting, extra_bytes: msg.other_msgs}}
  end
  def process_incoming_message(_expected_seqnum, @msg_type_logout = msg_type, session_name,
      %Session{config: config} = session, %InMessage{seqnum: seqnum} = msg) do
    %SessionConfig{session_handler: session_handler, env: env} = config
    session_handler.on_session_message(session_name, msg_type, msg, env)
    session_handler.on_logout(session_name, env)
    {:ok, [], %Session{session | in_lastseq: seqnum, status: :offline,
      extra_bytes: msg.other_msgs}}
  end

  def process_incoming_message(_expected_seqnum, @msg_type_heartbeat = msg_type, session_name,
      %Session{config: config} = session, %InMessage{seqnum: seqnum} = msg) do
    %SessionConfig{session_handler: session_handler, env: env} = config
    session_handler.on_session_message(session_name, msg_type, msg, env)
    {:ok, [], %Session{session | in_lastseq: seqnum, extra_bytes: msg.other_msgs}}
  end

  def process_incoming_message(expected_seqnum, msg_type, session_name,
      %Session{config: config, out_lastseq: out_lastseq} = session,
      %InMessage{poss_dup: false, fields: fields} = msg) do
    %SessionConfig{sender_comp_id: sender_comp_id,
      target_comp_id: target_comp_id, session_handler: session_handler, env: env} = config
    sender = :lists.keyfind(@field_sender_comp_id, 1, fields)
    target = :lists.keyfind(@field_target_comp_id, 1, fields)
    case {sender, target} do
      {{@field_sender_comp_id, ^target_comp_id}, {@field_target_comp_id, ^sender_comp_id}} ->
        ## Valid message
        session_handler.on_app_message(session_name, msg_type, msg, env)
        {:ok, [], %Session{session | in_lastseq: expected_seqnum,
          extra_bytes: msg.other_msgs}}
      _ ->
        invalid_field = case sender do
          {@field_sender_comp_id, ^target_comp_id} -> "TargetCompID"
          _ -> "SenderCompID"
        end
        session_handler.on_logout(session_name, env)
        out_lastseq = out_lastseq + 1
        reject_msg = build_message(config, @msg_type_reject, out_lastseq,
          [{@field_session_reject_reason, "9"},
            {@field_text, "CompID problem"}])
        out_lastseq = out_lastseq + 1
        logout_msg = build_message(config, @msg_type_logout, out_lastseq,
          [{@field_session_reject_reason, "1"},
            {@field_text, "Incorrect #{invalid_field} value"}])
        {:logout, [reject_msg, logout_msg], %Session{session |
          status: :disconnecting, out_lastseq: out_lastseq,
          extra_bytes: msg.other_msgs, in_lastseq: expected_seqnum}}
    end
  end

  def process_incoming_message(_expected_seqnum, msg_type, session_name,
      %Session{config: config, out_lastseq: out_lastseq} = session,
      %InMessage{poss_dup: true, seqnum: seqnum, fields: fields} = msg) do
    case :lists.keyfind(@field_orig_sending_time, 1, fields) do
      {@field_orig_sending_time, orig_sending_time} ->
        {@field_sending_time, sending_time} = :lists.keyfind(@field_sending_time, 1, fields)
        case orig_sending_time <= sending_time do
          true ->
            %SessionConfig{name: session_name, session_handler: session_handler, env: env} = config
            session_handler.on_app_message(session_name, msg_type, msg, env)
            {:ok, [], %Session{session | in_lastseq: seqnum, extra_bytes: msg.other_msgs}}
          false ->
            out_lastseq = out_lastseq + 1
            reject_msg = build_message(config, @msg_type_reject, out_lastseq,
              [{@field_session_reject_reason, "10"}, {@field_text, "SendingTime acccuracy problem"}])
            {:ok, [reject_msg], %Session{session | out_lastseq: out_lastseq, in_lastseq: seqnum,
              extra_bytes: msg.other_msgs}}
        end
      _ ->
        out_lastseq = out_lastseq + 1
        reject_msg = build_message(config, @msg_type_reject, out_lastseq,
          [{@field_session_reject_reason, "1"}, {@field_text, "Required tag missing: OrigSendingTime"}])
        {:ok, [reject_msg], %Session{session | out_lastseq: out_lastseq, in_lastseq: seqnum,
          extra_bytes: msg.other_msgs}}
    end
  end

  @doc """
  Respond to timeout (receiving or transmiting messages)
  """
  @spec handle_timeout(Session.t, term()) :: session_result
  def handle_timeout(%Session{config: config, out_lastseq: out_lastseq,
      last_test_req_id_sent: nil} = session, :rx) do
    out_lastseq = out_lastseq + 1
    test_req_id = generate_id()
    test_msg = build_message(config, @msg_type_test_request, out_lastseq, [
      {"112", test_req_id}])
    {:ok, [test_msg], %Session{session | out_lastseq: out_lastseq,
      last_test_req_id_sent: test_req_id}}
  end
  def handle_timeout(%Session{config: config, out_lastseq: out_lastseq} = session, :rx) do
    out_lastseq = out_lastseq + 1
    text = "Data not received"
    logout_msg = build_message(config, @msg_type_logout, out_lastseq, [{@field_text, text}])
    {:logout, [logout_msg], %Session{session | status: :disconnecting,
      out_lastseq: out_lastseq, last_test_req_id_sent: nil}}
  end
  def handle_timeout(%Session{config: config, out_lastseq: out_lastseq} = session, :tx) do
    out_lastseq = out_lastseq + 1
    hb_msg = build_message(config, @msg_type_heartbeat, out_lastseq, [])
    {:ok, [hb_msg], %Session{session | out_lastseq: out_lastseq}}
  end

  @doc """
  Process valid message
  """
  def process_valid_message(expected_seqnum, session_name, session,
      %InMessage{msg_type: msg_type, other_msgs: ""} = msg) do
    process_incoming_message(expected_seqnum, msg_type, session_name, session, msg)
  end
  def process_valid_message(expected_seqnum, session_name, session,
      %InMessage{msg_type: msg_type} = msg) do
    {result, msgs_to_send, session} = process_incoming_message(
      expected_seqnum, msg_type, session_name, session, msg)
    result2 = case result do
      :ok -> :continue # other_msgs is not empty; continue with next message
      v -> v
    end
    {result2, msgs_to_send, session}
  end

  @doc """
  Process invalid message
  """
  @spec process_invalid_message(Session.t, integer(), InMessage.t) :: session_result
  def process_invalid_message(session, _expected_seqnum, %InMessage{valid: false,
      error_reason: :garbled} = msg) do
    {:ok, [], %Session{session | extra_bytes: msg.other_msgs}}
  end
  def process_invalid_message(%Session{config: config, out_lastseq: out_lastseq} = session,
      _expected_seqnum, %InMessage{valid: false, error_reason: :begin_string_error} = msg) do
    out_lastseq = out_lastseq + 1
    text = "Incorrect BeginString value"
    logout_msg = build_message(config, @msg_type_logout, out_lastseq, [{@field_text, text}])
    {:logout, [logout_msg], %Session{session | status: :disconnecting,
      out_lastseq: out_lastseq, extra_bytes: msg.other_msgs}}
  end
  def process_invalid_message(%Session{config: config, out_lastseq: out_lastseq} = session,
      expected_seqnum, %InMessage{seqnum: seqnum} = msg)
      when is_number(seqnum) and seqnum > expected_seqnum do
    out_lastseq = out_lastseq + 1
    init_gap = expected_seqnum
    end_gap = seqnum - 1
    resend_request = build_message(config, @msg_type_resend_request, out_lastseq, [
      {@field_begin_seq_no, init_gap}, {@field_end_seq_no, end_gap}])
    session = add_to_in_queue(session, msg)
    {:ok, [resend_request], %Session{session | out_lastseq: out_lastseq,
      extra_bytes: msg.other_msgs}}
  end
  def process_invalid_message(%Session{config: config, out_lastseq: out_lastseq} = session,
      expected_seqnum, %InMessage{seqnum: seqnum, fields: fields} = msg)
      when is_number(seqnum) and seqnum < expected_seqnum do
    case :lists.keyfind(@field_poss_dup_flag, 1, fields) do
      {@field_poss_dup_flag, "Y"} ->
        {:ok, [], %Session{session | extra_bytes: msg.other_msgs}}
      _ ->
        out_lastseq = out_lastseq + 1
        text = "MsgSeqNum too low, expecting #{expected_seqnum} but received #{seqnum}"
        logout_msg = build_message(config, @msg_type_logout, out_lastseq, [{@field_text, text}])
        {:logout, [logout_msg],
          %Session{session | status: :disconnecting, out_lastseq: out_lastseq,
            extra_bytes: msg.other_msgs}}
    end
  end

  ##
  ## Private functions
  ##

  defp build_message(config, msg_type, seqnum, body) do
    %SessionConfig{sender_comp_id: sender, target_comp_id: target,
      time_service: time_service} = config
    orig_sending_time = case time_service do
      nil -> DateTime.utc_now()
      {m, f, a} -> :erlang.apply(m, f, a)
      %DateTime{} = v -> v
    end
    %MessageToSend{
      seqnum: seqnum, msg_type: msg_type, sender: sender,
      orig_sending_time: orig_sending_time, target: target, body: body}
  end

  defp add_to_in_queue(%Session{in_queue: in_queue} = session, %InMessage{valid: false,
      error_reason: :unexpected_seqnum} = msg) do
    msg = %InMessage{msg | valid: true, error_reason: nil}
    %Session{session | in_queue: in_queue ++ [msg]}
  end

  defp generate_id(len \\ 16) do
      len
      |> :crypto.strong_rand_bytes()
      |> Base.encode64()
      |> binary_part(0, len)
  end

  defp resend_messages(out_queue, begin_seq, end_seq) do
    guard = case end_seq do
      0 ->
        {:">", :"$2", begin_seq}
      v when v > 0 ->
        {:andalso, {:">=", :"$1", begin_seq}, {:"=<", :"$1", end_seq}}
    end
    spec = [{{:"$1", :"$2"}, [guard], [:"$2"]}]
    for msg <- :ets.select(out_queue, spec), do: get_message_for_resend(msg.msg_type, msg)
  end

  defp get_message_for_resend(@msg_type_logon, msg), do: seq_reset_gap_fill(msg)
  defp get_message_for_resend(@msg_type_heartbeat, msg), do: seq_reset_gap_fill(msg)
  defp get_message_for_resend(@msg_type_test_request, msg), do: seq_reset_gap_fill(msg)
  defp get_message_for_resend(@msg_type_resend_request, msg), do: seq_reset_gap_fill(msg)
  defp get_message_for_resend(@msg_type_reject, msg), do: seq_reset_gap_fill(msg)
  defp get_message_for_resend(@msg_type_sequence_reset, msg), do: seq_reset_gap_fill(msg)
  defp get_message_for_resend(@msg_type_logout, msg), do: seq_reset_gap_fill(msg)
  defp get_message_for_resend(_, msg), do: msg

  defp seq_reset_gap_fill(%MessageToSend{seqnum: seqnum} = msg) do
    %MessageToSend{msg |
      msg_type: @msg_type_sequence_reset,
      extra_header: [],
      body: [
        {@field_new_seq_no, seqnum},
        {@field_gap_fill, true}
      ]}
  end

  defp process_sequence_reset(true = _gap_fill, new_seq_no, seqnum, expected_seqnum, session)
      when new_seq_no > seqnum and expected_seqnum == seqnum do
    {:ok, [], %Session{session | in_lastseq: new_seq_no}}
  end
  defp process_sequence_reset(true = _gap_fill, new_seq_no, seqnum, expected_seqnum,
      %Session{config: config, out_lastseq: out_lastseq} = session)
      when new_seq_no <= seqnum and expected_seqnum == seqnum do
    out_lastseq = out_lastseq + 1
    reject_msg = build_message(config, @msg_type_reject, out_lastseq,
      [{@field_text,
        "Attempt to lower sequence number, invalid value NewSeqNum=#{new_seq_no}"}])
    {:ok, [reject_msg], %Session{session | in_lastseq: new_seq_no}}
  end
  defp process_sequence_reset(false = _gap_fill, new_seq_no, seqnum, expected_seqnum, session)
      when new_seq_no > seqnum and expected_seqnum < new_seq_no do
    {:ok, [], %Session{session | in_lastseq: new_seq_no - 1}}
  end
  defp process_sequence_reset(false = _gap_fill, new_seq_no, seqnum, expected_seqnum, session)
      when new_seq_no == seqnum and expected_seqnum == new_seq_no do
    {:ok, [], %Session{session | in_lastseq: new_seq_no - 1}}
  end
  defp process_sequence_reset(false = _gap_fill, new_seq_no, seqnum, expected_seqnum,
      %Session{config: config, out_lastseq: out_lastseq, in_lastseq: in_lastseq} = session)
      when new_seq_no < seqnum and expected_seqnum > new_seq_no do
    out_lastseq = out_lastseq + 1
    reject_msg = build_message(config, @msg_type_reject, out_lastseq,
      [{@field_session_reject_reason, "5"},
        {@field_text, "Value is incorrect (out of range) for this tag"}])
    {:ok, [reject_msg], %Session{session | in_lastseq: in_lastseq}}
  end
  defp process_sequence_reset(_gap_fill, _new_seq_no, seqnum, _expected_seqnum, session) do
    {:ok, [], %Session{session | in_lastseq: seqnum}}
  end
end
