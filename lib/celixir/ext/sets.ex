defmodule Celixir.Ext.Sets do
  @moduledoc """
  Sets extension for CEL — mirrors `ext.Sets()` from cel-go.

  Provides set-relationship tests on lists. Functions are available as
  built-ins and also via explicit registration.

  ## Usage

      env = Celixir.Environment.new() |> Celixir.Ext.Sets.register()
      Celixir.eval!("sets.contains([1, 2, 3], [2, 3])", env)     # => true
      Celixir.eval!("sets.equivalent([1, 2], [2, 1])", env)      # => true
      Celixir.eval!("sets.intersects([1, 2], [2, 3])", env)      # => true

  ## Functions

  - `sets.contains(list, list)` — true if first contains all elements of second
  - `sets.equivalent(list, list)` — true if sets are equal (order-independent)
  - `sets.intersects(list, list)` — true if any element appears in both lists
  """

  alias Celixir.Environment

  @doc """
  Registers sets extension functions into the given environment.
  """
  def register(env \\ Environment.new()) do
    env
    |> Environment.put_function("sets.contains", &contains/2)
    |> Environment.put_function("sets.equivalent", &equivalent/2)
    |> Environment.put_function("sets.intersects", &intersects/2)
  end

  def contains(list, sublist) when is_list(list) and is_list(sublist) do
    Enum.all?(sublist, &Enum.member?(list, &1))
  end

  def equivalent(list1, list2) when is_list(list1) and is_list(list2) do
    Enum.all?(list1, &Enum.member?(list2, &1)) and
      Enum.all?(list2, &Enum.member?(list1, &1))
  end

  def intersects(list1, list2) when is_list(list1) and is_list(list2) do
    Enum.any?(list1, &Enum.member?(list2, &1))
  end
end
