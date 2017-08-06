defmodule ExFix.OutMessage do
  @moduledoc """
  FIX message built on application layer
  """

  alias ExFix.OutMessage

  defstruct msg_type: nil,
      fields: []

  @type t :: %OutMessage{}

  @doc """

  """
  @spec new(String.t) :: OutMessage.t
  def new(msg_type) do
    %OutMessage{msg_type: msg_type}
  end

  @doc """

  """
  def set_field(%OutMessage{fields: fields} = msg, field, value) when is_binary(field) do
    %OutMessage{msg | fields: fields ++ [{field, value}]}
  end

  @doc """

  """
  def set_fields(%OutMessage{} = msg, new_fields) do
    Enum.reduce(new_fields, msg, fn({field, value}, %OutMessage{} = struct) ->
      set_field(struct, field, value)
    end)
  end
end
