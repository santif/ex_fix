defmodule ExFixBench do
  use Benchfella

  alias ExFix.Types.MessageToSend
  alias ExFix.Serializer
  alias ExFix.Parser

  @dictionary ExFix.DefaultDictionary

  bench "Serialize", [now: get_sending_time()] do
    %MessageToSend{seqnum: 10, sender: "SENDER",
      orig_sending_time: now, target: "TARGET", msg_type: "D", body: [
        {"1", 531},       # Account
        {"11", "99"},     # ClOrdID
        {"38", 5},        # OrderQty
        {"44", 1.2},      # Price
        {"54", "1"},      # Side
        {"55", "ABC"},    # Symbol
      ]}
    |> Serializer.serialize(now)
  end

  bench "Parse - Stage 1", [data: get_data()] do
    Parser.parse1(data, @dictionary, 12_345)
  end

  bench "Parse - Full Msg", [data: get_data()] do
    Parser.parse(data, @dictionary, 12_345)
  end

  bench "Parse - Stage 1 (without validation)", [data: get_data()] do
    Parser.parse1(data, @dictionary, nil, false)
  end

  bench "Parse - Full Msg (without validation)", [data: get_data()] do
    Parser.parse(data, @dictionary, nil, false)
  end


  ##
  ## Private functions
  ##

  defp get_sending_time() do
    {:ok, now, 0} = DateTime.from_iso8601("2017-07-17T17:50:56.560Z")
    now
  end

  defp get_data() do
    str_data = "8=FIXT.1.1|9=131|35=8|34=12345|49=SELL|52=20161007-16:28:50.802|" <>
      "56=BUY|1=531|11=99|14=5|17=872|31=1.2|32=5|37=456|38=5|39=2|54=1|55=ABC|" <>
      "150=F|151=0|10=240|"
    :binary.replace(str_data, "|", << 1 >>, [:global])
  end
end