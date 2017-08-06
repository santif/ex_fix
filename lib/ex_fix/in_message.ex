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
  def get_field(%InMessage{fields: fields}, field, nil) do
    tuple = case field do
      b when is_binary(b) ->
        :lists.keyfind(b, 1, fields)
      i when is_integer(i) ->
        :lists.keyfind("#{i}", 1, fields)
    end
    case tuple do
      {_key, value} ->
        value
      false ->
        nil
    end
  end
  def get_field(%InMessage{fields: fields}, field, dictionary) do
    dictionary.get_field(fields, field)
  end

  def get_fields(_msg, _field, dictionary \\ nil)
  def get_fields(%InMessage{fields: fields}, field, nil) do
    tuple = case field do
      b when is_binary(b) ->
        :lists.keyfind(b, 1, fields)
      i when is_integer(i) ->
        :lists.keyfind("#{i}", 1, fields)
    end
    case tuple do
      {_key, value} ->
        value
      false ->
        nil
    end
  end
  def get_fields(%InMessage{fields: fields}, field, dictionary) do
    dictionary.get_fields(fields, field)
  end


  ## TODO getter functions
  ## - get_string_field / get_int_field / etc
  ## - get_string_fields / get_int_fields / etc
end