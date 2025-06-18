defmodule ExFix.DateUtil do
  @moduledoc """
  FIX DateTime related functions
  """
  alias Calendar.DateTime.Format

  @compile {:inline, pad2: 1, pad3: 1}

  def serialize_date(%DateTime{
        calendar: Calendar.ISO,
        day: day,
        hour: hour,
        microsecond: {micro, _},
        minute: minute,
        month: month,
        second: second,
        std_offset: 0,
        time_zone: "Etc/UTC",
        utc_offset: 0,
        year: year
      }) do
    year_bin = "#{year}"
    month_bin = pad2(month)
    day_bin = pad2(day)
    hour_bin = pad2(hour)
    minute_bin = pad2(minute)
    second_bin = pad2(second)
    millis_bin = pad3(div(micro, 1000))

    <<year_bin::binary(), month_bin::binary(), day_bin::binary(), "-", hour_bin::binary(), ":",
      minute_bin::binary(), ":", second_bin::binary(), ".", millis_bin::binary()>>
  end

  def serialize_date(%DateTime{} = date_time) do
    <<yyyy::binary-size(4), "-", mm::binary-size(2), "-", dd::binary-size(2), "T",
      time::binary-size(12),
      _rest::binary()>> =
      date_time
      |> Calendar.DateTime.shift_zone!("Etc/UTC")
      |> Format.rfc3339(3)

    <<yyyy::binary(), mm::binary(), dd::binary(), "-", time::binary()>>
  end

  @doc """
  Parse FIX UTC timestamp ("YYYYMMDD-HH:MM:SS.sss")
  """
  @spec parse_date(binary()) :: {:ok, DateTime.t()} | {:error, term()}
  def parse_date(
        <<
          year::binary-size(4),
          month::binary-size(2),
          day::binary-size(2),
          "-",
          hour::binary-size(2),
          ":",
          minute::binary-size(2),
          ":",
          second::binary-size(2),
          ".",
          millis::binary-size(3)
        >>
      ) do
    with {year, ""} <- Integer.parse(year),
         {month, ""} <- Integer.parse(month),
         {day, ""} <- Integer.parse(day),
         {hour, ""} <- Integer.parse(hour),
         {minute, ""} <- Integer.parse(minute),
         {second, ""} <- Integer.parse(second),
         {millis, ""} <- Integer.parse(millis),
         {:ok, naive} <-
           NaiveDateTime.new(year, month, day, hour, minute, second, {millis * 1000, 3}) do
      DateTime.from_naive(naive, "Etc/UTC")
    else
      _ -> {:error, :invalid}
    end
  end

  def parse_date(_), do: {:error, :invalid}

  ##
  ## Private functions
  ##

  defp pad2(num) when num < 10, do: "0#{num}"
  defp pad2(num), do: "#{num}"

  defp pad3(num) when num < 10, do: "00#{num}"
  defp pad3(num) when num < 100, do: "0#{num}"
  defp pad3(num), do: "#{num}"
end
