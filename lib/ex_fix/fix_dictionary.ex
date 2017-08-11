defmodule ExFix.FixDictionary do
  import SweetXml
  xml_map = Application.get_env(:ex_fix, :dictionary_map, %{})

  docs = for {session, xml_name} <- xml_map, do: {"#{session}", File.read!(xml_name)}

  doc_map = docs
  |> Enum.into(%{})

  for {session_name, doc} <- doc_map do
    fields = doc
    |> xpath( ~x"//fields/field"l, [name: ~x"./@name"s,
        number: ~x"./@number"s, type: ~x"./@type"s])

    ## TODO add values
    for %{name: name, number: number, type: type} <- fields do

      ## TODO first case, then def
      def get_field(unquote(session_name), fields, unquote(name)) do
        field_number = unquote(number)
        case :lists.keyfind(field_number, 1, fields) do
          {^field_number, value} ->
            case unquote(type) do

              "PRICE" ->
                parse_float(value)

              "QTY" ->
                parse_float(value)

              "MULTIPLECHARVALUE" ->
                String.graphemes(value)

              "UTCTIMESTAMP" ->
                value ## FIXME

              "LOCALMKTDATE" ->
                value ## FIXME

              "FLOAT" ->
                parse_float(value)

              "PERCENTAGE" ->
                parse_float(value)

              "NUMINGROUP" ->
                parse_integer(value)

              "CHAR" ->
                value

              _ ->
                value
            end
          false ->
            nil
        end
      end
    end
  end

  def get_field(fields, field_name) when is_binary(field_name) do
    case :lists.keyfind(field_name, 1, fields) do
      {^field_name, value} ->
        value
      false ->
        nil
    end
  end

  defp parse_float(value) do
    {v, ""} = Float.parse(value)
    v
  end
  defp parse_integer(value) do
    {v, ""} = Float.parse(value)
    v
  end
end