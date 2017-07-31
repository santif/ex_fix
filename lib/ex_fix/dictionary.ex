defmodule ExFix.Dictionary do
  @moduledoc """
  FIX dictionary behaviour
  """

  @type tag_type() :: :string | :datetime | :number | :boolean
  @type tag_info() :: {tag_name :: String.t, tag_type :: tag_type()}
  @type subject_tag() :: String.t | {String.t, String.t} | nil
  @type msg_group_tag() :: String.t | nil

  @callback tag_info(tag :: String.t) :: tag_info()
  @callback subject(msg_type :: String.t) :: subject_tag()
  @callback group_by_tag(msg_type :: String.t) :: msg_group_tag()
end
