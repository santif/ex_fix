defmodule ExFix.InMessageTest do
  use ExUnit.Case
  import ExFix.TestHelper

  alias ExFix.Parser
  alias ExFix.InMessage
  alias ExFix.TestHelper.InMessageTestDict, as: Dictionary

  setup do
    bin_msg =
      msg(
        "8=FIXT.1.1|9=$$$|35=8|34=12345|49=MARKET|52=20161007-16:28:50.802" <>
          "|56=INITIATOR|1=1557|6=18050.000|11=clordid12345|14=5|17=T3231110|31=18050" <>
          "|32=5|37=76733014|38=5|39=2|40=2|44=18050|54=1|55=Symbol1|58=Filled|59=0|" <>
          "60=20161007-16:28:50.796|150=F|151=0|207=MARKET|453=1|448=|447=D|452=11|10=$$$|"
      )

    %{bin_msg: bin_msg}
  end

  test "get_field returns value", %{bin_msg: bin_msg} do
    fix_msg = Parser.parse1(bin_msg, Dictionary, 12_345)
    assert InMessage.get_field(fix_msg, "49") == "MARKET"
    assert InMessage.get_field(fix_msg, "52") == "20161007-16:28:50.802"
  end

  test "get_field returns nil for missing field", %{bin_msg: bin_msg} do
    fix_msg = Parser.parse1(bin_msg, Dictionary, 12_345)
    assert InMessage.get_field(fix_msg, "9999") == nil
  end
end
