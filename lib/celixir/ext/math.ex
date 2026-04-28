defmodule Celixir.Ext.Math do
  @moduledoc """
  Math extension for CEL — mirrors `ext.Math()` from cel-go.

  Provides numeric functions under the `math.*` namespace.

  ## Usage

      env = Celixir.Environment.new() |> Celixir.Ext.Math.register()
      Celixir.eval!("math.sqrt(16.0)", env)  # => 4.0
      Celixir.eval!("math.ceil(1.2)", env)   # => 2.0

  ## Functions

  - `math.ceil(double)` — ceiling
  - `math.floor(double)` — floor
  - `math.round(double)` — round (ties away from zero)
  - `math.trunc(double)` — truncate fractional part
  - `math.abs(int|uint|double)` — absolute value
  - `math.sign(int|uint|double)` — -1, 0, or 1
  - `math.sqrt(int|uint|double)` — square root (NaN for negative)
  - `math.isNaN(double)` — true if NaN
  - `math.isInf(double)` — true if ±Inf
  - `math.isFinite(double)` — true if neither NaN nor Inf
  - `math.bitAnd(int, int)` / `math.bitAnd(uint, uint)`
  - `math.bitOr(int, int)` / `math.bitOr(uint, uint)`
  - `math.bitXor(int, int)` / `math.bitXor(uint, uint)`
  - `math.bitNot(int)` / `math.bitNot(uint)`
  - `math.bitShiftLeft(int|uint, int)`
  - `math.bitShiftRight(int|uint, int)`
  - `math.greatest(arg, ...)` / `math.greatest(list)` — variadic max (built-in only)
  - `math.least(arg, ...)` / `math.least(list)` — variadic min (built-in only)
  """

  import Bitwise, only: [band: 2, bor: 2, bxor: 2, bnot: 1, bsl: 2, bsr: 2]

  @uint64_max 18_446_744_073_709_551_615

  alias Celixir.Environment

  @doc """
  Registers math extension functions into the given environment.

  Note: `math.greatest` and `math.least` are variadic macros handled by the
  built-in evaluator and do not need explicit registration.
  """
  def register(env \\ Environment.new()) do
    env
    |> Environment.put_function("math.ceil", &math_ceil/1)
    |> Environment.put_function("math.floor", &math_floor/1)
    |> Environment.put_function("math.round", &math_round/1)
    |> Environment.put_function("math.trunc", &math_trunc/1)
    |> Environment.put_function("math.sqrt", &math_sqrt/1)
    |> Environment.put_function("math.isNaN", &math_is_nan/1)
    |> Environment.put_function("math.isInf", &math_is_inf/1)
    |> Environment.put_function("math.isFinite", &math_is_finite/1)
    |> Environment.put_function("math.abs", &math_abs/1)
    |> Environment.put_function("math.sign", &math_sign/1)
  end

  def math_ceil(v) when is_float(v), do: Float.ceil(v) * 1.0
  def math_ceil(v) when v in [:nan, :infinity, :neg_infinity], do: v

  def math_floor(v) when is_float(v), do: Float.floor(v) * 1.0
  def math_floor(v) when v in [:nan, :infinity, :neg_infinity], do: v

  def math_round(v) when is_float(v), do: Float.round(v) * 1.0
  def math_round(v) when v in [:nan, :infinity, :neg_infinity], do: v

  def math_trunc(v) when is_float(v), do: Kernel.trunc(v) * 1.0
  def math_trunc(v) when v in [:nan, :infinity, :neg_infinity], do: v

  def math_sqrt(v) when is_float(v), do: if(v < 0.0, do: :nan, else: :math.sqrt(v))
  def math_sqrt(v) when is_integer(v), do: if(v < 0, do: :nan, else: :math.sqrt(v * 1.0))
  def math_sqrt(v) when v in [:nan, :infinity, :neg_infinity], do: v

  def math_is_nan(v) when is_float(v), do: false
  def math_is_nan(v) when v in [:nan, :infinity, :neg_infinity], do: v == :nan

  def math_is_inf(v) when is_float(v), do: false
  def math_is_inf(v) when v in [:nan, :infinity, :neg_infinity], do: v in [:infinity, :neg_infinity]

  def math_is_finite(v) when is_float(v), do: true
  def math_is_finite(v) when v in [:nan, :infinity, :neg_infinity], do: false

  def math_abs(v) when is_integer(v), do: abs(v)
  def math_abs(v) when is_float(v), do: abs(v)
  def math_abs(:nan), do: :nan
  def math_abs(:infinity), do: :infinity
  def math_abs(:neg_infinity), do: :infinity

  def math_sign(v) when is_integer(v) do
    cond do
      v > 0 -> 1
      v < 0 -> -1
      true -> 0
    end
  end

  def math_sign(v) when is_float(v) do
    cond do
      v > 0.0 -> 1.0
      v < 0.0 -> -1.0
      true -> 0.0
    end
  end

  def math_bit_and(a, b) when is_integer(a) and is_integer(b), do: band(a, b)
  def math_bit_or(a, b) when is_integer(a) and is_integer(b), do: bor(a, b)
  def math_bit_xor(a, b) when is_integer(a) and is_integer(b), do: bxor(a, b)
  def math_bit_not(v) when is_integer(v), do: bnot(v)
  def math_bit_not_uint(v) when is_integer(v), do: band(bnot(v), @uint64_max)

  def math_bit_shift_left(a, b) when is_integer(a) and is_integer(b) do
    band(bsl(band(a, @uint64_max), b), @uint64_max)
  end

  def math_bit_shift_right(a, b) when is_integer(a) and is_integer(b) do
    bsr(band(a, @uint64_max), b)
  end

  def math_greatest(list) when is_list(list) do
    if Enum.empty?(list), do: raise("math.greatest: requires at least one argument")

    pairs = Enum.map(list, fn item -> {to_comparable(item), item} end)

    if Enum.any?(pairs, fn {n, _} -> is_nil(n) end),
      do: raise("math.greatest: requires numeric arguments"),
      else: pairs |> Enum.max_by(fn {n, _} -> n end) |> elem(1)
  end

  def math_least(list) when is_list(list) do
    if Enum.empty?(list), do: raise("math.least: requires at least one argument")

    pairs = Enum.map(list, fn item -> {to_comparable(item), item} end)

    if Enum.any?(pairs, fn {n, _} -> is_nil(n) end),
      do: raise("math.least: requires numeric arguments"),
      else: pairs |> Enum.min_by(fn {n, _} -> n end) |> elem(1)
  end

  defp to_comparable(v) when is_float(v), do: v
  defp to_comparable(v) when is_integer(v), do: v * 1.0
  defp to_comparable(_), do: nil
end
