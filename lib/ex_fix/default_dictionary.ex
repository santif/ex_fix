defmodule ExFix.DefaultDictionary do
  @moduledoc """
  Dictionary - default implementation
  """

  @behaviour ExFix.Dictionary

  def tag_info(tag), do: {tag, :string}

  def subject("8"), do: "1"
  def subject("W"), do: "55"
  def subject(_), do: nil

  def group_by_tag(_msg_type), do: nil
end
