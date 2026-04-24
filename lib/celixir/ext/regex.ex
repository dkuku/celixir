defmodule Celixir.Ext.Regex do
  @moduledoc """
  Regex extension for CEL — mirrors `ext.Regex()` from cel-go.

  Provides regular expression functions under the `regex.*` namespace.
  All functions are available as built-ins (no registration needed), though
  calling `register/1` documents intent and is recommended for clarity.

  Note: `regex.extract` returns an optional value, so optional method calls
  like `.value()` and `.orValue(default)` work on the result.

  ## Usage

      # Functions work without registration (built-in)
      Celixir.eval!(~s|regex.replace("hello world", "hello", "hi")|)
      # => "hi world"

      Celixir.eval!(~s|regex.extract("item-A", "item-(\\\\w+)").value()|)
      # => "A"

      Celixir.eval!(~s|regex.extractAll("id:1, id:2", "id:\\\\d+")|)
      # => ["id:1", "id:2"]

      # Explicit opt-in (recommended)
      env = Celixir.Environment.new() |> Celixir.Ext.Regex.register()

  ## Functions

  - `regex.replace(target, pattern, replacement)` — replace all matches
  - `regex.replace(target, pattern, replacement, count)` — replace first N matches
    (count=0 keeps original, count<0 replaces all)
  - `regex.extract(target, pattern)` — optional first match (or first capture group)
  - `regex.extractAll(target, pattern)` — list of all matches

  All functions error on invalid regex or invalid replacement string.
  Only `\\N` numeric capture-group references are supported in replacements.
  `$N` style references are not supported (error).
  """

  alias Celixir.Environment
  alias Celixir.Types.Optional

  @doc """
  Registers regex extension functions into the given environment.

  Note: `regex.replace` cannot be registered via environment dispatch because
  it supports both 3-arg and 4-arg forms and Elixir anonymous functions do not
  support mixed arities. It is always available as a built-in.
  """
  def register(env \\ Environment.new()) do
    env
    |> Environment.put_function("regex.extract", &extract/2)
    |> Environment.put_function("regex.extractAll", &extract_all/2)
  end

  @doc "Replace matches of `pattern` in `target` with `replacement`. count=-1 replaces all."
  def replace(target, pattern, replacement, count \\ -1)
      when is_binary(target) and is_binary(pattern) and is_binary(replacement) and
             is_integer(count) do
    with :ok <- validate_replacement(replacement),
         {:ok, regex} <- Elixir.Regex.compile(pattern) do
      do_replace(target, regex, replacement, count)
    else
      {:error, msg} -> raise format_error(msg)
    end
  end

  @doc "Return optional first match (or first capture group) of `pattern` in `target`."
  def extract(target, pattern) when is_binary(target) and is_binary(pattern) do
    with {:ok, n} <- count_groups(pattern),
         {:ok, regex} <- Elixir.Regex.compile(pattern) do
      if n > 1 do
        raise "regex.extract: multiple capture groups not allowed"
      else
        case Elixir.Regex.run(regex, target) do
          nil -> Optional.none()
          [full_match] -> Optional.of(full_match)
          [_, group] -> Optional.of(group)
        end
      end
    else
      {:error, msg} -> raise msg
    end
  end

  @doc "Return list of all matches (or first capture groups) of `pattern` in `target`."
  def extract_all(target, pattern) when is_binary(target) and is_binary(pattern) do
    with {:ok, n} <- count_groups(pattern),
         {:ok, regex} <- Elixir.Regex.compile(pattern) do
      cond do
        n > 1 ->
          raise "regex.extractAll: multiple capture groups not allowed"

        n == 1 ->
          Elixir.Regex.scan(regex, target) |> Enum.map(fn [_, group] -> group end)

        true ->
          Elixir.Regex.scan(regex, target) |> Enum.map(fn [full] -> full end)
      end
    else
      {:error, msg} -> raise msg
    end
  end

  defp do_replace(target, _regex, _replacement, 0), do: target

  defp do_replace(target, regex, replacement, count) when count < 0 do
    Elixir.Regex.replace(regex, target, replacement)
  end

  defp do_replace(target, regex, replacement, n) when n > 0 do
    do_limited_replace(target, regex, replacement, n, "")
  end

  defp do_limited_replace(remaining, _regex, _replacement, 0, acc), do: acc <> remaining

  defp do_limited_replace(remaining, regex, replacement, n, acc) do
    case Elixir.Regex.run(regex, remaining, return: :index, capture: :all) do
      nil ->
        acc <> remaining

      [{start, len} | groups] ->
        prefix = binary_part(remaining, 0, start)
        replaced = apply_backrefs(replacement, remaining, groups)
        rest = binary_part(remaining, start + len, byte_size(remaining) - start - len)
        do_limited_replace(rest, regex, replacement, n - 1, acc <> prefix <> replaced)
    end
  end

  defp apply_backrefs(replacement, source, groups) do
    Elixir.Regex.replace(~r/\\(\d)/, replacement, fn _, n_str ->
      idx = String.to_integer(n_str) - 1

      case Enum.at(groups, idx) do
        nil -> ""
        {-1, 0} -> ""
        {gstart, glen} -> binary_part(source, gstart, glen)
      end
    end)
  end

  defp validate_replacement(replacement) do
    cond do
      String.contains?(replacement, "$") ->
        {:error, "invalid replacement string: $ is not supported, use \\N"}

      Elixir.Regex.match?(~r/\\[^0-9\\]/, replacement) ->
        {:error, "invalid replacement string: only \\N numeric group references are supported"}

      true ->
        :ok
    end
  end

  defp format_error(msg) when is_binary(msg), do: msg
  defp format_error({msg, _}) when is_list(msg), do: "invalid regex pattern: #{msg}"
  defp format_error(other), do: "regex error: #{inspect(other)}"

  defp count_groups(pattern) do
    case Elixir.Regex.compile(pattern) do
      {:error, _} -> {:error, "invalid regex pattern: #{inspect(pattern)}"}
      {:ok, _} -> {:ok, do_count_parens(pattern, 0)}
    end
  end

  defp do_count_parens(<<>>, n), do: n
  defp do_count_parens(<<"\\", _::8, rest::binary>>, n), do: do_count_parens(rest, n)
  defp do_count_parens(<<"(?:", rest::binary>>, n), do: do_count_parens(rest, n)
  defp do_count_parens(<<"(?=", rest::binary>>, n), do: do_count_parens(rest, n)
  defp do_count_parens(<<"(?!", rest::binary>>, n), do: do_count_parens(rest, n)
  defp do_count_parens(<<"(?<!", rest::binary>>, n), do: do_count_parens(rest, n)
  defp do_count_parens(<<"(?<=", rest::binary>>, n), do: do_count_parens(rest, n)
  defp do_count_parens(<<"(", rest::binary>>, n), do: do_count_parens(rest, n + 1)
  defp do_count_parens(<<_::8, rest::binary>>, n), do: do_count_parens(rest, n)
end
