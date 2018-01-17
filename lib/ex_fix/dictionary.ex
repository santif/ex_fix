defmodule ExFix.Dictionary do
  @moduledoc """
  FIX dictionary behaviour
  """

  @type subject_field :: String.t() | {String.t(), String.t()} | nil

  @doc """
  """
  @callback subject(msg_type :: String.t()) :: subject_field
end
