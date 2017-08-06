defmodule ExFix.ParserTest do
  use ExUnit.Case

  alias ExFix.Parser
  import ExFix.TestHelper

  @dictionary ExFix.DefaultDictionary

  test "Parse message - stage 1" do
    data = msg("8=FIXT.1.1|9=267|35=8|34=12345|49=MARKET|52=20161007-16:28:50.802" <>
      "|56=INITIATOR|1=1557|6=18050.000|11=clordid12345|14=5|17=T3231110|31=18050" <>
      "|32=5|37=76733014|38=5|39=2|40=2|44=18050|54=1|55=Symbol1|58=Filled|59=0|" <>
      "60=20161007-16:28:50.796|150=F|151=0|207=MARKET|453=1|448=|447=D|452=11|10=147|")
    fix_msg = Parser.parse1(data, @dictionary, 12_345)
    assert fix_msg.valid == true
    assert fix_msg.complete == false
    assert fix_msg.subject == "1557"
  end

  test "Parse message - full" do
    data = msg("8=FIXT.1.1|9=267|35=8|34=12345|49=MARKET|52=20161007-16:28:50.802" <>
      "|56=INITIATOR|1=1557|6=18050.000|11=clordid12345|14=5|17=T3231110|31=18050" <>
      "|32=5|37=76733014|38=5|39=2|40=2|44=18050|54=1|55=Symbol1|58=Filled|59=0|" <>
      "60=20161007-16:28:50.796|150=F|151=0|207=MARKET|453=1|448=|447=D|452=11|10=147|")
    fix_msg = Parser.parse(data, @dictionary, 12_345)
    assert fix_msg.valid == true
    assert fix_msg.complete == true
    assert fix_msg.subject == "1557"
    assert fix_msg.fields == [
      {"35", "8"},
      {"34", "12345"},
      {"49", "MARKET"},
      {"52", "20161007-16:28:50.802"},
      {"56", "INITIATOR"},
      {"1", "1557"},
      {"6", "18050.000"},
      {"11", "clordid12345"},
      {"14", "5"},
      {"17", "T3231110"},
      {"31", "18050"},
      {"32", "5"},
      {"37", "76733014"},
      {"38", "5"},
      {"39", "2"},
      {"40", "2"},
      {"44", "18050"},
      {"54", "1"},
      {"55", "Symbol1"},
      {"58", "Filled"},
      {"59", "0"},
      {"60", "20161007-16:28:50.796"},
      {"150", "F"},
      {"151", "0"},
      {"207", "MARKET"},
      {"453", "1"},
      {"448", ""},
      {"447", "D"},
      {"452", "11"},
    ]
  end

  test "Parse message with checksum error" do
    data = msg("8=FIXT.1.1|9=267|35=8|34=12345|49=MARKET|52=20161007-16:28:50.802|" <>
      "56=INITIATOR|1=1557|6=18050.000|11=clordid12345|14=5|17=T3231110|31=18050|" <>
      "32=5|37=76733014|38=5|39=2|40=2|44=18050|54=1|55=Symbol1|58=Filled|59=0|" <>
      "60=20161007-16:28:50.796|150=F|151=0|207=MARKET|453=1|448=|447=D|452=11|10=999|")
    fix_msg = Parser.parse1(data, @dictionary, 12_345)
    assert fix_msg.valid == false
    assert fix_msg.error_reason == :garbled
  end

  test "Parse valid message with RawData field" do
    raw_data = "123456789|0"
    data = msg("8=FIXT.1.1|9=$$$|35=B|34=12345|49=MARKET|52=20161007-16:28:50.802|" <>
      "56=INITIATOR|148=Headline|95=11|96=#{raw_data}|10=$$$|")
    fix_msg = Parser.parse1(data, @dictionary, 12_345)
    assert fix_msg.valid == true
    assert fix_msg.complete == true
    assert fix_msg.subject == nil
    assert fix_msg.fields == [
      {"35", "B"},
      {"34", "12345"},
      {"49", "MARKET"},
      {"52", "20161007-16:28:50.802"},
      {"56", "INITIATOR"},
      {"148", "Headline"},
      {"96", {:binary, << "123456789", 1, "0" >>}},
    ]
  end

  test "Parse invalid message with RawData field" do
    data = msg("8=FIXT.1.1|9=$$$|35=B|34=12345|49=MARKET|52=20161007-16:28:50.802|" <>
      "56=INITIATOR|148=Headline|95=20|96=123456789|0|10=$$$|")
    fix_msg = Parser.parse1(data, @dictionary, 12_345)
    assert fix_msg.valid == false
    assert fix_msg.error_reason == :garbled
  end
end
