defmodule ExFix.Dictionary do
  @moduledoc """
  FIX messages metadata
  """

  @type subject_field :: String.t | {String.t, String.t} | nil

  @doc """
  Returns an arbitrary field (or pair of fields) that allows to "classify" the message
  received, depending on the message's type.
  """
  @callback subject(msg_type :: String.t) :: subject_field
end
