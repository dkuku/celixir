defmodule Celixir.Compiler.Runtime do
  @moduledoc false
  # Runtime helpers called from compiled CEL programs.
  # All functions either return a plain value or raise Celixir.EvalError.

  alias Celixir.Environment
  alias Celixir.EvalError
  alias Celixir.Types.Duration
  alias Celixir.Types.Optional

  @type_denotations %{
    "bool" => :bool,
    "int" => :int,
    "uint" => :uint,
    "double" => :double,
    "string" => :string,
    "bytes" => :bytes,
    "list" => :list,
    "map" => :map,
    "type" => :type,
    "null_type" => :null_type,
    "optional_type" => :optional_type
  }

  # --- Variable resolution ---

  def lookup(env, name) when is_binary(name) do
    case Environment.get_variable(env, name) do
      {:ok, value} ->
        normalize_value(value)

      :error ->
        case Map.get(@type_denotations, name) do
          nil -> raise EvalError, message: "undefined variable: #{name}"
          type_val -> type_val
        end
    end
  end

  def lookup(env, name) when is_atom(name) do
    lookup(env, Atom.to_string(name))
  end

  # Returns {:ok, value} | :error — never raises. Used for qualified method dispatch.
  def lookup_opt(env, name) when is_binary(name) do
    case Environment.get_variable(env, name) do
      {:ok, value} ->
        {:ok, normalize_value(value)}

      :error ->
        case Map.get(@type_denotations, name) do
          nil -> :error
          type_val -> {:ok, type_val}
        end
    end
  end

  def lookup_opt(env, name) when is_atom(name) do
    lookup_opt(env, Atom.to_string(name))
  end

  # Fast path: primitive types don't need normalization
  defp normalize_value(v) when is_integer(v), do: v
  defp normalize_value(v) when is_float(v), do: v
  defp normalize_value(v) when is_binary(v), do: v
  defp normalize_value(v) when is_boolean(v), do: v
  defp normalize_value(nil), do: nil
  defp normalize_value(v) when is_list(v), do: v
  defp normalize_value(v) when is_map(v) and not is_struct(v), do: v
  defp normalize_value(v), do: Celixir.Evaluator.dispatch_normalize(v)

  # Convert {:cel_error, msg} from evaluator dispatch to a raise.
  defp cel_raise({:cel_error, msg}), do: raise(EvalError, message: msg)
  defp cel_raise(v), do: v

  # --- Short-circuit logical ops ---
  # Left-error absorption (error && false = false) is dropped: left now raises.
  # Lazy right evaluation is kept via thunk — false && expr never evals expr.

  def cel_and(false, _thunk), do: false
  def cel_and(true, thunk), do: thunk.()
  def cel_and(v, _), do: raise(EvalError, message: "no_matching_overload: && on #{cel_typeof(v)}")

  def cel_or(true, _thunk), do: true
  def cel_or(false, thunk), do: thunk.()
  def cel_or(v, _), do: raise(EvalError, message: "no_matching_overload: || on #{cel_typeof(v)}")

  # --- Unary ---

  def cel_not(v) when is_boolean(v), do: not v
  def cel_not(v), do: raise(EvalError, message: "no_matching_overload: ! on #{cel_typeof(v)}")

  def negate(%Duration{} = d), do: Duration.negate(d)
  def negate(v), do: raise(EvalError, message: "no_matching_overload: - on #{cel_typeof(v)}")

  # --- Safe arithmetic (operands guaranteed non-error — skip error checks) ---

  def safe_add(a, b) when is_integer(a) and is_integer(b), do: a + b
  def safe_add(a, b) when is_float(a) and is_float(b), do: a + b
  def safe_add(a, b) when is_binary(a) and is_binary(b), do: a <> b
  def safe_add(a, b) when is_list(a) and is_list(b), do: a ++ b
  def safe_add(a, b), do: cel_raise(Celixir.Evaluator.dispatch_add(a, b))

  def safe_sub(a, b) when is_integer(a) and is_integer(b), do: a - b
  def safe_sub(a, b) when is_float(a) and is_float(b), do: a - b
  def safe_sub(a, b), do: cel_raise(Celixir.Evaluator.dispatch_sub(a, b))

  def safe_mul(a, b) when is_integer(a) and is_integer(b), do: a * b
  def safe_mul(a, b) when is_float(a) and is_float(b), do: a * b
  def safe_mul(a, b), do: cel_raise(Celixir.Evaluator.dispatch_mul(a, b))

  def safe_div(a, b) when is_integer(a) and is_integer(b) and b != 0, do: div(a, b)
  def safe_div(a, b), do: cel_raise(Celixir.Evaluator.dispatch_div(a, b))

  def safe_mod(a, b) when is_integer(a) and is_integer(b) and b != 0, do: rem(a, b)
  def safe_mod(a, b), do: cel_raise(Celixir.Evaluator.dispatch_mod(a, b))

  # --- Non-safe arithmetic (used when operand safety is unknown) ---
  # With exceptions, these are identical to safe_* — kept for symmetry.

  def cel_add(a, b), do: safe_add(a, b)
  def cel_sub(a, b), do: safe_sub(a, b)
  def cel_mul(a, b), do: safe_mul(a, b)
  def cel_div(a, b), do: safe_div(a, b)
  def cel_mod(a, b), do: safe_mod(a, b)

  # --- Safe comparison ---

  def safe_compare(:lt, a, b) when is_integer(a) and is_integer(b), do: a < b
  def safe_compare(:lte, a, b) when is_integer(a) and is_integer(b), do: a <= b
  def safe_compare(:gt, a, b) when is_integer(a) and is_integer(b), do: a > b
  def safe_compare(:gte, a, b) when is_integer(a) and is_integer(b), do: a >= b
  def safe_compare(:lt, a, b) when is_float(a) and is_float(b), do: a < b
  def safe_compare(:lte, a, b) when is_float(a) and is_float(b), do: a <= b
  def safe_compare(:gt, a, b) when is_float(a) and is_float(b), do: a > b
  def safe_compare(:gte, a, b) when is_float(a) and is_float(b), do: a >= b
  def safe_compare(:lt, a, b) when is_binary(a) and is_binary(b), do: a < b
  def safe_compare(:lte, a, b) when is_binary(a) and is_binary(b), do: a <= b
  def safe_compare(:gt, a, b) when is_binary(a) and is_binary(b), do: a > b
  def safe_compare(:gte, a, b) when is_binary(a) and is_binary(b), do: a >= b
  def safe_compare(op, a, b), do: cel_raise(Celixir.Evaluator.dispatch_compare(op, a, b))

  def cel_compare(a, b, op), do: safe_compare(op, a, b)

  def safe_equal?(a, b) when is_integer(a) and is_integer(b), do: a == b
  def safe_equal?(a, b) when is_float(a) and is_float(b), do: a == b
  def safe_equal?(a, b) when is_binary(a) and is_binary(b), do: a == b
  def safe_equal?(a, b) when is_boolean(a) and is_boolean(b), do: a == b
  def safe_equal?(nil, nil), do: true
  def safe_equal?(a, b), do: Celixir.Evaluator.dispatch_equal?(a, b)

  def cel_eq(a, b), do: Celixir.Evaluator.dispatch_equal?(a, b)
  def cel_neq(a, b), do: not Celixir.Evaluator.dispatch_equal?(a, b)

  # --- Membership (in) ---

  def cel_in(left, right) when is_list(right) do
    Enum.any?(right, &Celixir.Evaluator.dispatch_equal?(&1, left))
  end

  def cel_in(left, right) when is_map(right) do
    Enum.any?(Map.keys(right), &Celixir.Evaluator.dispatch_equal?(&1, left))
  end

  def cel_in(_, right), do: raise(EvalError, message: "no_matching_overload: 'in' on #{cel_typeof(right)}")

  # --- Field selection ---

  def select(_env, operand_val, field, nil, test_only) do
    cel_raise(Celixir.Evaluator.dispatch_select(operand_val, field, test_only))
  end

  def select(env, operand_val, field, qualified, test_only) do
    cel_raise(Celixir.Evaluator.dispatch_qualify_select(env, operand_val, field, qualified, test_only))
  end

  def opt_select(target, field), do: cel_raise(Celixir.Evaluator.dispatch_opt_select(target, field))

  # --- Index ---

  def cel_index(target, idx), do: cel_raise(Celixir.Evaluator.dispatch_index(target, idx))
  def opt_index(target, idx), do: cel_raise(Celixir.Evaluator.dispatch_opt_index(target, idx))

  # --- Function / method dispatch ---

  def call(env, name, args) do
    cel_raise(Celixir.Evaluator.dispatch_function(name, args, env))
  end

  def method(env, name, target, args) do
    cel_raise(Celixir.Evaluator.dispatch_method(name, target, args, env))
  end

  # --- List / Map / Struct construction ---
  # Subexpressions raise on error so no {:cel_error, _} can appear in arguments.

  def make_list(elements) do
    elements
    |> Enum.reduce([], fn
      {:__cel_opt_elem__, %Optional{has_value: true, value: v}}, acc -> [v | acc]
      {:__cel_opt_elem__, %Optional{has_value: false}}, acc -> acc
      {:__cel_opt_elem__, v}, acc -> [v | acc]
      v, acc -> [v | acc]
    end)
    |> Enum.reverse()
  end

  def make_map(entries) do
    Enum.reduce(entries, %{}, fn
      {:__cel_opt_entry__, k, %Optional{has_value: true, value: v}}, acc ->
        do_add_map_entry!(k, v, acc)

      {:__cel_opt_entry__, _k, %Optional{has_value: false}}, acc ->
        acc

      {:__cel_opt_entry__, k, v}, acc ->
        do_add_map_entry!(k, v, acc)

      {:__cel_entry__, k, v}, acc ->
        do_add_map_entry!(k, v, acc)
    end)
  end

  defp do_add_map_entry!(nil, _, _), do: raise(EvalError, message: "unsupported key type")
  defp do_add_map_entry!(k, _, _) when is_float(k), do: raise(EvalError, message: "unsupported key type")

  defp do_add_map_entry!(k, v, acc) do
    if Map.has_key?(acc, k), do: raise(EvalError, message: "Failed with repeated key")
    Map.put(acc, k, v)
  end

  def make_struct(env, type_name, entries) do
    fields =
      Enum.reduce(entries, %{}, fn
        {:__cel_opt_entry__, field, %Optional{has_value: true, value: v}}, acc -> Map.put(acc, field, v)
        {:__cel_opt_entry__, _field, %Optional{has_value: false}}, acc -> acc
        {:__cel_opt_entry__, field, v}, acc -> Map.put(acc, field, v)
        {:__cel_entry__, field, v}, acc -> Map.put(acc, field, v)
      end)

    qualified_name = qualify_struct_type(type_name, env)
    cel_raise(Celixir.Proto.finalize_struct(qualified_name, fields))
  end

  defp qualify_struct_type(type_name, %{container: container}) when is_binary(container) and container != "" do
    qualified = container <> "." <> type_name
    if Celixir.Proto.get_schema(qualified), do: qualified, else: type_name
  end

  defp qualify_struct_type(type_name, _env), do: type_name

  # --- CelBlock (sequential bindings) ---

  def cel_block(env, binding_thunks, result_thunk) do
    final_env =
      Enum.reduce(Enum.with_index(binding_thunks), env, fn {thunk, idx}, acc_env ->
        v = thunk.(acc_env)
        Environment.put_local_raw(acc_env, "__cel_block_#{idx}__", v)
      end)

    result_thunk.(final_env)
  end

  # --- Comprehension ---

  def comprehension(env, range, iter_var, iter_var2, acc_var, acc_init, loop_cond_f, loop_step_f, result_f, kind) do
    run_comprehension(env, range, iter_var, iter_var2, acc_var, acc_init, loop_cond_f, loop_step_f, result_f, kind)
  end

  # Fast path: list range, no iter_var2, collect_list — prepend + reverse, O(n)
  defp run_comprehension(
         env,
         range,
         _iter_var,
         nil,
         _acc_var,
         _acc_init,
         _loop_cond_f,
         _loop_step_f,
         result_f,
         {:collect_list, transform_f, filter_f}
       )
       when is_list(range) do
    acc =
      Enum.reduce(range, [], fn v1, acc ->
        if filter_f == nil or filter_f.(env, v1, nil, acc) != false do
          [transform_f.(env, v1, nil, acc) | acc]
        else
          acc
        end
      end)

    result_f.(env, Enum.reverse(acc))
  end

  # Fast path: list range, no iter_var2 — iterate directly without tuple wrapping
  defp run_comprehension(env, range, _iter_var, nil, _acc_var, acc_init, loop_cond_f, loop_step_f, result_f, :standard)
       when is_list(range) do
    final_acc =
      Enum.reduce_while(range, acc_init, fn v1, current_acc ->
        if loop_cond_f.(env, v1, nil, current_acc) == false do
          {:halt, current_acc}
        else
          {:cont, loop_step_f.(env, v1, nil, current_acc)}
        end
      end)

    result_f.(env, final_acc)
  end

  defp run_comprehension(env, range, iter_var, iter_var2, acc_var, acc_init, loop_cond_f, loop_step_f, result_f, kind) do
    items = build_iter_items(range, iter_var2)
    run_comprehension_items(env, items, iter_var, iter_var2, acc_var, acc_init, loop_cond_f, loop_step_f, result_f, kind)
  end

  defp build_iter_items(range, nil) when is_map(range), do: Enum.map(Map.keys(range), &{&1})
  defp build_iter_items(range, nil) when is_list(range), do: Enum.map(range, &{&1})

  defp build_iter_items(range, _var2) when is_map(range) do
    Enum.map(range, fn {k, v} -> {k, v} end)
  end

  defp build_iter_items(range, _var2) when is_list(range) do
    range |> Enum.with_index() |> Enum.map(fn {v, i} -> {i, v} end)
  end

  defp item_v1({v1}), do: v1
  defp item_v1({v1, _v2}), do: v1
  defp item_v2({_v1}), do: nil
  defp item_v2({_v1, v2}), do: v2

  defp run_comprehension_items(
         env,
         items,
         _iter_var,
         _iter_var2,
         _acc_var,
         acc_init,
         loop_cond_f,
         loop_step_f,
         result_f,
         :standard
       ) do
    final_acc =
      Enum.reduce_while(items, acc_init, fn item, current_acc ->
        v1 = item_v1(item)
        v2 = item_v2(item)

        if loop_cond_f.(env, v1, v2, current_acc) == false do
          {:halt, current_acc}
        else
          {:cont, loop_step_f.(env, v1, v2, current_acc)}
        end
      end)

    result_f.(env, final_acc)
  end

  defp run_comprehension_items(
         env,
         items,
         _iter_var,
         _iter_var2,
         _acc_var,
         _acc_init,
         _loop_cond_f,
         _loop_step_f,
         result_f,
         {:collect_list, transform_f, filter_f}
       ) do
    acc =
      Enum.reduce(items, [], fn item, acc ->
        v1 = item_v1(item)
        v2 = item_v2(item)

        if filter_f == nil or filter_f.(env, v1, v2, acc) != false do
          [transform_f.(env, v1, v2, acc) | acc]
        else
          acc
        end
      end)

    result_f.(env, Enum.reverse(acc))
  end

  defp run_comprehension_items(
         env,
         items,
         _iter_var,
         _iter_var2,
         _acc_var,
         acc_init,
         _loop_cond_f,
         _loop_step_f,
         result_f,
         {:transform_map, transform_f, filter_f}
       ) do
    final_acc =
      Enum.reduce(items, acc_init, fn {key, _value} = item, current_acc ->
        v1 = item_v1(item)
        v2 = item_v2(item)

        if filter_f == nil or filter_f.(env, v1, v2, current_acc) != false do
          Map.put(current_acc, key, transform_f.(env, v1, v2, current_acc))
        else
          current_acc
        end
      end)

    result_f.(env, final_acc)
  end

  defp run_comprehension_items(
         env,
         items,
         _iter_var,
         _iter_var2,
         _acc_var,
         acc_init,
         _loop_cond_f,
         _loop_step_f,
         result_f,
         {:transform_map_entry, transform_f, filter_f}
       ) do
    final_acc =
      Enum.reduce(items, acc_init, fn item, current_acc ->
        v1 = item_v1(item)
        v2 = item_v2(item)

        if filter_f == nil or filter_f.(env, v1, v2, current_acc) != false do
          entry = transform_f.(env, v1, v2, current_acc)

          case entry do
            e when is_map(e) and not is_struct(e) and map_size(e) == 1 ->
              [{new_key, new_val}] = Map.to_list(e)

              if Map.has_key?(current_acc, new_key) do
                raise EvalError, message: "transformMapEntry: duplicate key"
              end

              Map.put(current_acc, new_key, new_val)

            _ ->
              raise EvalError, message: "transformMapEntry: transform must produce a single-entry map literal"
          end
        else
          current_acc
        end
      end)

    result_f.(env, final_acc)
  end

  defp run_comprehension_items(
         env,
         items,
         _iter_var,
         _iter_var2,
         _acc_var,
         acc_init,
         _loop_cond_f,
         _loop_step_f,
         result_f,
         {:sort_by, key_f}
       ) do
    sorted =
      items
      |> Enum.map(fn {value} = item ->
        v1 = item_v1(item)
        v2 = item_v2(item)
        {key_f.(env, v1, v2, acc_init), value}
      end)
      |> Enum.sort(fn {k1, _}, {k2, _} ->
        Celixir.Evaluator.dispatch_compare(:lt, k1, k2) == true
      end)
      |> Enum.map(fn {_, v} -> v end)

    result_f.(env, sorted)
  end

  # --- Optional lambda (optFlatMap / optMap) ---

  def opt_lambda(env, %Optional{has_value: true, value: v}, var, kind, expr_f) do
    inner_env = Environment.put_variable(env, var, v)
    result = expr_f.(inner_env)

    case kind do
      :flat_map -> result
      :map -> Optional.of(result)
    end
  end

  def opt_lambda(_env, %Optional{has_value: false}, _var, _kind, _expr_f) do
    Optional.none()
  end

  def opt_lambda(_env, other, _var, _kind, _expr_f) do
    raise EvalError, message: "optFlatMap/optMap called on non-optional: #{cel_typeof(other)}"
  end

  # --- typeof helper ---

  def cel_typeof(v), do: Celixir.Evaluator.dispatch_typeof(v)
end
