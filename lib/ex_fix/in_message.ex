defmodule ExFix.InMessage do
  @moduledoc """
  Represents a received FIX message.
  """

  alias ExFix.InMessage

  @type field_raw_value :: String.t | field_binary_value
  @type field_binary_value :: {:binary, binary()}

  defstruct valid: false,
      complete: false,
      msg_type: nil,
      subject: nil,
      poss_dup: false,
      fields: [],
      seqnum: nil,
      rest_msg: "",
      other_msgs: "",
      original_fix_msg: nil,
      error_reason: nil

  @type t :: %InMessage{}

  @doc """
  Returns the raw value of first field with name `field_name`.
  """
  @spec get_field(InMessage.t, String.t) :: field_raw_value
  def get_field(%InMessage{fields: fields}, field_name) when is_binary(field_name) do
    case :lists.keyfind(field_name, 1, fields) do
      {^field_name, value} ->
        value
      false ->
        nil
    end
  end

  ## TODO getter functions
  ## - get_string_field / get_int_field / etc
  ## - get_fields / get_string_fields / get_int_fields / etc
end
