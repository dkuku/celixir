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

  ## Create Reusable Functions

      validator = Celixir.to_fun!("age >= 18 && status == 'active'")

      validator.(%{age: 25, status: "active"})   # => {:ok, true}
      validator.(%{age: 15, status: "active"})   # => {:ok, false}

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
      or declaratively with `Celixir.API` and `defcel`
    * **Reusable functions**: `to_fun/1` compiles to a plain anonymous function
    * **File loading**: `load_file/1` loads expressions from files
    * **Value encoding**: `encode/1` converts Elixir values to CEL internal types
    * **Protobuf integration**: field access, has() checks, well-known type
      conversion via `Celixir.ProtobufAdapter`
    * **Static type checking**: optional pre-evaluation validation via
      `Celixir.Checker`
    * **Compile-time sigil**: `~CEL|expr|` for zero-cost parsed ASTs

  ## Custom Functions

  Register Elixir functions to call from CEL expressions. Functions receive
  plain Elixir values and should return plain Elixir values.

      # Simple function
      env = Celixir.Environment.new(%{name: "world"})
            |> Celixir.Environment.put_function("greet", fn name -> "Hello, \#{name}!" end)

      Celixir.eval("greet(name)", env)
      # => {:ok, "Hello, world!"}

      # Multi-argument
      env = Celixir.Environment.new()
            |> Celixir.Environment.put_function("clamp", fn val, lo, hi ->
              val |> max(lo) |> min(hi)
            end)

      Celixir.eval("clamp(150, 0, 100)", env)
      # => {:ok, 100}

      # Module function reference
      env = Celixir.Environment.new()
            |> Celixir.Environment.put_function("factorial", &MyMath.factorial/1)

      # Namespaced functions (dot-separated names)
      env = Celixir.Environment.new()
            |> Celixir.Environment.put_function("str.reverse", &MyString.reverse/1)
            |> Celixir.Environment.put_function("str.repeat", &MyString.repeat/2)

  To build a reusable function library, group registrations in a module:

      defmodule MyApp.CelLibrary do
        def register(env \\\\ Celixir.Environment.new()) do
          env
          |> Celixir.Environment.put_function("slugify", &slugify/1)
          |> Celixir.Environment.put_function("format.currency", &format_currency/2)
        end

        defp slugify(s), do: s |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")
        defp format_currency(amount, cur), do: "\#{cur} \#{:erlang.float_to_binary(amount / 1.0, decimals: 2)}"
      end
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
    with {:ok, ast} <- parse(expression) do
      {:ok, Celixir.Program.new(ast, expression)}
    end
  end

  @doc """
  Loads a CEL expression from a file and compiles it into a `Celixir.Program`.

  ## Examples

      {:ok, program} = Celixir.load_file("path/to/rule.cel")
      Celixir.Program.eval(program, %{x: 42})
  """
  @spec load_file(String.t()) :: {:ok, Celixir.Program.t()} | {:error, String.t()}
  def load_file(path) do
    case File.read(path) do
      {:ok, contents} -> compile(String.trim(contents))
      {:error, reason} -> {:error, "failed to read #{path}: #{:file.format_error(reason)}"}
    end
  end

  @doc """
  Like `load_file/1` but raises on error.
  """
  @spec load_file!(String.t()) :: Celixir.Program.t()
  def load_file!(path) do
    case load_file(path) do
      {:ok, program} -> program
      {:error, msg} -> raise Celixir.Error, message: msg
    end
  end

  @doc """
  Compiles a CEL expression and returns a callable function.

  The returned function takes a bindings map (or `Celixir.Environment`) and
  returns `{:ok, result}` or `{:error, message}`.

  ## Examples

      iex> fun = Celixir.to_fun!("x * 2 + y")
      iex> fun.(%{x: 5, y: 1})
      {:ok, 11}

      iex> fun = Celixir.to_fun!("name.startsWith('hello')")
      iex> fun.(%{name: "hello world"})
      {:ok, true}
  """
  @spec to_fun(String.t()) :: {:ok, (map() -> {:ok, any()} | {:error, String.t()})} | {:error, String.t()}
  def to_fun(expression) do
    with {:ok, ast} <- parse(expression) do
      fun = fn bindings ->
        env =
          case bindings do
            %Environment{} = e -> e
            map when is_map(map) -> Environment.new(map)
          end

        with {:ok, result} <- Evaluator.eval(ast, env) do
          {:ok, unwrap(result)}
        end
      end

      {:ok, fun}
    end
  end

  @doc """
  Like `to_fun/1` but raises on parse error.

  ## Examples

      iex> fun = Celixir.to_fun!("x + 1")
      iex> fun.(%{x: 10})
      {:ok, 11}
  """
  @spec to_fun!(String.t()) :: (map() -> {:ok, any()} | {:error, String.t()})
  def to_fun!(expression) do
    case to_fun(expression) do
      {:ok, fun} -> fun
      {:error, msg} -> raise Celixir.Error, message: "CEL compilation error: #{msg}"
    end
  end

  @doc """
  Evaluates a pre-parsed AST with the given environment or bindings map.
  """
  @spec eval_ast(Celixir.AST.expr(), Environment.t() | map()) ::
          {:ok, any()} | {:error, String.t()}
  def eval_ast(ast, %Environment{} = env) do
    with {:ok, result} <- Evaluator.eval(ast, env) do
      {:ok, unwrap(result)}
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

  @doc """
  Encodes a plain Elixir value into CEL internal representation.

  This is the inverse of `unwrap/1`. Since unwrapping loses some type
  information (e.g., both `cel_int` and `cel_uint` unwrap to plain integers),
  `encode` uses sensible defaults: integers become `{:cel_int, v}`.

  ## Examples

      iex> Celixir.encode(42)
      {:cel_int, 42}

      iex> Celixir.encode("hello")
      "hello"

      iex> Celixir.encode([1, 2, 3])
      [{:cel_int, 1}, {:cel_int, 2}, {:cel_int, 3}]

      iex> Celixir.encode(:optional_none)
      %Celixir.Types.Optional{has_value: false}
  """
  def encode(v) when is_integer(v), do: {:cel_int, v}
  def encode({:optional, v}), do: %Optional{has_value: true, value: encode(v)}
  def encode(:optional_none), do: %Optional{has_value: false}
  def encode(list) when is_list(list), do: Enum.map(list, &encode/1)

  def encode(map) when is_map(map) and not is_struct(map) do
    Map.new(map, fn {k, v} -> {encode(k), encode(v)} end)
  end

  def encode(v), do: v

  @doc """
  Encodes an integer as a CEL unsigned integer.

      iex> Celixir.encode_uint(42)
      {:cel_uint, 42}
  """
  def encode_uint(v) when is_integer(v) and v >= 0, do: {:cel_uint, v}

  @doc """
  Encodes a binary as CEL bytes.

      iex> Celixir.encode_bytes(<<1, 2, 3>>)
      {:cel_bytes, <<1, 2, 3>>}
  """
  def encode_bytes(v) when is_binary(v), do: {:cel_bytes, v}
end
