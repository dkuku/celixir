defmodule Celixir.Environment do
  @moduledoc """
  Execution environment for CEL expressions.
  Holds variable bindings, custom function definitions, and an optional type adapter.

  ## Building an environment

      env = Celixir.Environment.new(%{x: 10, name: "alice"})

  ## Registering custom functions

  Use `put_function/3` to register Elixir functions callable from CEL.
  Functions receive plain Elixir values (unwrapped from CEL internal types)
  and should return plain Elixir values.

      env = Celixir.Environment.new()
            |> Celixir.Environment.put_function("double", fn x -> x * 2 end)
            |> Celixir.Environment.put_function("math.clamp", fn v, lo, hi ->
              v |> max(lo) |> min(hi)
            end)

  You can also pass module function captures:

      env = Celixir.Environment.new()
            |> Celixir.Environment.put_function("slugify", &MyApp.Helpers.slugify/1)

  ## Building reusable libraries

  Group related functions into a module that configures an environment:

      defmodule MyApp.CelLibrary do
        alias Celixir.Environment

        def register(env \\\\ Environment.new()) do
          env
          |> Environment.put_function("format.currency", &format_currency/2)
          |> Environment.put_function("format.percent", &format_percent/1)
        end

        defp format_currency(amount, cur), do: "\#{cur} \#{amount}"
        defp format_percent(ratio), do: "\#{round(ratio * 100)}%"
      end

      env = MyApp.CelLibrary.register()
            |> Celixir.Environment.put_variable("price", 29.9)

      Celixir.eval!("format.currency(price, 'USD')", env)
  """

  defstruct variables: %{}, functions: %{}, type_adapter: nil

  @type t :: %__MODULE__{
          variables: %{String.t() => any()},
          functions: %{String.t() => function()},
          type_adapter: module() | nil
        }

  @doc "Creates a new empty environment."
  def new, do: %__MODULE__{}

  @doc "Creates an environment with the given variable bindings."
  def new(variables) when is_map(variables) do
    %__MODULE__{variables: stringify_keys(variables)}
  end

  @doc "Adds a variable binding."
  def put_variable(%__MODULE__{} = env, name, value) do
    %{env | variables: Map.put(env.variables, to_string(name), value)}
  end

  @doc "Looks up a variable."
  def get_variable(%__MODULE__{} = env, name) do
    case Map.fetch(env.variables, name) do
      {:ok, _} = ok -> ok
      :error -> :error
    end
  end

  @doc "Registers a custom function."
  def put_function(%__MODULE__{} = env, name, func) when is_function(func) do
    %{env | functions: Map.put(env.functions, to_string(name), func)}
  end

  @doc "Looks up a function."
  def get_function(%__MODULE__{} = env, name) do
    Map.fetch(env.functions, name)
  end

  @doc "Sets a custom type adapter module."
  def set_type_adapter(%__MODULE__{} = env, adapter) when is_atom(adapter) do
    %{env | type_adapter: adapter}
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
