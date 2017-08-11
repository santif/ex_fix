defmodule ExFix.FixDictionary do
  import SweetXml
  xml_name = Application.get_env(:ex_fix, :dictionary_xml)
  if xml_name do
    doc = File.read! xml_name

    fields = doc
    |> xpath( ~x"//fields/field"l, [name: ~x"./@name"s,
        number: ~x"./@number"s, type: ~x"./@type"s])

    for %{name: name, number: number, type: type} <- fields do
      def get_field(fields, unquote(name)) do
        case :lists.keyfind(unquote(number), 1, fields) do
          {unquote(number), value} ->
            get_value(unquote(type), value)
          false ->
            nil
        end
      end
    end

    def get_raw_field(fields, field_name) when is_binary(field_name) do
      case :lists.keyfind(field_name, 1, fields) do
        {^field_name, value} ->
          value
        false ->
          nil
      end
    end

    defp get_value("PRICE", value) do
      {v, _} = Float.parse(value)
      v
    end
    defp get_value("QTY", value) do
      {v, _} = Float.parse(value)
      v
    end
    defp get_value("MULTIPLECHARVALUE", value) do
      String.graphemes(value)
    end
    defp get_value("CHAR", value) do
      value
    end
    defp get_value("UTCTIMESTAMP", value) do
      value
    end
    defp get_value("LOCALMKTDATE", value) do
      value
    end
    defp get_value("FLOAT", value) do
      {v, _} = Float.parse(value)
      v
    end
    defp get_value("PERCENTAGE", value) do
      {v, _} = Float.parse(value)
      v
    end
    defp get_value("NUMINGROUP", value) do
      {v, _} = Integer.parse(value)
      v
    end
    defp get_value(_, value), do: value
  end
end