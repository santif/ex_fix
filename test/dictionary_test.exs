defmodule ExFix.FixDictionaryTest do
  use ExUnit.Case
  alias ExFix.FixDictionary

  test "" do
    fields = [{"1", "Account1"}, {"55", "Symbol"}, {"6", "1.234"}]

    assert FixDictionary.get_field(fields, "AvgPx") == 1.234

    assert FixDictionary.get_raw_field(fields, "6") == "1.234"
  end
end