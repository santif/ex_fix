defmodule ExFix.DefaultDictionary do
  @moduledoc false

  @behaviour ExFix.Dictionary

  def subject(_), do: nil
end
