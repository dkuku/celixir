defmodule Celixir.Ext.Strings do
  @moduledoc """
  Strings extension for CEL — mirrors `ext.Strings()` from cel-go.

  Provides extended string functions. Most string methods (charAt, indexOf,
  substring, split, join, lowerAscii, upperAscii, trim, replace, reverse,
  lastIndexOf) are available as built-ins. This module adds explicit
  registration and the `strings.quote` global function.

  ## Usage

      env = Celixir.Environment.new() |> Celixir.Ext.Strings.register()
      Celixir.eval!(~s|strings.quote("hello\\nworld")|, env)
      # => "\"hello\\\\nworld\""

  ## Functions (method style, on strings)

  - `str.charAt(int)` — character at index
  - `str.indexOf(string)` / `str.indexOf(string, int)` — first occurrence index
  - `str.lastIndexOf(string)` / `str.lastIndexOf(string, int)` — last occurrence
  - `str.substring(int)` / `str.substring(int, int)` — substring
  - `str.split(string)` / `str.split(string, int)` — split into list
  - `str.join()` / `str.join(string)` — join list of strings
  - `str.lowerAscii()` — ASCII lowercase
  - `str.upperAscii()` — ASCII uppercase
  - `str.trim()` — trim leading/trailing whitespace
  - `str.replace(old, new)` / `str.replace(old, new, int)` — replace substrings
  - `str.reverse()` — reverse characters
  - `strings.quote(string)` — safely quote a string for printing
  """

  alias Celixir.Environment

  @doc """
  Registers string extension functions into the given environment.
  """
  def register(env \\ Environment.new()) do
    Environment.put_function(env, "strings.quote", &quote_string/1)
  end

  def quote_string(s) when is_binary(s) do
    escaped =
      s
      |> String.graphemes()
      |> Enum.map_join(fn
        "\\" ->
          "\\\\"

        "\"" ->
          "\\\""

        "\n" ->
          "\\n"

        "\t" ->
          "\\t"

        "\r" ->
          "\\r"

        "\a" ->
          "\\a"

        "\b" ->
          "\\b"

        "\f" ->
          "\\f"

        "\v" ->
          "\\v"

        <<c::utf8>> = char ->
          if c >= 0x20 and c != 0x7F do
            char
          else
            "\\x" <> String.pad_leading(Integer.to_string(c, 16), 2, "0")
          end
      end)

    "\"" <> escaped <> "\""
  end
end
