defmodule Celixir.Compiler do
  @moduledoc false
  # Compiles a CEL AST to an Elixir anonymous function.
  #
  # The compiled function has the signature:
  #   fn(__cel_env__) -> {:ok, value} | {:error, msg} end
  #
  # This is done by generating an Elixir quoted AST and calling Code.eval_quoted/3
  # to produce a real BEAM-compiled function. Variable accesses are threaded
  # through the __cel_env__ parameter at runtime.
  #
  # Optimizations implemented:
  # 1. Variable inlining: free variables are pattern-matched from the Environment
  #    struct directly, skipping Runtime.lookup overhead.
  # 2. Safe operator inlining: when both operands cannot produce {:cel_error, _},
  #    skip the error-check wrappers.
  # 3. Comprehension variable argument-passing: iter_var, iter_var2, and acc_var
  #    are passed as direct function arguments to loop thunks, eliminating
  #    struct copies and map lookups per iteration.

  alias Celixir.AST

  # CEL type denotation names — these are not variable lookups
  @type_denotation_names ~w[bool int uint double string bytes list map type null_type optional_type]

  @doc """
  Compiles a CEL AST to an anonymous function.

  Returns `{:ok, fun}` where `fun` is `fn(env) -> {:ok, value} | {:error, msg} end`,
  or `{:error, reason}` if compilation fails.
  """
  @spec compile(AST.expr()) ::
          {:ok, (Celixir.Environment.t() -> {:ok, any()} | {:error, String.t()})}
          | {:error, String.t()}
  def compile(ast) do
    # Collect top-level free variables (names that come from the Environment)
    all_free = free_variables(ast)

    # Remove names that appear as base of a qualified method/function call.
    # These might be function namespaces (e.g. "math" in math.sqrt(x)),
    # not actual variables — they need the Runtime.lookup fallback.
    namespace_candidates = namespace_base_idents(ast)
    inlineable_vars = MapSet.difference(all_free, namespace_candidates)

    free_vars = inlineable_vars |> MapSet.to_list() |> Enum.sort()

    module_name = :"Celixir.Compiled.#{:erlang.unique_integer([:positive, :monotonic])}"

    # Generate the body with free variables inlined
    ctx = %{free_vars: MapSet.new(free_vars), bound_vars: MapSet.new(), comp_var_map: %{}}
    body = to_quoted(ast, ctx)

    # Check if the top-level expression is guaranteed error-free (can skip outer case)
    top_safe = safe?(ast, ctx)

    # Build the pattern-matching function head that extracts variables directly
    # from the Environment struct's variables map.
    eval_fn = build_eval_fn(body, free_vars, top_safe)

    Module.create(module_name, eval_fn, __ENV__)
    {:ok, :erlang.make_fun(module_name, :eval, 1)}
  rescue
    e -> {:error, "compile error: #{Exception.message(e)}"}
  end

  # ===================================================================
  # Build def eval(...) with pattern-matched variables for efficiency
  # ===================================================================

  defp build_eval_fn(body, [], top_safe) do
    # No free variables — simple function
    eval_body =
      if top_safe do
        quote do: {:ok, Celixir.unwrap(unquote(body))}
      else
        quote do
          case unquote(body) do
            {:cel_error, msg} -> {:error, msg}
            v -> {:ok, Celixir.unwrap(v)}
          end
        end
      end

    quote do
      def eval(__cel_env__) do
        unquote(eval_body)
      end
    end
  end

  defp build_eval_fn(body, free_vars, top_safe) do
    # Build a map pattern: %{x: x, y: y, ...} (atom keys)
    var_pairs =
      Enum.map(free_vars, fn name ->
        atom = String.to_atom(name)
        var = Macro.var(atom, __MODULE__)
        {atom, var}
      end)

    # Build the map pattern for the variables field
    vars_map_pattern = {:%{}, [], var_pairs}

    # Pattern match on the struct directly — extracts vars in one step
    env_pattern =
      quote do
        %Celixir.Environment{variables: unquote(vars_map_pattern)} = __cel_env__
      end

    # Build the missing-var fallback
    missing_check =
      Enum.reduce(Enum.reverse(free_vars), nil, fn name, acc ->
        atom = String.to_atom(name)
        if acc == nil do
          quote do: {:error, "undefined variable: #{unquote(name)}"}
        else
          quote do
            if Map.has_key?(__cel_env__.variables, unquote(atom)) do
              unquote(acc)
            else
              {:error, "undefined variable: #{unquote(name)}"}
            end
          end
        end
      end)

    eval_body =
      if top_safe do
        quote do: {:ok, Celixir.unwrap(unquote(body))}
      else
        quote do
          case unquote(body) do
            {:cel_error, msg} -> {:error, msg}
            v -> {:ok, Celixir.unwrap(v)}
          end
        end
      end

    quote do
      def eval(unquote(env_pattern)) do
        unquote(eval_body)
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
            "<expr>" -> namespace_base_idents(target, acc)
            base_name when base_name != nil ->
              # Only add if extract_qualified_name returns non-nil (it's a chain)
              if extract_qualified_name(target) != nil do
                MapSet.put(acc, base_name)
              else
                namespace_base_idents(target, acc)
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
  # to_quoted — generate Elixir AST from CEL AST
  # ctx = %{free_vars: MapSet, bound_vars: MapSet}
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

      # Free variable inlining — pattern-matched from the struct, no lookup needed
      MapSet.member?(ctx.free_vars, name) and not MapSet.member?(ctx.bound_vars, name) ->
        Macro.var(String.to_atom(name), __MODULE__)

      true ->
        quote do: Celixir.Compiler.Runtime.lookup(__cel_env__, unquote(String.to_atom(name)))
    end
  end

  # --- Unary operators ---

  defp to_quoted(%AST.UnaryOp{op: :not, operand: operand}, ctx) do
    o = to_quoted(operand, ctx)

    quote do
      case unquote(o) do
        {:cel_error, _} = e -> e
        v when is_boolean(v) -> not v
        v -> {:cel_error, "no_matching_overload: ! on #{Celixir.Compiler.Runtime.cel_typeof(v)}"}
      end
    end
  end

  defp to_quoted(%AST.UnaryOp{op: :negate, operand: operand}, ctx) do
    o = to_quoted(operand, ctx)

    quote do
      case unquote(o) do
        {:cel_error, _} = e -> e
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
      # Both sides are safe booleans — inline cel_and without closure allocation.
      # This avoids creating an anonymous function on every evaluation.
      quote do
        case unquote(lq) do
          false ->
            false

          true ->
            unquote(rq)

          {:cel_error, _} = __cel_err__ ->
            if unquote(rq) == false, do: false, else: __cel_err__

          __cel_v__ ->
            {:cel_error, "no_matching_overload: && on #{Celixir.Compiler.Runtime.cel_typeof(__cel_v__)}"}
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
      # Both sides are safe booleans — inline cel_or without closure allocation.
      quote do
        case unquote(lq) do
          true ->
            true

          false ->
            unquote(rq)

          {:cel_error, _} = __cel_err__ ->
            if unquote(rq) == true, do: true, else: __cel_err__

          __cel_v__ ->
            {:cel_error, "no_matching_overload: || on #{Celixir.Compiler.Runtime.cel_typeof(__cel_v__)}"}
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
        true -> unquote(tq)
        false -> unquote(fq)
        {:cel_error, _} = e -> e
        v -> {:cel_error, "ternary condition must be bool, got #{Celixir.Compiler.Runtime.cel_typeof(v)}"}
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

    if qname do
      quote do
        case unquote(tq) do
          {:cel_error, _} ->
            case Celixir.Compiler.Runtime.call(__cel_env__, unquote(qname), [unquote_splicing(args_quoted)]) do
              {:cel_error, "undefined function: " <> _} ->
                {:cel_error, "undefined variable: #{unquote(extract_base_name(target))}"}

              result ->
                result
            end

          target_val ->
            Celixir.Compiler.Runtime.method(__cel_env__, unquote(name), target_val, [unquote_splicing(args_quoted)])
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
    comp_var_map =
      ctx.comp_var_map
      |> Map.put(comp.iter_var, :__cel_v1__)
      |> Map.put(comp.acc_var, :__cel_acc__)
      |> then(fn m -> if comp.iter_var2, do: Map.put(m, comp.iter_var2, :__cel_v2__), else: m end)

    # Inner context uses comp_var_map for direct arg references (no bound_vars needed for these)
    inner_ctx = %{ctx | comp_var_map: comp_var_map}

    range_q = to_quoted(comp.iter_range, ctx)
    acc_init_q = to_quoted(comp.acc_init, ctx)
    loop_cond_q = to_quoted(comp.loop_condition, inner_ctx)
    loop_step_q = to_quoted(comp.loop_step, inner_ctx)
    # result thunk only needs acc_var (iter vars are out of scope after the loop)
    result_ctx = %{ctx | comp_var_map: Map.put(ctx.comp_var_map, comp.acc_var, :__cel_acc__)}
    result_q = to_quoted(comp.result, result_ctx)

    # Thunk argument variables
    v1 = Macro.var(:__cel_v1__, __MODULE__)
    v2 = Macro.var(:__cel_v2__, __MODULE__)
    acc = Macro.var(:__cel_acc__, __MODULE__)

    kind_q =
      case comp.kind do
        {:transform_map, transform_expr, filter_expr} ->
          tq = to_quoted(transform_expr, inner_ctx)

          fq =
            if filter_expr do
              fq_body = to_quoted(filter_expr, inner_ctx)
              quote do: fn __cel_env__, unquote(v1), unquote(v2), unquote(acc) -> unquote(fq_body) end
            else
              nil
            end

          quote do: {:transform_map, fn __cel_env__, unquote(v1), unquote(v2), unquote(acc) -> unquote(tq) end, unquote(fq)}

        {:transform_map_entry, transform_expr, filter_expr} ->
          tq = to_quoted(transform_expr, inner_ctx)

          fq =
            if filter_expr do
              fq_body = to_quoted(filter_expr, inner_ctx)
              quote do: fn __cel_env__, unquote(v1), unquote(v2), unquote(acc) -> unquote(fq_body) end
            else
              nil
            end

          quote do: {:transform_map_entry, fn __cel_env__, unquote(v1), unquote(v2), unquote(acc) -> unquote(tq) end, unquote(fq)}

        {:sort_by, key_expr} ->
          kq = to_quoted(key_expr, inner_ctx)
          quote do: {:sort_by, fn __cel_env__, unquote(v1), unquote(v2), unquote(acc) -> unquote(kq) end}

        :standard ->
          quote do: :standard
      end

    quote do
      Celixir.Compiler.Runtime.comprehension(
        __cel_env__,
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
