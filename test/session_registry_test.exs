defmodule ExFix.SessionRegistryTest do
  use ExUnit.Case

  alias ExFix.SessionRegistry

  test "SessionRegistry test" do
    assert SessionRegistry.get_status() == %{}
  end
end