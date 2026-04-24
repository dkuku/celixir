defmodule Celixir.Ext.Lists do
  @moduledoc """
  Lists extension for CEL — mirrors `ext.Lists()` from cel-go.

  Provides extended list functions. Functions are registered into the
  environment and also available as built-ins.

  ## Usage

      env = Celixir.Environment.new() |> Celixir.Ext.Lists.register()
      Celixir.eval!("lists.range(5)", env)          # => [0, 1, 2, 3, 4]
      Celixir.eval!("[3, 1, 2].distinct()", env)    # => [3, 1, 2]
      Celixir.eval!("[1, 2, 2].distinct()", env)    # => [1, 2]
      Celixir.eval!("[1, 2, 3].first().value()", env)  # => 1
      Celixir.eval!("[1, 2, 3].last().value()", env)   # => 3
      Celixir.eval!("[3, 1, 2].sort()", env)        # => [1, 2, 3]
      Celixir.eval!("[3, 1, 2].reverse()", env)     # => [2, 1, 3]
      Celixir.eval!("[1, [2, 3]].flatten()", env)   # => [1, 2, 3]
      Celixir.eval!("[1, [2, [3]]].flatten(1)", env)# => [1, 2, [3]]

  ## Two-variable comprehensions (parser macros, always available)

  - `list.sortBy(e, e.field)` — sort list by computed key expression
  - `list.transformMapEntry(k, v, {v: k})` — build map with custom key-value pairs

  ## Functions

  - `lists.range(int)` — generate [0, 1, ..., n-1]
  - `list.distinct()` — deduplicate preserving order
  - `list.first()` — optional first element
  - `list.last()` — optional last element
  - `list.slice(int, int)` — sub-list
  - `list.flatten()` / `list.flatten(int)` — recursive flatten with optional depth
  - `list.sort()` — sort comparable elements
  - `list.reverse()` — reverse
  """

  alias Celixir.Environment
  alias Celixir.Types.Optional

  @doc """
  Registers list extension functions into the given environment.
  """
  def register(env \\ Environment.new()) do
    env
    |> Environment.put_function("lists.range", &range/1)
    |> Environment.put_function("distinct", &distinct/1)
    |> Environment.put_function("first", &first/1)
    |> Environment.put_function("last", &last/1)
  end

  def range(n) when is_integer(n) and n < 0, do: raise("lists.range: negative argument")
  def range(0), do: []
  def range(n) when is_integer(n), do: Enum.to_list(0..(n - 1))

  def distinct(list) when is_list(list) do
    Enum.reduce(list, [], fn item, acc ->
      if Enum.member?(acc, item), do: acc, else: acc ++ [item]
    end)
  end

  def first([]), do: Optional.none()
  def first([head | _]), do: Optional.of(head)

  def last([]), do: Optional.none()
  def last(list) when is_list(list), do: Optional.of(List.last(list))

  def flatten(list, depth) when is_list(list) and is_integer(depth) do
    cond do
      depth < 0 -> raise "flatten: depth must be non-negative"
      depth == 0 -> list
      true -> do_flatten_depth(list, depth)
    end
  end

  defp do_flatten_depth(list, 0), do: list

  defp do_flatten_depth(list, depth) do
    Enum.flat_map(list, fn
      sub when is_list(sub) -> do_flatten_depth(sub, depth - 1)
      item -> [item]
    end)
  end
end
