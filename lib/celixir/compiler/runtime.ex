defmodule Celixir.Compiler.Runtime do
  @moduledoc false
  # Runtime helpers called from compiled CEL programs.
  # All functions return plain values or {:cel_error, msg} — never raise.

  alias Celixir.Environment
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

  def lookup(env, name) do
    case Environment.get_variable(env, name) do
      {:ok, value} -> Celixir.Evaluator.dispatch_normalize(value)
      :error ->
        case Map.get(@type_denotations, name) do
          nil -> {:cel_error, "undefined variable: #{name}"}
          type_val -> type_val
        end
    end
  end

  # --- Short-circuit logical ops with CEL error-absorption semantics ---

  def cel_and(left, right_thunk) do
    case left do
      false ->
        false

      true ->
        right = right_thunk.()

        case right do
          v when is_boolean(v) -> v
          {:cel_error, _} = e -> e
          v -> {:cel_error, "no_matching_overload: && on #{cel_typeof(v)}"}
        end

      {:cel_error, _} = err ->
        right = right_thunk.()
        if right == false, do: false, else: err

      v ->
        {:cel_error, "no_matching_overload: && on #{cel_typeof(v)}"}
    end
  end

  def cel_or(left, right_thunk) do
    case left do
      true ->
        true

      false ->
        right = right_thunk.()

        case right do
          v when is_boolean(v) -> v
          {:cel_error, _} = e -> e
          v -> {:cel_error, "no_matching_overload: || on #{cel_typeof(v)}"}
        end

      {:cel_error, _} = err ->
        right = right_thunk.()
        if right == true, do: true, else: err

      v ->
        {:cel_error, "no_matching_overload: || on #{cel_typeof(v)}"}
    end
  end

  # --- Negate for non-numeric types (Duration) ---

  def negate(%Duration{} = d), do: Duration.negate(d)
  def negate(v), do: {:cel_error, "no_matching_overload: - on #{cel_typeof(v)}"}

  # --- Arithmetic with error pass-through ---

  def cel_add({:cel_error, _} = e, _), do: e
  def cel_add(_, {:cel_error, _} = e), do: e
  def cel_add(a, b), do: Celixir.Evaluator.dispatch_add(a, b)

  def cel_sub({:cel_error, _} = e, _), do: e
  def cel_sub(_, {:cel_error, _} = e), do: e
  def cel_sub(a, b), do: Celixir.Evaluator.dispatch_sub(a, b)

  def cel_mul({:cel_error, _} = e, _), do: e
  def cel_mul(_, {:cel_error, _} = e), do: e
  def cel_mul(a, b), do: Celixir.Evaluator.dispatch_mul(a, b)

  def cel_div({:cel_error, _} = e, _), do: e
  def cel_div(_, {:cel_error, _} = e), do: e
  def cel_div(a, b), do: Celixir.Evaluator.dispatch_div(a, b)

  def cel_mod({:cel_error, _} = e, _), do: e
  def cel_mod(_, {:cel_error, _} = e), do: e
  def cel_mod(a, b), do: Celixir.Evaluator.dispatch_mod(a, b)

  # --- Comparison ---

  def cel_eq({:cel_error, _} = e, _), do: e
  def cel_eq(_, {:cel_error, _} = e), do: e
  def cel_eq(a, b), do: Celixir.Evaluator.dispatch_equal?(a, b)

  def cel_neq({:cel_error, _} = e, _), do: e
  def cel_neq(_, {:cel_error, _} = e), do: e
  def cel_neq(a, b), do: not Celixir.Evaluator.dispatch_equal?(a, b)

  def cel_compare({:cel_error, _} = e, _, _), do: e
  def cel_compare(_, {:cel_error, _} = e, _), do: e
  def cel_compare(a, b, op), do: Celixir.Evaluator.dispatch_compare(op, a, b)

  # --- Membership (in) ---

  def cel_in({:cel_error, _} = e, _), do: e
  def cel_in(_, {:cel_error, _} = e), do: e

  def cel_in(left, right) when is_list(right) do
    Enum.any?(right, &Celixir.Evaluator.dispatch_equal?(&1, left))
  end

  def cel_in(left, right) when is_map(right) do
    Enum.any?(Map.keys(right), &Celixir.Evaluator.dispatch_equal?(&1, left))
  end

  def cel_in(_, right), do: {:cel_error, "no_matching_overload: 'in' on #{cel_typeof(right)}"}

  # --- Field selection ---

  def select(_env, {:cel_error, _} = e, _field, _qualified, _test_only), do: e

  def select(_env, operand_val, field, nil, test_only) do
    Celixir.Evaluator.dispatch_select(operand_val, field, test_only)
  end

  def select(env, operand_val, field, qualified, test_only) do
    Celixir.Evaluator.dispatch_qualify_select(env, operand_val, field, qualified, test_only)
  end

  def opt_select({:cel_error, _} = e, _field), do: e
  def opt_select(target, field), do: Celixir.Evaluator.dispatch_opt_select(target, field)

  # --- Index ---

  def cel_index({:cel_error, _} = e, _), do: e
  def cel_index(_, {:cel_error, _} = e), do: e
  def cel_index(target, idx), do: Celixir.Evaluator.dispatch_index(target, idx)

  def opt_index({:cel_error, _} = e, _), do: e
  def opt_index(_, {:cel_error, _} = e), do: e
  def opt_index(target, idx), do: Celixir.Evaluator.dispatch_opt_index(target, idx)

  # --- Function / method dispatch ---

  def call(env, name, args) do
    case find_error(args) do
      {:cel_error, _} = e -> e
      nil -> Celixir.Evaluator.dispatch_function(name, args, env)
    end
  end

  def method(_env, _name, {:cel_error, _} = e, _args), do: e

  def method(env, name, target, args) do
    case find_error(args) do
      {:cel_error, _} = e -> e
      nil -> Celixir.Evaluator.dispatch_method(name, target, args, env)
    end
  end

  defp find_error(list), do: Enum.find(list, &match?({:cel_error, _}, &1))

  # --- List / Map / Struct construction ---

  def make_list(elements) do
    result =
      Enum.reduce_while(elements, [], fn
        {:__cel_opt_elem__, %Optional{has_value: true, value: v}}, acc -> {:cont, [v | acc]}
        {:__cel_opt_elem__, %Optional{has_value: false}}, acc -> {:cont, acc}
        {:__cel_opt_elem__, {:cel_error, _} = e}, _acc -> {:halt, e}
        {:__cel_opt_elem__, v}, acc -> {:cont, [v | acc]}
        {:cel_error, _} = e, _acc -> {:halt, e}
        v, acc -> {:cont, [v | acc]}
      end)

    case result do
      {:cel_error, _} = e -> e
      list -> Enum.reverse(list)
    end
  end

  def make_map(entries) do
    result =
      Enum.reduce_while(entries, %{}, fn
        {:__cel_opt_entry__, {:cel_error, _} = e, _}, _acc -> {:halt, e}
        {:__cel_opt_entry__, _, {:cel_error, _} = e}, _acc -> {:halt, e}
        {:__cel_opt_entry__, k, %Optional{has_value: true, value: v}}, acc ->
          do_add_map_entry(k, v, acc)
        {:__cel_opt_entry__, _k, %Optional{has_value: false}}, acc ->
          {:cont, acc}
        {:__cel_opt_entry__, k, v}, acc ->
          do_add_map_entry(k, v, acc)
        {:__cel_entry__, {:cel_error, _} = e, _}, _acc -> {:halt, e}
        {:__cel_entry__, _, {:cel_error, _} = e}, _acc -> {:halt, e}
        {:__cel_entry__, k, v}, acc ->
          do_add_map_entry(k, v, acc)
      end)

    case result do
      {:cel_error, _} = e -> e
      map -> map
    end
  end

  defp do_add_map_entry(nil, _, _), do: {:halt, {:cel_error, "unsupported key type"}}
  defp do_add_map_entry(k, _, _) when is_float(k), do: {:halt, {:cel_error, "unsupported key type"}}

  defp do_add_map_entry(k, v, acc) do
    if Map.has_key?(acc, k) do
      {:halt, {:cel_error, "Failed with repeated key"}}
    else
      {:cont, Map.put(acc, k, v)}
    end
  end

  def make_struct(env, type_name, entries) do
    result =
      Enum.reduce_while(entries, %{}, fn
        {:__cel_opt_entry__, {:cel_error, _} = e, _}, _acc -> {:halt, e}
        {:__cel_opt_entry__, _, {:cel_error, _} = e}, _acc -> {:halt, e}
        {:__cel_opt_entry__, field, %Optional{has_value: true, value: v}}, acc ->
          {:cont, Map.put(acc, field, v)}
        {:__cel_opt_entry__, _field, %Optional{has_value: false}}, acc ->
          {:cont, acc}
        {:__cel_opt_entry__, field, v}, acc ->
          {:cont, Map.put(acc, field, v)}
        {:__cel_entry__, {:cel_error, _} = e, _}, _acc -> {:halt, e}
        {:__cel_entry__, _, {:cel_error, _} = e}, _acc -> {:halt, e}
        {:__cel_entry__, field, v}, acc ->
          {:cont, Map.put(acc, field, v)}
      end)

    case result do
      {:cel_error, _} = e ->
        e

      fields ->
        qualified_name = qualify_struct_type(type_name, env)

        case Celixir.Proto.finalize_struct(qualified_name, fields) do
          {:cel_error, _} = e -> e
          struct -> struct
        end
    end
  end

  defp qualify_struct_type(type_name, %{container: container})
       when is_binary(container) and container != "" do
    qualified = container <> "." <> type_name
    if Celixir.Proto.get_schema(qualified), do: qualified, else: type_name
  end

  defp qualify_struct_type(type_name, _env), do: type_name

  # --- CelBlock (sequential bindings) ---

  def cel_block(env, binding_thunks, result_thunk) do
    result =
      Enum.reduce_while(Enum.with_index(binding_thunks), env, fn {thunk, idx}, acc_env ->
        case thunk.(acc_env) do
          {:cel_error, _} = e ->
            {:halt, e}

          v ->
            key = "__cel_block_#{idx}__"
            {:cont, Environment.put_local(acc_env, key, v)}
        end
      end)

    case result do
      {:cel_error, _} = e -> e
      final_env -> result_thunk.(final_env)
    end
  end

  # --- Comprehension ---

  def comprehension(env, range, iter_var, iter_var2, acc_var, acc_init, loop_cond_f, loop_step_f, result_f, kind) do
    case range do
      {:cel_error, _} = e ->
        e

      _ ->
        case acc_init do
          {:cel_error, _} = e ->
            e

          _ ->
            items = build_iter_items(range, iter_var2)
            run_comprehension(env, items, iter_var, iter_var2, acc_var, acc_init, loop_cond_f, loop_step_f, result_f, kind)
        end
    end
  end

  defp build_iter_items(range, nil) when is_map(range), do: Enum.map(Map.keys(range), &{&1})
  defp build_iter_items(range, nil) when is_list(range), do: Enum.map(range, &{&1})

  defp build_iter_items(range, _var2) when is_map(range) do
    Enum.map(range, fn {k, v} -> {k, v} end)
  end

  defp build_iter_items(range, _var2) when is_list(range) do
    range |> Enum.with_index() |> Enum.map(fn {v, i} -> {i, v} end)
  end

  defp bind_iter_env(env, iter_var, iter_var2, acc_var, acc_val, item) do
    env
    |> bind_item(iter_var, iter_var2, item)
    |> Environment.put_local(acc_var, acc_val)
  end

  defp bind_item(env, iter_var, nil, {v1}),
    do: Environment.put_local(env, iter_var, v1)

  defp bind_item(env, iter_var, iter_var2, {v1, v2}),
    do: env |> Environment.put_local(iter_var, v1) |> Environment.put_local(iter_var2, v2)

  defp run_comprehension(env, items, iter_var, iter_var2, acc_var, acc_init, loop_cond_f, loop_step_f, result_f, :standard) do
    final_acc =
      Enum.reduce_while(items, acc_init, fn item, current_acc ->
        loop_env = bind_iter_env(env, iter_var, iter_var2, acc_var, current_acc, item)
        cond_val = loop_cond_f.(loop_env)

        if cond_val == false do
          {:halt, current_acc}
        else
          {:cont, loop_step_f.(loop_env)}
        end
      end)

    case final_acc do
      {:cel_error, _} = e ->
        e

      _ ->
        result_env = Environment.put_local(env, acc_var, final_acc)
        result_f.(result_env)
    end
  end

  defp run_comprehension(env, items, iter_var, iter_var2, acc_var, acc_init, _loop_cond_f, _loop_step_f, result_f, {:transform_map, transform_f, filter_f}) do
    final_acc =
      Enum.reduce_while(items, acc_init, fn {key, _value} = item, current_acc ->
        loop_env = bind_iter_env(env, iter_var, iter_var2, acc_var, current_acc, item)

        include =
          if filter_f do
            filter_f.(loop_env)
          else
            true
          end

        case include do
          {:cel_error, _} = e ->
            {:halt, e}

          false ->
            {:cont, current_acc}

          _ ->
            transform_val = transform_f.(loop_env)

            case transform_val do
              {:cel_error, _} = e -> {:halt, e}
              v -> {:cont, Map.put(current_acc, key, v)}
            end
        end
      end)

    case final_acc do
      {:cel_error, _} = e ->
        e

      _ ->
        result_env = Environment.put_local(env, acc_var, final_acc)
        result_f.(result_env)
    end
  end

  defp run_comprehension(env, items, iter_var, iter_var2, acc_var, acc_init, _loop_cond_f, _loop_step_f, result_f, {:transform_map_entry, transform_f, filter_f}) do
    final_acc =
      Enum.reduce_while(items, acc_init, fn item, current_acc ->
        loop_env = bind_iter_env(env, iter_var, iter_var2, acc_var, current_acc, item)

        include =
          if filter_f do
            filter_f.(loop_env)
          else
            true
          end

        case include do
          {:cel_error, _} = e ->
            {:halt, e}

          false ->
            {:cont, current_acc}

          _ ->
            transform_val = transform_f.(loop_env)

            case transform_val do
              {:cel_error, _} = e ->
                {:halt, e}

              entry when is_map(entry) and not is_struct(entry) and map_size(entry) == 1 ->
                [{new_key, new_val}] = Map.to_list(entry)

                if Map.has_key?(current_acc, new_key) do
                  {:halt, {:cel_error, "transformMapEntry: duplicate key"}}
                else
                  {:cont, Map.put(current_acc, new_key, new_val)}
                end

              _ ->
                {:halt, {:cel_error, "transformMapEntry: transform must produce a single-entry map literal"}}
            end
        end
      end)

    case final_acc do
      {:cel_error, _} = e ->
        e

      _ ->
        result_env = Environment.put_local(env, acc_var, final_acc)
        result_f.(result_env)
    end
  end

  defp run_comprehension(env, items, iter_var, iter_var2, acc_var, acc_init, _loop_cond_f, _loop_step_f, result_f, {:sort_by, key_f}) do
    result =
      Enum.reduce_while(items, [], fn {value} = item, acc ->
        loop_env = bind_iter_env(env, iter_var, iter_var2, acc_var, acc_init, item)
        key = key_f.(loop_env)

        if match?({:cel_error, _}, key) do
          {:halt, key}
        else
          {:cont, [{key, value} | acc]}
        end
      end)

    case result do
      {:cel_error, _} = e ->
        e

      pairs ->
        sorted =
          pairs
          |> Enum.reverse()
          |> Enum.sort(fn {k1, _}, {k2, _} ->
            Celixir.Evaluator.dispatch_compare(:lt, k1, k2) == true
          end)
          |> Enum.map(fn {_, v} -> v end)

        result_env = Environment.put_local(env, acc_var, sorted)
        result_f.(result_env)
    end
  end

  # --- Optional lambda (optFlatMap / optMap) ---

  def opt_lambda(_env, {:cel_error, _} = e, _var, _kind, _expr_f), do: e

  def opt_lambda(env, %Optional{has_value: true, value: v}, var, kind, expr_f) do
    inner_env = Environment.put_variable(env, var, v)
    result = expr_f.(inner_env)

    case kind do
      :flat_map -> result
      :map -> if match?({:cel_error, _}, result), do: result, else: Optional.of(result)
    end
  end

  def opt_lambda(_env, %Optional{has_value: false}, _var, _kind, _expr_f) do
    Optional.none()
  end

  def opt_lambda(_env, other, _var, _kind, _expr_f) do
    {:cel_error, "optFlatMap/optMap called on non-optional: #{cel_typeof(other)}"}
  end

  # --- typeof helper (delegates to Evaluator) ---

  def cel_typeof(v), do: Celixir.Evaluator.dispatch_typeof(v)
end
