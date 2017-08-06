defmodule ExFix.Dictionary do
  @moduledoc """
  FIX dictionary behaviour
  """

  @type field_type :: :string | :datetime | :number | :boolean
  @type field_info :: {field_name :: String.t, field_type :: field_type}
  @type subject_field :: String.t | {String.t, String.t} | nil

  @doc """
  """
  @callback field_info(tag :: String.t) :: field_info()

  @doc """
  """
  @callback subject(msg_type :: String.t) :: subject_field()

  # @doc """
  # """
  # @callback get_field(msg_type)

end
