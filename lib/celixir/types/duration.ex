defmodule Celixir.Types.Duration do
  @moduledoc """
  CEL duration type. Stores duration as microseconds internally.
  Supports Go-style duration string parsing and arithmetic.
  """

  defstruct microseconds: 0, nanos_remainder: 0

  @type t :: %__MODULE__{microseconds: integer(), nanos_remainder: integer()}

  @us_per_ms 1_000
  @us_per_s 1_000_000
  @us_per_m 60_000_000
  @us_per_h 3_600_000_000

  # CEL duration range: approximately ±10,000 years in seconds
  @max_duration_seconds 315_576_000_000
  @max_duration_us @max_duration_seconds * @us_per_s

  @doc "Creates a duration from microseconds."
  def new(microseconds) when is_integer(microseconds), do: %__MODULE__{microseconds: microseconds, nanos_remainder: 0}

  @doc "Check if duration is within valid range."
  def in_range?(%__MODULE__{microseconds: us}), do: abs(us) <= @max_duration_us

  @doc "Creates a duration from seconds and optional nanos."
  def from_seconds(seconds, nanos \\ 0) when is_integer(seconds) and is_integer(nanos) do
    %__MODULE__{
      microseconds: seconds * @us_per_s + div(nanos, 1000),
      nanos_remainder: rem(nanos, 1000)
    }
  end

  @doc """
  Parses a Go-style duration string.
  Supports: h, m, s, ms, us, ns suffixes. Optional negative prefix.
  Examples: "3600s", "1h30m", "500ms", "-1.5s", "1h2m3s4ms5us6ns"
  """
  def parse(str) when is_binary(str) do
    {negative, rest} =
      case str do
        "-" <> r -> {true, r}
        r -> {false, r}
      end

    case parse_components(rest, 0) do
      {:ok, total_ns} ->
        us = if(negative, do: -div(total_ns, 1000), else: div(total_ns, 1000))
        nr = if(negative, do: -rem(total_ns, 1000), else: rem(total_ns, 1000))
        result = %__MODULE__{microseconds: us, nanos_remainder: nr}
        if in_range?(result), do: {:ok, result}, else: {:error, "duration out of range"}

      :error ->
        {:error, "invalid duration: #{str}"}
    end
  end

  @doc "Add two durations. Returns {:ok, duration} | {:error, msg}."
  def add(%__MODULE__{} = a, %__MODULE__{} = b) do
    total_ns = to_total_nanos(a) + to_total_nanos(b)
    result = from_total_nanos(total_ns)
    if in_range?(result), do: {:ok, result}, else: {:error, "duration overflow"}
  end

  @doc "Subtract two durations. Returns {:ok, duration} | {:error, msg}."
  def subtract(%__MODULE__{} = a, %__MODULE__{} = b) do
    total_ns = to_total_nanos(a) - to_total_nanos(b)
    result = from_total_nanos(total_ns)
    if in_range?(result), do: {:ok, result}, else: {:error, "duration overflow"}
  end

  @doc "Negate a duration."
  def negate(%__MODULE__{microseconds: us, nanos_remainder: nr}), do: %__MODULE__{microseconds: -us, nanos_remainder: -nr}

  @doc "Convert duration to total nanoseconds."
  def to_total_nanos(%__MODULE__{microseconds: us, nanos_remainder: nr}), do: us * 1000 + nr

  @doc "Create duration from total nanoseconds."
  def from_total_nanos(total_ns) do
    us = div(total_ns, 1000)
    nr = rem(total_ns, 1000)
    %__MODULE__{microseconds: us, nanos_remainder: nr}
  end

  @doc "Get a component of the duration."
  def get_component(%__MODULE__{microseconds: us}, component) do
    case component do
      :hours -> div(us, @us_per_h)
      :minutes -> div(us, @us_per_m)
      :seconds -> div(us, @us_per_s)
      :milliseconds -> rem(div(us, @us_per_ms), 1000)
    end
  end

  @doc "Convert to canonical string (seconds with optional fractional nanos)."
  def to_string(%__MODULE__{} = d) do
    total_ns = to_total_nanos(d)
    {neg, total_ns} = if total_ns < 0, do: {"-", -total_ns}, else: {"", total_ns}

    total_us = div(total_ns, 1000)
    seconds = div(total_us, @us_per_s)
    frac_us = rem(total_us, @us_per_s)
    extra_ns = rem(total_ns, 1000)

    nanos = frac_us * 1000 + extra_ns

    if nanos == 0 do
      "#{neg}#{seconds}s"
    else
      frac_str =
        nanos |> Integer.to_string() |> String.pad_leading(9, "0") |> String.trim_trailing("0")

      "#{neg}#{seconds}.#{frac_str}s"
    end
  end

  # --- Parser internals ---

  defp parse_components("", acc), do: {:ok, acc}

  defp parse_components(str, acc) do
    case parse_number(str) do
      {num, rest} ->
        case parse_unit(rest) do
          {multiplier, rest2} ->
            parse_components(rest2, acc + round(num * multiplier))

          :error ->
            :error
        end

      :error ->
        :error
    end
  end

  defp parse_number(str) do
    case Float.parse(str) do
      {num, rest} ->
        {num, rest}

      :error ->
        case Integer.parse(str) do
          {num, rest} -> {num * 1.0, rest}
          :error -> :error
        end
    end
  end

  # Multipliers are in nanoseconds
  defp parse_unit("ns" <> rest), do: {1, rest}
  defp parse_unit("us" <> rest), do: {1_000, rest}
  defp parse_unit("µs" <> rest), do: {1_000, rest}
  defp parse_unit("ms" <> rest), do: {1_000_000, rest}
  defp parse_unit("s" <> rest), do: {1_000_000_000, rest}
  defp parse_unit("m" <> rest), do: {60_000_000_000, rest}
  defp parse_unit("h" <> rest), do: {3_600_000_000_000, rest}
  defp parse_unit(_), do: :error
end
