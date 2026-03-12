defmodule Celixir do
  @moduledoc """
  A pure Elixir implementation of Google's Common Expression Language (CEL).

  CEL is a non-Turing-complete expression language designed for simplicity, speed,
  and safety. It is commonly used in security policies, protocol buffers, and
  configuration validation.

  ## Quick Start

      iex> Celixir.eval("1 + 2")
      {:ok, 3}

      iex> Celixir.eval("name.startsWith('hello')", %{name: "hello world"})
      {:ok, true}

      iex> Celixir.eval("x > 10 ? 'big' : 'small'", %{x: 42})
      {:ok, "big"}

  ## Compile Once, Evaluate Many

      {:ok, program} = Celixir.compile("x * 2 + y")

      Celixir.Program.eval(program, %{x: 5, y: 1})   # => {:ok, 11}
      Celixir.Program.eval(program, %{x: 10, y: 3})   # => {:ok, 23}

  ## Supported Features

    * **Types**: int, uint, double, bool, string, bytes, list, map, null,
      timestamp, duration, optional, type
    * **Operators**: arithmetic (`+`, `-`, `*`, `/`, `%`), comparison
      (`==`, `!=`, `<`, `<=`, `>`, `>=`), logical (`&&`, `||`, `!`),
      ternary (`?:`), membership (`in`)
    * **String functions**: `contains`, `startsWith`, `endsWith`, `matches`,
      `size`, `charAt`, `indexOf`, `lastIndexOf`, `lowerAscii`, `upperAscii`,
      `replace`, `split`, `substring`, `trim`, `join`, `reverse`
    * **Math functions**: `math.least`, `math.greatest`, `math.ceil`,
      `math.floor`, `math.round`, `math.abs`, `math.sign`, `math.isNaN`,
      `math.isInf`, `math.isFinite`
    * **List functions**: `size`, `sort`, `slice`, `flatten`, `reverse`,
      `lists.range`
    * **Set functions**: `sets.contains`, `sets.intersects`, `sets.equivalent`
    * **Comprehension macros**: `all`, `exists`, `exists_one`, `filter`, `map`
    * **Type conversions**: `int()`, `uint()`, `double()`, `string()`,
      `bool()`, `bytes()`, `timestamp()`, `duration()`, `dyn()`, `type()`
    * **Optional values**: `optional.of()`, `optional.none()`,
      `optional.ofNonZeroValue()`, `.hasValue()`, `.value()`, `.orValue()`, `.or()`
    * **Encoding**: `base64.encode()`, `base64.decode()`
    * **Custom functions**: register your own via `Celixir.Environment.put_function/3`
    * **Protobuf integration**: field access, has() checks, well-known type
      conversion via `Celixir.ProtobufAdapter`
    * **Static type checking**: optional pre-evaluation validation via
      `Celixir.Checker`
    * **Compile-time sigil**: `~CEL|expr|` for zero-cost parsed ASTs

  ## Custom Functions

      env = Celixir.Environment.new(%{name: "world"})
            |> Celixir.Environment.put_function("greet", fn name -> "Hello, \#{name}!" end)

      Celixir.eval("greet(name)", env)
      # => {:ok, "Hello, world!"}
  """

  alias Celixir.Environment
  alias Celixir.Evaluator
  alias Celixir.Lexer
  alias Celixir.Parser
  alias Celixir.Types.Optional

  defmodule Error do
    @moduledoc "Exception raised by bang functions on CEL evaluation failure."
    defexception [:message]
  end

  @doc """
  Parses and evaluates a CEL expression with optional variable bindings.

  Returns `{:ok, result}` on success or `{:error, message}` on failure.
  Results are unwrapped from internal tagged types to plain Elixir values.

  ## Examples

      iex> Celixir.eval("1 + 2")
      {:ok, 3}

      iex> Celixir.eval("x > 0", %{x: 5})
      {:ok, true}

      iex> Celixir.eval("undefined_var")
      {:error, "undefined variable: undefined_var"}
  """
  @spec eval(String.t(), map() | Environment.t()) :: {:ok, any()} | {:error, String.t()}
  def eval(expression, bindings \\ %{})

  def eval(expression, %Environment{} = env) do
    with {:ok, ast} <- parse(expression),
         {:ok, result} <- Evaluator.eval(ast, env) do
      {:ok, unwrap(result)}
    end
  end

  def eval(expression, bindings) when is_map(bindings) do
    eval(expression, Environment.new(bindings))
  end

  @doc """
  Parses a CEL expression string into an AST.

  The AST can be evaluated later with `eval_ast/2` or stored for reuse.

  ## Examples

      iex> {:ok, ast} = Celixir.parse("1 + 2")
      iex> Celixir.eval_ast(ast, %{})
      {:ok, 3}
  """
  @spec parse(String.t()) :: {:ok, Celixir.AST.expr()} | {:error, String.t()}
  def parse(expression) do
    with {:ok, tokens} <- Lexer.tokenize(expression) do
      Parser.parse(tokens)
    end
  end

  @doc """
  Parses and evaluates a CEL expression, raising on error.

  ## Examples

      iex> Celixir.eval!("2 * 3")
      6
  """
  @spec eval!(String.t(), map() | Environment.t()) :: any()
  def eval!(expression, bindings \\ %{}) do
    case eval(expression, bindings) do
      {:ok, result} -> result
      {:error, msg} -> raise Celixir.Error, message: "CEL evaluation error: #{msg}"
    end
  end

  @doc """
  Compiles a CEL expression into a reusable `Celixir.Program`.

  Parse once, evaluate many times with different bindings.

  ## Examples

      {:ok, program} = Celixir.compile("x > threshold")
      Celixir.Program.eval(program, %{x: 100, threshold: 50})
  """
  @spec compile(String.t()) :: {:ok, Celixir.Program.t()} | {:error, String.t()}
  def compile(expression) do
    case parse(expression) do
      {:ok, ast} -> {:ok, Celixir.Program.new(ast, expression)}
      {:error, _} = err -> err
    end
  end

  @doc """
  Evaluates a pre-parsed AST with the given environment or bindings map.
  """
  @spec eval_ast(Celixir.AST.expr(), Environment.t() | map()) ::
          {:ok, any()} | {:error, String.t()}
  def eval_ast(ast, %Environment{} = env) do
    case Evaluator.eval(ast, env) do
      {:ok, result} -> {:ok, unwrap(result)}
      {:error, _} = err -> err
    end
  end

  def eval_ast(ast, bindings) when is_map(bindings) do
    eval_ast(ast, Environment.new(bindings))
  end

  @doc false
  def unwrap({:cel_int, v}), do: v
  def unwrap({:cel_uint, v}), do: v
  def unwrap({:cel_bytes, v}), do: v
  def unwrap(%Optional{has_value: true, value: v}), do: {:optional, unwrap(v)}
  def unwrap(%Optional{has_value: false}), do: :optional_none
  def unwrap(list) when is_list(list), do: Enum.map(list, &unwrap/1)

  def unwrap(map) when is_map(map) and not is_struct(map) do
    Map.new(map, fn {k, v} -> {unwrap(k), unwrap(v)} end)
  end

  def unwrap(v), do: v
end
