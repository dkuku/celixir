defmodule Celixir.Conformance.Runner do
  @moduledoc """
  Runs cel-spec conformance tests from textproto files against the Celixir evaluator.

  ## Usage

      results = Celixir.Conformance.Runner.run_file("test/cel_spec/testdata/basic.textproto")
      IO.puts("\#{results.passed}/\#{results.total} passed")

      # Or run all files:
      Celixir.Conformance.Runner.run_all("test/cel_spec/testdata/")
  """

  alias Celixir.Conformance.TextprotoParser

  @type result :: %{
          file: String.t(),
          section: String.t(),
          test: String.t(),
          status: :pass | :fail | :skip,
          message: String.t() | nil
        }

  @type summary :: %{
          total: non_neg_integer(),
          passed: non_neg_integer(),
          failed: non_neg_integer(),
          skipped: non_neg_integer(),
          results: [result()]
        }

  @doc "Run all textproto files in a directory."
  def run_all(dir) do
    dir
    |> Path.join("*.textproto")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&run_file/1)
    |> merge_summaries()
  end

  @doc "Run a single textproto test file."
  def run_file(path) do
    content = File.read!(path)
    file_data = TextprotoParser.parse(content)
    file_name = file_data.name || Path.basename(path, ".textproto")

    results =
      for section <- file_data.sections,
          test <- section.tests do
        run_test(file_name, section.name, test)
      end

    summarize(results)
  end

  @doc "Run a parsed test and return a result."
  def run_test(file, section, test) do
    base = %{file: file, section: section, test: test.name, status: nil, message: nil}

    try do
      bindings = convert_bindings(test.bindings)

      case Celixir.eval(test.expr, bindings) do
        {:ok, actual} ->
          if test.eval_error do
            %{base | status: :fail, message: "expected error but got: #{inspect(actual)}"}
          else
            case match_value(test.value, actual) do
              :match -> %{base | status: :pass, message: nil}
              {:mismatch, msg} -> %{base | status: :fail, message: msg}
            end
          end

        {:error, _msg} ->
          if test.eval_error do
            %{base | status: :pass, message: nil}
          else
            %{base | status: :fail, message: "unexpected error for expr: #{test.expr}"}
          end
      end
    rescue
      e ->
        if test.eval_error do
          %{base | status: :pass, message: nil}
        else
          %{base | status: :fail, message: "exception: #{Exception.message(e)}"}
        end
    end
  end

  # Convert textproto binding values to Elixir values for the evaluator
  defp convert_bindings(bindings) when map_size(bindings) == 0, do: %{}

  defp convert_bindings(bindings) do
    Map.new(bindings, fn {key, typed_val} ->
      {key, convert_typed_value(typed_val)}
    end)
  end

  defp convert_typed_value({:int64, v}), do: v
  defp convert_typed_value({:uint64, v}), do: v
  defp convert_typed_value({:double, v}), do: v * 1.0
  defp convert_typed_value({:bool, v}), do: v
  defp convert_typed_value({:string, v}), do: v
  defp convert_typed_value({:bytes, v}), do: v
  defp convert_typed_value({:null, _}), do: nil
  defp convert_typed_value({:list, items}), do: Enum.map(items, &convert_typed_value/1)

  defp convert_typed_value({:map, entries}) do
    Map.new(entries, fn {k, v} -> {convert_typed_value(k), convert_typed_value(v)} end)
  end

  defp convert_typed_value(nil), do: nil

  # Match actual eval result against expected typed value
  # No expected value specified
  defp match_value(nil, _actual), do: :match
  defp match_value({:null, _}, nil), do: :match
  defp match_value({:null, _}, actual), do: {:mismatch, "expected null, got #{inspect(actual)}"}

  defp match_value({:bool, expected}, actual) when is_boolean(actual) do
    if expected == actual, do: :match, else: {:mismatch, "expected #{expected}, got #{actual}"}
  end

  defp match_value({:int64, expected}, actual) when is_integer(actual) do
    if expected == actual,
      do: :match,
      else: {:mismatch, "expected int #{expected}, got #{actual}"}
  end

  defp match_value({:uint64, expected}, actual) when is_integer(actual) do
    if expected == actual,
      do: :match,
      else: {:mismatch, "expected uint #{expected}, got #{actual}"}
  end

  defp match_value({:double, expected}, actual) when is_float(actual) do
    if close_enough?(expected, actual),
      do: :match,
      else: {:mismatch, "expected double #{expected}, got #{actual}"}
  end

  defp match_value({:double, expected}, actual) when is_atom(actual) and actual in [:infinity, :neg_infinity, :nan] do
    if expected == actual, do: :match, else: {:mismatch, "expected #{expected}, got #{actual}"}
  end

  defp match_value({:string, expected}, actual) when is_binary(actual) do
    if expected == actual,
      do: :match,
      else: {:mismatch, "expected string #{inspect(expected)}, got #{inspect(actual)}"}
  end

  defp match_value({:bytes, expected}, actual) when is_binary(actual) do
    if expected == actual,
      do: :match,
      else: {:mismatch, "expected bytes #{inspect(expected)}, got #{inspect(actual)}"}
  end

  defp match_value({:list, expected_items}, actual) when is_list(actual) do
    if length(expected_items) == length(actual) do
      results = expected_items |> Enum.zip(actual) |> Enum.map(fn {e, a} -> match_value(e, a) end)

      case Enum.find(results, fn r -> r != :match end) do
        nil -> :match
        err -> err
      end
    else
      {:mismatch, "list length mismatch: expected #{length(expected_items)}, got #{length(actual)}"}
    end
  end

  defp match_value({:map, expected_entries}, actual) when is_map(actual) do
    if length(expected_entries) == map_size(actual) do
      Enum.reduce_while(expected_entries, :match, fn {exp_key, exp_val}, :match ->
        # Find the actual map entry whose key matches the expected key
        case find_matching_key(actual, exp_key) do
          {:ok, actual_val} ->
            case match_value(exp_val, actual_val) do
              :match -> {:cont, :match}
              err -> {:halt, err}
            end

          :not_found ->
            {:halt, {:mismatch, "map key not found: #{inspect(exp_key)}"}}
        end
      end)
    else
      {:mismatch, "map size mismatch: expected #{length(expected_entries)}, got #{map_size(actual)}"}
    end
  end

  defp match_value({:type, expected_type}, actual) when is_atom(actual) do
    actual_str = Atom.to_string(actual)

    if expected_type == actual_str,
      do: :match,
      else: {:mismatch, "expected type #{expected_type}, got #{actual_str}"}
  end

  defp match_value(expected, actual) do
    {:mismatch, "type mismatch: expected #{inspect(expected)}, got #{inspect(actual)} (#{typeof(actual)})"}
  end

  defp typeof(v) when is_integer(v), do: "integer"
  defp typeof(v) when is_float(v), do: "float"
  defp typeof(v) when is_boolean(v), do: "bool"
  defp typeof(v) when is_binary(v), do: "string"
  defp typeof(v) when is_list(v), do: "list"
  defp typeof(v) when is_map(v), do: "map"
  defp typeof(v) when is_atom(v), do: "atom(#{v})"
  defp typeof(_), do: "unknown"

  defp close_enough?(a, b) when is_float(a) and is_float(b) do
    abs(a - b) < 1.0e-10 or (a == 0.0 and b == 0.0)
  end

  defp close_enough?(a, b), do: a == b

  # Find a key in the actual map that matches the expected typed key.
  # Expected keys are typed tuples like {:int64, 1}, {:string, "k"}, etc.
  # Actual map keys are plain Elixir values (integers, strings, etc.).
  defp find_matching_key(actual_map, expected_key) do
    expected_val = convert_typed_value(expected_key)

    Enum.find_value(actual_map, :not_found, fn {actual_key, actual_val} ->
      if keys_match?(expected_key, actual_key, expected_val) do
        {:ok, actual_val}
      end
    end)
  end

  defp keys_match?({:int64, v}, actual, _) when is_integer(actual), do: v == actual
  defp keys_match?({:uint64, v}, actual, _) when is_integer(actual), do: v == actual
  defp keys_match?({:string, v}, actual, _) when is_binary(actual), do: v == actual
  defp keys_match?({:bool, v}, actual, _) when is_boolean(actual), do: v == actual
  defp keys_match?({:double, v}, actual, _) when is_float(actual), do: close_enough?(v, actual)
  defp keys_match?(_, actual, expected_val), do: expected_val == actual

  defp summarize(results) do
    %{
      total: length(results),
      passed: Enum.count(results, &(&1.status == :pass)),
      failed: Enum.count(results, &(&1.status == :fail)),
      skipped: Enum.count(results, &(&1.status == :skip)),
      results: results
    }
  end

  defp merge_summaries(summaries) do
    %{
      total: Enum.sum(Enum.map(summaries, & &1.total)),
      passed: Enum.sum(Enum.map(summaries, & &1.passed)),
      failed: Enum.sum(Enum.map(summaries, & &1.failed)),
      skipped: Enum.sum(Enum.map(summaries, & &1.skipped)),
      results: Enum.flat_map(summaries, & &1.results)
    }
  end
end
