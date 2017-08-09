defmodule ExFix.InMessage do
  @moduledoc """
  Represents a received FIX message.
  """

  alias ExFix.InMessage

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

  def get_field(%InMessage{fields: fields}, field) when is_binary(field) do
    case :lists.keyfind(field, 1, fields) do
      {^field, value} ->
        value
      false ->
        nil
    end
  end

  ## TODO getter functions
  ## - get_string_field / get_int_field / etc
  ## - get_fields / get_string_fields / get_int_fields / etc
end
