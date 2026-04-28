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

  alias Celixir.AST

  @doc """
  Compiles a CEL AST to an anonymous function.

  Returns `{:ok, fun}` where `fun` is `fn(env) -> {:ok, value} | {:error, msg} end`,
  or `{:error, reason}` if compilation fails.
  """
  @spec compile(AST.expr()) ::
          {:ok, (Celixir.Environment.t() -> {:ok, any()} | {:error, String.t()})}
          | {:error, String.t()}
  def compile(ast) do
    body = to_quoted(ast)

    fun_quoted =
      quote do
        fn __cel_env__ ->
          case unquote(body) do
            {:cel_error, msg} -> {:error, msg}
            v -> {:ok, Celixir.unwrap(v)}
          end
        end
      end

    {fun, _} = Code.eval_quoted(fun_quoted, [], __ENV__)
    {:ok, fun}
  rescue
    e -> {:error, "compile error: #{Exception.message(e)}"}
  end

  # --- Literals ---

  defp to_quoted(%AST.IntLit{value: v}), do: v
  defp to_quoted(%AST.UintLit{value: v}), do: v
  defp to_quoted(%AST.FloatLit{value: v}), do: Macro.escape(v)
  defp to_quoted(%AST.StringLit{value: v}), do: v
  defp to_quoted(%AST.BytesLit{value: v}), do: v
  defp to_quoted(%AST.BoolLit{value: v}), do: v
  defp to_quoted(%AST.NullLit{}), do: nil

  # --- Identifiers ---

  defp to_quoted(%AST.Ident{name: "true"}), do: true
  defp to_quoted(%AST.Ident{name: "false"}), do: false
  defp to_quoted(%AST.Ident{name: "null"}), do: nil

  defp to_quoted(%AST.Ident{name: name}) do
    quote do: Celixir.Compiler.Runtime.lookup(__cel_env__, unquote(name))
  end

  # --- Unary operators ---

  defp to_quoted(%AST.UnaryOp{op: :not, operand: operand}) do
    o = to_quoted(operand)

    quote do
      case unquote(o) do
        {:cel_error, _} = e -> e
        v when is_boolean(v) -> not v
        v -> {:cel_error, "no_matching_overload: ! on #{Celixir.Compiler.Runtime.cel_typeof(v)}"}
      end
    end
  end

  defp to_quoted(%AST.UnaryOp{op: :negate, operand: operand}) do
    o = to_quoted(operand)

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

  defp to_quoted(%AST.BinaryOp{op: :and, left: l, right: r}) do
    lq = to_quoted(l)
    rq = to_quoted(r)
    quote do: Celixir.Compiler.Runtime.cel_and(unquote(lq), fn -> unquote(rq) end)
  end

  defp to_quoted(%AST.BinaryOp{op: :or, left: l, right: r}) do
    lq = to_quoted(l)
    rq = to_quoted(r)
    quote do: Celixir.Compiler.Runtime.cel_or(unquote(lq), fn -> unquote(rq) end)
  end

  # --- Arithmetic ---

  defp to_quoted(%AST.BinaryOp{op: :add, left: l, right: r}) do
    quote do: Celixir.Compiler.Runtime.cel_add(unquote(to_quoted(l)), unquote(to_quoted(r)))
  end

  defp to_quoted(%AST.BinaryOp{op: :sub, left: l, right: r}) do
    quote do: Celixir.Compiler.Runtime.cel_sub(unquote(to_quoted(l)), unquote(to_quoted(r)))
  end

  defp to_quoted(%AST.BinaryOp{op: :mul, left: l, right: r}) do
    quote do: Celixir.Compiler.Runtime.cel_mul(unquote(to_quoted(l)), unquote(to_quoted(r)))
  end

  defp to_quoted(%AST.BinaryOp{op: :div, left: l, right: r}) do
    quote do: Celixir.Compiler.Runtime.cel_div(unquote(to_quoted(l)), unquote(to_quoted(r)))
  end

  defp to_quoted(%AST.BinaryOp{op: :mod, left: l, right: r}) do
    quote do: Celixir.Compiler.Runtime.cel_mod(unquote(to_quoted(l)), unquote(to_quoted(r)))
  end

  # --- Comparison ---

  defp to_quoted(%AST.BinaryOp{op: :eq, left: l, right: r}) do
    quote do: Celixir.Compiler.Runtime.cel_eq(unquote(to_quoted(l)), unquote(to_quoted(r)))
  end

  defp to_quoted(%AST.BinaryOp{op: :neq, left: l, right: r}) do
    quote do: Celixir.Compiler.Runtime.cel_neq(unquote(to_quoted(l)), unquote(to_quoted(r)))
  end

  defp to_quoted(%AST.BinaryOp{op: op, left: l, right: r}) when op in [:lt, :lte, :gt, :gte] do
    quote do: Celixir.Compiler.Runtime.cel_compare(unquote(to_quoted(l)), unquote(to_quoted(r)), unquote(op))
  end

  # --- Membership ---

  defp to_quoted(%AST.BinaryOp{op: :in, left: l, right: r}) do
    quote do: Celixir.Compiler.Runtime.cel_in(unquote(to_quoted(l)), unquote(to_quoted(r)))
  end

  # --- Ternary ---

  defp to_quoted(%AST.Ternary{condition: c, true_expr: t, false_expr: f}) do
    cq = to_quoted(c)
    tq = to_quoted(t)
    fq = to_quoted(f)

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

  defp to_quoted(%AST.CreateList{elements: elements}) do
    items =
      Enum.map(elements, fn
        {:optional_list_elem, expr} ->
          eq = to_quoted(expr)
          quote do: {:__cel_opt_elem__, unquote(eq)}

        expr ->
          to_quoted(expr)
      end)

    quote do: Celixir.Compiler.Runtime.make_list([unquote_splicing(items)])
  end

  # --- Map construction ---

  defp to_quoted(%AST.CreateMap{entries: entries}) do
    items =
      Enum.map(entries, fn
        {:optional, k_expr, v_expr} ->
          kq = to_quoted(k_expr)
          vq = to_quoted(v_expr)
          quote do: {:__cel_opt_entry__, unquote(kq), unquote(vq)}

        {k_expr, v_expr} ->
          kq = to_quoted(k_expr)
          vq = to_quoted(v_expr)
          quote do: {:__cel_entry__, unquote(kq), unquote(vq)}
      end)

    quote do: Celixir.Compiler.Runtime.make_map([unquote_splicing(items)])
  end

  # --- Struct construction ---

  defp to_quoted(%AST.CreateStruct{type_name: type_name, entries: entries}) do
    items =
      Enum.map(entries, fn
        {:optional, field, v_expr} ->
          vq = to_quoted(v_expr)
          quote do: {:__cel_opt_entry__, unquote(field), unquote(vq)}

        {field, v_expr} ->
          vq = to_quoted(v_expr)
          quote do: {:__cel_entry__, unquote(field), unquote(vq)}
      end)

    quote do: Celixir.Compiler.Runtime.make_struct(__cel_env__, unquote(type_name), [unquote_splicing(items)])
  end

  # --- Field selection ---

  defp to_quoted(%AST.Select{operand: operand, field: field, test_only: test_only}) do
    qualified = qualified_prefix(operand, field)
    oq = to_quoted(operand)

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

  defp to_quoted(%AST.OptSelect{operand: operand, field: field}) do
    oq = to_quoted(operand)
    quote do: Celixir.Compiler.Runtime.opt_select(unquote(oq), unquote(field))
  end

  # --- Index ---

  defp to_quoted(%AST.Index{operand: operand, index: idx}) do
    oq = to_quoted(operand)
    iq = to_quoted(idx)
    quote do: Celixir.Compiler.Runtime.cel_index(unquote(oq), unquote(iq))
  end

  defp to_quoted(%AST.OptIndex{operand: operand, index: idx}) do
    oq = to_quoted(operand)
    iq = to_quoted(idx)
    quote do: Celixir.Compiler.Runtime.opt_index(unquote(oq), unquote(iq))
  end

  # --- Function call (no target) ---

  defp to_quoted(%AST.Call{function: name, target: nil, args: args}) do
    args_quoted = Enum.map(args, &to_quoted/1)
    quote do: Celixir.Compiler.Runtime.call(__cel_env__, unquote(name), [unquote_splicing(args_quoted)])
  end

  # --- Method call (target is an Ident or Select chain — qualified fallback needed) ---

  defp to_quoted(%AST.Call{function: name, target: target, args: args}) do
    args_quoted = Enum.map(args, &to_quoted/1)
    tq = to_quoted(target)
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

  defp to_quoted(%AST.Comprehension{} = comp) do
    range_q = to_quoted(comp.iter_range)
    acc_init_q = to_quoted(comp.acc_init)
    loop_cond_q = to_quoted(comp.loop_condition)
    loop_step_q = to_quoted(comp.loop_step)
    result_q = to_quoted(comp.result)

    kind_q =
      case comp.kind do
        {:transform_map, transform_expr, filter_expr} ->
          tq = to_quoted(transform_expr)
          fq = if filter_expr, do: quote(do: fn __cel_env__ -> unquote(to_quoted(filter_expr)) end), else: nil

          quote do: {:transform_map, fn __cel_env__ -> unquote(tq) end, unquote(fq)}

        {:transform_map_entry, transform_expr, filter_expr} ->
          tq = to_quoted(transform_expr)
          fq = if filter_expr, do: quote(do: fn __cel_env__ -> unquote(to_quoted(filter_expr)) end), else: nil

          quote do: {:transform_map_entry, fn __cel_env__ -> unquote(tq) end, unquote(fq)}

        {:sort_by, key_expr} ->
          kq = to_quoted(key_expr)
          quote do: {:sort_by, fn __cel_env__ -> unquote(kq) end}

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
        fn __cel_env__ -> unquote(loop_cond_q) end,
        fn __cel_env__ -> unquote(loop_step_q) end,
        fn __cel_env__ -> unquote(result_q) end,
        unquote(kind_q)
      )
    end
  end

  # --- Optional lambda ---

  defp to_quoted(%AST.OptLambda{kind: kind, target: target, var: var, expr: expr}) do
    tq = to_quoted(target)
    exq = to_quoted(expr)

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

  defp to_quoted(%AST.CelBlock{bindings: bindings, result: result}) do
    result_q = to_quoted(result)

    binding_thunks =
      Enum.map(bindings, fn expr ->
        bq = to_quoted(expr)
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

  defp to_quoted(%AST.CelIndex{index: n}) do
    name = "__cel_block_#{n}__"

    quote do
      case Celixir.Environment.get_variable(__cel_env__, unquote(name)) do
        {:ok, v} -> v
        :error -> {:cel_error, unquote("cel.index(#{n}): binding not found")}
      end
    end
  end

  # --- CelIterVar (reference to iteration variable) ---

  defp to_quoted(%AST.CelIterVar{depth: depth, index: idx}) do
    name = "__cel_iter_#{depth}_#{idx}__"

    quote do
      case Celixir.Environment.get_variable(__cel_env__, unquote(name)) do
        {:ok, v} -> v
        :error -> {:cel_error, unquote("cel.iterVar(#{depth}, #{idx}): variable not found")}
      end
    end
  end

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
