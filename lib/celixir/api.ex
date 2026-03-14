defmodule Celixir.API do
  @moduledoc """
  A macro-based way to define CEL function libraries.

  ## Usage

      defmodule MyApp.CelMath do
        use Celixir.API, scope: "mymath"

        defcel abs(x) do
          Kernel.abs(x)
        end

        defcel clamp(val, lo, hi) do
          val |> max(lo) |> min(hi)
        end
      end

      env = Celixir.Environment.new() |> MyApp.CelMath.register()
      Celixir.eval!("mymath.clamp(150, 0, 100)", env)
      # => 100

  Functions defined with `defcel` receive plain Elixir values (already
  unwrapped from CEL internal types) and should return plain Elixir values.

  ## Without a scope

      defmodule MyApp.CelHelpers do
        use Celixir.API

        defcel greet(name) do
          "Hello, \#{name}!"
        end
      end

      env = Celixir.Environment.new() |> MyApp.CelHelpers.register()
      Celixir.eval!("greet('world')", env)
      # => "Hello, world!"
  """

  defmacro __using__(opts) do
    scope = Keyword.get(opts, :scope)

    quote do
      import Celixir.API, only: [defcel: 2]
      Module.register_attribute(__MODULE__, :cel_functions, accumulate: true)
      @before_compile Celixir.API
      @cel_scope unquote(scope)
    end
  end

  @doc """
  Defines a CEL-callable function.

  The function receives plain Elixir values and should return a plain Elixir value.
  """
  defmacro defcel(call, do: body) do
    {name, _meta, args} = call
    args = args || []

    quote do
      @cel_functions {unquote(to_string(name)), unquote(length(args))}
      def unquote(name)(unquote_splicing(args)) do
        unquote(body)
      end
    end
  end

  defmacro __before_compile__(env) do
    functions = Module.get_attribute(env.module, :cel_functions)
    scope = Module.get_attribute(env.module, :cel_scope)
    mod = env.module

    register_body =
      for {name, arity} <- functions do
        cel_name = if scope, do: "#{scope}.#{name}", else: name
        func_atom = String.to_atom(name)
        args = Macro.generate_arguments(arity, __MODULE__)

        quote do
          env =
            Celixir.Environment.put_function(
              env,
              unquote(cel_name),
              fn unquote_splicing(args) ->
                unquote(mod).unquote(func_atom)(unquote_splicing(args))
              end
            )
        end
      end

    quote do
      @doc """
      Registers all `defcel` functions into the given environment.
      """
      def register(env \\ Celixir.Environment.new()) do
        unquote_splicing(register_body)
        env
      end

      @doc false
      def __cel_functions__, do: unquote(Macro.escape(functions))

      @doc false
      def __cel_scope__, do: unquote(scope)
    end
  end
end
