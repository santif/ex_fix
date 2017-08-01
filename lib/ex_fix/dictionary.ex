defmodule ExFix.Dictionary do
  @moduledoc """
  FIX dictionary behaviour
  """

  @type tag_type() :: :string | :datetime | :number | :boolean
  @type tag_info() :: {tag_name :: String.t, tag_type :: tag_type()}
  @type subject_tag() :: String.t | {String.t, String.t} | nil

  @callback msg_type(name :: String.t) :: String.t
  @callback tag_info(tag :: String.t) :: tag_info()
  @callback subject(msg_type :: String.t) :: subject_tag()
end
