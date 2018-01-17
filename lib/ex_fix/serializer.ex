defmodule ExFix.Serializer do
  @moduledoc """
  FIX message serialization
  """

  alias ExFix.Session.MessageToSend
  alias ExFix.DateUtil

  @tag_msg_type "35"
  @tag_seqnum "34"
  @tag_sender_comp_id "49"
  @tag_sending_time "52"
  @tag_target_comp_id "56"
  @tag_poss_dup_flag "43"
  @tag_orig_sending_time "122"

  @compile {:inline, calculate_checksum: 2}

  @doc """
  Encode FIX message
  """
  @spec serialize(MessageToSend.t(), DateTime.t(), boolean()) :: binary()
  def serialize(
        %MessageToSend{
          seqnum: seqnum,
          msg_type: msg_type,
          sender: sender,
          orig_sending_time: orig_sending_time,
          target: target,
          extra_header: extra_header,
          body: body
        },
        sending_time,
        resend \\ false
      ) do
    header =
      case resend do
        false ->
          [
            {@tag_sender_comp_id, sender},
            {@tag_sending_time, sending_time},
            {@tag_target_comp_id, target}
          ]

        true ->
          [
            {@tag_sender_comp_id, sender},
            {@tag_poss_dup_flag, true},
            {@tag_sending_time, sending_time},
            {@tag_orig_sending_time, orig_sending_time},
            {@tag_target_comp_id, target}
          ]
      end

    fields = header ++ extra_header ++ body

    {:ok, body, bin_len, cs_total} =
      fields_to_bin([{@tag_msg_type, msg_type}, {@tag_seqnum, seqnum} | fields])

    head = <<"8=FIXT.1.1", 1, "9=", bin_len::binary(), 1>>
    checksum_bin = calculate_checksum(cs_total, head)
    <<head::binary(), body::binary(), "10=", checksum_bin::binary(), 1>>
  end

  ##
  ## Private functions
  ##

  defp fields_to_bin(fields), do: fields_to_bin(fields, [], 0, 0)

  defp fields_to_bin([], bin, len, cs_total) do
    result =
      bin
      |> Enum.reverse()
      |> IO.iodata_to_binary()

    {:ok, result, "#{len}", cs_total}
  end

  defp fields_to_bin([{tag, value} | rest], bin, len, cstot) do
    bin_value = serialize_value(value)
    pair = <<tag::binary(), "=", bin_value::binary(), 1>>
    fields_to_bin(rest, [pair | bin], len + byte_size(pair), bin_sum(pair, cstot))
  end

  defp serialize_value(v) when is_binary(v) do
    :unicode.characters_to_binary(v, :utf8, :latin1)
  end

  defp serialize_value(v) when is_float(v) do
    :erlang.float_to_binary(v, [{:decimals, 10}, :compact])
  end

  defp serialize_value(%DateTime{} = v) do
    DateUtil.serialize_date(v)
  end

  defp serialize_value(v) when is_integer(v), do: Integer.to_string(v)
  defp serialize_value(true), do: "Y"
  defp serialize_value(false), do: "N"
  defp serialize_value(v) when is_atom(v), do: Atom.to_string(v)
  defp serialize_value(nil), do: ""

  def bin_sum(<<>>, acc), do: acc

  def bin_sum(<<value::binary-size(1), rest::binary()>>, acc) do
    bin_sum(rest, acc + :binary.decode_unsigned(value))
  end

  defp calculate_checksum(cs_total, extra_bytes) do
    checksum = rem(bin_sum(extra_bytes, cs_total), 256)

    case checksum do
      cs when cs < 10 -> "00#{cs}"
      cs when cs < 100 -> "0#{cs}"
      cs -> "#{cs}"
    end
  end
end
