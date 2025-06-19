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
  Parse FIX formatted UTC date string (YYYYMMDD-HH:MM:SS.mmm)
  """
  @spec parse_date(binary()) :: {:ok, DateTime.t()} | :error
  def parse_date(
        <<
          yyyy::binary-size(4),
          mm::binary-size(2),
          dd::binary-size(2),
          "-",
          hh::binary-size(2),
          ":",
          mi::binary-size(2),
          ":",
          ss::binary-size(2),
          ".",
          ms::binary-size(3)
        >>
      ) do
    with {year, ""} <- Integer.parse(yyyy),
         {month, ""} <- Integer.parse(mm),
         {day, ""} <- Integer.parse(dd),
         {hour, ""} <- Integer.parse(hh),
         {minute, ""} <- Integer.parse(mi),
         {second, ""} <- Integer.parse(ss),
         {millis, ""} <- Integer.parse(ms),
         {:ok, naive} <-
           NaiveDateTime.new(year, month, day, hour, minute, second, {millis * 1000, 3}),
         {:ok, dt} <- DateTime.from_naive(naive, "Etc/UTC") do
      {:ok, dt}
    else
      _ -> :error
    end
  end

  def parse_date(_), do: :error

  ##
  ## Private functions
  ##

  defp pad2(num) when num < 10, do: "0#{num}"
  defp pad2(num), do: "#{num}"

  defp pad3(num) when num < 10, do: "00#{num}"
  defp pad3(num) when num < 100, do: "0#{num}"
  defp pad3(num), do: "#{num}"
end
