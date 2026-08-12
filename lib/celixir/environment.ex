defmodule Celixir.Environment do
  @moduledoc """
  Execution environment for CEL expressions.
  Holds variable bindings, custom function definitions, and an optional type adapter.

  ## Building an environment

  Both atom-keyed and string-keyed maps are accepted. String keys are recommended
  when variable data comes from untrusted sources (JSON, user input, databases)
  to avoid atom exhaustion.

      # String-keyed (recommended for untrusted data)
      env = Celixir.Environment.new(%{"severity" => "high", "count" => 3})

      # Atom-keyed (convenient for trusted, developer-defined bindings)
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

  defstruct variables: %{},
            functions: %{},
            type_adapter: nil,
            container: nil,
            container_prefixes: [],
            locals: %{},
            private: %{}

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
    %__MODULE__{variables: normalize_keys(variables)}
  end

  @doc "Adds a variable binding."
  def put_variable(%__MODULE__{} = env, name, value) do
    %{env | variables: Map.put(env.variables, to_string_key(name), cel_encode(value))}
  end

  @doc "Adds a local variable binding that shadows container-resolved and outer names."
  def put_local(%__MODULE__{} = env, name, value) do
    %{env | locals: Map.put(env.locals, to_string_key(name), cel_encode(value))}
  end

  @doc "Adds multiple local variable bindings at once (single struct copy instead of N copies)."
  def put_locals_bulk(%__MODULE__{} = env, new_locals) when is_map(new_locals) do
    stringified = Map.new(new_locals, fn {k, v} -> {to_string_key(k), cel_encode(v)} end)
    %{env | locals: Map.merge(env.locals, stringified)}
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
  def get_variable(%__MODULE__{} = env, "." <> rest) do
    # Absolute: bypass locals and container, look up in outer variables only
    bare = String.trim_leading(rest, ".")
    Map.fetch(env.variables, bare)
  end

  def get_variable(%__MODULE__{} = env, name) when is_atom(name) do
    str = Atom.to_string(name)

    case Map.fetch(env.locals, str) do
      {:ok, _} = ok -> ok
      :error -> resolve_with_container(env, str)
    end
  end

  def get_variable(%__MODULE__{} = env, name) when is_binary(name) do
    case Map.fetch(env.locals, name) do
      {:ok, _} = ok -> ok
      :error -> resolve_with_container(env, name)
    end
  end

  @doc "Checks if a variable name is locally bound (e.g., comprehension iter var)."
  def local?(env, name), do: Map.has_key?(env.locals, to_string_key(name))

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

  defp to_string_key(name) when is_binary(name), do: name
  defp to_string_key(name) when is_atom(name), do: Atom.to_string(name)
  defp to_string_key(name), do: to_string(name)

  # Encode Elixir values for CEL at the binding boundary. `Celixir.encode/1` is
  # the single definition of that mapping — see its docs for what is converted
  # and what is preserved.
  defp cel_encode(value), do: Celixir.encode(value)

  defp normalize_keys(map) when map_size(map) == 0, do: %{}

  defp normalize_keys(map) do
    # Keys and values are normalized in a single pass. Fast path: if the first key
    # is already a string, assume all are (common case when the caller passes
    # string-keyed maps from JSON/database) and skip the key conversion.
    case :maps.next(:maps.iterator(map)) do
      {k, _v, _rest} when is_binary(k) -> Map.new(map, fn {k, v} -> {k, cel_encode(v)} end)
      _ -> Map.new(map, fn {k, v} -> {to_string_key(k), cel_encode(v)} end)
    end
  end
end
