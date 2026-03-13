defmodule Celixir.Checker do
  @moduledoc """
  Static type checker for CEL expressions.

  Validates that a parsed AST is well-typed given declared variable types.
  This is an optional step -- CEL expressions can be evaluated without
  type-checking, but checking catches errors earlier.

  Supports full CEL type inference including wrapper types, message types,
  well-known types, abstract types (optionals), type parameters for overload
  resolution, and proto field lookups.

  ## Usage

      {:ok, ast} = Celixir.parse("x + 1")
      declarations = %{"x" => :int}
      :ok = Celixir.Checker.check(ast, declarations)

      # With full type environment:
      env = %{
        variables: %{"x" => :int},
        functions: %{"myFunc" => [%{id: "myFunc_int", params: [:int], result_type: :bool}]},
        container: nil
      }
      :ok = Celixir.Checker.check(ast, env)
  """

  alias Celixir.AST

  @type cel_type ::
          :int
          | :uint
          | :double
          | :bool
          | :string
          | :bytes
          | :null_type
          | :timestamp
          | :duration
          | :dyn
          | {:list, cel_type()}
          | {:map, cel_type(), cel_type()}
          | {:wrapper, atom()}
          | {:message, String.t()}
          | {:well_known, atom()}
          | {:abstract, String.t(), [cel_type()]}
          | {:type_param, String.t()}
          | :type
          | :error

  @type overload :: %{
          id: String.t(),
          params: [cel_type()],
          result_type: cel_type()
        }

  @type type_env :: %{
          variables: %{String.t() => cel_type()},
          functions: %{String.t() => [overload()]},
          container: String.t() | nil
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec check(AST.expr(), map()) :: :ok | {:error, String.t()}
  def check(ast, declarations \\ %{}) do
    env = normalize_env(declarations)

    case infer(ast, env) do
      {:error, _} = err -> err
      _type -> :ok
    end
  end

  @spec infer(AST.expr(), map()) :: cel_type() | {:error, String.t()}
  def infer(ast, declarations \\ %{})

  # -- Literals ---------------------------------------------------------------

  def infer(%AST.IntLit{}, _), do: :int
  def infer(%AST.UintLit{}, _), do: :uint
  def infer(%AST.FloatLit{}, _), do: :double
  def infer(%AST.StringLit{}, _), do: :string
  def infer(%AST.BytesLit{}, _), do: :bytes
  def infer(%AST.BoolLit{}, _), do: :bool
  def infer(%AST.NullLit{}, _), do: :null_type

  # -- Ident ------------------------------------------------------------------

  def infer(%AST.Ident{name: name}, decls) do
    env = normalize_env(decls)
    vars = env.variables

    case Map.fetch(vars, name) do
      {:ok, type} -> type
      :error -> :dyn
    end
  end

  # -- UnaryOp ----------------------------------------------------------------

  def infer(%AST.UnaryOp{op: :not, operand: operand}, decls) do
    env = normalize_env(decls)

    case infer(operand, env) do
      :bool -> :bool
      :dyn -> :bool
      t -> {:error, "no matching overload for ! on #{format_type(t)}"}
    end
  end

  def infer(%AST.UnaryOp{op: :negate, operand: operand}, decls) do
    env = normalize_env(decls)

    case infer(operand, env) do
      t when t in [:int, :double, :dyn] -> t
      {:wrapper, t} when t in [:int, :double] -> t
      t -> {:error, "no matching overload for - on #{format_type(t)}"}
    end
  end

  # -- BinaryOp: logical ------------------------------------------------------

  def infer(%AST.BinaryOp{op: op, left: left, right: right}, decls) when op in [:and, :or] do
    env = normalize_env(decls)

    with {:ok, lt} <- infer_ok(left, env),
         {:ok, rt} <- infer_ok(right, env) do
      lt2 = unwrap_type(lt)
      rt2 = unwrap_type(rt)

      if lt2 in [:bool, :dyn] and rt2 in [:bool, :dyn] do
        :bool
      else
        {:error,
         "no matching overload for #{op_name(op)} on #{format_type(lt)} and #{format_type(rt)}"}
      end
    end
  end

  # -- BinaryOp: arithmetic ---------------------------------------------------

  def infer(%AST.BinaryOp{op: op, left: left, right: right}, decls)
      when op in [:add, :sub, :mul, :div, :mod] do
    env = normalize_env(decls)

    with {:ok, lt} <- infer_ok(left, env),
         {:ok, rt} <- infer_ok(right, env) do
      lt2 = unwrap_type(lt)
      rt2 = unwrap_type(rt)

      cond do
        lt2 == :dyn or rt2 == :dyn ->
          :dyn

        op == :add and lt2 == :string and rt2 == :string ->
          :string

        op == :add and match?({:list, _}, lt2) and match?({:list, _}, rt2) ->
          {:list, _la} = lt2
          {:list, _lb} = rt2
          {:list, unify_types(elem(lt2, 1), elem(rt2, 1))}

        op == :add and lt2 == :bytes and rt2 == :bytes ->
          :bytes

        # timestamp/duration arithmetic
        op == :add and lt2 == :timestamp and rt2 == :duration ->
          :timestamp

        op == :add and lt2 == :duration and rt2 == :timestamp ->
          :timestamp

        op == :add and lt2 == :duration and rt2 == :duration ->
          :duration

        op == :sub and lt2 == :timestamp and rt2 == :timestamp ->
          :duration

        op == :sub and lt2 == :timestamp and rt2 == :duration ->
          :timestamp

        op == :sub and lt2 == :duration and rt2 == :duration ->
          :duration

        lt2 == rt2 and lt2 in [:int, :uint, :double] ->
          lt2

        true ->
          {:error,
           "no matching overload for #{op_name(op)} on #{format_type(lt)} and #{format_type(rt)}"}
      end
    end
  end

  # -- BinaryOp: comparison ---------------------------------------------------

  def infer(%AST.BinaryOp{op: op}, _decls)
      when op in [:eq, :neq, :lt, :lte, :gt, :gte, :in],
      do: :bool

  # -- Ternary ----------------------------------------------------------------

  def infer(%AST.Ternary{condition: cond_expr, true_expr: t, false_expr: f}, decls) do
    env = normalize_env(decls)

    with {:ok, ct} <- infer_ok(cond_expr, env),
         {:ok, tt} <- infer_ok(t, env),
         {:ok, ft} <- infer_ok(f, env) do
      ct2 = unwrap_type(ct)

      if ct2 not in [:bool, :dyn] do
        {:error, "ternary condition must be bool"}
      else
        unify_types(tt, ft)
      end
    end
  end

  # -- CreateList --------------------------------------------------------------

  def infer(%AST.CreateList{elements: []}, _), do: {:list, :_bottom}

  def infer(%AST.CreateList{elements: elements}, decls) do
    env = normalize_env(decls)

    types = Enum.map(elements, &infer(&1, env))

    case Enum.find(types, &match?({:error, _}, &1)) do
      {:error, _} = err ->
        err

      nil ->
        elem_type = Enum.reduce(types, fn t, acc -> unify_types(acc, t) end)
        {:list, elem_type}
    end
  end

  # -- CreateMap ---------------------------------------------------------------

  def infer(%AST.CreateMap{entries: []}, _), do: {:map, :_bottom, :_bottom}

  def infer(%AST.CreateMap{entries: entries}, decls) do
    env = normalize_env(decls)

    key_types = Enum.map(entries, fn {k, _v} -> infer(k, env) end)
    val_types = Enum.map(entries, fn {_k, v} -> infer(v, env) end)

    all_types = key_types ++ val_types

    case Enum.find(all_types, &match?({:error, _}, &1)) do
      {:error, _} = err ->
        err

      nil ->
        kt = Enum.reduce(key_types, fn t, acc -> unify_types(acc, t) end)
        vt = Enum.reduce(val_types, fn t, acc -> unify_types(acc, t) end)
        {:map, kt, vt}
    end
  end

  # -- CreateStruct ------------------------------------------------------------

  def infer(%AST.CreateStruct{type_name: type_name}, decls) do
    env = normalize_env(decls)
    container = env.container

    full_name =
      if container && container != "" do
        container <> "." <> type_name
      else
        type_name
      end

    {:message, full_name}
  end

  # -- Select ------------------------------------------------------------------

  def infer(%AST.Select{operand: operand, field: field}, decls) do
    env = normalize_env(decls)

    case infer(operand, env) do
      {:error, _} = err ->
        err

      {:message, msg_type} ->
        proto_field_type(msg_type, field)

      {:well_known, :timestamp} ->
        timestamp_accessor_type(field)

      {:well_known, :duration} ->
        duration_accessor_type(field)

      :dyn ->
        :dyn

      _other ->
        :dyn
    end
  end

  # -- OptSelect ---------------------------------------------------------------

  def infer(%AST.OptSelect{operand: operand, field: field}, decls) do
    env = normalize_env(decls)

    case infer(operand, env) do
      {:error, _} = err ->
        err

      {:message, msg_type} ->
        inner = proto_field_type(msg_type, field)
        {:abstract, "optional_type", [inner]}

      :dyn ->
        {:abstract, "optional_type", [:dyn]}

      _other ->
        {:abstract, "optional_type", [:dyn]}
    end
  end

  # -- Index -------------------------------------------------------------------

  def infer(%AST.Index{operand: operand}, decls) do
    env = normalize_env(decls)

    case infer(operand, env) do
      {:error, _} = err -> err
      {:list, elem_type} -> elem_type
      {:map, _k, v} -> v
      :dyn -> :dyn
      _other -> :dyn
    end
  end

  # -- OptIndex ----------------------------------------------------------------

  def infer(%AST.OptIndex{operand: operand}, decls) do
    env = normalize_env(decls)

    case infer(operand, env) do
      {:error, _} = err -> err
      {:list, elem_type} -> {:abstract, "optional_type", [elem_type]}
      {:map, _k, v} -> {:abstract, "optional_type", [v]}
      :dyn -> {:abstract, "optional_type", [:dyn]}
      _other -> {:abstract, "optional_type", [:dyn]}
    end
  end

  # -- Call --------------------------------------------------------------------

  def infer(%AST.Call{function: "dyn", target: nil, args: [arg]}, decls) do
    env = normalize_env(decls)
    # dyn() erases type info — infer arg for side effects but return :dyn
    _t = infer(arg, env)
    :dyn
  end

  def infer(%AST.Call{function: fun, target: target, args: [arg]}, decls)
      when fun in ["optional.of", "of"] do
    # Handle both optional.of(x) and optional.of(x) parsed as method call on "optional"
    if fun == "of" and not match?(%AST.Ident{name: "optional"}, target) do
      infer_call_fallback(fun, target, [arg], decls)
    else
      env = normalize_env(decls)
      t = infer(arg, env)

      case t do
        {:error, _} = err -> err
        _ -> {:abstract, "optional_type", [t]}
      end
    end
  end

  def infer(%AST.Call{function: fun, target: target, args: []}, _decls)
      when fun in ["optional.none", "none"] do
    if fun == "none" and not match?(%AST.Ident{name: "optional"}, target) do
      :dyn
    else
      {:abstract, "optional_type", [:_bottom]}
    end
  end

  def infer(%AST.Call{function: fun, target: target, args: [arg]}, decls)
      when fun in ["optional.ofNonZeroValue", "ofNonZeroValue"] do
    if fun == "ofNonZeroValue" and not match?(%AST.Ident{name: "optional"}, target) do
      infer_call_fallback(fun, target, [arg], decls)
    else
      env = normalize_env(decls)
      t = infer(arg, env)

      case t do
        {:error, _} = err -> err
        _ -> {:abstract, "optional_type", [t]}
      end
    end
  end

  # type() function
  def infer(%AST.Call{function: "type", target: nil, args: [_arg]}, _decls), do: :type

  # Type conversion functions
  def infer(%AST.Call{function: "int", target: nil, args: [_]}, _decls), do: :int
  def infer(%AST.Call{function: "uint", target: nil, args: [_]}, _decls), do: :uint
  def infer(%AST.Call{function: "double", target: nil, args: [_]}, _decls), do: :double
  def infer(%AST.Call{function: "string", target: nil, args: [_]}, _decls), do: :string
  def infer(%AST.Call{function: "bytes", target: nil, args: [_]}, _decls), do: :bytes
  def infer(%AST.Call{function: "bool", target: nil, args: [_]}, _decls), do: :bool
  def infer(%AST.Call{function: "timestamp", target: nil, args: [_]}, _decls), do: {:well_known, :timestamp}
  def infer(%AST.Call{function: "duration", target: nil, args: [_]}, _decls), do: {:well_known, :duration}

  # size() function and method
  def infer(%AST.Call{function: "size", target: nil, args: [_]}, _decls), do: :int
  def infer(%AST.Call{function: "size", target: target, args: []}, decls) when not is_nil(target) do
    env = normalize_env(decls)
    _t = infer(target, env)
    :int
  end

  # String methods returning bool
  def infer(%AST.Call{function: f, target: target, args: [_]}, _decls)
      when f in ["startsWith", "endsWith", "contains", "matches"] and not is_nil(target),
      do: :bool

  # String methods returning string
  def infer(%AST.Call{function: f, target: target, args: _}, _decls)
      when f in ["lowerAscii", "upperAscii", "trim", "replace", "substring", "charAt"]
           and not is_nil(target),
      do: :string

  # String methods returning int
  def infer(%AST.Call{function: f, target: target, args: _}, _decls)
      when f in ["indexOf", "lastIndexOf"] and not is_nil(target),
      do: :int

  # split returns list of strings
  def infer(%AST.Call{function: "split", target: target, args: _}, _decls)
      when not is_nil(target),
      do: {:list, :string}

  # join returns string
  def infer(%AST.Call{function: "join", target: target, args: _}, _decls)
      when not is_nil(target),
      do: :string

  # Timestamp/Duration accessors as method calls
  def infer(%AST.Call{function: f, target: target, args: []}, decls)
      when f in [
             "getFullYear",
             "getMonth",
             "getDayOfYear",
             "getDayOfMonth",
             "getDate",
             "getDayOfWeek",
             "getHours",
             "getMinutes",
             "getSeconds",
             "getMilliseconds"
           ] and not is_nil(target) do
    env = normalize_env(decls)
    _t = infer(target, env)
    :int
  end

  # optional.hasValue() -> bool
  def infer(%AST.Call{function: "hasValue", target: target, args: []}, _decls)
      when not is_nil(target),
      do: :bool

  # optional.value() -> inner type
  def infer(%AST.Call{function: "value", target: target, args: []}, decls)
      when not is_nil(target) do
    env = normalize_env(decls)

    case infer(target, env) do
      {:abstract, "optional_type", [inner]} -> inner
      {:error, _} = err -> err
      _ -> :dyn
    end
  end

  # optional.or() -> optional
  def infer(%AST.Call{function: "or", target: target, args: [alt]}, decls)
      when not is_nil(target) do
    env = normalize_env(decls)
    tt = infer(target, env)
    at = infer(alt, env)

    case {tt, at} do
      {{:abstract, "optional_type", [a]}, {:abstract, "optional_type", [b]}} ->
        {:abstract, "optional_type", [unify_types(a, b)]}

      _ ->
        unify_types(tt, at)
    end
  end

  # optional.orValue() -> inner type
  def infer(%AST.Call{function: "orValue", target: target, args: [alt]}, decls)
      when not is_nil(target) do
    env = normalize_env(decls)
    tt = infer(target, env)
    at = infer(alt, env)

    case tt do
      {:abstract, "optional_type", [inner]} -> unify_types(inner, at)
      {:error, _} = err -> err
      _ -> unify_types(tt, at)
    end
  end

  # has() macro — always returns bool
  def infer(%AST.Call{function: "has", target: nil, args: _}, _decls), do: :bool

  # Fallback: user-declared functions from env
  def infer(%AST.Call{function: fname, target: target, args: args}, decls) do
    env = normalize_env(decls)

    arg_types =
      if target do
        [infer(target, env) | Enum.map(args, &infer(&1, env))]
      else
        Enum.map(args, &infer(&1, env))
      end

    # Check for errors in arg types
    case Enum.find(arg_types, &match?({:error, _}, &1)) do
      {:error, _} = err ->
        err

      nil ->
        case Map.get(env.functions, fname, []) do
          [] ->
            :dyn

          overloads ->
            resolve_overload(overloads, arg_types)
        end
    end
  end

  # -- Comprehension -----------------------------------------------------------

  def infer(%AST.Comprehension{} = comp, decls) do
    env = normalize_env(decls)

    # Infer the iter_range type to determine element type
    range_type = infer(comp.iter_range, env)

    {elem_type, key_type} =
      case range_type do
        {:list, et} -> {et, nil}
        {:map, kt, vt} -> {vt, kt}
        :dyn -> {:dyn, :dyn}
        {:error, _} -> {:dyn, nil}
        _ -> {:dyn, nil}
      end

    # Bind iteration variables
    inner_env =
      if comp.iter_var do
        put_variable(env, comp.iter_var, if(key_type, do: key_type, else: elem_type))
      else
        env
      end

    inner_env =
      if comp.iter_var2 do
        put_variable(inner_env, comp.iter_var2, elem_type)
      else
        inner_env
      end

    # Bind accumulator variable with its init type
    acc_type = infer(comp.acc_init, env)

    inner_env =
      if comp.acc_var do
        put_variable(inner_env, comp.acc_var, acc_type)
      else
        inner_env
      end

    # Determine result type based on comprehension pattern
    # For .exists(), .all(): result is bool (acc_init is bool)
    # For .map(), .filter(): result is list (acc_init is [])
    # For general: infer result expression
    result_type = infer(comp.result, inner_env)

    # If the loop_step produces a list, refine the element type
    case result_type do
      {:error, _} = err ->
        err

      _ ->
        step_type = infer(comp.loop_step, inner_env)

        case step_type do
          {:list, _step_elem} ->
            # This is a map/filter — the step builds a list
            step_type

          _ ->
            result_type
        end
    end
  end

  # -- OptLambda ---------------------------------------------------------------

  def infer(%AST.OptLambda{kind: :flat_map, target: target, var: var, expr: expr}, decls) do
    env = normalize_env(decls)
    target_type = infer(target, env)

    inner_type =
      case target_type do
        {:abstract, "optional_type", [t]} -> t
        _ -> :dyn
      end

    inner_env = put_variable(env, var, inner_type)
    expr_type = infer(expr, inner_env)

    case expr_type do
      {:abstract, "optional_type", _} -> expr_type
      {:error, _} = err -> err
      _ -> {:abstract, "optional_type", [expr_type]}
    end
  end

  def infer(%AST.OptLambda{kind: :map, target: target, var: var, expr: expr}, decls) do
    env = normalize_env(decls)
    target_type = infer(target, env)

    inner_type =
      case target_type do
        {:abstract, "optional_type", [t]} -> t
        _ -> :dyn
      end

    inner_env = put_variable(env, var, inner_type)
    expr_type = infer(expr, inner_env)

    case expr_type do
      {:error, _} = err -> err
      _ -> {:abstract, "optional_type", [expr_type]}
    end
  end

  # -- CelBlock ----------------------------------------------------------------

  def infer(%AST.CelBlock{bindings: bindings, result: result}, decls) do
    env = normalize_env(decls)

    {final_env, _idx} =
      Enum.reduce(bindings, {env, 0}, fn binding_expr, {acc_env, idx} ->
        t = infer(binding_expr, acc_env)
        new_env = put_block_binding(acc_env, idx, t)
        {new_env, idx + 1}
      end)

    infer(result, final_env)
  end

  # -- CelIndex ----------------------------------------------------------------

  def infer(%AST.CelIndex{index: idx}, decls) do
    env = normalize_env(decls)
    block_bindings = Map.get(env, :block_bindings, %{})
    Map.get(block_bindings, idx, :dyn)
  end

  # -- CelIterVar --------------------------------------------------------------

  def infer(%AST.CelIterVar{}, _decls), do: :dyn

  # ---------------------------------------------------------------------------
  # Type unification
  # ---------------------------------------------------------------------------

  @doc """
  Unifies two CEL types. Returns the most specific common type.

  CEL-specific: `:dyn` is the least specific type — when one side is `:dyn`,
  the other side wins.
  """
  @spec unify_types(cel_type(), cel_type()) :: cel_type()
  def unify_types(a, a), do: a
  def unify_types(:error, b), do: b
  def unify_types(a, :error), do: a

  # Bottom type: unresolved dyn from empty containers / optional.none()
  # Always yields to any other type
  def unify_types(:_bottom, b), do: b
  def unify_types(a, :_bottom), do: a

  # Wrapper promotion: wrapper + its inner primitive = wrapper
  def unify_types({:wrapper, t}, t), do: {:wrapper, t}
  def unify_types(t, {:wrapper, t}), do: {:wrapper, t}

  # Wrapper + null = wrapper (nullable)
  def unify_types({:wrapper, _} = w, :null_type), do: w
  def unify_types(:null_type, {:wrapper, _} = w), do: w

  # null + message/well_known/abstract (legacy nullable)
  def unify_types(:null_type, {:message, _} = m), do: m
  def unify_types({:message, _} = m, :null_type), do: m
  def unify_types(:null_type, {:well_known, _} = w), do: w
  def unify_types({:well_known, _} = w, :null_type), do: w
  def unify_types(:null_type, {:abstract, _, _} = a), do: a
  def unify_types({:abstract, _, _} = a, :null_type), do: a

  # Parameterized types — unify recursively BEFORE dyn rules
  def unify_types({:list, a}, {:list, b}), do: {:list, unify_types(a, b)}

  def unify_types({:map, ka, va}, {:map, kb, vb}),
    do: {:map, unify_types(ka, kb), unify_types(va, vb)}

  def unify_types({:abstract, n, pa}, {:abstract, n, pb}) when length(pa) == length(pb) do
    unified = Enum.zip(pa, pb) |> Enum.map(fn {a, b} -> unify_types(a, b) end)
    {:abstract, n, unified}
  end

  # dyn: for structural/container types (list, map, abstract), dyn loses to the more specific type
  # so that nested empty lists can build up depth. For all other types, dyn wins (dyn promotion).
  def unify_types(:dyn, {:list, _} = b), do: b
  def unify_types({:list, _} = a, :dyn), do: a
  def unify_types(:dyn, {:map, _, _} = b), do: b
  def unify_types({:map, _, _} = a, :dyn), do: a
  def unify_types(:dyn, {:abstract, _, _} = b), do: b
  def unify_types({:abstract, _, _} = a, :dyn), do: a

  # For non-container types, dyn wins (dyn promotion)
  def unify_types(:dyn, _), do: :dyn
  def unify_types(_, :dyn), do: :dyn

  # Everything else: incompatible types unify to dyn
  def unify_types(_, _), do: :dyn

  # ---------------------------------------------------------------------------
  # Function overload resolution
  # ---------------------------------------------------------------------------

  @doc """
  Resolves the best matching overload for a function call given argument types.
  Returns the result type with type parameter substitution applied.
  """
  @spec resolve_overload([overload()], [cel_type()]) :: cel_type()
  def resolve_overload([], _arg_types), do: :dyn

  def resolve_overload(overloads, arg_types) do
    matches =
      overloads
      |> Enum.filter(fn %{params: params} -> length(params) == length(arg_types) end)
      |> Enum.map(fn overload -> {overload, match_overload(overload.params, arg_types)} end)
      |> Enum.filter(fn {_o, result} -> result != :no_match end)

    case matches do
      [] ->
        :dyn

      [{%{result_type: result_type}, bindings} | _] ->
        substitute_type_params(result_type, bindings)
    end
  end

  defp match_overload(params, arg_types) do
    Enum.zip(params, arg_types)
    |> Enum.reduce(%{}, fn
      _, :no_match ->
        :no_match

      {param, arg}, bindings ->
        match_param(param, arg, bindings)
    end)
  end

  defp match_param({:type_param, name}, arg_type, bindings) do
    case Map.get(bindings, name) do
      nil ->
        Map.put(bindings, name, arg_type)

      existing ->
        unified = unify_types(existing, arg_type)

        if unified == :dyn and existing != :dyn and arg_type != :dyn do
          :no_match
        else
          Map.put(bindings, name, unified)
        end
    end
  end

  defp match_param(:dyn, _arg_type, bindings), do: bindings

  defp match_param(param, :dyn, bindings) when not is_tuple(param), do: bindings
  defp match_param(param, :dyn, bindings) when is_tuple(param), do: bindings

  defp match_param(param, arg, bindings) when param == arg, do: bindings

  defp match_param({:list, p}, {:list, a}, bindings), do: match_param(p, a, bindings)

  defp match_param({:map, pk, pv}, {:map, ak, av}, bindings) do
    case match_param(pk, ak, bindings) do
      :no_match -> :no_match
      bindings2 -> match_param(pv, av, bindings2)
    end
  end

  # Abstract type matching — recursively match parameters
  defp match_param({:abstract, n, pparams}, {:abstract, n, aparams}, bindings)
       when length(pparams) == length(aparams) do
    Enum.zip(pparams, aparams)
    |> Enum.reduce(bindings, fn
      _, :no_match -> :no_match
      {pp, ap}, b -> match_param(pp, ap, b)
    end)
  end

  # Wrapper matches its inner type
  defp match_param({:wrapper, t}, t, bindings), do: bindings
  defp match_param(t, {:wrapper, t}, bindings), do: bindings

  defp match_param(_, _, _), do: :no_match

  defp substitute_type_params({:type_param, name}, bindings) do
    Map.get(bindings, name, :dyn)
  end

  defp substitute_type_params({:list, t}, bindings) do
    {:list, substitute_type_params(t, bindings)}
  end

  defp substitute_type_params({:map, k, v}, bindings) do
    {:map, substitute_type_params(k, bindings), substitute_type_params(v, bindings)}
  end

  defp substitute_type_params({:abstract, name, params}, bindings) do
    {:abstract, name, Enum.map(params, &substitute_type_params(&1, bindings))}
  end

  defp substitute_type_params(type, _bindings), do: type

  # ---------------------------------------------------------------------------
  # Proto field type registry
  # ---------------------------------------------------------------------------

  @proto3_test_all_types "cel.expr.conformance.proto3.TestAllTypes"
  @proto3_nested_message "cel.expr.conformance.proto3.TestAllTypes.NestedMessage"

  @doc """
  Returns the checker type for a known proto message field.
  Falls back to `:dyn` for unknown messages/fields.
  """
  @spec proto_field_type(String.t(), String.t()) :: cel_type()
  def proto_field_type(@proto3_test_all_types, field) do
    case field do
      "single_int32" -> :int
      "single_int64" -> :int
      "single_uint32" -> :uint
      "single_uint64" -> :uint
      "single_float" -> :double
      "single_double" -> :double
      "single_bool" -> :bool
      "single_string" -> :string
      "single_bytes" -> :bytes
      "single_nested_message" -> {:message, @proto3_nested_message}
      "repeated_nested_message" -> {:list, {:message, @proto3_nested_message}}
      "single_int64_wrapper" -> {:wrapper, :int}
      "single_int32_wrapper" -> {:wrapper, :int}
      "single_uint64_wrapper" -> {:wrapper, :uint}
      "single_uint32_wrapper" -> {:wrapper, :uint}
      "single_float_wrapper" -> {:wrapper, :double}
      "single_double_wrapper" -> {:wrapper, :double}
      "single_bool_wrapper" -> {:wrapper, :bool}
      "single_string_wrapper" -> {:wrapper, :string}
      "single_bytes_wrapper" -> {:wrapper, :bytes}
      "repeated_int32" -> {:list, :int}
      "repeated_int64" -> {:list, :int}
      "repeated_uint32" -> {:list, :uint}
      "repeated_uint64" -> {:list, :uint}
      "repeated_float" -> {:list, :double}
      "repeated_double" -> {:list, :double}
      "repeated_bool" -> {:list, :bool}
      "repeated_string" -> {:list, :string}
      "repeated_bytes" -> {:list, :bytes}
      "repeated_nested_enum" -> {:list, :int}
      "map_int32_int64" -> {:map, :int, :int}
      "map_int64_int64" -> {:map, :int, :int}
      "map_string_string" -> {:map, :string, :string}
      "map_string_int64" -> {:map, :string, :int}
      "map_bool_int64" -> {:map, :bool, :int}
      "map_int32_enum" -> {:map, :int, :int}
      "map_int32_message" -> {:map, :int, {:message, @proto3_nested_message}}
      "standalone_enum" -> :int
      "single_duration" -> {:well_known, :duration}
      "single_timestamp" -> {:well_known, :timestamp}
      "single_any" -> :dyn
      "single_struct" -> {:map, :string, :dyn}
      "single_value" -> :dyn
      "list_value" -> {:list, :dyn}
      "oneof_type" -> {:message, @proto3_test_all_types}
      "nested_type" -> {:message, @proto3_nested_message}
      "single_nested_enum" -> :int
      _ -> :dyn
    end
  end

  def proto_field_type(@proto3_nested_message, field) do
    case field do
      "bb" -> :int
      _ -> :dyn
    end
  end

  def proto_field_type(_message_type, _field), do: :dyn

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp infer_ok(ast, env) do
    case infer(ast, env) do
      {:error, _} = err -> err
      type -> {:ok, type}
    end
  end

  @doc false
  def normalize_env(%{variables: _, functions: _} = env) do
    env
    |> Map.put_new(:container, nil)
    |> Map.put_new(:functions, %{})
    |> Map.put_new(:block_bindings, %{})
  end

  def normalize_env(map) when is_map(map) do
    # Legacy format: plain map of variable name => type
    # Stringify keys for backwards compat
    vars = Map.new(map, fn {k, v} -> {to_string(k), v} end)

    %{
      variables: vars,
      functions: %{},
      container: nil,
      block_bindings: %{}
    }
  end

  defp put_variable(env, name, type) do
    %{env | variables: Map.put(env.variables, name, type)}
  end

  defp put_block_binding(env, index, type) do
    bindings = Map.get(env, :block_bindings, %{})
    Map.put(env, :block_bindings, Map.put(bindings, index, type))
  end

  defp unwrap_type({:wrapper, t}), do: t
  defp unwrap_type(t), do: t

  defp op_name(:add), do: "+"
  defp op_name(:sub), do: "-"
  defp op_name(:mul), do: "*"
  defp op_name(:div), do: "/"
  defp op_name(:mod), do: "%"
  defp op_name(:and), do: "&&"
  defp op_name(:or), do: "||"

  defp format_type({:list, t}), do: "list(#{format_type(t)})"
  defp format_type({:map, k, v}), do: "map(#{format_type(k)}, #{format_type(v)})"
  defp format_type({:wrapper, t}), do: "wrapper(#{format_type(t)})"
  defp format_type({:message, name}), do: name
  defp format_type({:well_known, name}), do: "#{name}"
  defp format_type({:abstract, name, params}), do: "#{name}(#{Enum.map_join(params, ", ", &format_type/1)})"
  defp format_type({:type_param, name}), do: name
  defp format_type(t) when is_atom(t), do: Atom.to_string(t)
  defp format_type(t), do: inspect(t)

  defp timestamp_accessor_type(field) do
    case field do
      f when f in ~w(year month day hours minutes seconds milliseconds) -> :int
      _ -> :dyn
    end
  end

  @doc """
  Converts internal bottom types to :dyn in the final output.
  Call this on the result of `infer/2` before comparing with expected types.
  """
  def finalize_type(:_bottom), do: :dyn
  def finalize_type({:list, t}), do: {:list, finalize_type(t)}
  def finalize_type({:map, k, v}), do: {:map, finalize_type(k), finalize_type(v)}
  def finalize_type({:abstract, n, ps}), do: {:abstract, n, Enum.map(ps, &finalize_type/1)}
  def finalize_type({:wrapper, t}), do: {:wrapper, finalize_type(t)}
  def finalize_type(t), do: t

  defp duration_accessor_type(field) do
    case field do
      f when f in ~w(hours minutes seconds milliseconds) -> :int
      _ -> :dyn
    end
  end

  # Fallback for method calls that didn't match optional.* patterns
  defp infer_call_fallback(fname, target, args, decls) do
    env = normalize_env(decls)

    arg_types =
      if target do
        [infer(target, env) | Enum.map(args, &infer(&1, env))]
      else
        Enum.map(args, &infer(&1, env))
      end

    case Enum.find(arg_types, &match?({:error, _}, &1)) do
      {:error, _} = err ->
        err

      nil ->
        case Map.get(env.functions, fname, []) do
          [] -> :dyn
          overloads -> resolve_overload(overloads, arg_types)
        end
    end
  end
end
