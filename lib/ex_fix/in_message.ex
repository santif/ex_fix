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

  def get_string_field!(%InMessage{fields: fields}, field) when is_integer(field) do
    :lists.keyfind("#{field}", 1, fields)
  end

  def get_field(_msg, _field, dictionary \\ nil)
  def get_field(%InMessage{fields: fields}, field, dictionary) when is_integer(field) do
    case dictionary do
      nil -> :lists.keyfind("#{field}", 1, fields)
      dict -> dict.get_field(fields, field)
    end
  end
  def get_field(%InMessage{fields: fields}, field, dictionary) when is_binary(field) do
    case dictionary do
      nil -> :lists.keyfind(field, 1, fields)
      dict -> dict.get_field(fields, field)
    end
  end

  ## TODO getter functions
  ## - get_string_field / get_int_field / etc
  ## - get_string_fields / get_int_fields / etc
end