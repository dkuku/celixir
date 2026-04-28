defmodule Celixir.Program do
  @moduledoc """
  A compiled CEL program — parse once, evaluate many times.

  ## Usage

      {:ok, program} = Celixir.compile("x > 10 && y < 20")

      {:ok, true} = Celixir.Program.eval(program, %{x: 15, y: 5})
      {:ok, false} = Celixir.Program.eval(program, %{x: 5, y: 5})
  """

  defstruct [:ast, :source, :fun]

  @type t :: %__MODULE__{
          ast: Celixir.AST.expr(),
          source: String.t(),
          fun: (Celixir.Environment.t() -> {:ok, any()} | {:error, String.t()}) | nil
        }

  @doc "Creates a program from a parsed AST, compiling to a native function."
  def new(ast, source \\ "<compiled>") do
    fun =
      case Celixir.Compiler.compile(ast) do
        {:ok, f} -> f
        {:error, _} -> nil
      end

    %__MODULE__{ast: ast, source: source, fun: fun}
  end

  @doc "Evaluates the program with the given bindings."
  def eval(%__MODULE__{fun: fun, ast: ast}, bindings \\ %{}) do
    env =
      case bindings do
        %Celixir.Environment{} = e -> e
        map when is_map(map) -> Celixir.Environment.new(map)
      end

    if fun do
      fun.(env)
    else
      with {:ok, result} <- Celixir.Evaluator.eval(ast, env) do
        {:ok, Celixir.unwrap(result)}
      end
    end
  end

  @doc "Evaluates the program, raising on error."
  def eval!(%__MODULE__{} = program, bindings \\ %{}) do
    case eval(program, bindings) do
      {:ok, result} -> result
      {:error, msg} -> raise Celixir.Error, message: "CEL evaluation error: #{msg}"
    end
  end
end
