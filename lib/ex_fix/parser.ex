defmodule ExFix.Parser do
  @moduledoc """
  FIX message parser
  """

  alias ExFix.Types.Message

  @compile {:inline, parse_field: 1}
  @compile {:inline, parse_expected_seqnum: 6}
  @compile {:inline, parse_unexpected_seqnum: 6}
  @soh 1

  @doc """
  Parse full message
  """
  def parse(data, dictionary, expected_seqnum \\ nil, validate \\ true) do
    with %Message{valid: true} = msg1 <- parse1(data, dictionary, expected_seqnum, validate),
         msg2 <- parse2(msg1) do
      msg2
    end
  end

  @doc """
  Parse - stage1
  """
  def parse1(data, dictionary, expected_seqnum \\ nil, validate \\ true)
  def parse1(<<"8=FIXT.1.1", @soh, "9=", rest::binary()>>, dictionary, expected_seqnum, validate) do
    [str_len, rest1] = :binary.split(rest, << @soh >>)
    {len, _} = Integer.parse(str_len)
    case rest1 do
      << body::binary-size(len), "10=", checksum::binary-size(3),
         @soh, other_msgs::binary() >> ->

        orig_msg = << "8=FIXT.1.1", @soh, "9=", str_len::binary(),
          @soh, body::binary(), @soh, "10=", checksum::binary(), @soh >>

        case validate_msg(validate, str_len, body, checksum) do
          true ->
            parse_message(rest1, expected_seqnum, orig_msg, dictionary, other_msgs)

          false ->
            %Message{valid: false, msg_type: nil, seqnum: nil,
              other_msgs: other_msgs, original_fix_msg: orig_msg,
              error_reason: :garbled}
        end

      _ ->
        orig_msg = << "8=FIXT.1.1", @soh, "9=", rest::binary() >>
        %Message{valid: false, msg_type: nil, seqnum: nil, other_msgs: orig_msg,
          original_fix_msg: orig_msg, error_reason: :garbled}
    end
  end
  def parse1(<<"8=", _rest::binary()>> = orig_msg, _dictionary, _expected_seqnum, _validate) do
    %Message{valid: false, msg_type: nil, seqnum: nil,
      other_msgs: "", original_fix_msg: orig_msg,
      error_reason: :begin_string_error}
  end
  def parse1(data, _dictionary, _expected_seqnum, _validate) do
    %Message{valid: false, msg_type: nil, seqnum: nil, other_msgs: "",
      original_fix_msg: data, error_reason: :garbled}
  end

  @doc """
  Parse rest of the message
  """
  def parse2(%Message{valid: true, complete: false, fields: fields,
      rest_msg: rest} = msg) do
    case do_parse(rest, nil, []) do
      {:ok, nil, fields2, ""} ->
        %Message{msg | complete: true, fields: fields ++ fields2, rest_msg: ""}
      {:error, :invalid_rawdata, nil, fields2} ->
        %Message{msg | valid: false, error_reason: :garbled, fields: fields ++ fields2, rest_msg: ""}
    end
  end
  def parse2(%Message{valid: true, complete: true} = msg) do
    msg
  end

  ##
  ## Private functions
  ##

  ## Parse when checksum is valid
  defp parse_message(rest1, expected_seqnum, orig_msg, dictionary, other_msgs) do
    case :binary.split(rest1, << @soh >>) do
      [<< "35=", msg_type::binary()>>, rest2] ->
        [<< "34=", str_seqnum::binary()>>, msg] = :binary.split(rest2, << @soh >>)
        {msg_seqnum, _} = Integer.parse(str_seqnum)
        case (msg_seqnum == expected_seqnum or expected_seqnum == nil) do
          true ->
            parse_expected_seqnum(msg_seqnum, msg_type, msg,
              dictionary.subject(msg_type), orig_msg, other_msgs)
          false ->
            parse_unexpected_seqnum(msg_seqnum, msg_type, msg,
              dictionary.subject(msg_type), orig_msg, other_msgs)
        end

      _ ->
        %Message{valid: false, msg_type: nil, seqnum: nil, other_msgs: other_msgs,
          original_fix_msg: orig_msg, error_reason: :garbled}
    end
  end

  defp do_parse(<<"10=", _cs::binary()>>, _subject_field, acc) do
    {:ok, nil, :lists.reverse(acc), ""}
  end
  defp do_parse(<<"95=", rest::binary()>>, subject_field, acc) do
    [str_len, rest1] = :binary.split(rest, << @soh >>)
    {len, _} = Integer.parse(str_len)
    case rest1 do
      << "96=", rawdata::binary-size(len), @soh, other_fields::binary() >> ->
        do_parse(other_fields, subject_field, [{"96", {:binary, rawdata}} | acc])
      _ ->
        {:error, :invalid_rawdata, subject_field, :lists.reverse(acc)}
    end
  end
  defp do_parse(binmsg, nil, acc) do
    [pair, rest2] = :binary.split(binmsg, << @soh >>)
    {name, value} = parse_field(pair)
    do_parse(rest2, nil, [{name, value} | acc])
  end
  defp do_parse(binmsg, subject_field, acc) do
    [pair, rest2] = :binary.split(binmsg, << @soh >>)
    {name, value} = parse_field(pair)
    case name == subject_field do
      true ->
        fields = :lists.reverse([{name, value} | acc])
        {:ok, value, fields, rest2}
      false ->
        do_parse(rest2, subject_field, [{name, value} | acc])
    end
  end

  defp parse_expected_seqnum(seqnum, msg_type, data, subject_field, orig_msg, other_msgs) do
    case do_parse(data, subject_field, [{"34", "#{seqnum}"}, {"35", msg_type}]) do
      {:ok, sub, fields, rest0} ->
        poss_dup = :lists.keyfind("43", 1, fields) == {"43", "Y"}
        %Message{valid: true, complete: rest0 == "", msg_type: msg_type,
          subject: sub, poss_dup: poss_dup, fields: fields,
          seqnum: seqnum, rest_msg: rest0,
          original_fix_msg: orig_msg, other_msgs: other_msgs}
      {:error, :invalid_rawdata, sub, fields} ->
        poss_dup = :lists.keyfind("43", 1, fields) == {"43", "Y"}
        %Message{valid: false, complete: true, msg_type: msg_type,
          subject: sub, poss_dup: poss_dup, fields: fields,
          seqnum: seqnum, rest_msg: "", error_reason: :garbled,
          original_fix_msg: orig_msg, other_msgs: other_msgs}
    end
  end

  defp parse_unexpected_seqnum(seqnum, msg_type, data, subject_field, orig_msg, other_msgs) do
    case do_parse(data, subject_field, [{"34", "#{seqnum}"}, {"35", msg_type}]) do
      {:ok, sub, fields, rest0} ->
        poss_dup = :lists.keyfind("43", 1, fields) == {"43", "Y"}
        %Message{valid: false, msg_type: msg_type, seqnum: seqnum,
          subject: sub, fields: fields, rest_msg: rest0,
          other_msgs: other_msgs, original_fix_msg: orig_msg,
          error_reason: :unexpected_seqnum}
      {:error, :invalid_rawdata, sub, fields} ->
        poss_dup = :lists.keyfind("43", 1, fields) == {"43", "Y"}
        %Message{valid: false, complete: true, msg_type: msg_type,
          subject: sub, poss_dup: poss_dup, fields: fields,
          seqnum: seqnum, rest_msg: "", error_reason: :garbled,
          original_fix_msg: orig_msg, other_msgs: other_msgs}
    end
  end

  defp parse_field(pair) do
    [name, value] = :binary.split(pair, <<"=">>)
    {name, :unicode.characters_to_binary(value, :latin1, :utf8)}
  end

  defp validate_msg(false, _, _, _), do: true
  defp validate_msg(true, str_len, body, checksum) do
    received_checksum = String.to_integer(checksum)
    payload = << "8=FIXT.1.1", @soh, "9=", str_len::binary(), @soh, body::binary() >>
    received_checksum == calc_checksum(payload, 0)
  end

  defp calc_checksum(<<w::little-unsigned-integer-size(8), r::bytes()>>, acc) do
    calc_checksum(r, acc + w)
  end
  defp calc_checksum("", acc) do
    rem(acc, 256)
  end
end
