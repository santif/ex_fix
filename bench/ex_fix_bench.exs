defmodule ExFixBench do
  use Benchfella

  alias ExFix.Session.MessageToSend
  alias ExFix.Serializer
  alias ExFix.OutMessage
  alias ExFix.Parser

  @dictionary ExFix.DefaultDictionary

  bench "Serialize", [msg: get_message_to_send(), now: get_sending_time()] do
    Serializer.serialize(msg, now)
  end

  bench "Parse - Stage 1", [data: get_parse_data()] do
    Parser.parse1(data, @dictionary, 12_345)
  end

  bench "Parse - Full Msg", [data: get_parse_data()] do
    Parser.parse(data, @dictionary, 12_345)
  end

  bench "Parse - Stage 1 (without validation)", [data: get_parse_data()] do
    Parser.parse1(data, @dictionary, nil, false)
  end

  bench "Parse - Full Msg (without validation)", [data: get_parse_data()] do
    Parser.parse(data, @dictionary, nil, false)
  end

  ##
  ## Private functions
  ##

  defp get_sending_time() do
    {:ok, now, 0} = DateTime.from_iso8601("2017-07-17T17:50:56.560Z")
    now
  end

  defp get_parse_data() do
    str_data = "8=FIXT.1.1|9=131|35=8|34=12345|49=SELL|52=20161007-16:28:50.802|" <>
      "56=BUY|1=531|11=99|14=5|17=872|31=1.2|32=5|37=456|38=5|39=2|54=1|55=ABC|" <>
      "150=F|151=0|10=240|"
    :binary.replace(str_data, "|", << 1 >>, [:global])
  end

  defp get_message_to_send() do
    msg_type = "D"
    out_message = msg_type
    |> OutMessage.new()
    |> OutMessage.set_field(1, "531")
    |> OutMessage.set_field(11, "99")
    |> OutMessage.set_field(38, 5)
    |> OutMessage.set_field(44, 1.2)
    |> OutMessage.set_field(54, 1)
    |> OutMessage.set_field(55, "ABC")
    %MessageToSend{seqnum: 10, msg_type: msg_type, sender: "SENDER",
      orig_sending_time: DateTime.utc_now(), target: "TARGET",
      body: out_message.fields}
  end
end
