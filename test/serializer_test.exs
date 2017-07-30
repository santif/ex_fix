defmodule ExFix.SerializerTest do
  use ExUnit.Case

  alias ExFix.Types.MessageToSend
  alias ExFix.Serializer

  import ExFix.TestHelper

  test "Message serialization - NewOrderSingle" do
    {:ok, now, 0} = DateTime.from_iso8601("2017-07-17T17:50:56.560Z")
    {:ok, transact_time, 0} = DateTime.from_iso8601("2017-07-17T17:50:56.559Z")
    body = [
      {"1", 1234},           # Account
      {"11", "cod12345"},    # ClOrdID
      {"38", 10},            # OrderQty
      {"40", "2"},           # OrdType
      {"44", 1.23},          # Price
      {"54", "1"},           # Side
      {"55", "SYM1"},        # Symbol
      {"59", "0"},           # TimeInForce
      {"60", transact_time}, # TransactTime
    ]
    bin_message = %MessageToSend{seqnum: 10, sender: "SENDER",
      orig_sending_time: now, target: "TARGET", msg_type: "D", body: body}
    |> Serializer.serialize(now)

    assert bin_message == msg("8=FIXT.1.1|9=137|35=D|34=10|49=SENDER|" <>
      "52=20170717-17:50:56.560|56=TARGET|1=1234|11=cod12345|38=10|40=2|" <>
      "44=1.23|54=1|55=SYM1|59=0|60=20170717-17:50:56.559|10=240|")
  end

  test "Message serialization - Logon" do
    {:ok, now, _offset} = DateTime.from_iso8601("2017-05-06T17:18:19.123Z")
    body = [
      {"98", "0"},
      {"108", 120},
      {"141", true},
      {"553", "testuser"},
      {"554", "testpwd"},
      {"1137", "9"}
    ]
    bin_message = %MessageToSend{seqnum: 1, sender: "SENDER", orig_sending_time: now,
      target: "TARGET", msg_type: "A", body: body}
    |> Serializer.serialize(now)

    assert bin_message == msg("8=FIXT.1.1|9=106|35=A|34=1|49=SENDER|" <>
      "52=20170506-17:18:19.123|56=TARGET|98=0|108=120|141=Y|" <>
      "553=testuser|554=testpwd|1137=9|10=234|")
  end

  test "Message serialization - without milliseconds and another timezone" do
    now = %DateTime{year: 2017, month: 5, day: 6, zone_abbr: "ART",
      hour: 11, minute: 12, second: 13, microsecond: {0, 0},
      utc_offset: -10_800, std_offset: 0,
      time_zone: "America/Argentina/Buenos_Aires"}
    body = [
      {"98", "0"},
      {"108", 120},
      {"141", true},
      {"553", "testuser"},
      {"554", "testpwd"},
      {"1137", "9"}
    ]
    bin_message = %MessageToSend{seqnum: 1, sender: "SENDER", orig_sending_time: now,
      target: "TARGET", msg_type: "A", body: body}
    |> Serializer.serialize(now)

    expected_message = msg("8=FIXT.1.1|9=106|35=A|34=1|49=SENDER|" <>
      "52=20170506-14:12:13.000|56=TARGET|98=0|108=120|141=Y|" <>
      "553=testuser|554=testpwd|1137=9|10=213|")

    assert bin_message == expected_message
  end

  test "Message serialization - ASCII" do
    now = %DateTime{year: 2017, month: 07, day: 17, zone_abbr: "UTC",
      hour: 17, minute: 50, second: 56, microsecond: {560_000, 3},
      utc_offset: 0, std_offset: 0, time_zone: "Etc/UTC"}
    bin_message = %MessageToSend{seqnum: 10, sender: "SENDER", orig_sending_time: now,
      target: "Dólar", msg_type: "D", body: []}
    |> Serializer.serialize(now)

    expected_message = msg("8=FIXT.1.1|9=55|35=D|34=10|49=SENDER|" <>
      "52=20170717-17:50:56.560|56=Dólar|10=171|")

    assert bin_message == expected_message
  end
end