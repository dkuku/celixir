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

  defstruct variables: %{}, functions: %{}, type_adapter: nil, container: nil, container_prefixes: [], locals: %{}, private: %{}

  @type t :: %__MODULE__{
          variables: %{String.t() => any()},
          functions: %{String.t() => function()},
          type_adapter: module() | nil,
          container: String.t() | nil,
          container_prefixes: [String.t()],
          locals: %{String.t() => any()},
          private: %{any() => any()}
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

  @doc "Adds a local variable binding that shadows container-resolved and outer names."
  def put_local(%__MODULE__{} = env, name, value) do
    %{env | locals: Map.put(env.locals, to_string(name), value)}
  end

  @doc "Sets the container (namespace) for identifier resolution."
  def set_container(%__MODULE__{} = env, container) do
    %{env | container: container, container_prefixes: compute_container_prefixes(container)}
  end

  @doc """
  Looks up a variable with proper resolution order:
  - Absolute names (`.y`) bypass locals and container, look up in outer variables only
  - Local names check locals first (comprehension iter vars, cel.bind), then container-resolved outer vars
  """
  def get_variable(%__MODULE__{} = env, name) do
    if String.starts_with?(name, ".") do
      # Absolute: bypass locals and container, look up in outer variables only
      bare = String.trim_leading(name, ".")
      Map.fetch(env.variables, bare)
    else
      # Check local scope first (comprehension/bind vars shadow everything)
      case Map.fetch(env.locals, name) do
        {:ok, _} = ok -> ok
        :error -> resolve_with_container(env, name)
      end
    end
  end

  @doc "Checks if a variable name is locally bound (e.g., comprehension iter var)."
  def local?(env, name), do: Map.has_key?(env.locals, to_string(name))

  defp resolve_with_container(%{container: nil} = env, name) do
    Map.fetch(env.variables, name)
  end

  defp resolve_with_container(env, name) do
    # Try progressively shorter container prefixes: com.example.y, com.y, y
    Enum.find_value(env.container_prefixes, fn prefix ->
      qualified = prefix <> "." <> name

      case Map.fetch(env.variables, qualified) do
        {:ok, _} = ok -> ok
        :error -> nil
      end
    end) || Map.fetch(env.variables, name)
  end

  defp compute_container_prefixes(nil), do: []

  defp compute_container_prefixes(container) do
    parts = String.split(container, ".")
    # ["com.example", "com"] for container "com.example"
    Enum.map(length(parts)..1//-1, fn n ->
      parts |> Enum.take(n) |> Enum.join(".")
    end)
  end

  @doc "Registers a custom function."
  def put_function(%__MODULE__{} = env, name, func) when is_function(func) do
    %{env | functions: Map.put(env.functions, to_string(name), func)}
  end

  @doc "Looks up a function."
  def get_function(%__MODULE__{} = env, name) do
    Map.fetch(env.functions, name)
  end

  @doc """
  Stores a private value in the environment.

  Private values are not visible to CEL expressions — they are only
  accessible from custom Elixir functions that receive the environment.

  ## Examples

      env = Celixir.Environment.new()
            |> Celixir.Environment.put_private(:repo, MyApp.Repo)
  """
  def put_private(%__MODULE__{} = env, key, value) do
    %{env | private: Map.put(env.private, key, value)}
  end

  @doc """
  Retrieves a private value from the environment.

  Returns `{:ok, value}` or `:error`.
  """
  def get_private(%__MODULE__{} = env, key) do
    Map.fetch(env.private, key)
  end

  @doc """
  Retrieves a private value, raising if the key doesn't exist.
  """
  def get_private!(%__MODULE__{} = env, key) do
    case get_private(env, key) do
      {:ok, value} -> value
      :error -> raise KeyError, key: key, term: :private
    end
  end

  @doc """
  Deletes a private value from the environment.
  """
  def delete_private(%__MODULE__{} = env, key) do
    %{env | private: Map.delete(env.private, key)}
  end

  @doc "Sets a custom type adapter module."
  def set_type_adapter(%__MODULE__{} = env, adapter) when is_atom(adapter) do
    %{env | type_adapter: adapter}
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
