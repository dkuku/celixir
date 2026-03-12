defmodule Celixir.Evaluator do
  @moduledoc """
  Tree-walk evaluator for CEL AST nodes.

  Implements error-as-value semantics: errors propagate as {:cel_error, msg}
  tuples through expressions, but are absorbed by short-circuit operators.
  """

  alias Celixir.AST
  alias Celixir.Environment
  alias Celixir.Proto
  alias Celixir.Types.Duration
  alias Celixir.Types.Optional
  alias Celixir.Types.Timestamp

  @int64_min -9_223_372_036_854_775_808
  @int64_max 9_223_372_036_854_775_807
  @uint64_max 18_446_744_073_709_551_615

  @spec eval(AST.expr(), Environment.t()) :: {:ok, any()} | {:error, String.t()}
  def eval(expr, env) do
    case do_eval(expr, env) do
      {:cel_error, msg} -> {:error, msg}
      value -> {:ok, value}
    end
  end

  # --- Error helpers ---

  defp cel_error(msg), do: {:cel_error, msg}
  defp is_error({:cel_error, _}), do: true
  defp is_error(_), do: false

  defp with_value(val, fun) do
    if is_error(val), do: val, else: fun.(val)
  end

  defp with_values(l, r, fun) do
    cond do
      is_error(l) -> l
      is_error(r) -> r
      true -> fun.(l, r)
    end
  end

  # Wraps a non-error value in {:ok, val} for use with `with` chains.
  # Passes through {:cel_error, _} unchanged so `with` falls to `else`.
  defp ensure_value({:cel_error, _} = e), do: e
  defp ensure_value(val), do: {:ok, val}

  # ===================================================================
  # do_eval — all clauses grouped together
  # ===================================================================

  # Literals
  defp do_eval(%AST.IntLit{value: v}, _env), do: {:cel_int, v}
  defp do_eval(%AST.UintLit{value: v}, _env), do: {:cel_uint, v}
  defp do_eval(%AST.FloatLit{value: v}, _env), do: v
  defp do_eval(%AST.StringLit{value: v}, _env), do: v
  defp do_eval(%AST.BytesLit{value: v}, _env), do: {:cel_bytes, v}
  defp do_eval(%AST.BoolLit{value: v}, _env), do: v
  defp do_eval(%AST.NullLit{}, _env), do: nil

  # Identifier
  # CEL proto enum definitions (legacy mode: enums are ints)
  @enum_values %{
    "GlobalEnum" => %{"GOO" => 0, "GAR" => 1, "GAZ" => 2},
    "TestAllTypes.NestedEnum" => %{"FOO" => 0, "BAR" => 1, "BAZ" => 2}
  }

  # CEL type name constants
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

  defp do_eval(%AST.Ident{name: name}, env) do
    case Environment.get_variable(env, name) do
      {:ok, value} ->
        normalize(value)

      :error ->
        case Map.get(@type_denotations, name) do
          nil -> cel_error("undefined variable: #{name}")
          type_val -> type_val
        end
    end
  end

  # Field selection
  defp do_eval(%AST.Select{operand: operand, field: field, test_only: test_only}, env) do
    # First try to resolve as a qualified type name (e.g., google.protobuf.Timestamp)
    case try_qualified_type(operand, field) do
      {:ok, type_val} ->
        type_val

      :not_type ->
        # Try to resolve as a qualified variable name (e.g., a.b.c from bindings)
        case try_qualified_variable(operand, field, env) do
          {:ok, val} ->
            if test_only, do: val != nil, else: normalize(val)

          :not_var ->
            with_value(do_eval(operand, env), fn target ->
              if test_only, do: select_test(target, field), else: select_field(target, field)
            end)
        end
    end
  end

  # Optional field select: expr.?field — returns optional
  defp do_eval(%AST.OptSelect{operand: operand, field: field}, env) do
    with_value(do_eval(operand, env), fn target ->
      opt_select_field(target, field)
    end)
  end

  # Optional index: expr[?index] — returns optional
  defp do_eval(%AST.OptIndex{operand: operand, index: index}, env) do
    with_values(do_eval(operand, env), do_eval(index, env), &opt_index/2)
  end

  # Index
  defp do_eval(%AST.Index{operand: operand, index: index}, env) do
    with_values(do_eval(operand, env), do_eval(index, env), &do_index/2)
  end

  # Unary operators
  defp do_eval(%AST.UnaryOp{op: :not, operand: operand}, env) do
    with_value(do_eval(operand, env), fn
      v when is_boolean(v) -> not v
      v -> cel_error("no_matching_overload: ! on #{cel_typeof(v)}")
    end)
  end

  defp do_eval(%AST.UnaryOp{op: :negate, operand: operand}, env) do
    with_value(do_eval(operand, env), fn
      {:cel_int, v} -> check_int(-v)
      {:cel_uint, _} -> cel_error("no_matching_overload: negation on uint")
      v when is_float(v) -> -v
      %Duration{} = d -> Duration.negate(d)
      v -> cel_error("no_matching_overload: - on #{cel_typeof(v)}")
    end)
  end

  # Short-circuit: &&
  defp do_eval(%AST.BinaryOp{op: :and, left: left, right: right}, env) do
    case do_eval(left, env) do
      false ->
        false

      true ->
        case do_eval(right, env) do
          v when is_boolean(v) -> v
          {:cel_error, _} = e -> e
          v -> cel_error("no_matching_overload: && on #{cel_typeof(v)}")
        end

      {:cel_error, _} = e ->
        case do_eval(right, env) do
          false -> false
          _ -> e
        end

      v ->
        # Non-bool left is a type error; check if right side can absorb it
        e = cel_error("no_matching_overload: && on #{cel_typeof(v)}")

        case do_eval(right, env) do
          false -> false
          _ -> e
        end
    end
  end

  # Short-circuit: ||
  defp do_eval(%AST.BinaryOp{op: :or, left: left, right: right}, env) do
    case do_eval(left, env) do
      true ->
        true

      false ->
        case do_eval(right, env) do
          v when is_boolean(v) -> v
          {:cel_error, _} = e -> e
          v -> cel_error("no_matching_overload: || on #{cel_typeof(v)}")
        end

      {:cel_error, _} = e ->
        if do_eval(right, env) == true do
          true
        else
          e
        end

      v ->
        # Non-bool left is a type error; check if right side can absorb it
        e = cel_error("no_matching_overload: || on #{cel_typeof(v)}")

        # Must use case, not if — if treats any truthy value (e.g. strings) as true
        if do_eval(right, env) == true do
          true
        else
          e
        end
    end
  end

  # Arithmetic
  defp do_eval(%AST.BinaryOp{op: :add, left: left, right: right}, env),
    do: with_values(do_eval(left, env), do_eval(right, env), &do_add/2)

  defp do_eval(%AST.BinaryOp{op: :sub, left: left, right: right}, env),
    do: with_values(do_eval(left, env), do_eval(right, env), &do_sub/2)

  defp do_eval(%AST.BinaryOp{op: :mul, left: left, right: right}, env),
    do: with_values(do_eval(left, env), do_eval(right, env), &do_mul/2)

  defp do_eval(%AST.BinaryOp{op: :div, left: left, right: right}, env),
    do: with_values(do_eval(left, env), do_eval(right, env), &do_div/2)

  defp do_eval(%AST.BinaryOp{op: :mod, left: left, right: right}, env),
    do: with_values(do_eval(left, env), do_eval(right, env), &do_mod/2)

  # Comparison
  defp do_eval(%AST.BinaryOp{op: op, left: left, right: right}, env) when op in [:eq, :neq, :lt, :lte, :gt, :gte] do
    with_values(do_eval(left, env), do_eval(right, env), &do_compare(op, &1, &2))
  end

  # Membership: in
  defp do_eval(%AST.BinaryOp{op: :in, left: left, right: right}, env) do
    with_values(do_eval(left, env), do_eval(right, env), fn l, r ->
      cond do
        is_list(r) -> Enum.any?(r, &cel_equal?(l, &1))
        is_map(r) -> Enum.any?(Map.keys(r), &cel_equal?(l, &1))
        true -> cel_error("no_matching_overload: 'in' on #{cel_typeof(r)}")
      end
    end)
  end

  # Ternary
  defp do_eval(%AST.Ternary{condition: cond_expr, true_expr: t, false_expr: f}, env) do
    case do_eval(cond_expr, env) do
      true -> do_eval(t, env)
      false -> do_eval(f, env)
      {:cel_error, _} = e -> e
      v -> cel_error("ternary condition must be bool, got #{cel_typeof(v)}")
    end
  end

  # List construction
  defp do_eval(%AST.CreateList{elements: elements}, env), do: eval_list(elements, env, [])

  # Map construction
  defp do_eval(%AST.CreateMap{entries: entries}, env), do: eval_map(entries, env, %{})

  # Struct/message creation: TypeName{field: value, ...}
  defp do_eval(%AST.CreateStruct{type_name: type_name, entries: entries}, env) do
    eval_struct_fields(entries, env, type_name, %{})
  end

  # Optional lambda: optFlatMap / optMap
  defp do_eval(%AST.OptLambda{kind: kind, target: target, var: var, expr: expr}, env) do
    with_value(do_eval(target, env), fn
      %Optional{has_value: true, value: v} ->
        inner_env = Environment.put_variable(env, var, v)
        result = do_eval(expr, inner_env)

        case kind do
          :flat_map -> result
          :map -> if is_error(result), do: result, else: Optional.of(result)
        end

      %Optional{has_value: false} ->
        Optional.none()

      other ->
        cel_error("optFlatMap/optMap called on non-optional: #{cel_typeof(other)}")
    end)
  end

  # Function / method call
  defp do_eval(%AST.Call{function: name, target: nil, args: args}, env) do
    with {:ok, args_list} <- ensure_value(eval_args(args, env)) do
      call_function(name, args_list, env)
    end
  end

  defp do_eval(%AST.Call{function: name, target: target, args: args}, env) do
    with {:ok, args_list} <- ensure_value(eval_args(args, env)) do
      case ensure_value(do_eval(target, env)) do
        {:ok, t} ->
          call_method(name, t, args_list, env)

        {:cel_error, _} = e ->
          # If target is a simple ident that failed to resolve, try as qualified function
          if match?(%AST.Ident{}, target) or match?(%AST.Select{}, target) do
            qualified = qualified_name(target, name)

            case call_function(qualified, args_list, env) do
              {:cel_error, "undefined function: " <> _} -> e
              result -> result
            end
          else
            e
          end
      end
    end
  end

  # cel.block([bindings...], result) — evaluate bindings sequentially, then result
  defp do_eval(%AST.CelBlock{bindings: bindings, result: result}, env) do
    env2 =
      bindings
      |> Enum.with_index()
      |> Enum.reduce(env, fn {binding_expr, idx}, acc_env ->
        val = do_eval(binding_expr, acc_env)
        Environment.put_variable(acc_env, "__cel_block_#{idx}__", val)
      end)

    do_eval(result, env2)
  end

  # cel.index(N) — resolve block binding
  defp do_eval(%AST.CelIndex{index: n}, env) do
    case Environment.get_variable(env, "__cel_block_#{n}__") do
      {:ok, value} -> value
      :error -> cel_error("cel.index(#{n}): binding not found")
    end
  end

  # cel.iterVar(depth, index) — resolve iteration variable from comprehension context
  defp do_eval(%AST.CelIterVar{depth: depth, index: idx}, env) do
    var_name = "__cel_iter_#{depth}_#{idx}__"

    case Environment.get_variable(env, var_name) do
      {:ok, value} -> value
      :error -> cel_error("cel.iterVar(#{depth}, #{idx}): variable not found")
    end
  end

  # Comprehension
  defp do_eval(%AST.Comprehension{} = comp, env) do
    with {:ok, range} <- ensure_value(do_eval(comp.iter_range, env)),
         {:ok, acc} <- ensure_value(do_eval(comp.acc_init, env)) do
      # Build iteration items based on whether we have one or two iteration variables
      items = build_iter_items(range, comp.iter_var2)

      final_acc =
        case comp.kind do
          {:transform_map, transform_expr, filter_expr} ->
            eval_transform_map(items, comp, transform_expr, filter_expr, acc, env)

          :standard ->
            eval_standard_comprehension(items, comp, acc, env)
        end

      with {:ok, final_acc} <- ensure_value(final_acc) do
        result_env = Environment.put_variable(env, comp.acc_var, final_acc)
        do_eval(comp.result, result_env)
      end
    end
  end

  # Build iteration items: list of {var1_value, var2_value} or {var1_value}
  defp build_iter_items(range, nil) when is_map(range), do: Enum.map(Map.keys(range), &{&1})
  defp build_iter_items(range, nil) when is_list(range), do: Enum.map(range, &{&1})

  defp build_iter_items(range, _var2) when is_map(range) do
    Enum.map(range, fn {k, v} -> {k, v} end)
  end

  defp build_iter_items(range, _var2) when is_list(range) do
    range |> Enum.with_index() |> Enum.map(fn {v, i} -> {{:cel_int, i}, v} end)
  end

  defp bind_iter_vars(env, comp, {var1_val}) do
    Environment.put_variable(env, comp.iter_var, var1_val)
  end

  defp bind_iter_vars(env, comp, {var1_val, var2_val}) do
    env
    |> Environment.put_variable(comp.iter_var, var1_val)
    |> Environment.put_variable(comp.iter_var2, var2_val)
  end

  defp eval_standard_comprehension(items, comp, acc, env) do
    Enum.reduce_while(items, acc, fn item, current_acc ->
      loop_env =
        env
        |> bind_iter_vars(comp, item)
        |> Environment.put_variable(comp.acc_var, current_acc)

      cond_val = do_eval(comp.loop_condition, loop_env)

      cond do
        # Error in loop_condition: continue to allow error absorption
        is_error(cond_val) ->
          step_val = do_eval(comp.loop_step, loop_env)
          {:cont, step_val}

        # Condition true: evaluate step
        cond_val ->
          step_val = do_eval(comp.loop_step, loop_env)
          {:cont, step_val}

        # Condition false: early exit (all found false, or exists found true)
        true ->
          {:halt, current_acc}
      end
    end)
  end

  defp eval_transform_map(items, comp, transform_expr, filter_expr, acc, env) do
    Enum.reduce_while(items, acc, fn {key, _value} = item, current_acc ->
      loop_env =
        env
        |> bind_iter_vars(comp, item)
        |> Environment.put_variable(comp.acc_var, current_acc)

      with {:ok, include} <- eval_filter(filter_expr, loop_env),
           {:ok, new_acc} <- apply_transform(include, key, transform_expr, loop_env, current_acc) do
        {:cont, new_acc}
      else
        {:cel_error, _} = e -> {:halt, e}
      end
    end)
  end

  defp eval_filter(nil, _env), do: {:ok, true}

  defp eval_filter(filter_expr, env) do
    filter_val = do_eval(filter_expr, env)

    cond do
      is_error(filter_val) -> filter_val
      is_boolean(filter_val) -> {:ok, filter_val}
      true -> cel_error("filter must be bool, got #{cel_typeof(filter_val)}")
    end
  end

  defp apply_transform(false, _key, _transform_expr, _env, acc), do: {:ok, acc}

  defp apply_transform(true, key, transform_expr, env, acc) do
    with {:ok, transform_val} <- ensure_value(do_eval(transform_expr, env)) do
      {:ok, Map.put(acc, key, transform_val)}
    end
  end

  # ===================================================================
  # Eval helpers (not do_eval)
  # ===================================================================

  defp normalize(v) when is_integer(v), do: {:cel_int, v}

  defp normalize({:cel_lazy_default, name}) do
    case Proto.get_schema(name) do
      nil -> nil
      schema -> Proto.default_struct(name, schema)
    end
  end

  defp normalize(v), do: v

  # Auto-unpack Any struct values when they're accessed (read from a field, etc.)
  defp maybe_unpack_any({:cel_struct, "google.protobuf.Any", fields}) do
    Proto.unpack_any(fields)
  end

  defp maybe_unpack_any(v), do: v

  # Try to resolve a Select chain as a qualified proto type name.
  # e.g., Select(Select(Ident("google"), "protobuf"), "Timestamp") → "google.protobuf.Timestamp"
  defp try_qualified_type(operand, field) do
    case extract_qualified_name(operand) do
      nil ->
        :not_type

      prefix ->
        qualified = "#{prefix}.#{field}"

        cond do
          # NullValue.NULL_VALUE is a proto enum constant for null
          qualified == "NullValue.NULL_VALUE" ->
            {:ok, {:cel_int, 0}}

          Proto.well_known_type?(qualified) or Proto.get_schema(qualified) != nil ->
            {:ok, {:cel_type, qualified}}

          qualified in ["net.IP", "net.CIDR"] ->
            {:ok, {:cel_type, qualified}}

          # Enum value: prefix is a known enum type, field is a value name
          Map.has_key?(@enum_values, prefix) ->
            case get_in(@enum_values, [prefix, field]) do
              nil -> :not_type
              int_val -> {:ok, {:cel_int, int_val}}
            end

          true ->
            :not_type
        end
    end
  end

  # Try to resolve a Select chain as a qualified variable name (e.g., a.b.c from bindings)
  defp try_qualified_variable(operand, field, env) do
    with name when name != nil <- extract_qualified_name(operand),
         qualified = "#{name}.#{field}",
         {:ok, val} <- Environment.get_variable(env, qualified) do
      {:ok, val}
    else
      _ -> :not_var
    end
  end

  defp extract_qualified_name(%AST.Ident{name: name}), do: name

  defp extract_qualified_name(%AST.Select{operand: operand, field: field}) do
    case extract_qualified_name(operand) do
      nil -> nil
      prefix -> "#{prefix}.#{field}"
    end
  end

  defp extract_qualified_name(_), do: nil

  # Optional field selection — auto-wrap in Optional when chaining
  # If inner value supports field access (map/struct), missing field -> optional.none()
  # If inner value doesn't support field access, propagate the error
  defp select_field(%Optional{has_value: true, value: v}, field) do
    if field_accessible?(v) do
      result = select_field(v, field)
      if is_error(result), do: Optional.none(), else: Optional.of(result)
    else
      cel_error("no_such_field: #{field}")
    end
  end

  defp select_field(%Optional{has_value: false}, _field), do: Optional.none()

  defp select_field({:cel_struct, _type_name, fields}, field) do
    case Map.fetch(fields, field) do
      {:ok, v} -> normalize(maybe_unpack_any(v))
      :error -> cel_error("no_such_field: #{field}")
    end
  end

  defp select_field(target, field) when is_map(target) do
    result =
      cond do
        Map.has_key?(target, field) -> {:found, Map.get(target, field)}
        is_atom_key?(target, field) -> {:found, Map.get(target, String.to_existing_atom(field))}
        true -> :not_found
      end

    case result do
      {:found, v} -> normalize(v)
      :not_found -> cel_error("no_such_field: #{field}")
    end
  rescue
    ArgumentError -> cel_error("no_such_field: #{field}")
  end

  defp select_field(target, field), do: cel_error("cannot select field '#{field}' on #{cel_typeof(target)}")

  # Optional field select: returns optional wrapping the field value
  defp opt_select_field(%Optional{has_value: true, value: v}, field), do: opt_select_field(v, field)

  defp opt_select_field(%Optional{has_value: false}, _field), do: Optional.none()

  defp opt_select_field({:cel_struct, _type_name, fields}, field) do
    # For proto structs with tracked provided fields, only return present
    # if the field was explicitly set
    provided = Map.get(fields, :__provided_fields__)

    cond do
      provided != nil and not MapSet.member?(provided, field) ->
        Optional.none()

      Map.has_key?(fields, field) ->
        Optional.of(Map.get(fields, field))

      true ->
        Optional.none()
    end
  end

  defp opt_select_field(target, field) when is_map(target) do
    cond do
      Map.has_key?(target, field) -> Optional.of(Map.get(target, field))
      is_atom_key?(target, field) -> Optional.of(Map.get(target, String.to_existing_atom(field)))
      true -> Optional.none()
    end
  rescue
    ArgumentError -> Optional.none()
  end

  defp opt_select_field(_target, _field), do: Optional.none()

  # Optional index: returns optional wrapping the indexed value
  defp opt_index(%Optional{has_value: true, value: v}, idx), do: opt_index(v, idx)
  defp opt_index(%Optional{has_value: false}, _idx), do: Optional.none()

  defp opt_index(target, idx) when is_map(target) do
    # Use cross-type numeric key matching (cel_equal?)
    case map_find_key(target, idx) do
      {:ok, matched_key} -> Optional.of(Map.get(target, matched_key))
      :error -> Optional.none()
    end
  end

  defp opt_index(target, idx) when is_list(target) do
    i =
      case idx do
        {:cel_int, v} -> v
        {:cel_uint, v} -> v
        v when is_integer(v) -> v
        _ -> -1
      end

    if i >= 0 and i < length(target) do
      Optional.of(Enum.at(target, i))
    else
      Optional.none()
    end
  end

  defp opt_index(_target, _idx), do: Optional.none()

  # has() on Optional — check if the optional has a value and the inner value has the field
  defp select_test(%Optional{has_value: true, value: v}, field), do: select_test(v, field)
  defp select_test(%Optional{has_value: false}, _field), do: false

  defp select_test({:cel_struct, _type_name, fields}, field) do
    provided = Map.get(fields, :__provided_fields__)

    # Unknown field → error (spec requires it)
    if Map.has_key?(fields, field) || provided == nil do
      cond do
        # No schema tracking — fall back to key presence
        provided == nil ->
          Map.has_key?(fields, field)

        # Field was not explicitly provided
        not MapSet.member?(provided, field) ->
          false

        # For repeated (list) and map fields, has() returns false when the value
        # is the default (empty list/map), even if explicitly set (proto3 semantics).
        true ->
          case Map.get(fields, field) do
            v when is_list(v) -> v != []
            v when is_map(v) -> v != %{}
            _ -> true
          end
      end
    else
      cel_error("no_such_field: #{field}")
    end
  end

  defp select_test(target, field) when is_map(target) do
    cond do
      Map.has_key?(target, field) -> true
      is_atom_key?(target, field) -> true
      true -> false
    end
  rescue
    ArgumentError -> false
  end

  defp select_test(_target, _field), do: false

  defp is_atom_key?(map, field) do
    atom = String.to_existing_atom(field)
    Map.has_key?(map, atom)
  rescue
    ArgumentError -> false
  end

  # Check if a value supports field access (maps and structs)
  defp field_accessible?(v) when is_map(v), do: true
  defp field_accessible?({:cel_struct, _, _}), do: true
  defp field_accessible?(_), do: false

  # Check if a value supports indexing (lists and maps)
  defp indexable?(v) when is_list(v), do: true
  defp indexable?(v) when is_map(v), do: true
  defp indexable?({:cel_struct, _, _}), do: true
  defp indexable?(_), do: false

  # Index on Optional — auto-wrap result in Optional
  # If inner value supports indexing (list/map), missing key -> optional.none()
  # If inner value doesn't support indexing, propagate the error
  defp do_index(%Optional{has_value: true, value: v}, idx) do
    if indexable?(v) do
      result = do_index(v, idx)
      if is_error(result), do: Optional.none(), else: Optional.of(result)
    else
      cel_error("cannot index into #{cel_typeof(v)}")
    end
  end

  defp do_index(%Optional{has_value: false}, _idx), do: Optional.none()

  defp do_index(target, {:cel_int, idx}) when is_list(target) do
    if idx >= 0 and idx < length(target),
      do: normalize(Enum.at(target, idx)),
      else: cel_error("index #{idx} out of range")
  end

  defp do_index(target, idx) when is_list(target) and is_integer(idx), do: do_index(target, {:cel_int, idx})

  defp do_index(target, {:cel_uint, idx}) when is_list(target), do: do_index(target, {:cel_int, idx})

  defp do_index(target, idx) when is_list(target) and is_float(idx) do
    int_idx = trunc(idx)

    if idx == int_idx * 1.0,
      do: do_index(target, {:cel_int, int_idx}),
      else: cel_error("invalid_argument: list index must be a whole number, got #{idx}")
  end

  defp do_index(target, idx) when is_map(target) do
    unwrapped =
      case idx do
        {:cel_int, v} -> v
        {:cel_uint, v} -> v
        other -> other
      end

    cond do
      Map.has_key?(target, idx) ->
        normalize(Map.get(target, idx))

      Map.has_key?(target, unwrapped) ->
        normalize(Map.get(target, unwrapped))

      true ->
        # Fall back to cel_equal? key matching (handles int/uint cross-type lookup)
        case map_find_key(target, idx) do
          {:ok, matched_key} -> normalize(Map.get(target, matched_key))
          :error -> cel_error("key #{inspect(unwrapped)} not found in map")
        end
    end
  end

  defp do_index(target, _idx), do: cel_error("cannot index into #{cel_typeof(target)}")

  defp eval_list([], _env, acc), do: Enum.reverse(acc)

  # Optional list element: ?expr — include only if present optional
  defp eval_list([{:optional_list_elem, expr} | t], env, acc) do
    case do_eval(expr, env) do
      {:cel_error, _} = e -> e
      %Optional{has_value: true, value: v} -> eval_list(t, env, [v | acc])
      %Optional{has_value: false} -> eval_list(t, env, acc)
      v -> eval_list(t, env, [v | acc])
    end
  end

  defp eval_list([h | t], env, acc) do
    case do_eval(h, env) do
      {:cel_error, _} = e -> e
      v -> eval_list(t, env, [v | acc])
    end
  end

  defp eval_map([], _env, acc), do: acc

  # Optional map entry: ?key: value — only include if value has_value
  defp eval_map([{:optional, k_expr, v_expr} | rest], env, acc) do
    with {:ok, k} <- ensure_value(do_eval(k_expr, env)),
         {:ok, v} <- ensure_value(do_eval(v_expr, env)) do
      case v do
        %Optional{has_value: true, value: inner} ->
          eval_map(rest, env, Map.put(acc, k, inner))

        %Optional{has_value: false} ->
          eval_map(rest, env, acc)

        _ ->
          eval_map(rest, env, Map.put(acc, k, v))
      end
    end
  end

  defp eval_map([{k_expr, v_expr} | rest], env, acc) do
    with {:ok, k} <- ensure_value(do_eval(k_expr, env)),
         :ok <- validate_map_key(k),
         :ok <- check_duplicate_key(k, acc),
         {:ok, v} <- ensure_value(do_eval(v_expr, env)) do
      eval_map(rest, env, Map.put(acc, k, v))
    end
  end

  defp validate_map_key(nil), do: cel_error("unsupported key type")
  defp validate_map_key(k) when is_float(k), do: cel_error("unsupported key type")
  defp validate_map_key(_), do: :ok

  defp check_duplicate_key(k, acc) do
    if Map.has_key?(acc, k) or has_equivalent_key?(k, acc) do
      cel_error("Failed with repeated key")
    else
      :ok
    end
  end

  # Check for cross-type numeric key equivalence (e.g., 0 int == 0u uint)
  defp has_equivalent_key?({:cel_int, v}, acc) do
    Map.has_key?(acc, {:cel_uint, v})
  end

  defp has_equivalent_key?({:cel_uint, v}, acc) do
    Map.has_key?(acc, {:cel_int, v})
  end

  defp has_equivalent_key?(_, _acc), do: false

  # Struct field evaluation — evaluates entries then finalizes via Proto module
  defp eval_struct_fields([], _env, type_name, acc) do
    Proto.finalize_struct(type_name, acc)
  end

  # Optional struct field: ?field_name: expr — only include if value is a present optional
  defp eval_struct_fields([{:optional, field_name, v_expr} | rest], env, type_name, acc) do
    with {:ok, v} <- ensure_value(do_eval(v_expr, env)) do
      case v do
        %Optional{has_value: true, value: inner} ->
          eval_struct_fields(rest, env, type_name, Map.put(acc, field_name, inner))

        %Optional{has_value: false} ->
          eval_struct_fields(rest, env, type_name, acc)

        _ ->
          eval_struct_fields(rest, env, type_name, Map.put(acc, field_name, v))
      end
    end
  end

  defp eval_struct_fields([{field_name, v_expr} | rest], env, type_name, acc) do
    with {:ok, v} <- ensure_value(do_eval(v_expr, env)) do
      eval_struct_fields(rest, env, type_name, Map.put(acc, field_name, v))
    end
  end

  defp eval_args([], _env), do: []

  defp eval_args([h | t], env) do
    with {:ok, v} <- ensure_value(do_eval(h, env)),
         {:ok, rest} <- ensure_value(eval_args(t, env)) do
      [v | rest]
    end
  end

  # ===================================================================
  # Arithmetic operations with strict types
  # ===================================================================

  defp do_add({:cel_int, a}, {:cel_int, b}), do: check_int(a + b)
  defp do_add({:cel_uint, a}, {:cel_uint, b}), do: check_uint(a + b)
  defp do_add(a, b) when is_float(a) and is_float(b), do: a + b
  defp do_add(a, b) when is_binary(a) and is_binary(b), do: a <> b
  defp do_add({:cel_bytes, a}, {:cel_bytes, b}), do: {:cel_bytes, a <> b}
  defp do_add(a, b) when is_list(a) and is_list(b), do: a ++ b

  defp do_add(%Timestamp{} = t, %Duration{} = d) do
    {result, _result_ns} = Timestamp.add_nanos(t, Duration.to_total_nanos(d))
    check_timestamp(result)
  end

  defp do_add(%Duration{} = d, %Timestamp{} = t) do
    {result, _result_ns} = Timestamp.add_nanos(t, Duration.to_total_nanos(d))
    check_timestamp(result)
  end

  defp do_add(%Duration{} = a, %Duration{} = b) do
    case Duration.add(a, b) do
      {:ok, d} -> d
      {:error, msg} -> cel_error(msg)
    end
  end

  defp do_add(l, r), do: cel_error("no_matching_overload: + on #{cel_typeof(l)} and #{cel_typeof(r)}")

  defp do_sub({:cel_int, a}, {:cel_int, b}), do: check_int(a - b)
  defp do_sub({:cel_uint, a}, {:cel_uint, b}), do: check_uint(a - b)
  defp do_sub(a, b) when is_float(a) and is_float(b), do: a - b

  defp do_sub(%Timestamp{} = a, %Timestamp{} = b) do
    diff_ns = Timestamp.diff_nanos(a, b)
    # Check if the diff in nanoseconds overflows int64
    if diff_ns > 9_223_372_036_854_775_807 or diff_ns < -9_223_372_036_854_775_808 do
      cel_error("timestamp overflow")
    else
      d = Duration.from_total_nanos(diff_ns)
      if Duration.in_range?(d), do: d, else: cel_error("duration overflow")
    end
  end

  defp do_sub(%Timestamp{} = t, %Duration{} = d) do
    {result, _result_ns} = Timestamp.add_nanos(t, -Duration.to_total_nanos(d))
    check_timestamp(result)
  end

  defp do_sub(%Duration{} = a, %Duration{} = b) do
    case Duration.subtract(a, b) do
      {:ok, d} -> d
      {:error, msg} -> cel_error(msg)
    end
  end

  defp do_sub(l, r), do: cel_error("no_matching_overload: - on #{cel_typeof(l)} and #{cel_typeof(r)}")

  defp do_mul({:cel_int, a}, {:cel_int, b}), do: check_int(a * b)
  defp do_mul({:cel_uint, a}, {:cel_uint, b}), do: check_uint(a * b)

  defp do_mul(a, b) when is_float(a) and is_float(b) do
    a * b
  rescue
    ArithmeticError ->
      if (a > 0 and b > 0) or (a < 0 and b < 0) do
        :infinity
      else
        :neg_infinity
      end
  end

  defp do_mul(l, r), do: cel_error("no_matching_overload: * on #{cel_typeof(l)} and #{cel_typeof(r)}")

  defp do_div({:cel_int, _}, {:cel_int, 0}), do: cel_error("division by zero")
  defp do_div({:cel_int, a}, {:cel_int, b}), do: check_int(div(a, b))
  defp do_div({:cel_uint, _}, {:cel_uint, 0}), do: cel_error("division by zero")
  defp do_div({:cel_uint, a}, {:cel_uint, b}), do: {:cel_uint, div(a, b)}

  defp do_div(a, b) when is_float(a) and is_float(b) do
    cond do
      b == 0.0 and a > 0.0 -> :infinity
      b == 0.0 and a < 0.0 -> :neg_infinity
      b == 0.0 -> :nan
      true -> a / b
    end
  end

  defp do_div(l, r), do: cel_error("no_matching_overload: / on #{cel_typeof(l)} and #{cel_typeof(r)}")

  defp do_mod({:cel_int, _}, {:cel_int, 0}), do: cel_error("modulo by zero")
  defp do_mod({:cel_int, a}, {:cel_int, b}), do: {:cel_int, rem(a, b)}
  defp do_mod({:cel_uint, _}, {:cel_uint, 0}), do: cel_error("modulo by zero")
  defp do_mod({:cel_uint, a}, {:cel_uint, b}), do: {:cel_uint, rem(a, b)}

  defp do_mod(l, r), do: cel_error("no_matching_overload: % on #{cel_typeof(l)} and #{cel_typeof(r)}")

  # ===================================================================
  # Comparison with heterogeneous numeric equality
  # ===================================================================

  defp do_compare(:eq, l, r), do: cel_equal?(l, r)
  defp do_compare(:neq, l, r), do: not cel_equal?(l, r)

  defp do_compare(op, l, r) when op in [:lt, :lte, :gt, :gte] do
    case cel_order(l, r) do
      :error -> cel_error("no_matching_overload: #{op} on (#{cel_typeof(l)}, #{cel_typeof(r)})")
      :neq -> false
      ord -> apply_ord(op, ord)
    end
  end

  defp apply_ord(:lt, ord), do: ord == :lt
  defp apply_ord(:lte, ord), do: ord in [:lt, :eq]
  defp apply_ord(:gt, ord), do: ord == :gt
  defp apply_ord(:gte, ord), do: ord in [:gt, :eq]

  # --- Cross-type numeric helpers ---

  # Extract a raw numeric value or nil for non-numeric types
  defp to_number({:cel_int, v}), do: v
  defp to_number({:cel_uint, v}), do: v
  defp to_number(v) when is_float(v), do: v
  defp to_number(v) when is_integer(v), do: v
  defp to_number(:nan), do: :nan
  defp to_number(:infinity), do: :infinity
  defp to_number(:neg_infinity), do: :neg_infinity
  defp to_number(_), do: nil

  # Compare two raw numeric values handling int-vs-float precision.
  # Returns :lt | :eq | :gt | :neq (for NaN — unordered)
  defp numeric_compare(:nan, _), do: :neq
  defp numeric_compare(_, :nan), do: :neq

  defp numeric_compare(:infinity, :infinity), do: :eq
  defp numeric_compare(:neg_infinity, :neg_infinity), do: :eq
  defp numeric_compare(:infinity, _), do: :gt
  defp numeric_compare(_, :infinity), do: :lt
  defp numeric_compare(:neg_infinity, _), do: :lt
  defp numeric_compare(_, :neg_infinity), do: :gt

  # Both integers (including extracted from cel_int/cel_uint) — exact compare
  defp numeric_compare(a, b) when is_integer(a) and is_integer(b) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> :eq
    end
  end

  # Both floats — direct compare
  defp numeric_compare(a, b) when is_float(a) and is_float(b) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> :eq
    end
  end

  # Mixed int/float — careful with precision.
  # Float64 can exactly represent integers up to 2^53. Beyond that we must
  # avoid converting the integer to float. Instead, if the float is a whole
  # number we convert it to integer; otherwise we can safely determine ordering
  # by comparing the float against the integer's truncation.
  defp numeric_compare(a, b) when is_integer(a) and is_float(b) do
    invert(numeric_compare_float_int(b, a))
  end

  defp numeric_compare(a, b) when is_float(a) and is_integer(b) do
    numeric_compare_float_int(a, b)
  end

  # Compare float `f` against integer `i`, returning :lt | :eq | :gt for f vs i
  # CEL uses float64 comparison semantics: both operands are converted to double.
  # This matters at the int64 boundary where large ints round to the same float64
  # (e.g. 9223372036854775807 and 9223372036854775808.0 are the same double).
  defp numeric_compare_float_int(f, i) do
    fi = i * 1.0

    cond do
      f < fi -> :lt
      f > fi -> :gt
      true -> :eq
    end
  end

  defp invert(:lt), do: :gt
  defp invert(:gt), do: :lt
  defp invert(:eq), do: :eq

  # --- Deep equality with cross-type numeric comparison ---

  defp cel_equal?(:nan, _), do: false
  defp cel_equal?(_, :nan), do: false

  defp cel_equal?(a, b) do
    na = to_number(a)
    nb = to_number(b)

    cond do
      na != nil and nb != nil ->
        numeric_compare(na, nb) == :eq

      is_list(a) and is_list(b) ->
        list_equal?(a, b)

      is_map(a) and is_map(b) and not is_struct(a) and not is_struct(b) ->
        map_equal?(a, b)

      match?({:cel_struct, _, _}, a) and match?({:cel_struct, _, _}, b) ->
        struct_equal?(a, b)

      match?({:cel_ip, _}, a) and match?({:cel_ip, _}, b) ->
        ip_equal?(a, b)

      match?({:cel_cidr, _, _}, a) and match?({:cel_cidr, _, _}, b) ->
        a == b

      true ->
        a == b
    end
  end

  defp struct_equal?({:cel_struct, t1, f1}, {:cel_struct, t2, f2}) do
    t1 == t2 and
      struct_fields_equal?(
        Map.delete(f1, :__provided_fields__),
        Map.delete(f2, :__provided_fields__)
      )
  end

  # Compare struct fields with proto message semantics:
  # nil and a default struct are equivalent (both mean "not set")
  defp struct_fields_equal?(f1, f2) do
    ka = Map.keys(f1)
    kb = Map.keys(f2)

    length(ka) == length(kb) and
      Enum.all?(ka, fn key ->
        v1 = Map.get(f1, key)
        v2 = Map.get(f2, key)
        proto_field_equal?(v1, v2)
      end)
  end

  # nil message field == default struct (both represent unset)
  defp proto_field_equal?(nil, {:cel_struct, _, _}), do: true
  defp proto_field_equal?({:cel_struct, _, _}, nil), do: true
  defp proto_field_equal?(nil, {:cel_lazy_default, _}), do: true
  defp proto_field_equal?({:cel_lazy_default, _}, nil), do: true
  defp proto_field_equal?({:cel_lazy_default, a}, {:cel_lazy_default, b}), do: a == b
  defp proto_field_equal?({:cel_lazy_default, _}, {:cel_struct, _, _}), do: true
  defp proto_field_equal?({:cel_struct, _, _}, {:cel_lazy_default, _}), do: true

  # Unpack Any values before comparing
  defp proto_field_equal?({:cel_struct, "google.protobuf.Any", f1}, {:cel_struct, "google.protobuf.Any", f2}) do
    cel_equal?(
      maybe_unpack_any({:cel_struct, "google.protobuf.Any", f1}),
      maybe_unpack_any({:cel_struct, "google.protobuf.Any", f2})
    )
  end

  defp proto_field_equal?(a, b), do: cel_equal?(a, b)

  defp list_equal?([], []), do: true
  defp list_equal?([], _), do: false
  defp list_equal?(_, []), do: false

  defp list_equal?([ha | ta], [hb | tb]) do
    cel_equal?(ha, hb) and list_equal?(ta, tb)
  end

  defp map_equal?(a, b) do
    # Maps are equal if they have the same number of keys and every key in a
    # has a matching key in b (under cross-type numeric equality) with equal values.
    ka = Map.keys(a)
    kb = Map.keys(b)

    length(ka) == length(kb) and
      Enum.all?(ka, fn key_a ->
        case map_find_key(b, key_a) do
          {:ok, key_b} -> cel_equal?(Map.get(a, key_a), Map.get(b, key_b))
          :error -> false
        end
      end)
  end

  # Find a key in the map that is cel_equal? to target_key
  defp map_find_key(map, target_key) do
    Enum.find_value(Map.keys(map), :error, fn k ->
      if cel_equal?(k, target_key), do: {:ok, k}
    end)
  end

  # --- Ordering ---

  defp cel_order(a, b) do
    na = to_number(a)
    nb = to_number(b)

    cond do
      na != nil and nb != nil ->
        numeric_compare(na, nb)

      is_binary(a) and is_binary(b) ->
        compare_values(a, b)

      is_boolean(a) and is_boolean(b) ->
        compare_values(a, b)

      match?({:cel_bytes, _}, a) and match?({:cel_bytes, _}, b) ->
        compare_values(elem(a, 1), elem(b, 1))

      match?(%Timestamp{}, a) and match?(%Timestamp{}, b) ->
        compare_values(
          DateTime.to_unix(a.datetime, :microsecond),
          DateTime.to_unix(b.datetime, :microsecond)
        )

      match?(%Duration{}, a) and match?(%Duration{}, b) ->
        compare_values(a.microseconds, b.microseconds)

      true ->
        :error
    end
  end

  defp compare_values(a, b) when a < b, do: :lt
  defp compare_values(a, b) when a > b, do: :gt
  defp compare_values(_, _), do: :eq

  # ===================================================================
  # Overflow checking
  # ===================================================================

  defp check_int(v) when v >= @int64_min and v <= @int64_max, do: {:cel_int, v}
  defp check_int(_), do: cel_error("integer overflow")

  defp check_uint(v) when v >= 0 and v <= @uint64_max, do: {:cel_uint, v}
  defp check_uint(_), do: cel_error("unsigned integer overflow")

  @int32_min -2_147_483_648
  @int32_max 2_147_483_647

  defp check_enum_int32_range(v) when v >= @int32_min and v <= @int32_max, do: :ok
  defp check_enum_int32_range(_), do: cel_error("enum value out of range")

  # CEL timestamp range: 0001-01-01 to 9999-12-31
  @min_ts_year 1
  @max_ts_year 9999
  defp check_timestamp(%Timestamp{datetime: dt} = ts) do
    if dt.year >= @min_ts_year and dt.year <= @max_ts_year do
      ts
    else
      cel_error("timestamp overflow")
    end
  end

  # Convert signed int64 to unsigned 64-bit representation
  defp to_uint64_bits(v) when v >= 0, do: v
  defp to_uint64_bits(v), do: Bitwise.band(v, @uint64_max)

  # Convert unsigned 64-bit back to signed int64
  defp int64_from_bits(v) when v > @int64_max, do: {:cel_int, v - @uint64_max - 1}
  defp int64_from_bits(v), do: {:cel_int, v}

  defp cel_lte?(a, b), do: cel_order(a, b) in [:lt, :eq]

  # ===================================================================
  # Standard functions
  # ===================================================================

  defp call_function(name, args, env) do
    case Environment.get_function(env, name) do
      {:ok, func} -> apply(func, unwrap_args(args))
      :error -> call_builtin(name, args, env)
    end
  end

  defp call_builtin("size", [arg], _env) do
    case arg do
      s when is_binary(s) -> {:cel_int, String.length(s)}
      l when is_list(l) -> {:cel_int, length(l)}
      {:cel_bytes, b} -> {:cel_int, byte_size(b)}
      %Timestamp{} -> cel_error("no_matching_overload: size() on timestamp")
      %Duration{} -> cel_error("no_matching_overload: size() on duration")
      m when is_map(m) -> {:cel_int, map_size(m)}
      _ -> cel_error("no_matching_overload: size() on #{cel_typeof(arg)}")
    end
  end

  defp call_builtin("type", [arg], _env) do
    case arg do
      v when is_boolean(v) ->
        :bool

      {:cel_int, _} ->
        :int

      {:cel_uint, _} ->
        :uint

      v when is_float(v) ->
        :double

      v when is_binary(v) ->
        :string

      {:cel_bytes, _} ->
        :bytes

      v when is_list(v) ->
        :list

      nil ->
        :null_type

      %Timestamp{} ->
        {:cel_type, "google.protobuf.Timestamp"}

      %Duration{} ->
        {:cel_type, "google.protobuf.Duration"}

      %Optional{} ->
        :optional_type

      {:cel_ip, _} ->
        {:cel_type, "net.IP"}

      {:cel_cidr, _, _} ->
        {:cel_type, "net.CIDR"}

      {:cel_struct, type_name, _} ->
        {:cel_type, type_name}

      v when is_map(v) ->
        :map

      v
      when is_atom(v) and
             v in [
               :bool,
               :int,
               :uint,
               :double,
               :string,
               :bytes,
               :list,
               :map,
               :type,
               :null_type,
               :optional_type
             ] ->
        :type

      {:cel_type, _} ->
        :type

      _ ->
        :dyn
    end
  end

  defp call_builtin("int", [arg], _env) do
    case arg do
      {:cel_int, _} = v ->
        v

      {:cel_uint, v} ->
        check_int(v)

      v when is_float(v) ->
        check_int(trunc(v))

      v when is_binary(v) ->
        case Integer.parse(v) do
          {n, ""} -> check_int(n)
          _ -> cel_error("cannot convert '#{v}' to int")
        end

      true ->
        {:cel_int, 1}

      false ->
        {:cel_int, 0}

      %Timestamp{} = t ->
        {:cel_int, Timestamp.to_unix(t)}

      v when is_integer(v) ->
        check_int(v)

      _ ->
        cel_error("no_matching_overload: int() on #{cel_typeof(arg)}")
    end
  end

  defp call_builtin("uint", [arg], _env) do
    case arg do
      {:cel_uint, _} = v ->
        v

      {:cel_int, v} ->
        check_uint(v)

      v when is_float(v) ->
        check_uint(trunc(v))

      v when is_binary(v) ->
        case Integer.parse(v) do
          {n, ""} -> check_uint(n)
          _ -> cel_error("cannot convert '#{v}' to uint")
        end

      v when is_integer(v) ->
        check_uint(v)

      _ ->
        cel_error("no_matching_overload: uint() on #{cel_typeof(arg)}")
    end
  end

  defp call_builtin("double", [arg], _env) do
    case arg do
      v when is_float(v) ->
        v

      {:cel_int, v} ->
        v * 1.0

      {:cel_uint, v} ->
        v * 1.0

      "NaN" ->
        :nan

      "Infinity" ->
        :infinity

      "-Infinity" ->
        :neg_infinity

      v when is_binary(v) ->
        case Float.parse(v) do
          {f, ""} ->
            f

          _ ->
            case Integer.parse(v) do
              {n, ""} -> n * 1.0
              _ -> cel_error("cannot convert '#{v}' to double")
            end
        end

      v when is_integer(v) ->
        v * 1.0

      _ ->
        cel_error("no_matching_overload: double() on #{cel_typeof(arg)}")
    end
  end

  defp call_builtin("string", [arg], _env) do
    case arg do
      v when is_binary(v) -> v
      {:cel_int, v} -> Integer.to_string(v)
      {:cel_uint, v} -> Integer.to_string(v)
      v when is_float(v) -> Float.to_string(v)
      :nan -> "NaN"
      :infinity -> "Infinity"
      :neg_infinity -> "-Infinity"
      true -> "true"
      false -> "false"
      nil -> "null"
      {:cel_bytes, v} -> v
      %Timestamp{} = t -> Timestamp.to_string(t)
      %Duration{} = d -> Duration.to_string(d)
      {:cel_ip, addr} -> List.to_string(:inet.ntoa(addr))
      {:cel_cidr, addr, prefix} -> List.to_string(:inet.ntoa(addr)) <> "/" <> Integer.to_string(prefix)
      v when is_integer(v) -> Integer.to_string(v)
      _ -> cel_error("no_matching_overload: string() on #{cel_typeof(arg)}")
    end
  end

  defp call_builtin("bytes", [arg], _env) do
    case arg do
      {:cel_bytes, _} = v -> v
      v when is_binary(v) -> {:cel_bytes, v}
      _ -> cel_error("no_matching_overload: bytes() on #{cel_typeof(arg)}")
    end
  end

  @bool_true_strings ~w(true True TRUE t 1)
  @bool_false_strings ~w(false False FALSE f 0)

  defp call_builtin("bool", [arg], _env) do
    case arg do
      v when is_boolean(v) -> v
      v when v in @bool_true_strings -> true
      v when v in @bool_false_strings -> false
      v when is_binary(v) -> cel_error("Type conversion error: bool() on #{inspect(v)}")
      _ -> cel_error("no_matching_overload: bool() on #{cel_typeof(arg)}")
    end
  end

  defp call_builtin("timestamp", [arg], _env) do
    case arg do
      %Timestamp{} = t ->
        check_timestamp(t)

      v when is_binary(v) ->
        case Timestamp.parse(v) do
          {:ok, t} -> check_timestamp(t)
          {:error, msg} -> cel_error(msg)
        end

      v when is_integer(v) ->
        check_timestamp(Timestamp.new(DateTime.from_unix!(v)))

      {:cel_int, v} ->
        check_timestamp(Timestamp.new(DateTime.from_unix!(v)))

      _ ->
        cel_error("no_matching_overload: timestamp() on #{cel_typeof(arg)}")
    end
  end

  defp call_builtin("duration", [arg], _env) do
    case arg do
      %Duration{} = d ->
        d

      v when is_binary(v) ->
        case Duration.parse(v) do
          {:ok, d} -> d
          {:error, msg} -> cel_error(msg)
        end

      _ ->
        cel_error("no_matching_overload: duration() on #{cel_typeof(arg)}")
    end
  end

  defp call_builtin("dyn", [arg], _env), do: arg
  defp call_builtin("has", _args, _env), do: cel_error("has() macro was not properly expanded")

  defp call_builtin("math.least", [arg], _env) when is_list(arg) do
    pairs = Enum.map(arg, fn item -> {to_number(item), item} end)

    if Enum.any?(pairs, fn {n, _} -> is_nil(n) end),
      do: cel_error("no_matching_overload: math.least() requires numeric arguments"),
      else: pairs |> Enum.min_by(fn {n, _} -> n end) |> elem(1)
  end

  defp call_builtin("math.least", args, _env) when length(args) >= 1 do
    pairs = Enum.map(args, fn arg -> {to_number(arg), arg} end)

    if Enum.any?(pairs, fn {n, _} -> is_nil(n) end),
      do: cel_error("no_matching_overload: math.least() requires numeric arguments"),
      else: pairs |> Enum.min_by(fn {n, _} -> n end) |> elem(1)
  end

  defp call_builtin("math.greatest", [arg], _env) when is_list(arg) do
    pairs = Enum.map(arg, fn item -> {to_number(item), item} end)

    if Enum.any?(pairs, fn {n, _} -> is_nil(n) end),
      do: cel_error("no_matching_overload: math.greatest() requires numeric arguments"),
      else: pairs |> Enum.max_by(fn {n, _} -> n end) |> elem(1)
  end

  defp call_builtin("math.greatest", args, _env) when length(args) >= 1 do
    pairs = Enum.map(args, fn arg -> {to_number(arg), arg} end)

    if Enum.any?(pairs, fn {n, _} -> is_nil(n) end),
      do: cel_error("no_matching_overload: math.greatest() requires numeric arguments"),
      else: pairs |> Enum.max_by(fn {n, _} -> n end) |> elem(1)
  end

  # Optional support
  defp call_builtin("optional.of", [arg], _env), do: Optional.of(arg)
  defp call_builtin("optional.none", [], _env), do: Optional.none()
  defp call_builtin("optional.ofNonZeroValue", [arg], _env), do: Optional.of_non_zero_value(arg)

  # matches() as a global function
  defp call_builtin("matches", [target, pattern], _env) when is_binary(target) and is_binary(pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} -> Regex.match?(regex, target)
      {:error, _} -> cel_error("invalid regex pattern: #{pattern}")
    end
  end

  # Encoding extensions
  defp call_builtin("base64.encode", [{:cel_bytes, v}], _env), do: Base.encode64(v)
  defp call_builtin("base64.encode", [v], _env) when is_binary(v), do: Base.encode64(v)

  defp call_builtin("base64.decode", [v], _env) when is_binary(v) do
    with :error <- Base.decode64(v),
         :error <- Base.decode64(v, padding: false) do
      cel_error("base64 decode error")
    else
      {:ok, decoded} -> {:cel_bytes, decoded}
    end
  end

  # Math extensions (double → double only)
  defp call_builtin("math.ceil", [v], _env) when is_float(v), do: Float.ceil(v) * 1.0
  defp call_builtin("math.ceil", [v], _env) when v in [:infinity, :neg_infinity, :nan], do: v

  defp call_builtin("math.floor", [v], _env) when is_float(v), do: Float.floor(v) * 1.0
  defp call_builtin("math.floor", [v], _env) when v in [:infinity, :neg_infinity, :nan], do: v

  defp call_builtin("math.round", [v], _env) when is_float(v), do: Float.round(v) * 1.0
  defp call_builtin("math.round", [v], _env) when v in [:infinity, :neg_infinity, :nan], do: v

  defp call_builtin("math.trunc", [v], _env) when is_float(v), do: trunc(v) * 1.0
  defp call_builtin("math.trunc", [v], _env) when v in [:infinity, :neg_infinity, :nan], do: v

  defp call_builtin("math.abs", [{:cel_int, v}], _env), do: check_int(abs(v))
  defp call_builtin("math.abs", [{:cel_uint, _} = v], _env), do: v
  defp call_builtin("math.abs", [v], _env) when is_float(v), do: abs(v)

  defp call_builtin("math.sign", [{:cel_int, v}], _env) do
    cond do
      v > 0 -> {:cel_int, 1}
      v < 0 -> {:cel_int, -1}
      true -> {:cel_int, 0}
    end
  end

  defp call_builtin("math.sign", [{:cel_uint, v}], _env) do
    if v > 0, do: {:cel_uint, 1}, else: {:cel_uint, 0}
  end

  defp call_builtin("math.sign", [v], _env) when is_float(v) do
    cond do
      v > 0.0 -> 1.0
      v < 0.0 -> -1.0
      true -> 0.0
    end
  end

  defp call_builtin("math.isNaN", [v], _env) when is_float(v), do: false

  defp call_builtin("math.isNaN", [v], _env) when v in [:nan, :infinity, :neg_infinity], do: v == :nan

  defp call_builtin("math.isInf", [v], _env) when is_float(v), do: false

  defp call_builtin("math.isInf", [v], _env) when v in [:nan, :infinity, :neg_infinity],
    do: v in [:infinity, :neg_infinity]

  defp call_builtin("math.isFinite", [v], _env) when is_float(v), do: true

  defp call_builtin("math.isFinite", [v], _env) when v in [:nan, :infinity, :neg_infinity], do: false

  # Math bit operations
  defp call_builtin("math.bitAnd", [{:cel_int, a}, {:cel_int, b}], _env), do: {:cel_int, Bitwise.band(a, b)}

  defp call_builtin("math.bitAnd", [{:cel_uint, a}, {:cel_uint, b}], _env), do: {:cel_uint, Bitwise.band(a, b)}

  defp call_builtin("math.bitOr", [{:cel_int, a}, {:cel_int, b}], _env), do: {:cel_int, Bitwise.bor(a, b)}

  defp call_builtin("math.bitOr", [{:cel_uint, a}, {:cel_uint, b}], _env), do: {:cel_uint, Bitwise.bor(a, b)}

  defp call_builtin("math.bitXor", [{:cel_int, a}, {:cel_int, b}], _env), do: {:cel_int, Bitwise.bxor(a, b)}

  defp call_builtin("math.bitXor", [{:cel_uint, a}, {:cel_uint, b}], _env), do: {:cel_uint, Bitwise.bxor(a, b)}

  defp call_builtin("math.bitNot", [{:cel_int, a}], _env), do: {:cel_int, Bitwise.bnot(a)}

  defp call_builtin("math.bitNot", [{:cel_uint, a}], _env), do: check_uint(Bitwise.band(Bitwise.bnot(a), @uint64_max))

  # Negative shift on uint is an error
  defp call_builtin("math.bitShiftLeft", [{:cel_uint, _}, {:cel_int, b}], _env) when b < 0,
    do: cel_error("math.bitShiftLeft: negative shift")

  defp call_builtin("math.bitShiftLeft", [{:cel_int, a}, {:cel_int, b}], _env),
    do: int64_from_bits(Bitwise.band(Bitwise.bsl(to_uint64_bits(a), b), @uint64_max))

  defp call_builtin("math.bitShiftLeft", [{:cel_uint, a}, {:cel_int, b}], _env),
    do: {:cel_uint, Bitwise.band(Bitwise.bsl(a, b), @uint64_max)}

  defp call_builtin("math.bitShiftRight", [{:cel_uint, _}, {:cel_int, b}], _env) when b < 0,
    do: cel_error("math.bitShiftRight: negative shift")

  defp call_builtin("math.bitShiftRight", [{:cel_int, a}, {:cel_int, b}], _env),
    do: int64_from_bits(Bitwise.bsr(to_uint64_bits(a), b))

  defp call_builtin("math.bitShiftRight", [{:cel_uint, a}, {:cel_int, b}], _env), do: {:cel_uint, Bitwise.bsr(a, b)}

  # Lists extensions
  defp call_builtin("lists.range", [{:cel_int, a}, {:cel_int, b}], _env) do
    if b < a, do: [], else: Enum.map(a..b, &{:cel_int, &1})
  end

  # Sets extensions
  defp call_builtin("sets.contains", [list, sublist], _env) when is_list(list) and is_list(sublist) do
    Enum.all?(sublist, fn item -> Enum.any?(list, &cel_equal?(&1, item)) end)
  end

  defp call_builtin("sets.intersects", [list1, list2], _env) when is_list(list1) and is_list(list2) do
    Enum.any?(list1, fn item -> Enum.any?(list2, &cel_equal?(&1, item)) end)
  end

  defp call_builtin("sets.equivalent", [list1, list2], _env) when is_list(list1) and is_list(list2) do
    Enum.all?(list1, fn item -> Enum.any?(list2, &cel_equal?(&1, item)) end) and
      Enum.all?(list2, fn item -> Enum.any?(list1, &cel_equal?(&1, item)) end)
  end

  # String extension: strings.quote(s) — global function form
  defp call_builtin("strings.quote", [s], _env) when is_binary(s) do
    cel_quote_string(s)
  end

  # --- Network extension: ip(), cidr(), isIP(), ip.isCanonical() ---

  defp call_builtin("ip", [str], _env) when is_binary(str) do
    with :ok <- reject_zone_id(str),
         {:ok, addr} <- :inet.parse_address(String.to_charlist(str)),
         :ok <- reject_ipv4_mapped_ipv6(str, addr) do
      {:cel_ip, addr}
    else
      _ -> cel_error("invalid IP address: #{str}")
    end
  end

  defp call_builtin("ip", [{:cel_ip, _} = ip], _env), do: ip

  defp call_builtin("cidr", [str], _env) when is_binary(str) do
    with [ip_str, prefix_str] <- String.split(str, "/", parts: 2),
         :ok <- reject_zone_id(ip_str),
         {prefix_len, ""} <- Integer.parse(prefix_str),
         {:ok, addr} <- :inet.parse_address(String.to_charlist(ip_str)),
         :ok <- reject_ipv4_mapped_ipv6(ip_str, addr),
         true <- valid_prefix_length?(addr, prefix_len) do
      {:cel_cidr, addr, prefix_len}
    else
      _ -> cel_error("invalid CIDR: #{str}")
    end
  end

  defp call_builtin("isIP", [str], _env) when is_binary(str) do
    with :ok <- reject_zone_id(str),
         {:ok, addr} <- :inet.parse_address(String.to_charlist(str)),
         :ok <- reject_ipv4_mapped_ipv6(str, addr) do
      true
    else
      _ -> false
    end
  end

  defp call_builtin("isIP", [{:cel_cidr, _, _}], _env), do: cel_error("isIP: expected string argument")
  defp call_builtin("isIP", [_], _env), do: false

  defp call_builtin("ip.isCanonical", [str], _env) when is_binary(str) do
    with :ok <- reject_zone_id(str),
         {:ok, addr} <- :inet.parse_address(String.to_charlist(str)),
         :ok <- reject_ipv4_mapped_ipv6(str, addr) do
      canonical = List.to_string(:inet.ntoa(addr))
      str == canonical
    else
      _ -> cel_error("invalid IP address: #{str}")
    end
  end

  # Enum constructor: GlobalEnum(-33) or TestAllTypes.NestedEnum(2)
  # In legacy mode, returns the int value directly
  defp call_builtin(name, [arg], _env) when is_map_key(@enum_values, name) do
    case arg do
      {:cel_int, v} ->
        with :ok <- check_enum_int32_range(v) do
          {:cel_int, v}
        end

      s when is_binary(s) ->
        case get_in(@enum_values, [name, s]) do
          nil -> cel_error("invalid enum value: #{s}")
          int_val -> {:cel_int, int_val}
        end

      _ ->
        cel_error("no_matching_overload: enum constructor on #{cel_typeof(arg)}")
    end
  end

  defp call_builtin(name, _args, _env), do: cel_error("undefined function: #{name}")

  # ===================================================================
  # Standard methods
  # ===================================================================

  defp call_method("contains", target, [substr], _env) when is_binary(target) and is_binary(substr),
    do: String.contains?(target, substr)

  defp call_method("startsWith", target, [prefix], _env) when is_binary(target) and is_binary(prefix),
    do: String.starts_with?(target, prefix)

  defp call_method("endsWith", target, [suffix], _env) when is_binary(target) and is_binary(suffix),
    do: String.ends_with?(target, suffix)

  defp call_method("matches", target, [pattern], _env) when is_binary(target) and is_binary(pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} -> Regex.match?(regex, target)
      {:error, _} -> cel_error("invalid regex pattern: #{pattern}")
    end
  end

  defp call_method("size", target, [], _env) do
    case target do
      s when is_binary(s) -> {:cel_int, String.length(s)}
      l when is_list(l) -> {:cel_int, length(l)}
      {:cel_bytes, b} -> {:cel_int, byte_size(b)}
      %Timestamp{} -> cel_error("no_matching_overload: size() on timestamp")
      %Duration{} -> cel_error("no_matching_overload: size() on duration")
      m when is_map(m) -> {:cel_int, map_size(m)}
      _ -> cel_error("no_matching_overload: size() on #{cel_typeof(target)}")
    end
  end

  # String extension methods
  defp call_method("charAt", target, [{:cel_int, idx}], _env) when is_binary(target) do
    len = String.length(target)

    cond do
      idx == len -> ""
      idx >= 0 and idx < len -> String.at(target, idx)
      true -> cel_error("index out of range: #{idx}")
    end
  end

  defp call_method("indexOf", target, [substr], _env) when is_binary(target) and is_binary(substr) do
    if substr == "" do
      {:cel_int, 0}
    else
      case :binary.match(target, substr) do
        {pos, _len} -> {:cel_int, pos}
        :nomatch -> {:cel_int, -1}
      end
    end
  end

  defp call_method("indexOf", target, [substr, {:cel_int, offset}], _env) when is_binary(target) and is_binary(substr) do
    len = String.length(target)

    cond do
      offset < 0 or offset > len ->
        cel_error("index out of range: #{offset}")

      substr == "" ->
        {:cel_int, offset}

      true ->
        sliced = String.slice(target, offset, len)

        case :binary.match(sliced, substr) do
          {pos, _len} -> {:cel_int, pos + offset}
          :nomatch -> {:cel_int, -1}
        end
    end
  end

  defp call_method("lastIndexOf", target, [substr], _env) when is_binary(target) and is_binary(substr) do
    if substr == "" do
      {:cel_int, String.length(target)}
    else
      case find_last(target, substr) do
        nil -> {:cel_int, -1}
        pos -> {:cel_int, pos}
      end
    end
  end

  defp call_method("lastIndexOf", target, [substr, {:cel_int, offset}], _env)
       when is_binary(target) and is_binary(substr) do
    len = String.length(target)

    cond do
      offset < 0 or offset > len ->
        cel_error("index out of range: #{offset}")

      substr == "" ->
        {:cel_int, offset}

      true ->
        # Take the portion of the string up to offset + length of substr
        # so that a match starting at offset is included
        sliced = String.slice(target, 0, offset + String.length(substr))

        case find_last(sliced, substr) do
          nil -> {:cel_int, -1}
          pos when pos <= offset -> {:cel_int, pos}
          _pos -> {:cel_int, -1}
        end
    end
  end

  # String extension: s.quote() — receiver method form
  defp call_method("quote", target, [], _env) when is_binary(target) do
    cel_quote_string(target)
  end

  defp call_method("lowerAscii", target, [], _env) when is_binary(target), do: String.downcase(target, :ascii)

  defp call_method("upperAscii", target, [], _env) when is_binary(target), do: String.upcase(target, :ascii)

  defp call_method("replace", target, [old, new_str], _env)
       when is_binary(target) and is_binary(old) and is_binary(new_str), do: String.replace(target, old, new_str)

  defp call_method("replace", target, [old, new_str, {:cel_int, count}], _env)
       when is_binary(target) and is_binary(old) and is_binary(new_str) do
    if count < 0,
      do: String.replace(target, old, new_str),
      else:
        target
        |> String.replace(old, new_str, global: false)
        |> apply_replace_n(old, new_str, count - 1)
  end

  defp call_method("split", target, [sep], _env) when is_binary(target) and is_binary(sep), do: String.split(target, sep)

  defp call_method("split", target, [sep, {:cel_int, limit}], _env) when is_binary(target) and is_binary(sep) do
    cond do
      limit < 0 -> String.split(target, sep)
      limit == 0 -> []
      true -> String.split(target, sep, parts: limit)
    end
  end

  defp call_method("substring", target, [{:cel_int, start}], _env) when is_binary(target) do
    len = String.length(target)

    if start < 0 or start > len do
      cel_error("index out of range: #{start}")
    else
      String.slice(target, start, len)
    end
  end

  defp call_method("substring", target, [{:cel_int, start}, {:cel_int, stop}], _env) when is_binary(target) do
    len = String.length(target)

    cond do
      start < 0 or start > len ->
        cel_error("index out of range: #{start}")

      stop < 0 or stop > len ->
        cel_error("index out of range: #{stop}")

      stop < start ->
        cel_error("invalid substring range. start: #{start}, end: #{stop}")

      true ->
        String.slice(target, start, stop - start)
    end
  end

  defp call_method("trim", target, [], _env) when is_binary(target), do: String.trim(target)

  # String extension: join
  defp call_method("join", target, [], _env) when is_list(target) do
    if Enum.all?(target, &is_binary/1),
      do: Enum.join(target, ""),
      else: cel_error("no_matching_overload: join() requires list of strings")
  end

  defp call_method("join", target, [sep], _env) when is_list(target) and is_binary(sep) do
    if Enum.all?(target, &is_binary/1),
      do: Enum.join(target, sep),
      else: cel_error("no_matching_overload: join() requires list of strings")
  end

  # List methods: sort, slice, flatten
  defp call_method("sort", target, [], _env) when is_list(target) do
    Enum.sort(target, &cel_lte?/2)
  end

  defp call_method("slice", target, [{:cel_int, start}, {:cel_int, count}], _env) when is_list(target) do
    Enum.slice(target, start, count)
  end

  defp call_method("flatten", target, [], _env) when is_list(target) do
    List.flatten(target)
  end

  # String extension: format
  defp call_method("format", target, [args], _env) when is_binary(target) and is_list(args) do
    do_format_string(target, args, 0, [])
  end

  defp call_method("reverse", target, [], _env) when is_binary(target), do: String.reverse(target)

  defp call_method("reverse", target, [], _env) when is_list(target), do: Enum.reverse(target)

  # Timestamp accessor methods
  @timestamp_accessors ~w(getFullYear getMonth getDate getDayOfMonth getDayOfWeek getDayOfYear getHours getMinutes getSeconds getMilliseconds)

  defp call_method(name, %Timestamp{} = ts, args, _env) when name in @timestamp_accessors do
    component = timestamp_component(name)

    tz =
      case args do
        [] -> nil
        [tz_str] when is_binary(tz_str) -> tz_str
        _ -> nil
      end

    {:cel_int, Timestamp.get_component(ts, component, tz)}
  end

  # Duration accessor methods
  defp call_method("getHours", %Duration{} = d, [], _env), do: {:cel_int, Duration.get_component(d, :hours)}

  defp call_method("getMinutes", %Duration{} = d, [], _env), do: {:cel_int, Duration.get_component(d, :minutes)}

  defp call_method("getSeconds", %Duration{} = d, [], _env), do: {:cel_int, Duration.get_component(d, :seconds)}

  defp call_method("getMilliseconds", %Duration{} = d, [], _env), do: {:cel_int, Duration.get_component(d, :milliseconds)}

  # Optional methods
  defp call_method("hasValue", %Optional{} = opt, [], _env), do: Optional.has_value?(opt)

  defp call_method("value", %Optional{has_value: true, value: v}, [], _env), do: v

  defp call_method("value", %Optional{has_value: false}, [], _env), do: cel_error("optional.none() dereference")

  defp call_method("orValue", %Optional{} = opt, [default], _env), do: Optional.or_value(opt, default)

  defp call_method("or", %Optional{} = opt, [%Optional{} = other], _env), do: Optional.or_optional(opt, other)

  # --- Network extension: IP methods ---

  defp call_method("family", {:cel_ip, addr}, [], _env) do
    with {:ok, family} <- ip_family(addr) do
      {:cel_int, family}
    end
  end

  defp call_method("isLoopback", {:cel_ip, addr}, [], _env), do: ip_is_loopback?(addr)

  defp call_method("isUnspecified", {:cel_ip, addr}, [], _env), do: ip_is_unspecified?(addr)

  defp call_method("isGlobalUnicast", {:cel_ip, addr}, [], _env), do: ip_is_global_unicast?(addr)

  defp call_method("isLinkLocalMulticast", {:cel_ip, addr}, [], _env), do: ip_is_link_local_multicast?(addr)

  defp call_method("isLinkLocalUnicast", {:cel_ip, addr}, [], _env), do: ip_is_link_local_unicast?(addr)

  # --- Network extension: CIDR methods ---

  defp call_method("containsIP", {:cel_cidr, _, _} = cidr, [arg], _env) do
    with {:ok, ip_addr} <- resolve_ip_arg(arg) do
      cidr_contains_ip?(cidr, ip_addr)
    end
  end

  defp call_method("containsCIDR", {:cel_cidr, _, _} = outer, [arg], _env) do
    with {:ok, inner} <- resolve_cidr_arg(arg) do
      cidr_contains_cidr?(outer, inner)
    end
  end

  defp call_method("ip", {:cel_cidr, addr, _prefix}, [], _env), do: {:cel_ip, addr}

  defp call_method("masked", {:cel_cidr, addr, prefix}, [], _env) do
    masked_addr = apply_mask(addr, prefix)
    {:cel_cidr, masked_addr, prefix}
  end

  defp call_method("prefixLength", {:cel_cidr, _addr, prefix}, [], _env), do: {:cel_int, prefix}

  # Protobuf struct field access as method
  defp call_method(name, target, [], _env) when is_struct(target) do
    atom_name = String.to_existing_atom(name)

    if Map.has_key?(target, atom_name) do
      normalize(Map.get(target, atom_name))
    else
      cel_error("no_such_field: #{name}")
    end
  rescue
    ArgumentError -> cel_error("no_such_field: #{name}")
  end

  # Fallback to custom functions
  defp call_method(name, target, args, env) do
    all_args = [target | args]

    case Environment.get_function(env, name) do
      {:ok, func} -> apply(func, unwrap_args(all_args))
      :error -> cel_error("no_matching_overload: #{name}() on #{cel_typeof(target)}")
    end
  end

  # ===================================================================
  # Helpers
  # ===================================================================

  defp timestamp_component("getFullYear"), do: :full_year
  defp timestamp_component("getMonth"), do: :month
  defp timestamp_component("getDate"), do: :date
  defp timestamp_component("getDayOfMonth"), do: :day_of_month
  defp timestamp_component("getDayOfWeek"), do: :day_of_week
  defp timestamp_component("getDayOfYear"), do: :day_of_year
  defp timestamp_component("getHours"), do: :hours
  defp timestamp_component("getMinutes"), do: :minutes
  defp timestamp_component("getSeconds"), do: :seconds
  defp timestamp_component("getMilliseconds"), do: :milliseconds

  defp cel_typeof({:cel_ip, _}), do: "net.IP"
  defp cel_typeof({:cel_cidr, _, _}), do: "net.CIDR"
  defp cel_typeof({:cel_struct, type_name, _}), do: type_name
  defp cel_typeof({:cel_int, _}), do: "int"
  defp cel_typeof({:cel_uint, _}), do: "uint"
  defp cel_typeof({:cel_bytes, _}), do: "bytes"
  defp cel_typeof(v) when is_boolean(v), do: "bool"
  defp cel_typeof(v) when is_float(v), do: "double"
  defp cel_typeof(v) when is_binary(v), do: "string"
  defp cel_typeof(v) when is_list(v), do: "list"
  defp cel_typeof(nil), do: "null_type"
  defp cel_typeof(%Timestamp{}), do: "timestamp"
  defp cel_typeof(%Duration{}), do: "duration"
  defp cel_typeof(%Optional{}), do: "optional_type"
  defp cel_typeof(v) when is_map(v), do: "map"
  defp cel_typeof(v) when is_integer(v), do: "int"

  defp cel_typeof(v)
       when is_atom(v) and
              v in [
                :bool,
                :int,
                :uint,
                :double,
                :string,
                :bytes,
                :list,
                :map,
                :type,
                :null_type,
                :timestamp,
                :duration,
                :optional_type
              ], do: "type"

  defp cel_typeof({:cel_type, _}), do: "type"

  defp cel_typeof(_), do: "dyn"

  defp unwrap_args(args), do: Enum.map(args, &unwrap_value/1)

  defp unwrap_value({:cel_int, v}), do: v
  defp unwrap_value({:cel_uint, v}), do: v
  defp unwrap_value({:cel_bytes, v}), do: v
  defp unwrap_value(v), do: v

  defp find_last(string, pattern) do
    case :binary.matches(string, pattern) do
      [] -> nil
      matches -> matches |> List.last() |> elem(0)
    end
  end

  # CEL strings.quote: wraps string in double quotes with Go-style escaping
  defp cel_quote_string(s) do
    escaped =
      s
      |> String.graphemes()
      |> Enum.map_join(fn
        "\\" ->
          "\\\\"

        "\"" ->
          "\\\""

        "\n" ->
          "\\n"

        "\t" ->
          "\\t"

        "\r" ->
          "\\r"

        "\a" ->
          "\\a"

        "\b" ->
          "\\b"

        "\f" ->
          "\\f"

        "\v" ->
          "\\v"

        <<c::utf8>> = char ->
          if c >= 0x20 and c != 0x7F do
            char
          else
            # Non-printable ASCII: use \xHH
            "\\x" <> String.pad_leading(Integer.to_string(c, 16), 2, "0")
          end
      end)

    "\"" <> escaped <> "\""
  end

  defp apply_replace_n(str, _old, _new, 0), do: str

  defp apply_replace_n(str, old, new_str, n) do
    case String.split(str, old, parts: 2) do
      [_] -> str
      [before, after_str] -> before <> new_str <> apply_replace_n(after_str, old, new_str, n - 1)
    end
  end

  # Build a qualified function name from AST target + method name
  defp qualified_name(%AST.Ident{name: prefix}, method), do: prefix <> "." <> method

  defp qualified_name(%AST.Select{operand: operand, field: field}, method),
    do: qualified_name(operand, field) <> "." <> method

  defp qualified_name(_, method), do: method

  # ===================================================================
  # String format() implementation
  # ===================================================================

  defp do_format_string("", _args, _idx, acc), do: IO.iodata_to_binary(Enum.reverse(acc))

  defp do_format_string("%" <> rest, args, idx, acc) do
    case do_parse_fmt_spec(rest) do
      {:literal_percent, remaining} ->
        do_format_string(remaining, args, idx, ["%" | acc])

      {:spec, specifier, precision, remaining} ->
        if idx >= length(args) do
          cel_error("index #{idx} out of range")
        else
          arg = Enum.at(args, idx)

          case do_fmt_arg(specifier, precision, arg) do
            {:cel_error, _} = err -> err
            formatted -> do_format_string(remaining, args, idx + 1, [formatted | acc])
          end
        end

      {:error, msg} ->
        cel_error(msg)
    end
  end

  defp do_format_string(<<c::utf8, rest::binary>>, args, idx, acc) do
    do_format_string(rest, args, idx, [<<c::utf8>> | acc])
  end

  defp do_parse_fmt_spec("%" <> rest), do: {:literal_percent, rest}

  defp do_parse_fmt_spec(rest) do
    {precision, rest2} = do_parse_fmt_prec(rest)

    case rest2 do
      "s" <> rem_str ->
        {:spec, :s, precision, rem_str}

      "d" <> rem_str ->
        {:spec, :d, precision, rem_str}

      "f" <> rem_str ->
        {:spec, :f, precision, rem_str}

      "e" <> rem_str ->
        {:spec, :e, precision, rem_str}

      "x" <> rem_str ->
        {:spec, :x, precision, rem_str}

      "X" <> rem_str ->
        {:spec, :upper_x, precision, rem_str}

      "o" <> rem_str ->
        {:spec, :o, precision, rem_str}

      "b" <> rem_str ->
        {:spec, :b, precision, rem_str}

      <<c::utf8, _::binary>> ->
        {:error, "could not parse formatting clause: unrecognized formatting clause \"#{<<c::utf8>>}\""}

      "" ->
        {:error, "could not parse formatting clause: unexpected end of string"}
    end
  end

  defp do_parse_fmt_prec("." <> rest) do
    {digits, remaining} = do_consume_fmt_digits(rest, [])
    prec = if digits == [], do: 0, else: List.to_integer(digits)
    {prec, remaining}
  end

  defp do_parse_fmt_prec(rest), do: {nil, rest}

  defp do_consume_fmt_digits(<<c, rest::binary>>, acc) when c >= ?0 and c <= ?9,
    do: do_consume_fmt_digits(rest, acc ++ [c])

  defp do_consume_fmt_digits(rest, acc), do: {acc, rest}

  defp do_fmt_arg(:s, _p, val), do: do_fmt_str(val)

  defp do_fmt_arg(:d, _p, :nan), do: "NaN"
  defp do_fmt_arg(:d, _p, :infinity), do: "Infinity"
  defp do_fmt_arg(:d, _p, :neg_infinity), do: "-Infinity"
  defp do_fmt_arg(:d, _p, {:cel_int, v}), do: Integer.to_string(v)
  defp do_fmt_arg(:d, _p, {:cel_uint, v}), do: Integer.to_string(v)
  defp do_fmt_arg(:d, _p, v) when is_integer(v), do: Integer.to_string(v)
  defp do_fmt_arg(:d, _p, v) when is_float(v), do: Integer.to_string(trunc(v))

  defp do_fmt_arg(:d, _p, arg),
    do: cel_error("error during formatting: decimal clause can only be used on integers, was given #{do_fmt_type(arg)}")

  defp do_fmt_arg(:f, _p, :nan), do: "NaN"
  defp do_fmt_arg(:f, _p, :infinity), do: "Infinity"
  defp do_fmt_arg(:f, _p, :neg_infinity), do: "-Infinity"
  defp do_fmt_arg(:f, p, {:cel_int, v}), do: do_fmt_fixed(v * 1.0, p)
  defp do_fmt_arg(:f, p, {:cel_uint, v}), do: do_fmt_fixed(v * 1.0, p)
  defp do_fmt_arg(:f, p, v) when is_integer(v), do: do_fmt_fixed(v * 1.0, p)
  defp do_fmt_arg(:f, p, v) when is_float(v), do: do_fmt_fixed(v, p)

  defp do_fmt_arg(:f, _p, arg),
    do:
      cel_error("error during formatting: fixed-point clause can only be used on doubles, was given #{do_fmt_type(arg)}")

  defp do_fmt_arg(:e, _p, :nan), do: "NaN"
  defp do_fmt_arg(:e, _p, :infinity), do: "Infinity"
  defp do_fmt_arg(:e, _p, :neg_infinity), do: "-Infinity"
  defp do_fmt_arg(:e, p, {:cel_int, v}), do: do_fmt_sci(v * 1.0, p)
  defp do_fmt_arg(:e, p, {:cel_uint, v}), do: do_fmt_sci(v * 1.0, p)
  defp do_fmt_arg(:e, p, v) when is_integer(v), do: do_fmt_sci(v * 1.0, p)
  defp do_fmt_arg(:e, p, v) when is_float(v), do: do_fmt_sci(v, p)

  defp do_fmt_arg(:e, _p, arg),
    do: cel_error("error during formatting: scientific clause can only be used on doubles, was given #{do_fmt_type(arg)}")

  defp do_fmt_arg(:x, _p, {:cel_int, v}), do: v |> Integer.to_string(16) |> String.downcase()
  defp do_fmt_arg(:x, _p, {:cel_uint, v}), do: v |> Integer.to_string(16) |> String.downcase()
  defp do_fmt_arg(:x, _p, v) when is_integer(v), do: v |> Integer.to_string(16) |> String.downcase()
  defp do_fmt_arg(:x, _p, v) when is_binary(v), do: do_hex_bytes(v, :lower)
  defp do_fmt_arg(:x, _p, {:cel_bytes, v}), do: do_hex_bytes(v, :lower)

  defp do_fmt_arg(:x, _p, arg),
    do:
      cel_error(
        "error during formatting: only integers, byte buffers, and strings can be formatted as hex, was given #{do_fmt_type(arg)}"
      )

  defp do_fmt_arg(:upper_x, _p, {:cel_int, v}), do: v |> Integer.to_string(16) |> String.upcase()
  defp do_fmt_arg(:upper_x, _p, {:cel_uint, v}), do: v |> Integer.to_string(16) |> String.upcase()

  defp do_fmt_arg(:upper_x, _p, v) when is_integer(v), do: v |> Integer.to_string(16) |> String.upcase()

  defp do_fmt_arg(:upper_x, _p, v) when is_binary(v), do: do_hex_bytes(v, :upper)
  defp do_fmt_arg(:upper_x, _p, {:cel_bytes, v}), do: do_hex_bytes(v, :upper)

  defp do_fmt_arg(:upper_x, _p, arg),
    do:
      cel_error(
        "error during formatting: only integers, byte buffers, and strings can be formatted as hex, was given #{do_fmt_type(arg)}"
      )

  defp do_fmt_arg(:o, _p, {:cel_int, v}), do: Integer.to_string(v, 8)
  defp do_fmt_arg(:o, _p, {:cel_uint, v}), do: Integer.to_string(v, 8)
  defp do_fmt_arg(:o, _p, v) when is_integer(v), do: Integer.to_string(v, 8)

  defp do_fmt_arg(:o, _p, arg),
    do: cel_error("error during formatting: octal clause can only be used on integers, was given #{do_fmt_type(arg)}")

  defp do_fmt_arg(:b, _p, {:cel_int, v}), do: Integer.to_string(v, 2)
  defp do_fmt_arg(:b, _p, {:cel_uint, v}), do: Integer.to_string(v, 2)
  defp do_fmt_arg(:b, _p, v) when is_integer(v), do: Integer.to_string(v, 2)
  defp do_fmt_arg(:b, _p, true), do: "1"
  defp do_fmt_arg(:b, _p, false), do: "0"

  defp do_fmt_arg(:b, _p, arg),
    do:
      cel_error(
        "error during formatting: only integers and bools can be formatted as binary, was given #{do_fmt_type(arg)}"
      )

  defp do_fmt_str(v) when is_binary(v), do: v
  defp do_fmt_str({:cel_int, v}), do: Integer.to_string(v)
  defp do_fmt_str({:cel_uint, v}), do: Integer.to_string(v)
  defp do_fmt_str(v) when is_integer(v), do: Integer.to_string(v)
  defp do_fmt_str(true), do: "true"
  defp do_fmt_str(false), do: "false"
  defp do_fmt_str(nil), do: "null"
  defp do_fmt_str(:nan), do: "NaN"
  defp do_fmt_str(:infinity), do: "Infinity"
  defp do_fmt_str(:neg_infinity), do: "-Infinity"
  defp do_fmt_str({:cel_bytes, v}), do: v
  defp do_fmt_str(v) when is_float(v), do: Float.to_string(v)
  defp do_fmt_str(%Timestamp{} = t), do: Timestamp.to_string(t)
  defp do_fmt_str(%Duration{microseconds: us}), do: Integer.to_string(div(us, 1_000_000)) <> "s"

  defp do_fmt_str(v) when is_list(v) do
    case do_fmt_list(v) do
      {:cel_error, _} = err -> err
      elems -> "[" <> Enum.join(elems, ", ") <> "]"
    end
  end

  defp do_fmt_str(v) when is_map(v) do
    case do_fmt_map(v) do
      {:cel_error, _} = err -> err
      entries -> "{" <> Enum.join(entries, ", ") <> "}"
    end
  end

  defp do_fmt_str(v)
       when is_atom(v) and
              v in [
                :bool,
                :int,
                :uint,
                :double,
                :string,
                :bytes,
                :list,
                :map,
                :type,
                :null_type,
                :timestamp,
                :duration,
                :optional_type
              ], do: Atom.to_string(v)

  defp do_fmt_str(arg) do
    cel_error(
      "error during formatting: string clause can only be used on strings, bools, bytes, ints, doubles, maps, lists, types, durations, and timestamps, was given #{do_fmt_type(arg)}"
    )
  end

  defp do_fmt_list(list) do
    Enum.reduce_while(list, [], fn elem, acc ->
      case do_fmt_str(elem) do
        {:cel_error, _} = err -> {:halt, err}
        s -> {:cont, acc ++ [s]}
      end
    end)
  end

  defp do_fmt_map(map) do
    sorted = map |> Map.to_list() |> Enum.sort_by(fn {k, _} -> do_fmt_key_sort(k) end)

    Enum.reduce_while(sorted, [], fn {k, v}, acc ->
      ks = do_fmt_str(k)
      vs = do_fmt_str(v)

      cond do
        match?({:cel_error, _}, ks) -> {:halt, ks}
        match?({:cel_error, _}, vs) -> {:halt, vs}
        true -> {:cont, acc ++ [ks <> ": " <> vs]}
      end
    end)
  end

  defp do_fmt_key_sort({:cel_int, v}), do: {0, v, ""}
  defp do_fmt_key_sort({:cel_uint, v}), do: {1, v, ""}
  defp do_fmt_key_sort(v) when is_integer(v), do: {0, v, ""}
  defp do_fmt_key_sort(true), do: {3, 1, ""}
  defp do_fmt_key_sort(false), do: {3, 0, ""}
  defp do_fmt_key_sort(v) when is_binary(v), do: {2, 0, v}
  defp do_fmt_key_sort(_), do: {4, 0, ""}

  defp do_hex_bytes(bin, casing) do
    bin
    |> :binary.bin_to_list()
    |> Enum.map_join(fn byte ->
      hex = byte |> Integer.to_string(16) |> String.pad_leading(2, "0")
      if casing == :upper, do: String.upcase(hex), else: String.downcase(hex)
    end)
  end

  defp do_fmt_fixed(v, nil), do: do_fmt_fixed(v, 6)

  defp do_fmt_fixed(v, 0) do
    # Banker's rounding (round half to even)
    floored = :math.floor(v)
    frac = v - floored
    int_floor = trunc(floored)

    rounded =
      cond do
        frac > 0.5 -> int_floor + 1
        frac < 0.5 -> int_floor
        # Exactly 0.5: round to nearest even
        rem(int_floor, 2) == 0 -> int_floor
        true -> int_floor + 1
      end

    Integer.to_string(rounded)
  end

  defp do_fmt_fixed(v, prec), do: ~c"~.#{prec}f" |> :io_lib.format([v]) |> IO.iodata_to_binary()

  defp do_fmt_sci(v, nil), do: do_fmt_sci(v, 6)

  defp do_fmt_sci(v, prec) do
    {sign, abs_v} = if v < 0, do: {"-", -v}, else: {"", v}

    if abs_v == 0.0 do
      sign <> do_fmt_fixed(0.0, prec) <> "e+00"
    else
      exp = abs_v |> :math.log10() |> :math.floor() |> trunc()
      mantissa = abs_v / :math.pow(10, exp)
      m_str = do_fmt_fixed(mantissa, prec)
      e_sign = if exp >= 0, do: "+", else: "-"
      e_str = exp |> abs() |> Integer.to_string() |> String.pad_leading(2, "0")
      sign <> m_str <> "e" <> e_sign <> e_str
    end
  end

  defp do_fmt_type(%Duration{}), do: "google.protobuf.Duration"
  defp do_fmt_type(%Timestamp{}), do: "google.protobuf.Timestamp"
  defp do_fmt_type(v), do: cel_typeof(v)

  # ===================================================================
  # Network extension helpers
  # ===================================================================

  # Reject zone IDs (e.g., "fe80::1%en0")
  defp reject_zone_id(str) do
    if String.contains?(str, "%"), do: :error, else: :ok
  end

  # Reject IPv4-mapped IPv6 addresses in dotted-decimal form (e.g., "::ffff:192.168.0.1")
  # but allow hex form (e.g., "::ffff:c0a8:1") which is valid IPv6
  defp reject_ipv4_mapped_ipv6(str, {0, 0, 0, 0, 0, 0xFFFF, _, _}) do
    if String.match?(str, ~r/\d+\.\d+\.\d+\.\d+/), do: :error, else: :ok
  end

  defp reject_ipv4_mapped_ipv6(_str, _addr), do: :ok

  defp valid_prefix_length?(addr, prefix) when tuple_size(addr) == 4, do: prefix >= 0 and prefix <= 32
  defp valid_prefix_length?(addr, prefix) when tuple_size(addr) == 8, do: prefix >= 0 and prefix <= 128
  defp valid_prefix_length?(_, _), do: false

  # IP equality: normalize IPv4-mapped IPv6 (::ffff:x:y) to IPv4 for comparison
  defp ip_equal?({:cel_ip, a}, {:cel_ip, b}), do: normalize_ip(a) == normalize_ip(b)

  defp normalize_ip({0, 0, 0, 0, 0, 0xFFFF, hi, lo}) do
    {Bitwise.bsr(hi, 8), Bitwise.band(hi, 0xFF), Bitwise.bsr(lo, 8), Bitwise.band(lo, 0xFF)}
  end

  defp normalize_ip(addr), do: addr

  defp ip_family(addr) when tuple_size(addr) == 4, do: {:ok, 4}
  defp ip_family(addr) when tuple_size(addr) == 8, do: {:ok, 6}
  defp ip_family(_), do: cel_error("unknown IP family")

  # IPv4 semantics
  defp ip_is_loopback?({127, _, _, _}), do: true
  defp ip_is_loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp ip_is_loopback?(_), do: false

  defp ip_is_unspecified?({0, 0, 0, 0}), do: true
  defp ip_is_unspecified?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  defp ip_is_unspecified?(_), do: false

  defp ip_is_link_local_unicast?({169, 254, _, _}), do: true

  defp ip_is_link_local_unicast?({a, _, _, _, _, _, _, _}) do
    # fe80::/10 means top 10 bits are 1111111010
    Bitwise.band(a, 0xFFC0) == 0xFE80
  end

  defp ip_is_link_local_unicast?(_), do: false

  defp ip_is_link_local_multicast?({224, 0, 0, _}), do: true

  defp ip_is_link_local_multicast?({0xFF02, _, _, _, _, _, _, _}), do: true

  defp ip_is_link_local_multicast?(_), do: false

  defp ip_is_global_unicast?(addr) when tuple_size(addr) == 4 do
    not ip_is_loopback?(addr) and
      not ip_is_unspecified?(addr) and
      not ip_is_link_local_unicast?(addr) and
      not ip_is_link_local_multicast?(addr) and
      not ip_is_multicast_v4?(addr) and
      addr != {255, 255, 255, 255}
  end

  defp ip_is_global_unicast?(addr) when tuple_size(addr) == 8 do
    {a, _, _, _, _, _, _, _} = addr
    # 2000::/3 — top 3 bits are 001
    Bitwise.band(a, 0xE000) == 0x2000
  end

  defp ip_is_global_unicast?(_), do: false

  defp ip_is_multicast_v4?({a, _, _, _}) when a >= 224 and a <= 239, do: true
  defp ip_is_multicast_v4?(_), do: false

  defp resolve_ip_arg({:cel_ip, addr}), do: {:ok, addr}

  defp resolve_ip_arg(str) when is_binary(str) do
    case :inet.parse_address(String.to_charlist(str)) do
      {:ok, addr} -> {:ok, addr}
      _ -> cel_error("invalid IP address: #{str}")
    end
  end

  defp resolve_ip_arg(other), do: cel_error("expected IP or string, got #{cel_typeof(other)}")

  defp resolve_cidr_arg({:cel_cidr, _, _} = cidr), do: {:ok, cidr}

  defp resolve_cidr_arg(str) when is_binary(str) do
    with [ip_str, prefix_str] <- String.split(str, "/", parts: 2),
         {prefix_len, ""} <- Integer.parse(prefix_str),
         {:ok, addr} <- :inet.parse_address(String.to_charlist(ip_str)),
         true <- valid_prefix_length?(addr, prefix_len) do
      {:ok, {:cel_cidr, addr, prefix_len}}
    else
      _ -> cel_error("invalid CIDR: #{str}")
    end
  end

  defp resolve_cidr_arg(other), do: cel_error("expected CIDR or string, got #{cel_typeof(other)}")

  defp cidr_contains_ip?({:cel_cidr, net_addr, prefix}, ip_addr) do
    if tuple_size(net_addr) == tuple_size(ip_addr) do
      masked_net = apply_mask(net_addr, prefix)
      masked_ip = apply_mask(ip_addr, prefix)
      masked_net == masked_ip
    else
      false
    end
  end

  defp cidr_contains_cidr?({:cel_cidr, outer_addr, outer_prefix}, {:cel_cidr, inner_addr, inner_prefix}) do
    with true <- tuple_size(outer_addr) == tuple_size(inner_addr),
         true <- outer_prefix <= inner_prefix do
      masked_outer = apply_mask(outer_addr, outer_prefix)
      masked_inner = apply_mask(inner_addr, outer_prefix)
      masked_outer == masked_inner
    else
      _ -> false
    end
  end

  defp apply_mask(addr, prefix) when tuple_size(addr) == 4 do
    bits = ip4_to_integer(addr)
    mask = if prefix == 0, do: 0, else: Bitwise.band(0xFFFFFFFF, Bitwise.bsl(0xFFFFFFFF, 32 - prefix))
    integer_to_ip4(Bitwise.band(bits, mask))
  end

  defp apply_mask(addr, prefix) when tuple_size(addr) == 8 do
    bits = ip6_to_integer(addr)

    mask =
      if prefix == 0,
        do: 0,
        else:
          Bitwise.band(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, Bitwise.bsl(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128 - prefix))

    integer_to_ip6(Bitwise.band(bits, mask))
  end

  defp ip4_to_integer({a, b, c, d}) do
    a |> Bitwise.bsl(24) |> Bitwise.bor(Bitwise.bsl(b, 16)) |> Bitwise.bor(Bitwise.bsl(c, 8)) |> Bitwise.bor(d)
  end

  defp integer_to_ip4(n) do
    {Bitwise.band(Bitwise.bsr(n, 24), 0xFF), Bitwise.band(Bitwise.bsr(n, 16), 0xFF),
     Bitwise.band(Bitwise.bsr(n, 8), 0xFF), Bitwise.band(n, 0xFF)}
  end

  defp ip6_to_integer({a, b, c, d, e, f, g, h}) do
    a
    |> Bitwise.bsl(112)
    |> Bitwise.bor(Bitwise.bsl(b, 96))
    |> Bitwise.bor(Bitwise.bsl(c, 80))
    |> Bitwise.bor(Bitwise.bsl(d, 64))
    |> Bitwise.bor(Bitwise.bsl(e, 48))
    |> Bitwise.bor(Bitwise.bsl(f, 32))
    |> Bitwise.bor(Bitwise.bsl(g, 16))
    |> Bitwise.bor(h)
  end

  defp integer_to_ip6(n) do
    {Bitwise.band(Bitwise.bsr(n, 112), 0xFFFF), Bitwise.band(Bitwise.bsr(n, 96), 0xFFFF),
     Bitwise.band(Bitwise.bsr(n, 80), 0xFFFF), Bitwise.band(Bitwise.bsr(n, 64), 0xFFFF),
     Bitwise.band(Bitwise.bsr(n, 48), 0xFFFF), Bitwise.band(Bitwise.bsr(n, 32), 0xFFFF),
     Bitwise.band(Bitwise.bsr(n, 16), 0xFFFF), Bitwise.band(n, 0xFFFF)}
  end
end
