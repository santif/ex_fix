defmodule ExFix.DefaultDictionary do
  @moduledoc """
  Simple FIX Dictionary
  """

  @behaviour ExFix.Dictionary

  def subject(_), do: nil
end
