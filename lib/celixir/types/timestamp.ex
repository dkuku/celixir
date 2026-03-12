defmodule Celixir.Types.Timestamp do
  @moduledoc """
  CEL timestamp type. Wraps an Elixir DateTime (UTC).
  Supports RFC3339 parsing, arithmetic with durations, and accessor methods.
  """

  defstruct datetime: nil, nanos_remainder: 0

  @type t :: %__MODULE__{datetime: DateTime.t(), nanos_remainder: integer()}

  @doc "Creates a timestamp from a DateTime."
  def new(%DateTime{} = dt), do: %__MODULE__{datetime: normalize_precision(dt), nanos_remainder: 0}

  @doc "Parses an RFC3339 timestamp string."
  def parse(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} ->
        nanos_rem = extract_nanos_remainder(str)

        {:ok,
         %__MODULE__{
           datetime: normalize_precision(DateTime.shift_zone!(dt, "Etc/UTC")),
           nanos_remainder: nanos_rem
         }}

      {:error, _} ->
        {:error, "invalid timestamp: #{str}"}
    end
  end

  # Extract sub-microsecond nanoseconds from the original string.
  # DateTime.from_iso8601 truncates to microseconds, so we need to recover the last 3 nanos digits.
  defp extract_nanos_remainder(str) do
    case Regex.run(~r/\.(\d+)/, str) do
      [_, frac] ->
        # Pad to 9 digits (nanoseconds)
        padded = frac |> String.pad_trailing(9, "0") |> String.slice(0, 9)
        nanos = String.to_integer(padded)
        # The sub-microsecond remainder is the last 3 digits
        rem(nanos, 1000)

      _ ->
        0
    end
  end

  @doc "Returns Unix epoch seconds."
  def to_unix(%__MODULE__{datetime: dt}), do: DateTime.to_unix(dt, :second)

  @doc "Converts to RFC3339 string."
  def to_string(%__MODULE__{datetime: dt}) do
    # Trim trailing fractional zeros for canonical output
    case dt.microsecond do
      {0, _} ->
        dt |> Map.put(:microsecond, {0, 0}) |> DateTime.to_iso8601()

      {us, _} ->
        # Keep only significant fractional digits
        nanos = us * 1000
        frac = nanos |> Integer.to_string() |> String.pad_leading(9, "0") |> String.trim_trailing("0")
        base = %{dt | microsecond: {0, 0}} |> DateTime.to_iso8601() |> String.trim_trailing("Z")
        "#{base}.#{frac}Z"
    end
  end

  @doc "Add a duration (total nanoseconds) to a timestamp, returning {timestamp, total_result_nanos_since_epoch}."
  def add_nanos(%__MODULE__{datetime: dt, nanos_remainder: ts_nr}, duration_total_ns) do
    # Compute result at nanosecond precision
    ts_us = DateTime.to_unix(dt, :microsecond)
    ts_total_ns = ts_us * 1000 + ts_nr
    result_ns = ts_total_ns + duration_total_ns

    # Convert result back to microseconds + nanos_remainder
    # Use floor division to handle negative values correctly
    result_us = floor_div(result_ns, 1000)
    result_nr = result_ns - result_us * 1000

    # Compute the microsecond delta to apply to the DateTime
    delta_us = result_us - ts_us
    result_dt = DateTime.add(dt, delta_us, :microsecond)
    {%__MODULE__{datetime: result_dt, nanos_remainder: result_nr}, result_ns}
  end

  defp floor_div(a, b) when rem(a, b) == 0, do: div(a, b)
  defp floor_div(a, b) when a < 0 and b > 0, do: div(a, b) - 1
  defp floor_div(a, b), do: div(a, b)

  @doc "Add a duration (in microseconds) to a timestamp."
  def add(%__MODULE__{datetime: dt}, duration_us) when is_integer(duration_us) do
    %__MODULE__{datetime: DateTime.add(dt, duration_us, :microsecond), nanos_remainder: 0}
  end

  @doc "Subtract a duration (in microseconds) from a timestamp."
  def subtract(%__MODULE__{datetime: dt}, duration_us) when is_integer(duration_us) do
    %__MODULE__{datetime: DateTime.add(dt, -duration_us, :microsecond), nanos_remainder: 0}
  end

  @doc "Difference between two timestamps in microseconds."
  def diff(%__MODULE__{datetime: dt1}, %__MODULE__{datetime: dt2}) do
    DateTime.diff(dt1, dt2, :microsecond)
  end

  @doc "Difference between two timestamps in nanoseconds."
  def diff_nanos(%__MODULE__{datetime: dt1, nanos_remainder: nr1}, %__MODULE__{datetime: dt2, nanos_remainder: nr2}) do
    us_diff = DateTime.diff(dt1, dt2, :microsecond)
    us_diff * 1000 + (nr1 - nr2)
  end

  @doc "Get a component of the timestamp, optionally in a timezone."
  def get_component(%__MODULE__{} = ts, component, timezone \\ nil) do
    dt = resolve_timezone(ts, timezone)

    case component do
      :full_year -> dt.year
      :month -> dt.month - 1
      :date -> dt.day
      :day_of_month -> dt.day - 1
      :day_of_week -> dt |> DateTime.to_date() |> Date.day_of_week() |> day_of_week_sunday_zero()
      :day_of_year -> Date.day_of_year(DateTime.to_date(dt)) - 1
      :hours -> dt.hour
      :minutes -> dt.minute
      :seconds -> dt.second
      :milliseconds -> dt.microsecond |> elem(0) |> div(1000)
    end
  end

  defp resolve_timezone(%__MODULE__{datetime: dt}, nil), do: dt

  defp resolve_timezone(%__MODULE__{datetime: dt}, tz) when is_binary(tz) do
    case parse_utc_offset(tz) do
      {:ok, offset_seconds} ->
        # Apply a fixed UTC offset
        shifted = DateTime.add(dt, offset_seconds, :second)
        %{shifted | utc_offset: offset_seconds, time_zone: tz, zone_abbr: tz}

      :not_offset ->
        case DateTime.shift_zone(dt, tz, Tz.TimeZoneDatabase) do
          {:ok, shifted} -> shifted
          {:error, _} -> raise "unknown timezone: #{tz}"
        end
    end
  end

  # Parse fixed UTC offsets like "+05:30", "-09:30", "-00:00", "02:00"
  defp parse_utc_offset(<<sign, h1, h2, ?:, m1, m2>>) when sign in [?+, ?-] do
    hours = String.to_integer(<<h1, h2>>)
    minutes = String.to_integer(<<m1, m2>>)
    total = hours * 3600 + minutes * 60
    {:ok, if(sign == ?-, do: -total, else: total)}
  end

  # Without sign prefix, assume positive: "02:00"
  defp parse_utc_offset(<<h1, h2, ?:, m1, m2>>) when h1 in ?0..?9 and h2 in ?0..?9 and m1 in ?0..?9 and m2 in ?0..?9 do
    hours = String.to_integer(<<h1, h2>>)
    minutes = String.to_integer(<<m1, m2>>)
    {:ok, hours * 3600 + minutes * 60}
  end

  defp parse_utc_offset(_), do: :not_offset

  # Normalize microsecond precision so equality works correctly.
  # DateTime.add changes {0, 0} to {0, 6}, causing false inequality.
  defp normalize_precision(%DateTime{microsecond: {us, _}} = dt) do
    %{dt | microsecond: {us, 6}}
  end

  # CEL: Sunday = 0, Monday = 1, ..., Saturday = 6
  # Elixir Date.day_of_week: Monday = 1, ..., Sunday = 7
  defp day_of_week_sunday_zero(7), do: 0
  defp day_of_week_sunday_zero(d), do: d
end
