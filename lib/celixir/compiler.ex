defmodule Celixir.Compiler do
  @moduledoc false
  # Compiles a CEL AST to an Elixir anonymous function.
  #
  # The compiled function has the signature:
  #   fn(__cel_env__) -> {:ok, value} | {:error, msg} end
  #
  # Two compilation strategies are supported:
  #
  # 1. `:closure` (default) — compiles the AST into a tree of native closures
  #    backed by `Celixir.Compiler.Runtime`. Creates zero atoms and loads zero
  #    BEAM modules at runtime, so compiled programs are garbage-collected
  #    normally and untrusted expressions cannot exhaust the atom or code table.
  #
  # 2. `:module` (opt-in via `strategy: :module` or `jit: true`) — generates an
  #    Elixir quoted AST and compiles a uniquely-named BEAM module via
  #    `Module.create/3`. Faster for tight arithmetic loops, at the cost of
  #    two permanent atoms and one resident module per call.
  #
  # Optimizations implemented in both strategies:
  # 1. Variable inlining: free variables are pattern-matched from the Environment
  #    struct directly, skipping Runtime.lookup overhead.
  # 2. Safe operator inlining: when both operands cannot produce {:cel_error, _},
  #    skip the error-check wrappers.
  # 3. Comprehension variable argument-passing: iter_var, iter_var2, and acc_var
  #    are passed as direct function arguments to loop thunks, eliminating
  #    struct copies and map lookups per iteration.

  alias Celixir.AST
  alias Celixir.Compiler.Runtime
  alias Celixir.Environment

  @compile {:inline, eval_ir: 5}

  # CEL type denotation names — these are not variable lookups
  @type_denotation_names ~w[bool int uint double string bytes list map type null_type optional_type]

  # Pre-allocated positional variable atoms for the `:module` strategy so that
  # compiling expressions with up to 64 free variables creates no variable atoms
  # at runtime. Expressions with more than 64 free variables inline the first 64
  # and resolve the remainder through `Runtime.lookup/2`.
  @max_inlined_module_vars 64
  @positional_var_atoms List.to_tuple(for idx <- 0..(@max_inlined_module_vars - 1), do: :"__cel_var_#{idx}__")

  @doc """
  Compiles a CEL AST to an anonymous function.

  ## Options

    * `:strategy` — `:closure` (default, zero atoms/modules) or `:module`
      (compiles a native BEAM module via `Module.create/3`).
    * `:jit` — boolean shorthand; `jit: true` selects `strategy: :module`.

  Returns `{:ok, fun}` where `fun` is `fn(env) -> {:ok, value} | {:error, msg} end`,
  or `{:error, reason}` if compilation fails.
  """
  @spec compile(AST.expr(), keyword()) ::
          {:ok, (Environment.t() -> {:ok, any()} | {:error, String.t()})}
          | {:error, String.t()}
  def compile(ast, opts \\ []) do
    case resolve_strategy(opts) do
      :closure -> compile_closure(ast)
      :module -> compile_module(ast)
    end
  end

  defp resolve_strategy(opts) when is_list(opts) do
    case Keyword.fetch(opts, :strategy) do
      {:ok, :module} -> :module
      {:ok, :closure} -> :closure
      {:ok, other} -> raise ArgumentError, "unknown compile strategy: #{inspect(other)} (expected :closure or :module)"
      :error -> if Keyword.get(opts, :jit, false), do: :module, else: :closure
    end
  end

  # ===================================================================
  # Strategy 1: Closure compiler (default — 0 atoms, 0 modules, GC-safe)
  # ===================================================================

  defp compile_closure(ast) do
    all_free = free_variables(ast)
    namespace_candidates = namespace_base_idents(ast)
    inlineable_vars = MapSet.difference(all_free, namespace_candidates)
    free_vars = inlineable_vars |> MapSet.to_list() |> Enum.sort()

    # At the top level (outside comprehensions/lambdas), the 3 slot arguments
    # (v1, v2, acc) of eval_ir/5 are otherwise unused, so we bind the first 3
    # free variables directly to (:v1, :v2, :acc). This lets the top-level map
    # pattern match pass their values straight into registers with zero further
    # map lookups.
    top_var_map =
      free_vars
      |> Enum.take(3)
      |> Enum.zip([:v1, :v2, :acc])
      |> Map.new()

    ctx = %{
      free_vars: MapSet.new(free_vars),
      bound_vars: MapSet.new(),
      comp_var_map: %{},
      top_var_map: top_var_map,
      top_level?: true
    }

    root_ir = compile_ir(ast, ctx)
    {:ok, build_closure_entry(root_ir, free_vars)}
  rescue
    e -> {:error, "compile error: #{Exception.message(e)}"}
  end

  defp build_closure_entry(root_ir, []) do
    fn cel_env ->
      try do
        {:ok, Celixir.unwrap(eval_ir(root_ir, cel_env, nil, nil, nil))}
      rescue
        e in Celixir.EvalError -> {:error, e.message}
      end
    end
  end

  defp build_closure_entry(root_ir, [k0]) do
    fn
      %Environment{variables: %{^k0 => v0}} = env ->
        try do
          {:ok, Celixir.unwrap(eval_ir(root_ir, env, v0, nil, nil))}
        rescue
          e in Celixir.EvalError -> {:error, e.message}
        end

      _env ->
        {:error, "undefined variable: #{k0}"}
    end
  end

  defp build_closure_entry(root_ir, [k0, k1] = free_vars) do
    fn
      %Environment{variables: %{^k0 => v0, ^k1 => v1}} = env ->
        try do
          {:ok, Celixir.unwrap(eval_ir(root_ir, env, v0, v1, nil))}
        rescue
          e in Celixir.EvalError -> {:error, e.message}
        end

      %Environment{variables: vars} ->
        missing_var_error(vars, free_vars)
    end
  end

  defp build_closure_entry(root_ir, [k0, k1, k2] = free_vars) do
    fn
      %Environment{variables: %{^k0 => v0, ^k1 => v1, ^k2 => v2}} = env ->
        try do
          {:ok, Celixir.unwrap(eval_ir(root_ir, env, v0, v1, v2))}
        rescue
          e in Celixir.EvalError -> {:error, e.message}
        end

      %Environment{variables: vars} ->
        missing_var_error(vars, free_vars)
    end
  end

  defp build_closure_entry(root_ir, [k0, k1, k2 | rest] = free_vars) do
    fn
      %Environment{variables: %{^k0 => v0, ^k1 => v1, ^k2 => v2} = vars} = env ->
        case find_missing_var(vars, rest) do
          nil ->
            try do
              {:ok, Celixir.unwrap(eval_ir(root_ir, env, v0, v1, v2))}
            rescue
              e in Celixir.EvalError -> {:error, e.message}
            end

          missing ->
            {:error, "undefined variable: #{missing}"}
        end

      %Environment{variables: vars} ->
        missing_var_error(vars, free_vars)
    end
  end

  defp missing_var_error(vars, free_vars) do
    case find_missing_var(vars, free_vars) do
      nil -> {:error, "undefined variable"}
      missing -> {:error, "undefined variable: #{missing}"}
    end
  end

  defp find_missing_var(_vars, []), do: nil

  defp find_missing_var(vars, [k | rest]) do
    if Map.has_key?(vars, k), do: find_missing_var(vars, rest), else: k
  end

  # Inline evaluator for IR nodes
  defp eval_ir({:const, v}, _env, _v1, _v2, _acc), do: v
  defp eval_ir(:v1, _env, v1, _v2, _acc), do: v1
  defp eval_ir(:v2, _env, _v1, v2, _acc), do: v2
  defp eval_ir(:acc, _env, _v1, _v2, acc), do: acc
  defp eval_ir({:var, name}, env, _v1, _v2, _acc), do: :erlang.map_get(name, env.variables)
  defp eval_ir(fun, env, v1, v2, acc) when is_function(fun, 4), do: fun.(env, v1, v2, acc)

  # Convert an IR node into a 4-arity closure when a higher-order runtime helper
  # (like Runtime.comprehension) expects a function reference.
  defp ir_to_fn4(fun) when is_function(fun, 4), do: fun
  defp ir_to_fn4(:v1), do: &fn4_v1/4
  defp ir_to_fn4(:v2), do: &fn4_v2/4
  defp ir_to_fn4(:acc), do: &fn4_acc/4
  defp ir_to_fn4({:const, v}), do: fn _env, _v1, _v2, _acc -> v end
  defp ir_to_fn4({:var, name}), do: fn env, _v1, _v2, _acc -> :erlang.map_get(name, env.variables) end

  defp fn4_v1(_env, v1, _v2, _acc), do: v1
  defp fn4_v2(_env, _v1, v2, _acc), do: v2
  defp fn4_acc(_env, _v1, _v2, acc), do: acc
  defp fn2_acc(_env, acc), do: acc

  # Specialize binary operator closures for common operand shapes (:v1, :v2, :acc, {:const, _}, {:var, _})
  # so hot loops and simple expressions avoid runtime `eval_ir/5` tag matching.
  defmacrop binop_ir(op_fun, li, ri) do
    quote do
      case {unquote(li), unquote(ri)} do
        {:v1, {:const, r}} ->
          fn _env, v1, _v2, _acc -> Runtime.unquote(op_fun)(v1, r) end

        {{:const, l}, :v1} ->
          fn _env, v1, _v2, _acc -> Runtime.unquote(op_fun)(l, v1) end

        {:v1, :v2} ->
          fn _env, v1, v2, _acc -> Runtime.unquote(op_fun)(v1, v2) end

        {:v2, {:const, r}} ->
          fn _env, _v1, v2, _acc -> Runtime.unquote(op_fun)(v2, r) end

        {:acc, {:const, r}} ->
          fn _env, _v1, _v2, acc -> Runtime.unquote(op_fun)(acc, r) end

        {:v1, {:var, k}} ->
          fn env, v1, _v2, _acc -> Runtime.unquote(op_fun)(v1, :erlang.map_get(k, env.variables)) end

        {{:var, k}, {:const, r}} ->
          fn env, _v1, _v2, _acc -> Runtime.unquote(op_fun)(:erlang.map_get(k, env.variables), r) end

        {lf, :v2} when is_function(lf, 4) ->
          fn env, v1, v2, acc -> Runtime.unquote(op_fun)(lf.(env, v1, v2, acc), v2) end

        {lf, {:const, r}} when is_function(lf, 4) ->
          fn env, v1, v2, acc -> Runtime.unquote(op_fun)(lf.(env, v1, v2, acc), r) end

        {li_other, ri_other} ->
          fn env, v1, v2, acc ->
            Runtime.unquote(op_fun)(eval_ir(li_other, env, v1, v2, acc), eval_ir(ri_other, env, v1, v2, acc))
          end
      end
    end
  end

  # --- compile_ir: CEL AST -> closure IR ---

  defp compile_ir(%AST.IntLit{value: v}, _ctx), do: {:const, v}
  defp compile_ir(%AST.UintLit{value: v}, _ctx), do: {:const, v}
  defp compile_ir(%AST.FloatLit{value: v}, _ctx), do: {:const, v}
  defp compile_ir(%AST.StringLit{value: v}, _ctx), do: {:const, v}
  defp compile_ir(%AST.BytesLit{value: v}, _ctx), do: {:const, v}
  defp compile_ir(%AST.BoolLit{value: v}, _ctx), do: {:const, v}
  defp compile_ir(%AST.NullLit{}, _ctx), do: {:const, nil}

  defp compile_ir(%AST.Ident{name: "true"}, _ctx), do: {:const, true}
  defp compile_ir(%AST.Ident{name: "false"}, _ctx), do: {:const, false}
  defp compile_ir(%AST.Ident{name: "null"}, _ctx), do: {:const, nil}

  defp compile_ir(%AST.Ident{name: name}, ctx) do
    cond do
      Map.has_key?(ctx.comp_var_map, name) ->
        Map.fetch!(ctx.comp_var_map, name)

      MapSet.member?(ctx.free_vars, name) and not MapSet.member?(ctx.bound_vars, name) ->
        if ctx.top_level? and Map.has_key?(ctx.top_var_map, name) do
          Map.fetch!(ctx.top_var_map, name)
        else
          {:var, name}
        end

      true ->
        fn env, _v1, _v2, _acc -> Runtime.lookup(env, name) end
    end
  end

  defp compile_ir(%AST.UnaryOp{op: :not, operand: operand}, ctx) do
    case compile_ir(operand, ctx) do
      :acc -> fn _env, _v1, _v2, acc -> Runtime.cel_not(acc) end
      :v1 -> fn _env, v1, _v2, _acc -> Runtime.cel_not(v1) end
      o -> fn env, v1, v2, acc -> Runtime.cel_not(eval_ir(o, env, v1, v2, acc)) end
    end
  end

  defp compile_ir(%AST.UnaryOp{op: :negate, operand: operand}, ctx) do
    o = compile_ir(operand, ctx)

    fn env, v1, v2, acc ->
      case eval_ir(o, env, v1, v2, acc) do
        v when is_integer(v) -> -v
        v when is_float(v) -> -v
        v -> Runtime.negate(v)
      end
    end
  end

  defp compile_ir(%AST.BinaryOp{op: :and, left: l, right: r}, ctx) do
    li = compile_ir(l, ctx)

    if safe?(l, ctx) and safe?(r, ctx) do
      # Fast path for `.all(x, pred)` comprehension loop_step (`__result__ && pred`):
      # fuse `acc && (v1 <cmp> const)` into a single closure with zero inner calls.
      case {li, r} do
        {:acc, %AST.BinaryOp{op: cmp_op, left: rl, right: rr}} when cmp_op in [:lt, :lte, :gt, :gte] ->
          case {compile_ir(rl, ctx), compile_ir(rr, ctx)} do
            {:v1, {:const, rc}} ->
              fn _env, v1, _v2, acc ->
                case acc do
                  true -> Runtime.safe_compare(cmp_op, v1, rc)
                  false -> false
                  other -> Runtime.cel_and(other, fn -> Runtime.safe_compare(cmp_op, v1, rc) end)
                end
              end

            {:v1, {:var, rk}} ->
              fn env, v1, _v2, acc ->
                case acc do
                  true ->
                    Runtime.safe_compare(cmp_op, v1, :erlang.map_get(rk, env.variables))

                  false ->
                    false

                  other ->
                    Runtime.cel_and(other, fn -> Runtime.safe_compare(cmp_op, v1, :erlang.map_get(rk, env.variables)) end)
                end
              end

            _ ->
              compile_safe_and(li, compile_ir(r, ctx))
          end

        _ ->
          compile_safe_and(li, compile_ir(r, ctx))
      end
    else
      ri = compile_ir(r, ctx)

      fn env, v1, v2, acc ->
        Runtime.cel_and(eval_ir(li, env, v1, v2, acc), fn -> eval_ir(ri, env, v1, v2, acc) end)
      end
    end
  end

  defp compile_ir(%AST.BinaryOp{op: :or, left: l, right: r}, ctx) do
    li = compile_ir(l, ctx)
    ri = compile_ir(r, ctx)

    if safe?(l, ctx) and safe?(r, ctx) do
      case {li, ri} do
        {:acc, rf} when is_function(rf, 4) ->
          fn env, v1, v2, acc ->
            case acc do
              false -> rf.(env, v1, v2, acc)
              true -> true
              other -> Runtime.cel_or(other, fn -> rf.(env, v1, v2, acc) end)
            end
          end

        _ ->
          fn env, v1, v2, acc ->
            case eval_ir(li, env, v1, v2, acc) do
              true -> true
              false -> eval_ir(ri, env, v1, v2, acc)
              other -> Runtime.cel_or(other, fn -> eval_ir(ri, env, v1, v2, acc) end)
            end
          end
      end
    else
      fn env, v1, v2, acc ->
        Runtime.cel_or(eval_ir(li, env, v1, v2, acc), fn -> eval_ir(ri, env, v1, v2, acc) end)
      end
    end
  end

  defp compile_ir(%AST.BinaryOp{op: :add, left: l, right: r}, ctx) do
    li = compile_ir(l, ctx)
    ri = compile_ir(r, ctx)
    binop_ir(:safe_add, li, ri)
  end

  defp compile_ir(%AST.BinaryOp{op: :sub, left: l, right: r}, ctx) do
    li = compile_ir(l, ctx)
    ri = compile_ir(r, ctx)
    binop_ir(:safe_sub, li, ri)
  end

  defp compile_ir(%AST.BinaryOp{op: :mul, left: l, right: r}, ctx) do
    li = compile_ir(l, ctx)
    ri = compile_ir(r, ctx)
    binop_ir(:safe_mul, li, ri)
  end

  defp compile_ir(%AST.BinaryOp{op: :div, left: l, right: r}, ctx) do
    li = compile_ir(l, ctx)
    ri = compile_ir(r, ctx)
    binop_ir(:safe_div, li, ri)
  end

  defp compile_ir(%AST.BinaryOp{op: :mod, left: l, right: r}, ctx) do
    li = compile_ir(l, ctx)
    ri = compile_ir(r, ctx)
    binop_ir(:safe_mod, li, ri)
  end

  defp compile_ir(%AST.BinaryOp{op: :eq, left: l, right: r}, ctx) do
    li = compile_ir(l, ctx)
    ri = compile_ir(r, ctx)

    if safe?(l, ctx) and safe?(r, ctx) do
      binop_ir(:safe_equal?, li, ri)
    else
      binop_ir(:cel_eq, li, ri)
    end
  end

  defp compile_ir(%AST.BinaryOp{op: :neq, left: l, right: r}, ctx) do
    li = compile_ir(l, ctx)
    ri = compile_ir(r, ctx)
    binop_ir(:cel_neq, li, ri)
  end

  defp compile_ir(%AST.BinaryOp{op: op, left: l, right: r}, ctx) when op in [:lt, :lte, :gt, :gte] do
    li = compile_ir(l, ctx)
    ri = compile_ir(r, ctx)

    case {li, ri} do
      {:v1, {:const, rc}} ->
        fn _env, v1, _v2, _acc -> Runtime.safe_compare(op, v1, rc) end

      {{:const, lc}, :v1} ->
        fn _env, v1, _v2, _acc -> Runtime.safe_compare(op, lc, v1) end

      {:v1, :v2} ->
        fn _env, v1, v2, _acc -> Runtime.safe_compare(op, v1, v2) end

      {:v1, {:var, rk}} ->
        fn env, v1, _v2, _acc -> Runtime.safe_compare(op, v1, :erlang.map_get(rk, env.variables)) end

      {{:var, lk}, {:const, rc}} ->
        fn env, _v1, _v2, _acc -> Runtime.safe_compare(op, :erlang.map_get(lk, env.variables), rc) end

      _ ->
        fn env, v1, v2, acc -> Runtime.safe_compare(op, eval_ir(li, env, v1, v2, acc), eval_ir(ri, env, v1, v2, acc)) end
    end
  end

  defp compile_ir(%AST.BinaryOp{op: :in, left: l, right: r}, ctx) do
    li = compile_ir(l, ctx)
    ri = compile_ir(r, ctx)
    binop_ir(:cel_in, li, ri)
  end

  defp compile_ir(%AST.Ternary{condition: c, true_expr: t, false_expr: f}, ctx) do
    ci = compile_ir(c, ctx)
    ti = compile_ir(t, ctx)
    fi = compile_ir(f, ctx)

    fn env, v1, v2, acc ->
      case eval_ir(ci, env, v1, v2, acc) do
        true ->
          eval_ir(ti, env, v1, v2, acc)

        false ->
          eval_ir(fi, env, v1, v2, acc)

        v ->
          raise Celixir.EvalError,
            message: "ternary condition must be bool, got #{Runtime.cel_typeof(v)}"
      end
    end
  end

  defp compile_ir(%AST.CreateList{elements: []}, _ctx), do: {:const, []}

  defp compile_ir(%AST.CreateList{elements: elements}, ctx) do
    compiled_elems =
      Enum.map(elements, fn
        {:optional_list_elem, expr} -> {:opt, compile_ir(expr, ctx)}
        expr -> {:req, compile_ir(expr, ctx)}
      end)

    fn env, v1, v2, acc ->
      items =
        Enum.map(compiled_elems, fn
          {:opt, ir} -> {:__cel_opt_elem__, eval_ir(ir, env, v1, v2, acc)}
          {:req, ir} -> eval_ir(ir, env, v1, v2, acc)
        end)

      Runtime.make_list(items)
    end
  end

  defp compile_ir(%AST.CreateMap{entries: []}, _ctx), do: {:const, %{}}

  defp compile_ir(%AST.CreateMap{entries: entries}, ctx) do
    compiled_entries =
      Enum.map(entries, fn
        {:optional, k_expr, v_expr} -> {:opt, compile_ir(k_expr, ctx), compile_ir(v_expr, ctx)}
        {k_expr, v_expr} -> {:req, compile_ir(k_expr, ctx), compile_ir(v_expr, ctx)}
      end)

    fn env, v1, v2, acc ->
      items =
        Enum.map(compiled_entries, fn
          {:opt, ki, vi} -> {:__cel_opt_entry__, eval_ir(ki, env, v1, v2, acc), eval_ir(vi, env, v1, v2, acc)}
          {:req, ki, vi} -> {:__cel_entry__, eval_ir(ki, env, v1, v2, acc), eval_ir(vi, env, v1, v2, acc)}
        end)

      Runtime.make_map(items)
    end
  end

  defp compile_ir(%AST.CreateStruct{type_name: type_name, entries: entries}, ctx) do
    compiled_entries =
      Enum.map(entries, fn
        {:optional, field, v_expr} -> {:opt, field, compile_ir(v_expr, ctx)}
        {field, v_expr} -> {:req, field, compile_ir(v_expr, ctx)}
      end)

    fn env, v1, v2, acc ->
      items =
        Enum.map(compiled_entries, fn
          {:opt, field, vi} -> {:__cel_opt_entry__, field, eval_ir(vi, env, v1, v2, acc)}
          {:req, field, vi} -> {:__cel_entry__, field, eval_ir(vi, env, v1, v2, acc)}
        end)

      Runtime.make_struct(env, type_name, items)
    end
  end

  defp compile_ir(%AST.Select{operand: operand, field: field, test_only: test_only}, ctx) do
    qualified = qualified_prefix(operand, field)
    oi = compile_ir(operand, ctx)

    fn env, v1, v2, acc ->
      Runtime.select(env, eval_ir(oi, env, v1, v2, acc), field, qualified, test_only)
    end
  end

  defp compile_ir(%AST.OptSelect{operand: operand, field: field}, ctx) do
    oi = compile_ir(operand, ctx)
    fn env, v1, v2, acc -> Runtime.opt_select(eval_ir(oi, env, v1, v2, acc), field) end
  end

  defp compile_ir(%AST.Index{operand: operand, index: idx}, ctx) do
    oi = compile_ir(operand, ctx)
    ii = compile_ir(idx, ctx)
    fn env, v1, v2, acc -> Runtime.cel_index(eval_ir(oi, env, v1, v2, acc), eval_ir(ii, env, v1, v2, acc)) end
  end

  defp compile_ir(%AST.OptIndex{operand: operand, index: idx}, ctx) do
    oi = compile_ir(operand, ctx)
    ii = compile_ir(idx, ctx)
    fn env, v1, v2, acc -> Runtime.opt_index(eval_ir(oi, env, v1, v2, acc), eval_ir(ii, env, v1, v2, acc)) end
  end

  defp compile_ir(%AST.Call{function: name, target: nil, args: args}, ctx) do
    case Enum.map(args, &compile_ir(&1, ctx)) do
      [] ->
        fn env, _v1, _v2, _acc -> Runtime.call(env, name, []) end

      [a0] ->
        fn env, v1, v2, acc -> Runtime.call(env, name, [eval_ir(a0, env, v1, v2, acc)]) end

      [a0, a1] ->
        fn env, v1, v2, acc ->
          Runtime.call(env, name, [eval_ir(a0, env, v1, v2, acc), eval_ir(a1, env, v1, v2, acc)])
        end

      args_ir ->
        fn env, v1, v2, acc ->
          Runtime.call(env, name, Enum.map(args_ir, &eval_ir(&1, env, v1, v2, acc)))
        end
    end
  end

  defp compile_ir(%AST.Call{function: name, target: target, args: args}, ctx) do
    ti = compile_ir(target, ctx)
    args_ir = Enum.map(args, &compile_ir(&1, ctx))
    qname = qualified_function_name(target, name)
    base_name = extract_base_name(target)

    is_known_var =
      MapSet.member?(ctx.free_vars, base_name) or Map.has_key?(ctx.comp_var_map, base_name)

    if qname && not is_known_var do
      case args_ir do
        [] ->
          fn env, v1, v2, acc ->
            case Runtime.lookup_opt(env, base_name) do
              :error -> Runtime.call(env, qname, [])
              {:ok, _} -> Runtime.method(env, name, eval_ir(ti, env, v1, v2, acc), [])
            end
          end

        [a0] ->
          fn env, v1, v2, acc ->
            arg0 = eval_ir(a0, env, v1, v2, acc)

            case Runtime.lookup_opt(env, base_name) do
              :error -> Runtime.call(env, qname, [arg0])
              {:ok, _} -> Runtime.method(env, name, eval_ir(ti, env, v1, v2, acc), [arg0])
            end
          end

        [a0, a1] ->
          fn env, v1, v2, acc ->
            eval_args = [eval_ir(a0, env, v1, v2, acc), eval_ir(a1, env, v1, v2, acc)]

            case Runtime.lookup_opt(env, base_name) do
              :error -> Runtime.call(env, qname, eval_args)
              {:ok, _} -> Runtime.method(env, name, eval_ir(ti, env, v1, v2, acc), eval_args)
            end
          end

        _ ->
          fn env, v1, v2, acc ->
            eval_args = Enum.map(args_ir, &eval_ir(&1, env, v1, v2, acc))

            case Runtime.lookup_opt(env, base_name) do
              :error -> Runtime.call(env, qname, eval_args)
              {:ok, _} -> Runtime.method(env, name, eval_ir(ti, env, v1, v2, acc), eval_args)
            end
          end
      end
    else
      case args_ir do
        [] ->
          fn env, v1, v2, acc ->
            Runtime.method(env, name, eval_ir(ti, env, v1, v2, acc), [])
          end

        [a0] ->
          fn env, v1, v2, acc ->
            Runtime.method(env, name, eval_ir(ti, env, v1, v2, acc), [eval_ir(a0, env, v1, v2, acc)])
          end

        [a0, a1] ->
          fn env, v1, v2, acc ->
            Runtime.method(env, name, eval_ir(ti, env, v1, v2, acc), [
              eval_ir(a0, env, v1, v2, acc),
              eval_ir(a1, env, v1, v2, acc)
            ])
          end

        _ ->
          fn env, v1, v2, acc ->
            Runtime.method(
              env,
              name,
              eval_ir(ti, env, v1, v2, acc),
              Enum.map(args_ir, &eval_ir(&1, env, v1, v2, acc))
            )
          end
      end
    end
  end

  defp compile_ir(%AST.Comprehension{} = comp, ctx) do
    range_ir = compile_ir(comp.iter_range, ctx)
    acc_init_ir = compile_ir(comp.acc_init, ctx)

    # If nested inside an outer comprehension, push outer comprehension vars into
    # bound_vars and flush their runtime values into `env.locals` before running
    # the inner loop so inner (:v1, :v2, :acc) slots never shadow outer vars.
    outer_comp_vars = Map.to_list(ctx.comp_var_map)

    bound_with_outer =
      Enum.reduce(outer_comp_vars, ctx.bound_vars, fn {name, _slot}, b -> MapSet.put(b, name) end)

    comp_var_map =
      then(%{comp.iter_var => :v1, comp.acc_var => :acc}, fn m ->
        if comp.iter_var2, do: Map.put(m, comp.iter_var2, :v2), else: m
      end)

    inner_ctx = %{
      ctx
      | comp_var_map: comp_var_map,
        bound_vars: bound_with_outer,
        top_level?: false
    }

    result_ctx = %{
      ctx
      | comp_var_map: %{comp.acc_var => :acc},
        bound_vars: bound_with_outer,
        top_level?: false
    }

    loop_cond_f = comp.loop_condition |> compile_ir(inner_ctx) |> ir_to_fn4()
    loop_step_f = comp.loop_step |> compile_ir(inner_ctx) |> ir_to_fn4()

    result_f =
      case compile_ir(comp.result, result_ctx) do
        :acc ->
          &fn2_acc/2

        result_ir ->
          fn env, final_acc -> eval_ir(result_ir, env, nil, nil, final_acc) end
      end

    kind_compiled =
      case comp.kind do
        {:transform_map, transform_expr, filter_expr} ->
          tf = transform_expr |> compile_ir(inner_ctx) |> ir_to_fn4()
          ff = if filter_expr, do: filter_expr |> compile_ir(inner_ctx) |> ir_to_fn4()
          {:transform_map, tf, ff}

        {:transform_map_entry, transform_expr, filter_expr} ->
          tf = transform_expr |> compile_ir(inner_ctx) |> ir_to_fn4()
          ff = if filter_expr, do: filter_expr |> compile_ir(inner_ctx) |> ir_to_fn4()
          {:transform_map_entry, tf, ff}

        {:sort_by, key_expr} ->
          kf = key_expr |> compile_ir(inner_ctx) |> ir_to_fn4()
          {:sort_by, kf}

        {:collect_list, filter_expr, transform_expr} ->
          tf = transform_expr |> compile_ir(inner_ctx) |> ir_to_fn4()
          ff = if filter_expr, do: filter_expr |> compile_ir(inner_ctx) |> ir_to_fn4()
          {:collect_list, tf, ff}

        :standard ->
          :standard
      end

    iter_var = comp.iter_var
    iter_var2 = comp.iter_var2
    acc_var = comp.acc_var

    if outer_comp_vars == [] do
      fn env, v1, v2, acc ->
        Runtime.comprehension(
          env,
          eval_ir(range_ir, env, v1, v2, acc),
          iter_var,
          iter_var2,
          acc_var,
          eval_ir(acc_init_ir, env, v1, v2, acc),
          loop_cond_f,
          loop_step_f,
          result_f,
          kind_compiled
        )
      end
    else
      fn env, v1, v2, acc ->
        range_val = eval_ir(range_ir, env, v1, v2, acc)
        init_val = eval_ir(acc_init_ir, env, v1, v2, acc)
        inner_env = bind_outer_comp_vars(env, outer_comp_vars, v1, v2, acc)

        Runtime.comprehension(
          inner_env,
          range_val,
          iter_var,
          iter_var2,
          acc_var,
          init_val,
          loop_cond_f,
          loop_step_f,
          result_f,
          kind_compiled
        )
      end
    end
  end

  defp compile_ir(%AST.OptLambda{kind: kind, target: target, var: var, expr: expr}, ctx) do
    ti = compile_ir(target, ctx)
    outer_comp_vars = Map.to_list(ctx.comp_var_map)

    bound_with_outer =
      outer_comp_vars
      |> Enum.reduce(ctx.bound_vars, fn {name, _slot}, b -> MapSet.put(b, name) end)
      |> MapSet.put(var)

    inner_ctx = %{
      ctx
      | comp_var_map: %{},
        bound_vars: bound_with_outer,
        top_level?: false
    }

    expr_ir = compile_ir(expr, inner_ctx)
    expr_thunk = fn inner_env -> eval_ir(expr_ir, inner_env, nil, nil, nil) end

    if outer_comp_vars == [] do
      fn env, v1, v2, acc ->
        Runtime.opt_lambda(env, eval_ir(ti, env, v1, v2, acc), var, kind, expr_thunk)
      end
    else
      fn env, v1, v2, acc ->
        target_val = eval_ir(ti, env, v1, v2, acc)
        inner_env = bind_outer_comp_vars(env, outer_comp_vars, v1, v2, acc)
        Runtime.opt_lambda(inner_env, target_val, var, kind, expr_thunk)
      end
    end
  end

  defp compile_ir(%AST.CelBlock{bindings: bindings, result: result}, ctx) do
    outer_comp_vars = Map.to_list(ctx.comp_var_map)

    bound_with_outer =
      Enum.reduce(outer_comp_vars, ctx.bound_vars, fn {name, _slot}, b -> MapSet.put(b, name) end)

    inner_ctx = %{
      ctx
      | comp_var_map: %{},
        bound_vars: bound_with_outer,
        top_level?: false
    }

    binding_thunks =
      Enum.map(bindings, fn expr ->
        bi = compile_ir(expr, inner_ctx)
        fn step_env -> eval_ir(bi, step_env, nil, nil, nil) end
      end)

    result_ir = compile_ir(result, inner_ctx)
    result_thunk = fn final_env -> eval_ir(result_ir, final_env, nil, nil, nil) end

    if outer_comp_vars == [] do
      fn env, _v1, _v2, _acc ->
        Runtime.cel_block(env, binding_thunks, result_thunk)
      end
    else
      fn env, v1, v2, acc ->
        inner_env = bind_outer_comp_vars(env, outer_comp_vars, v1, v2, acc)
        Runtime.cel_block(inner_env, binding_thunks, result_thunk)
      end
    end
  end

  defp compile_ir(%AST.CelIndex{index: n}, _ctx) do
    name = "__cel_block_#{n}__"
    err = {:cel_error, "cel.index(#{n}): binding not found"}

    fn env, _v1, _v2, _acc ->
      case Environment.get_variable(env, name) do
        {:ok, v} -> v
        :error -> err
      end
    end
  end

  defp compile_ir(%AST.CelIterVar{depth: depth, index: idx}, _ctx) do
    name = "__cel_iter_#{depth}_#{idx}__"
    err = {:cel_error, "cel.iterVar(#{depth}, #{idx}): variable not found"}

    fn env, _v1, _v2, _acc ->
      case Environment.get_variable(env, name) do
        {:ok, v} -> v
        :error -> err
      end
    end
  end

  defp compile_safe_and(:acc, rf) when is_function(rf, 4) do
    fn env, v1, v2, acc ->
      case acc do
        true -> rf.(env, v1, v2, acc)
        false -> false
        other -> Runtime.cel_and(other, fn -> rf.(env, v1, v2, acc) end)
      end
    end
  end

  defp compile_safe_and(li, ri) do
    fn env, v1, v2, acc ->
      case eval_ir(li, env, v1, v2, acc) do
        false -> false
        true -> eval_ir(ri, env, v1, v2, acc)
        other -> Runtime.cel_and(other, fn -> eval_ir(ri, env, v1, v2, acc) end)
      end
    end
  end

  defp bind_outer_comp_vars(env, [], _v1, _v2, _acc), do: env

  defp bind_outer_comp_vars(env, [{name, slot} | rest], v1, v2, acc) do
    val =
      case slot do
        :v1 -> v1
        :v2 -> v2
        :acc -> acc
      end

    env
    |> Environment.put_local_raw(name, val)
    |> bind_outer_comp_vars(rest, v1, v2, acc)
  end

  # ===================================================================
  # Strategy 2: Module compiler (opt-in via `strategy: :module` / `jit: true`)
  # ===================================================================

  defp compile_module(ast) do
    # Collect top-level free variables (names that come from the Environment)
    all_free = free_variables(ast)

    # Remove names that appear as base of a qualified method/function call.
    # These might be function namespaces (e.g. "math" in math.sqrt(x)),
    # not actual variables — they need the Runtime.lookup fallback.
    namespace_candidates = namespace_base_idents(ast)
    inlineable_vars = MapSet.difference(all_free, namespace_candidates)

    free_vars =
      inlineable_vars
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.take(@max_inlined_module_vars)

    module_name = :"Celixir.Compiled.#{:erlang.unique_integer([:positive, :monotonic])}"

    # Map each free variable name to a pre-allocated positional atom (:__cel_var_0__, ...).
    var_index_map =
      free_vars
      |> Enum.with_index()
      |> Map.new(fn {name, idx} -> {name, elem(@positional_var_atoms, idx)} end)

    # Generate the body with free variables inlined
    ctx = %{
      free_vars: MapSet.new(free_vars),
      bound_vars: MapSet.new(),
      comp_var_map: %{},
      var_index_map: var_index_map
    }

    body = to_quoted(ast, ctx)

    # Build the pattern-matching function head that extracts variables directly
    # from the Environment struct's variables map.
    eval_fn = build_eval_fn(body, free_vars)

    Module.create(module_name, eval_fn, __ENV__)
    {:ok, :erlang.make_fun(module_name, :eval, 1)}
  rescue
    e -> {:error, "compile error: #{Exception.message(e)}"}
  end

  # ===================================================================
  # Build def eval(...) with pattern-matched variables for efficiency
  # ===================================================================

  defp build_eval_fn(body, []) do
    quote do
      def eval(__cel_env__) do
        {:ok, Celixir.unwrap(unquote(body))}
      rescue
        e in Celixir.EvalError -> {:error, e.message}
      end
    end
  end

  defp build_eval_fn(body, free_vars) do
    # Build a map pattern: %{"x" => __cel_var_0__, "y" => __cel_var_1__, ...}
    # Uses pre-allocated positional atoms as Elixir AST variable names rather than
    # converting CEL identifier strings to atoms.
    var_pairs =
      Enum.with_index(free_vars, fn name, idx ->
        var = Macro.var(elem(@positional_var_atoms, idx), __MODULE__)
        {name, var}
      end)

    vars_map_pattern = {:%{}, [], var_pairs}

    env_pattern =
      quote do
        %Celixir.Environment{variables: unquote(vars_map_pattern)} = __cel_env__
      end

    # Fallback when a free variable is missing from the environment
    missing_check =
      Enum.reduce(Enum.reverse(free_vars), nil, fn name, acc ->
        if acc == nil do
          quote do: {:error, "undefined variable: #{unquote(name)}"}
        else
          quote do
            if Map.has_key?(__cel_env__.variables, unquote(name)) do
              unquote(acc)
            else
              {:error, "undefined variable: #{unquote(name)}"}
            end
          end
        end
      end)

    quote do
      def eval(unquote(env_pattern)) do
        {:ok, Celixir.unwrap(unquote(body))}
      rescue
        e in Celixir.EvalError -> {:error, e.message}
      end

      def eval(__cel_env__) do
        unquote(missing_check)
      end
    end
  end

  # ===================================================================
  # Free variable collection
  # ===================================================================

  # Walk the AST and collect all identifier names that are free variables
  # (i.e., come from the Environment, not locally bound).
  defp free_variables(ast), do: free_variables(ast, MapSet.new(), MapSet.new())

  defp free_variables(%AST.IntLit{}, _bound, acc), do: acc
  defp free_variables(%AST.UintLit{}, _bound, acc), do: acc
  defp free_variables(%AST.FloatLit{}, _bound, acc), do: acc
  defp free_variables(%AST.StringLit{}, _bound, acc), do: acc
  defp free_variables(%AST.BytesLit{}, _bound, acc), do: acc
  defp free_variables(%AST.BoolLit{}, _bound, acc), do: acc
  defp free_variables(%AST.NullLit{}, _bound, acc), do: acc

  defp free_variables(%AST.Ident{name: name}, bound, acc) do
    if name in ["true", "false", "null"] or
         name in @type_denotation_names or
         MapSet.member?(bound, name) do
      acc
    else
      MapSet.put(acc, name)
    end
  end

  defp free_variables(%AST.UnaryOp{operand: operand}, bound, acc) do
    free_variables(operand, bound, acc)
  end

  defp free_variables(%AST.BinaryOp{left: l, right: r}, bound, acc) do
    acc |> then(&free_variables(l, bound, &1)) |> then(&free_variables(r, bound, &1))
  end

  defp free_variables(%AST.Ternary{condition: c, true_expr: t, false_expr: f}, bound, acc) do
    acc
    |> then(&free_variables(c, bound, &1))
    |> then(&free_variables(t, bound, &1))
    |> then(&free_variables(f, bound, &1))
  end

  defp free_variables(%AST.CreateList{elements: elements}, bound, acc) do
    Enum.reduce(elements, acc, fn
      {:optional_list_elem, expr}, a -> free_variables(expr, bound, a)
      expr, a -> free_variables(expr, bound, a)
    end)
  end

  defp free_variables(%AST.CreateMap{entries: entries}, bound, acc) do
    Enum.reduce(entries, acc, fn
      {:optional, k, v}, a ->
        a |> then(&free_variables(k, bound, &1)) |> then(&free_variables(v, bound, &1))

      {k, v}, a ->
        a |> then(&free_variables(k, bound, &1)) |> then(&free_variables(v, bound, &1))
    end)
  end

  defp free_variables(%AST.CreateStruct{entries: entries}, bound, acc) do
    Enum.reduce(entries, acc, fn
      {:optional, _field, v}, a -> free_variables(v, bound, a)
      {_field, v}, a -> free_variables(v, bound, a)
    end)
  end

  defp free_variables(%AST.Select{operand: operand}, bound, acc) do
    free_variables(operand, bound, acc)
  end

  defp free_variables(%AST.OptSelect{operand: operand}, bound, acc) do
    free_variables(operand, bound, acc)
  end

  defp free_variables(%AST.Index{operand: operand, index: idx}, bound, acc) do
    acc |> then(&free_variables(operand, bound, &1)) |> then(&free_variables(idx, bound, &1))
  end

  defp free_variables(%AST.OptIndex{operand: operand, index: idx}, bound, acc) do
    acc |> then(&free_variables(operand, bound, &1)) |> then(&free_variables(idx, bound, &1))
  end

  defp free_variables(%AST.Call{target: target, args: args}, bound, acc) do
    acc2 = if target, do: free_variables(target, bound, acc), else: acc
    Enum.reduce(args, acc2, fn arg, a -> free_variables(arg, bound, a) end)
  end

  defp free_variables(%AST.Comprehension{} = comp, bound, acc) do
    # The range and acc_init use the outer bound set
    acc2 =
      acc
      |> then(&free_variables(comp.iter_range, bound, &1))
      |> then(&free_variables(comp.acc_init, bound, &1))

    # Inside the loop, iter_var, iter_var2, acc_var are locally bound
    inner_bound =
      bound
      |> MapSet.put(comp.iter_var)
      |> MapSet.put(comp.acc_var)
      |> then(fn b -> if comp.iter_var2, do: MapSet.put(b, comp.iter_var2), else: b end)

    acc3 =
      acc2
      |> then(&free_variables(comp.loop_condition, inner_bound, &1))
      |> then(&free_variables(comp.loop_step, inner_bound, &1))
      |> then(&free_variables(comp.result, inner_bound, &1))

    # kind extras
    case comp.kind do
      {:transform_map, transform_expr, filter_expr} ->
        acc4 = free_variables(transform_expr, inner_bound, acc3)
        if filter_expr, do: free_variables(filter_expr, inner_bound, acc4), else: acc4

      {:transform_map_entry, transform_expr, filter_expr} ->
        acc4 = free_variables(transform_expr, inner_bound, acc3)
        if filter_expr, do: free_variables(filter_expr, inner_bound, acc4), else: acc4

      {:sort_by, key_expr} ->
        free_variables(key_expr, inner_bound, acc3)

      {:collect_list, filter_expr, transform_expr} ->
        acc4 = free_variables(transform_expr, inner_bound, acc3)
        if filter_expr, do: free_variables(filter_expr, inner_bound, acc4), else: acc4

      :standard ->
        acc3
    end
  end

  defp free_variables(%AST.OptLambda{target: target, expr: expr, var: var}, bound, acc) do
    acc2 = free_variables(target, bound, acc)
    inner_bound = MapSet.put(bound, var)
    free_variables(expr, inner_bound, acc2)
  end

  defp free_variables(%AST.CelBlock{bindings: bindings, result: result}, bound, acc) do
    acc2 = Enum.reduce(bindings, acc, fn b, a -> free_variables(b, bound, a) end)
    free_variables(result, bound, acc2)
  end

  defp free_variables(%AST.CelIndex{}, _bound, acc), do: acc
  defp free_variables(%AST.CelIterVar{}, _bound, acc), do: acc
  defp free_variables(_, _bound, acc), do: acc

  # ===================================================================
  # Namespace base ident collection
  # ===================================================================
  # Collect all ident names that appear as the base of a qualified method/function
  # call target (e.g. "math" in math.sqrt(x), "base64" in base64.encode(s)).
  # These names might be function namespaces, not variables, so we don't inline them.

  defp namespace_base_idents(ast), do: namespace_base_idents(ast, MapSet.new())

  defp namespace_base_idents(%AST.Call{target: target, args: args}, acc) do
    acc2 =
      case target do
        nil ->
          acc

        _ ->
          # If target is a qualified chain, extract the base ident name
          case extract_base_name(target) do
            "<expr>" ->
              namespace_base_idents(target, acc)

            base_name when base_name != nil ->
              # Only add if extract_qualified_name returns non-nil (it's a chain)
              if extract_qualified_name(target) == nil do
                namespace_base_idents(target, acc)
              else
                MapSet.put(acc, base_name)
              end
          end
      end

    Enum.reduce(args, acc2, fn arg, a -> namespace_base_idents(arg, a) end)
  end

  defp namespace_base_idents(%AST.BinaryOp{left: l, right: r}, acc) do
    acc |> then(&namespace_base_idents(l, &1)) |> then(&namespace_base_idents(r, &1))
  end

  defp namespace_base_idents(%AST.UnaryOp{operand: o}, acc) do
    namespace_base_idents(o, acc)
  end

  defp namespace_base_idents(%AST.Ternary{condition: c, true_expr: t, false_expr: f}, acc) do
    acc
    |> then(&namespace_base_idents(c, &1))
    |> then(&namespace_base_idents(t, &1))
    |> then(&namespace_base_idents(f, &1))
  end

  defp namespace_base_idents(%AST.Select{operand: o}, acc), do: namespace_base_idents(o, acc)
  defp namespace_base_idents(%AST.OptSelect{operand: o}, acc), do: namespace_base_idents(o, acc)

  defp namespace_base_idents(%AST.Index{operand: o, index: i}, acc) do
    acc |> then(&namespace_base_idents(o, &1)) |> then(&namespace_base_idents(i, &1))
  end

  defp namespace_base_idents(%AST.OptIndex{operand: o, index: i}, acc) do
    acc |> then(&namespace_base_idents(o, &1)) |> then(&namespace_base_idents(i, &1))
  end

  defp namespace_base_idents(%AST.CreateList{elements: elems}, acc) do
    Enum.reduce(elems, acc, fn
      {:optional_list_elem, e}, a -> namespace_base_idents(e, a)
      e, a -> namespace_base_idents(e, a)
    end)
  end

  defp namespace_base_idents(%AST.CreateMap{entries: entries}, acc) do
    Enum.reduce(entries, acc, fn
      {:optional, k, v}, a ->
        a |> then(&namespace_base_idents(k, &1)) |> then(&namespace_base_idents(v, &1))

      {k, v}, a ->
        a |> then(&namespace_base_idents(k, &1)) |> then(&namespace_base_idents(v, &1))
    end)
  end

  defp namespace_base_idents(%AST.CreateStruct{entries: entries}, acc) do
    Enum.reduce(entries, acc, fn
      {:optional, _, v}, a -> namespace_base_idents(v, a)
      {_, v}, a -> namespace_base_idents(v, a)
    end)
  end

  defp namespace_base_idents(%AST.Comprehension{} = comp, acc) do
    acc
    |> then(&namespace_base_idents(comp.iter_range, &1))
    |> then(&namespace_base_idents(comp.acc_init, &1))
    |> then(&namespace_base_idents(comp.loop_condition, &1))
    |> then(&namespace_base_idents(comp.loop_step, &1))
    |> then(&namespace_base_idents(comp.result, &1))
    |> then(fn a ->
      case comp.kind do
        {:transform_map, t, f} ->
          a2 = namespace_base_idents(t, a)
          if f, do: namespace_base_idents(f, a2), else: a2

        {:transform_map_entry, t, f} ->
          a2 = namespace_base_idents(t, a)
          if f, do: namespace_base_idents(f, a2), else: a2

        {:sort_by, k} ->
          namespace_base_idents(k, a)

        {:collect_list, f, t} ->
          a2 = namespace_base_idents(t, a)
          if f, do: namespace_base_idents(f, a2), else: a2

        :standard ->
          a
      end
    end)
  end

  defp namespace_base_idents(%AST.OptLambda{target: t, expr: e}, acc) do
    acc |> then(&namespace_base_idents(t, &1)) |> then(&namespace_base_idents(e, &1))
  end

  defp namespace_base_idents(%AST.CelBlock{bindings: bindings, result: result}, acc) do
    acc2 = Enum.reduce(bindings, acc, &namespace_base_idents/2)
    namespace_base_idents(result, acc2)
  end

  defp namespace_base_idents(_, acc), do: acc

  # ===================================================================
  # to_quoted — generate Elixir AST from CEL AST (for :module strategy)
  # ===================================================================

  # --- Literals ---

  defp to_quoted(%AST.IntLit{value: v}, _ctx), do: v
  defp to_quoted(%AST.UintLit{value: v}, _ctx), do: v
  defp to_quoted(%AST.FloatLit{value: v}, _ctx), do: Macro.escape(v)
  defp to_quoted(%AST.StringLit{value: v}, _ctx), do: v
  defp to_quoted(%AST.BytesLit{value: v}, _ctx), do: v
  defp to_quoted(%AST.BoolLit{value: v}, _ctx), do: v
  defp to_quoted(%AST.NullLit{}, _ctx), do: nil

  # --- Identifiers ---

  defp to_quoted(%AST.Ident{name: "true"}, _ctx), do: true
  defp to_quoted(%AST.Ident{name: "false"}, _ctx), do: false
  defp to_quoted(%AST.Ident{name: "null"}, _ctx), do: nil

  defp to_quoted(%AST.Ident{name: name}, ctx) do
    cond do
      # Comprehension loop variable — passed as a direct function argument to thunks
      Map.has_key?(ctx.comp_var_map, name) ->
        Macro.var(Map.get(ctx.comp_var_map, name), __MODULE__)

      # Free variable inlining — reference the positional variable bound in the
      # pattern-matched function head (e.g. :__cel_var_0__ for the first free var).
      # No atoms are created from the CEL identifier name.
      MapSet.member?(ctx.free_vars, name) and not MapSet.member?(ctx.bound_vars, name) ->
        Macro.var(Map.fetch!(ctx.var_index_map, name), __MODULE__)

      true ->
        quote do: Celixir.Compiler.Runtime.lookup(__cel_env__, unquote(name))
    end
  end

  # --- Unary operators ---

  defp to_quoted(%AST.UnaryOp{op: :not, operand: operand}, ctx) do
    o = to_quoted(operand, ctx)
    quote do: Celixir.Compiler.Runtime.cel_not(unquote(o))
  end

  defp to_quoted(%AST.UnaryOp{op: :negate, operand: operand}, ctx) do
    o = to_quoted(operand, ctx)

    quote do
      case unquote(o) do
        v when is_integer(v) -> -v
        v when is_float(v) -> -v
        v -> Celixir.Compiler.Runtime.negate(v)
      end
    end
  end

  # --- Logical operators (short-circuit with error absorption) ---

  defp to_quoted(%AST.BinaryOp{op: :and, left: l, right: r}, ctx) do
    lq = to_quoted(l, ctx)
    rq = to_quoted(r, ctx)

    if safe?(l, ctx) and safe?(r, ctx) do
      # Both sides are safe — inline without closure allocation
      quote do
        case unquote(lq) do
          false -> false
          true -> unquote(rq)
          __cel_v__ -> Celixir.Compiler.Runtime.cel_and(__cel_v__, fn -> unquote(rq) end)
        end
      end
    else
      quote do: Celixir.Compiler.Runtime.cel_and(unquote(lq), fn -> unquote(rq) end)
    end
  end

  defp to_quoted(%AST.BinaryOp{op: :or, left: l, right: r}, ctx) do
    lq = to_quoted(l, ctx)
    rq = to_quoted(r, ctx)

    if safe?(l, ctx) and safe?(r, ctx) do
      # Both sides are safe — inline without closure allocation
      quote do
        case unquote(lq) do
          true -> true
          false -> unquote(rq)
          __cel_v__ -> Celixir.Compiler.Runtime.cel_or(__cel_v__, fn -> unquote(rq) end)
        end
      end
    else
      quote do: Celixir.Compiler.Runtime.cel_or(unquote(lq), fn -> unquote(rq) end)
    end
  end

  # --- Arithmetic ---

  defp to_quoted(%AST.BinaryOp{op: :add, left: l, right: r}, ctx) do
    lq = to_quoted(l, ctx)
    rq = to_quoted(r, ctx)

    if safe?(l, ctx) and safe?(r, ctx) do
      quote do: Celixir.Compiler.Runtime.safe_add(unquote(lq), unquote(rq))
    else
      quote do: Celixir.Compiler.Runtime.cel_add(unquote(lq), unquote(rq))
    end
  end

  defp to_quoted(%AST.BinaryOp{op: :sub, left: l, right: r}, ctx) do
    lq = to_quoted(l, ctx)
    rq = to_quoted(r, ctx)

    if safe?(l, ctx) and safe?(r, ctx) do
      quote do: Celixir.Compiler.Runtime.safe_sub(unquote(lq), unquote(rq))
    else
      quote do: Celixir.Compiler.Runtime.cel_sub(unquote(lq), unquote(rq))
    end
  end

  defp to_quoted(%AST.BinaryOp{op: :mul, left: l, right: r}, ctx) do
    lq = to_quoted(l, ctx)
    rq = to_quoted(r, ctx)

    if safe?(l, ctx) and safe?(r, ctx) do
      quote do: Celixir.Compiler.Runtime.safe_mul(unquote(lq), unquote(rq))
    else
      quote do: Celixir.Compiler.Runtime.cel_mul(unquote(lq), unquote(rq))
    end
  end

  defp to_quoted(%AST.BinaryOp{op: :div, left: l, right: r}, ctx) do
    lq = to_quoted(l, ctx)
    rq = to_quoted(r, ctx)

    if safe?(l, ctx) and safe?(r, ctx) do
      quote do: Celixir.Compiler.Runtime.safe_div(unquote(lq), unquote(rq))
    else
      quote do: Celixir.Compiler.Runtime.cel_div(unquote(lq), unquote(rq))
    end
  end

  defp to_quoted(%AST.BinaryOp{op: :mod, left: l, right: r}, ctx) do
    lq = to_quoted(l, ctx)
    rq = to_quoted(r, ctx)

    if safe?(l, ctx) and safe?(r, ctx) do
      quote do: Celixir.Compiler.Runtime.safe_mod(unquote(lq), unquote(rq))
    else
      quote do: Celixir.Compiler.Runtime.cel_mod(unquote(lq), unquote(rq))
    end
  end

  # --- Comparison ---

  defp to_quoted(%AST.BinaryOp{op: :eq, left: l, right: r}, ctx) do
    lq = to_quoted(l, ctx)
    rq = to_quoted(r, ctx)

    if safe?(l, ctx) and safe?(r, ctx) do
      quote do: Celixir.Compiler.Runtime.safe_equal?(unquote(lq), unquote(rq))
    else
      quote do: Celixir.Compiler.Runtime.cel_eq(unquote(lq), unquote(rq))
    end
  end

  defp to_quoted(%AST.BinaryOp{op: :neq, left: l, right: r}, ctx) do
    lq = to_quoted(l, ctx)
    rq = to_quoted(r, ctx)

    if safe?(l, ctx) and safe?(r, ctx) do
      quote do: not Celixir.Compiler.Runtime.safe_equal?(unquote(lq), unquote(rq))
    else
      quote do: Celixir.Compiler.Runtime.cel_neq(unquote(lq), unquote(rq))
    end
  end

  defp to_quoted(%AST.BinaryOp{op: op, left: l, right: r}, ctx) when op in [:lt, :lte, :gt, :gte] do
    lq = to_quoted(l, ctx)
    rq = to_quoted(r, ctx)

    if safe?(l, ctx) and safe?(r, ctx) do
      quote do: Celixir.Compiler.Runtime.safe_compare(unquote(op), unquote(lq), unquote(rq))
    else
      quote do: Celixir.Compiler.Runtime.cel_compare(unquote(lq), unquote(rq), unquote(op))
    end
  end

  # --- Membership ---

  defp to_quoted(%AST.BinaryOp{op: :in, left: l, right: r}, ctx) do
    lq = to_quoted(l, ctx)
    rq = to_quoted(r, ctx)
    quote do: Celixir.Compiler.Runtime.cel_in(unquote(lq), unquote(rq))
  end

  # --- Ternary ---

  defp to_quoted(%AST.Ternary{condition: c, true_expr: t, false_expr: f}, ctx) do
    cq = to_quoted(c, ctx)
    tq = to_quoted(t, ctx)
    fq = to_quoted(f, ctx)

    quote do
      case unquote(cq) do
        true ->
          unquote(tq)

        false ->
          unquote(fq)

        v ->
          raise Celixir.EvalError,
            message: "ternary condition must be bool, got #{Celixir.Compiler.Runtime.cel_typeof(v)}"
      end
    end
  end

  # --- List construction ---

  defp to_quoted(%AST.CreateList{elements: elements}, ctx) do
    items =
      Enum.map(elements, fn
        {:optional_list_elem, expr} ->
          eq = to_quoted(expr, ctx)
          quote do: {:__cel_opt_elem__, unquote(eq)}

        expr ->
          to_quoted(expr, ctx)
      end)

    quote do: Celixir.Compiler.Runtime.make_list([unquote_splicing(items)])
  end

  # --- Map construction ---

  defp to_quoted(%AST.CreateMap{entries: entries}, ctx) do
    items =
      Enum.map(entries, fn
        {:optional, k_expr, v_expr} ->
          kq = to_quoted(k_expr, ctx)
          vq = to_quoted(v_expr, ctx)
          quote do: {:__cel_opt_entry__, unquote(kq), unquote(vq)}

        {k_expr, v_expr} ->
          kq = to_quoted(k_expr, ctx)
          vq = to_quoted(v_expr, ctx)
          quote do: {:__cel_entry__, unquote(kq), unquote(vq)}
      end)

    quote do: Celixir.Compiler.Runtime.make_map([unquote_splicing(items)])
  end

  # --- Struct construction ---

  defp to_quoted(%AST.CreateStruct{type_name: type_name, entries: entries}, ctx) do
    items =
      Enum.map(entries, fn
        {:optional, field, v_expr} ->
          vq = to_quoted(v_expr, ctx)
          quote do: {:__cel_opt_entry__, unquote(field), unquote(vq)}

        {field, v_expr} ->
          vq = to_quoted(v_expr, ctx)
          quote do: {:__cel_entry__, unquote(field), unquote(vq)}
      end)

    quote do: Celixir.Compiler.Runtime.make_struct(__cel_env__, unquote(type_name), [unquote_splicing(items)])
  end

  # --- Field selection ---

  defp to_quoted(%AST.Select{operand: operand, field: field, test_only: test_only}, ctx) do
    qualified = qualified_prefix(operand, field)
    oq = to_quoted(operand, ctx)

    quote do
      Celixir.Compiler.Runtime.select(
        __cel_env__,
        unquote(oq),
        unquote(field),
        unquote(qualified),
        unquote(test_only)
      )
    end
  end

  defp to_quoted(%AST.OptSelect{operand: operand, field: field}, ctx) do
    oq = to_quoted(operand, ctx)
    quote do: Celixir.Compiler.Runtime.opt_select(unquote(oq), unquote(field))
  end

  # --- Index ---

  defp to_quoted(%AST.Index{operand: operand, index: idx}, ctx) do
    oq = to_quoted(operand, ctx)
    iq = to_quoted(idx, ctx)
    quote do: Celixir.Compiler.Runtime.cel_index(unquote(oq), unquote(iq))
  end

  defp to_quoted(%AST.OptIndex{operand: operand, index: idx}, ctx) do
    oq = to_quoted(operand, ctx)
    iq = to_quoted(idx, ctx)
    quote do: Celixir.Compiler.Runtime.opt_index(unquote(oq), unquote(iq))
  end

  # --- Function call (no target) ---

  defp to_quoted(%AST.Call{function: name, target: nil, args: args}, ctx) do
    args_quoted = Enum.map(args, &to_quoted(&1, ctx))
    quote do: Celixir.Compiler.Runtime.call(__cel_env__, unquote(name), [unquote_splicing(args_quoted)])
  end

  # --- Method call (target is an Ident or Select chain — qualified fallback needed) ---

  defp to_quoted(%AST.Call{function: name, target: target, args: args}, ctx) do
    args_quoted = Enum.map(args, &to_quoted(&1, ctx))
    tq = to_quoted(target, ctx)
    qname = qualified_function_name(target, name)

    base_name = extract_base_name(target)
    # Only use the namespace-vs-variable dispatch if the base name is not already
    # known to be a variable (free_vars = inlined from env, comp_var_map = comprehension arg).
    is_known_var =
      MapSet.member?(ctx.free_vars, base_name) or Map.has_key?(ctx.comp_var_map, base_name)

    if qname && not is_known_var do
      quote do
        case Celixir.Compiler.Runtime.lookup_opt(__cel_env__, unquote(base_name)) do
          :error ->
            # Base name is not a variable — try as a qualified function call
            Celixir.Compiler.Runtime.call(__cel_env__, unquote(qname), [unquote_splicing(args_quoted)])

          {:ok, _} ->
            # Base name is a variable — evaluate full target and call method
            Celixir.Compiler.Runtime.method(__cel_env__, unquote(name), unquote(tq), [unquote_splicing(args_quoted)])
        end
      end
    else
      quote do
        Celixir.Compiler.Runtime.method(__cel_env__, unquote(name), unquote(tq), [unquote_splicing(args_quoted)])
      end
    end
  end

  # --- Comprehension ---

  defp to_quoted(%AST.Comprehension{} = comp, ctx) do
    # Build inner context: iter_var(s) and acc_var are passed as direct function arguments
    # to loop thunks. We map each name to a stable internal argument name.
    # __cel_v1__ = iter_var, __cel_v2__ = iter_var2 (or nil), __cel_acc__ = acc_var
    outer_comp_vars = Map.to_list(ctx.comp_var_map)

    bound_with_outer =
      Enum.reduce(outer_comp_vars, ctx.bound_vars, fn {name, _slot}, b -> MapSet.put(b, name) end)

    comp_var_map =
      then(%{comp.iter_var => :__cel_v1__, comp.acc_var => :__cel_acc__}, fn m ->
        if comp.iter_var2, do: Map.put(m, comp.iter_var2, :__cel_v2__), else: m
      end)

    # Inner context uses comp_var_map for direct arg references
    inner_ctx = %{ctx | comp_var_map: comp_var_map, bound_vars: bound_with_outer}

    range_q = to_quoted(comp.iter_range, ctx)
    acc_init_q = to_quoted(comp.acc_init, ctx)
    loop_cond_q = to_quoted(comp.loop_condition, inner_ctx)
    loop_step_q = to_quoted(comp.loop_step, inner_ctx)
    # result thunk only needs acc_var (iter vars are out of scope after the loop)
    result_ctx = %{ctx | comp_var_map: %{comp.acc_var => :__cel_acc__}, bound_vars: bound_with_outer}
    result_q = to_quoted(comp.result, result_ctx)

    # Thunk argument variables
    v1 = Macro.var(:__cel_v1__, __MODULE__)
    v2 = Macro.var(:__cel_v2__, __MODULE__)
    acc = Macro.var(:__cel_acc__, __MODULE__)

    env_expr =
      Enum.reduce(outer_comp_vars, quote(do: __cel_env__), fn {name, slot_atom}, env_acc ->
        slot_var = Macro.var(slot_atom, __MODULE__)
        quote do: Celixir.Environment.put_local_raw(unquote(env_acc), unquote(name), unquote(slot_var))
      end)

    kind_q =
      case comp.kind do
        {:transform_map, transform_expr, filter_expr} ->
          tq = to_quoted(transform_expr, inner_ctx)

          fq =
            if filter_expr do
              fq_body = to_quoted(filter_expr, inner_ctx)
              quote do: fn __cel_env__, unquote(v1), unquote(v2), unquote(acc) -> unquote(fq_body) end
            end

          quote do:
                  {:transform_map, fn __cel_env__, unquote(v1), unquote(v2), unquote(acc) -> unquote(tq) end, unquote(fq)}

        {:transform_map_entry, transform_expr, filter_expr} ->
          tq = to_quoted(transform_expr, inner_ctx)

          fq =
            if filter_expr do
              fq_body = to_quoted(filter_expr, inner_ctx)
              quote do: fn __cel_env__, unquote(v1), unquote(v2), unquote(acc) -> unquote(fq_body) end
            end

          quote do:
                  {:transform_map_entry, fn __cel_env__, unquote(v1), unquote(v2), unquote(acc) -> unquote(tq) end,
                   unquote(fq)}

        {:sort_by, key_expr} ->
          kq = to_quoted(key_expr, inner_ctx)
          quote do: {:sort_by, fn __cel_env__, unquote(v1), unquote(v2), unquote(acc) -> unquote(kq) end}

        {:collect_list, filter_expr, transform_expr} ->
          tq = to_quoted(transform_expr, inner_ctx)

          fq =
            if filter_expr do
              fq_body = to_quoted(filter_expr, inner_ctx)
              quote do: fn __cel_env__, unquote(v1), unquote(v2), unquote(acc) -> unquote(fq_body) end
            end

          quote do:
                  {:collect_list, fn __cel_env__, unquote(v1), unquote(v2), unquote(acc) -> unquote(tq) end, unquote(fq)}

        :standard ->
          quote do: :standard
      end

    quote do
      Celixir.Compiler.Runtime.comprehension(
        unquote(env_expr),
        unquote(range_q),
        unquote(comp.iter_var),
        unquote(comp.iter_var2),
        unquote(comp.acc_var),
        unquote(acc_init_q),
        fn __cel_env__, unquote(v1), unquote(v2), unquote(acc) -> unquote(loop_cond_q) end,
        fn __cel_env__, unquote(v1), unquote(v2), unquote(acc) -> unquote(loop_step_q) end,
        fn __cel_env__, unquote(acc) -> unquote(result_q) end,
        unquote(kind_q)
      )
    end
  end

  # --- Optional lambda ---

  defp to_quoted(%AST.OptLambda{kind: kind, target: target, var: var, expr: expr}, ctx) do
    tq = to_quoted(target, ctx)
    inner_ctx = %{ctx | bound_vars: MapSet.put(ctx.bound_vars, var)}
    exq = to_quoted(expr, inner_ctx)

    quote do
      Celixir.Compiler.Runtime.opt_lambda(
        __cel_env__,
        unquote(tq),
        unquote(var),
        unquote(kind),
        fn __cel_env__ -> unquote(exq) end
      )
    end
  end

  # --- CelBlock ---

  defp to_quoted(%AST.CelBlock{bindings: bindings, result: result}, ctx) do
    result_q = to_quoted(result, ctx)

    binding_thunks =
      Enum.map(bindings, fn expr ->
        bq = to_quoted(expr, ctx)
        quote do: fn __cel_env__ -> unquote(bq) end
      end)

    quote do
      Celixir.Compiler.Runtime.cel_block(
        __cel_env__,
        [unquote_splicing(binding_thunks)],
        fn __cel_env__ -> unquote(result_q) end
      )
    end
  end

  # --- CelIndex (reference to block binding) ---

  defp to_quoted(%AST.CelIndex{index: n}, _ctx) do
    name = "__cel_block_#{n}__"

    quote do
      case Celixir.Environment.get_variable(__cel_env__, unquote(name)) do
        {:ok, v} -> v
        :error -> {:cel_error, unquote("cel.index(#{n}): binding not found")}
      end
    end
  end

  # --- CelIterVar (reference to iteration variable) ---

  defp to_quoted(%AST.CelIterVar{depth: depth, index: idx}, _ctx) do
    name = "__cel_iter_#{depth}_#{idx}__"

    quote do
      case Celixir.Environment.get_variable(__cel_env__, unquote(name)) do
        {:ok, v} -> v
        :error -> {:cel_error, unquote("cel.iterVar(#{depth}, #{idx}): variable not found")}
      end
    end
  end

  # ===================================================================
  # Safe operand predicate
  # ===================================================================

  # A value is "safe" (cannot be {:cel_error, _}) if it is a literal
  # or a free variable (pattern-matched, not through lookup).
  defp safe?(%AST.IntLit{}, _ctx), do: true
  defp safe?(%AST.UintLit{}, _ctx), do: true
  defp safe?(%AST.FloatLit{}, _ctx), do: true
  defp safe?(%AST.StringLit{}, _ctx), do: true
  defp safe?(%AST.BytesLit{}, _ctx), do: true
  defp safe?(%AST.BoolLit{}, _ctx), do: true
  defp safe?(%AST.NullLit{}, _ctx), do: true
  defp safe?(%AST.Ident{name: "true"}, _ctx), do: true
  defp safe?(%AST.Ident{name: "false"}, _ctx), do: true
  defp safe?(%AST.Ident{name: "null"}, _ctx), do: true

  defp safe?(%AST.Ident{name: name}, ctx) do
    # Comprehension vars passed as direct args are safe (no error wrapping)
    Map.has_key?(ctx.comp_var_map, name) or
      (MapSet.member?(ctx.free_vars, name) and not MapSet.member?(ctx.bound_vars, name))
  end

  # Compound expressions are safe if all their sub-expressions are safe.
  # Note: arithmetic on safe operands uses safe_* helpers which return plain values.
  defp safe?(%AST.BinaryOp{op: op, left: l, right: r}, ctx)
       when op in [:add, :sub, :mul, :div, :mod, :eq, :neq, :lt, :lte, :gt, :gte] do
    safe?(l, ctx) and safe?(r, ctx)
  end

  defp safe?(%AST.UnaryOp{op: :negate, operand: o}, ctx), do: safe?(o, ctx)

  defp safe?(_, _ctx), do: false

  # ===================================================================
  # Compile-time helpers
  # ===================================================================

  # Build a qualified "prefix.field" name if the operand is an Ident/Select chain.
  defp qualified_prefix(operand, field) do
    case extract_qualified_name(operand) do
      nil -> nil
      prefix -> "#{prefix}.#{field}"
    end
  end

  # Build the fully qualified function name for a target.method() call.
  defp qualified_function_name(target, method_name) do
    case extract_qualified_name(target) do
      nil -> nil
      prefix -> "#{prefix}.#{method_name}"
    end
  end

  # Extract the base identifier name of a target (for error messages).
  defp extract_base_name(%AST.Ident{name: name}), do: name
  defp extract_base_name(%AST.Select{operand: op}), do: extract_base_name(op)
  defp extract_base_name(_), do: "<expr>"

  # Walk an Ident/Select chain to extract the qualified dotted name.
  defp extract_qualified_name(%AST.Ident{name: name}), do: name

  defp extract_qualified_name(%AST.Select{operand: operand, field: field}) do
    case extract_qualified_name(operand) do
      nil -> nil
      prefix -> "#{prefix}.#{field}"
    end
  end

  defp extract_qualified_name(_), do: nil
end
