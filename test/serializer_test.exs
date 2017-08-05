defmodule ExFix.SerializerTest do
  use ExUnit.Case

  alias ExFix.Session.MessageToSend
  alias ExFix.Serializer

  import ExFix.TestHelper

  @tag_account       "1"
  @tag_cl_ord_id     "11"
  @tag_order_qty     "38"
  @tag_ord_type      "40"
  @tag_price         "44"
  @tag_side          "54"
  @tag_symbol        "55"
  @tag_time_in_force "59"
  @tag_transact_time "60"

  test "Message serialization - NewOrderSingle" do
    {:ok, now, 0} = DateTime.from_iso8601("2017-07-17T17:50:56.560Z")
    {:ok, transact_time, 0} = DateTime.from_iso8601("2017-07-17T17:50:56.559Z")
    body = [
      {@tag_account, 1234},
      {@tag_cl_ord_id, "cod12345"},
      {@tag_order_qty, 10},
      {@tag_ord_type, "2"},
      {@tag_price, 1.23},
      {@tag_side, "1"},
      {@tag_symbol, "SYM1"},
      {@tag_time_in_force, "0"},
      {@tag_transact_time, transact_time},
    ]
    bin_message = Serializer.serialize(%MessageToSend{seqnum: 10, sender: "SENDER",
      orig_sending_time: now, target: "TARGET", msg_type: "D", body: body}, now)

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
    bin_message = Serializer.serialize(%MessageToSend{seqnum: 1, sender: "SENDER",
      orig_sending_time: now, target: "TARGET", msg_type: "A", body: body}, now)

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
    bin_message = Serializer.serialize(%MessageToSend{seqnum: 1, sender: "SENDER",
      orig_sending_time: now, target: "TARGET", msg_type: "A", body: body}, now)

    expected_message = msg("8=FIXT.1.1|9=106|35=A|34=1|49=SENDER|" <>
      "52=20170506-14:12:13.000|56=TARGET|98=0|108=120|141=Y|" <>
      "553=testuser|554=testpwd|1137=9|10=213|")

    assert bin_message == expected_message
  end

  test "Message serialization - ASCII" do
    now = %DateTime{year: 2017, month: 07, day: 17, zone_abbr: "UTC",
      hour: 17, minute: 50, second: 56, microsecond: {560_000, 3},
      utc_offset: 0, std_offset: 0, time_zone: "Etc/UTC"}
    bin_message = Serializer.serialize(%MessageToSend{seqnum: 10, sender: "SENDER",
      orig_sending_time: now, target: "Dólar", msg_type: "D", body: []}, now)

    expected_message = msg("8=FIXT.1.1|9=55|35=D|34=10|49=SENDER|" <>
      "52=20170717-17:50:56.560|56=Dólar|10=171|")

    assert bin_message == expected_message
  end

  test "serialize_date - 1" do
    now = %DateTime{year: 2017, month: 5, day: 6, zone_abbr: "ART",
      hour: 11, minute: 12, second: 13, microsecond: {1_000, 3},
      utc_offset: 0, std_offset: 0, time_zone: "Etc/UTC"}
    msg = %MessageToSend{seqnum: 1, sender: "SENDER", orig_sending_time: now,
      target: "TARGET", msg_type: "0", body: []}
    |> Serializer.serialize(now)
    |> :binary.replace(<<1>>, "|", [:global])

    assert msg =~ ~r/20170506-11:12:13\.001/
  end

  test "serialize_date - 2" do
    now = %DateTime{year: 2017, month: 5, day: 6, zone_abbr: "ART",
      hour: 11, minute: 12, second: 13, microsecond: {12_000, 3},
      utc_offset: 0, std_offset: 0, time_zone: "Etc/UTC"}
    msg = %MessageToSend{seqnum: 1, sender: "SENDER", orig_sending_time: now,
      target: "TARGET", msg_type: "0", body: []}
    |> Serializer.serialize(now)
    |> :binary.replace(<<1>>, "|", [:global])

    assert msg =~ ~r/20170506-11:12:13\.012/
  end

  test "serialize_date - 3" do
    now = %DateTime{year: 2017, month: 5, day: 6, zone_abbr: "ART",
      hour: 11, minute: 12, second: 13, microsecond: {123_000, 3},
      utc_offset: 0, std_offset: 0, time_zone: "Etc/UTC"}
    msg = %MessageToSend{seqnum: 1, sender: "SENDER", orig_sending_time: now,
      target: "TARGET", msg_type: "0", body: []}
    |> Serializer.serialize(now)
    |> :binary.replace(<<1>>, "|", [:global])

    assert msg =~ ~r/20170506-11:12:13\.123/
  end
end
