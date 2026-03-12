defmodule Celixir.Sigil do
  @moduledoc """
  Provides the `~CEL` sigil for compile-time parsing of CEL expressions.

  ## Usage

      import Celixir.Sigil

      # Parse at compile time, evaluate at runtime
      ast = ~CEL|request.method == "GET" && user.role == "admin"|
      Celixir.Evaluator.eval(ast, env)

      # With the 'e' modifier, evaluates immediately with an empty environment
      result = ~CEL|1 + 2 * 3|e
  """

  alias Celixir.Environment
  alias Celixir.Evaluator
  alias Celixir.Lexer
  alias Celixir.Parser

  @doc """
  Parses a CEL expression at compile time into an AST.

  Modifiers:
    - (none): returns the parsed AST
    - `e`: evaluates with an empty environment and returns the result

  ## Examples

      import Celixir.Sigil

      ast = ~CEL|1 + 2|
      {:ok, 3} = Celixir.Evaluator.eval(ast, Celixir.Environment.new())

      7 = ~CEL|3 + 4|e
  """
  defmacro sigil_CEL(term, modifiers)

  defmacro sigil_CEL({:<<>>, _meta, [expr]}, []) when is_binary(expr) do
    ast =
      with {:ok, tokens} <- Lexer.tokenize(expr),
           {:ok, ast} <- Parser.parse(tokens) do
        ast
      else
        {:error, msg} -> raise CompileError, description: "CEL error: #{msg}"
      end

    Macro.escape(ast)
  end

  defmacro sigil_CEL({:<<>>, _meta, [expr]}, [?e]) when is_binary(expr) do
    result =
      with {:ok, tokens} <- Lexer.tokenize(expr),
           {:ok, ast} <- Parser.parse(tokens),
           {:ok, value} <- Evaluator.eval(ast, Environment.new()) do
        Celixir.unwrap(value)
      else
        {:error, msg} -> raise CompileError, description: "CEL error: #{msg}"
      end

    Macro.escape(result)
  end
end
