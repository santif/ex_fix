defmodule ExFixBench do
  use Benchfella

  alias ExFix.Session.MessageToSend
  alias ExFix.Serializer
  alias ExFix.OutMessage
  alias ExFix.Parser

  defmodule MyDictionary do
    @behaviour ExFix.Dictionary

    def subject("8"), do: "1"  ## 8 (ExecutionReport) subject: 1 (Account)
    def subject(_), do: nil
  end

  @field_account           "1"
  @field_cl_ord_id        "11"
  @field_order_qty        "38"
  @field_price            "44"
  @field_side             "54"
  @field_symbol           "55"

  @dictionary ExFixBench.MyDictionary

  bench "Serialize", [data: get_serialize_data(), now: get_sending_time()] do
    Serializer.serialize(data, now)
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

  def get_serialize_data() do
    out_message = "D"
    |> OutMessage.new()
    |> OutMessage.set_field(@field_account, "531")
    |> OutMessage.set_field(@field_cl_ord_id, "99")
    |> OutMessage.set_field(@field_order_qty, 5)
    |> OutMessage.set_field(@field_price, 1.2)
    |> OutMessage.set_field(@field_side, 1)
    |> OutMessage.set_field(@field_symbol, "SYM")

    %MessageToSend{seqnum: 10, msg_type: out_message.msg_type, sender: "SENDER",
      orig_sending_time: DateTime.utc_now(), target: "TARGET",
      body: out_message.fields}
  end
end
