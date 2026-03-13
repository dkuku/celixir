defmodule Celixir.CelSpecHelpers do
  @moduledoc false

  import ExUnit.Assertions

  # Tests we know we can't pass yet (proto-specific, unsupported features)
  @skip_tests MapSet.new([
                # Proto field access — evaluator doesn't have proto schema for these fields
                {"type_deductions", "field_access", "map_bool_int"},
                {"type_deductions", "legacy_nullable_types", "null_assignable_to_duration_parameter_candidate"},
                {"type_deductions", "legacy_nullable_types", "null_assignable_to_timestamp_parameter_candidate"},
                # Proto Any — var test needs textproto parser support for nested Any object_value bindings
                {"dynamic", "any", "var"},
                # Proto Any field_assign proto3 — needs container resolution for correct type_url
                {"dynamic", "any", "field_assign_proto3"},
                # Nanosecond precision — Elixir DateTime only supports microseconds
                {"timestamps", "timestamp_conversions", "toString_timestamp_nanos"},
                # Float32 narrowing — requires single-precision float emulation
                {"dynamic", "float", "literal_not_double"},
                {"dynamic", "float", "field_assign_proto2_subnorm"},
                # Strong enum mode — requires enum types (not just ints)
                {"enums", "strong_proto2", "type_global"},
                {"enums", "strong_proto2", "type_nested"},
                {"enums", "strong_proto2", "field_type"},
                {"enums", "strong_proto3", "type_global"},
                {"enums", "strong_proto3", "type_nested"},
                {"enums", "strong_proto3", "field_type"},
                # Proto2/Proto3 has() default semantics — requires container-aware proto version tracking
                {"proto3", "has", "single_set_to_default"},
                {"proto3", "has", "single_enum_set_zero"},
                # Proto2 scalar_with_default — proto2 field defaults differ from proto3
                {"proto2", "empty_field", "scalar_with_default"},
                # Proto Any literal encoding — requires proto binary serialization
                {"proto2", "literal_wellknown", "any"},
                {"proto3", "literal_wellknown", "any"},
                # Proto literal_wellknown — requires proto-encoded representation for Duration/Timestamp/Struct
                {"proto2", "literal_wellknown", "duration"},
                {"proto3", "literal_wellknown", "duration"},
                {"proto2", "literal_wellknown", "timestamp"},
                {"proto3", "literal_wellknown", "timestamp"},
                {"proto2", "literal_wellknown", "struct"},
                {"proto3", "literal_wellknown", "struct"},
                # Block ext with deeply nested proto struct bindings — textproto parser lacks nested type awareness
                {"block_ext", "basic", "select_nested_1"},
                {"block_ext", "basic", "select_nested_message_map_index_1"},
                {"block_ext", "basic", "select_nested_message_map_index_2"},
                {"block_ext", "basic", "presence_test_with_ternary_nested"},
                # Proto2 extensions — requires proto.hasExt() with qualified extension descriptors
                {"proto2_ext", "has_ext", "package_scoped_int32"},
                {"proto2_ext", "has_ext", "package_scoped_nested_ext"},
                {"proto2_ext", "has_ext", "package_scoped_test_all_types_ext"},
                {"proto2_ext", "has_ext", "package_scoped_test_all_types_nested_enum_ext"},
                {"proto2_ext", "has_ext", "package_scoped_repeated_test_all_types"},
                # Namespace/container resolution — requires container-aware identifier resolution
                {"namespace", "namespace", "self_eval_container_lookup"},
                {"namespace", "namespace", "self_eval_container_lookup_unchecked"},
                {"namespace", "namespace_shadowing", "basic"},
                {"namespace", "namespace_shadowing", "disambiguation"},
                {"namespace", "namespace_shadowing", "comprehension_shadowing_disambiguation"},
                {"namespace", "namespace_shadowing", "comprehension_shadowing_selector"},
                {"namespace", "namespace_shadowing", "comprehension_shadowing_selector_parse_only"},
                {"namespace", "namespace_shadowing", "comprehension_shadowing_namespaced_selector_disambiguation"},
                # Nanosecond precision in wrapper to_json (Elixir DateTime only supports microseconds)
                {"wrappers", "timestamp", "to_json"}
              ])

  def skip_tests, do: @skip_tests

  def run_cel_spec_check_test(test) do
    {:ok, ast} = Celixir.parse(test.expr)

    # Build type environment from test's type_env declarations
    env = build_check_env(test[:type_env] || [])

    inferred = Celixir.Checker.infer(ast, env) |> Celixir.Checker.finalize_type()
    expected = test[:deduced_type]

    assert(
      inferred == expected,
      "#{test.expr}: expected type #{inspect(expected)}, got #{inspect(inferred)}"
    )
  end

  defp build_check_env(type_env_entries) do
    variables =
      type_env_entries
      |> Enum.filter(&(&1.kind == :ident))
      |> Map.new(&{&1.name, &1.type})

    functions =
      type_env_entries
      |> Enum.filter(&(&1.kind == :function))
      |> Map.new(&{&1.name, &1.overloads})

    %{variables: variables, functions: functions}
  end

  def run_cel_spec_test(_file, _section, test) do
    bindings = convert_bindings(test.bindings)

    case Celixir.eval(test.expr, bindings) do
      {:ok, actual} ->
        if test.eval_error do
          flunk("Expected error for: #{test.expr}, but got: #{inspect(actual)}")
        else
          assert_value_match(test.value, actual, test.expr)
        end

      {:error, msg} ->
        if test.eval_error do
          :ok
        else
          flunk("Unexpected error for: #{test.expr} — #{msg}")
        end
    end
  end

  def convert_bindings(bindings) when map_size(bindings) == 0, do: %{}

  def convert_bindings(bindings) do
    Map.new(bindings, fn {key, typed_val} -> {key, convert_value(typed_val)} end)
  end

  def convert_value({:int64, v}), do: v
  def convert_value({:uint64, v}), do: v
  def convert_value({:double, v}) when is_number(v), do: v * 1.0
  def convert_value({:double, v}) when is_atom(v), do: v
  def convert_value({:bool, v}), do: v
  def convert_value({:string, v}), do: v
  def convert_value({:bytes, v}), do: {:cel_bytes, v}
  def convert_value({:null, _}), do: nil

  def convert_value({:duration, seconds, nanos}) do
    micros = seconds * 1_000_000 + div(nanos, 1000)
    Celixir.Types.Duration.new(micros)
  end

  def convert_value({:timestamp, seconds, nanos}) do
    micros = seconds * 1_000_000 + div(nanos, 1000)
    {:ok, dt} = DateTime.from_unix(micros, :microsecond)
    Celixir.Types.Timestamp.new(dt)
  end

  def convert_value({:list, items}), do: Enum.map(items, &convert_value/1)

  def convert_value({:map, entries}) do
    Map.new(entries, fn {k, v} -> {convert_value(k), convert_value(v)} end)
  end

  def convert_value({:object, type_name, fields}) do
    convert_proto_object(type_name, fields)
  end

  def convert_value(nil), do: nil

  defp convert_proto_object(type_name, fields) do
    case type_name do
      "google.protobuf.BoolValue" ->
        Map.get(fields, "value", false)

      "google.protobuf.Int32Value" ->
        Map.get(fields, "value", 0)

      "google.protobuf.Int64Value" ->
        Map.get(fields, "value", 0)

      "google.protobuf.UInt32Value" ->
        Map.get(fields, "value", 0)

      "google.protobuf.UInt64Value" ->
        Map.get(fields, "value", 0)

      "google.protobuf.FloatValue" ->
        Map.get(fields, "value", 0.0) * 1.0

      "google.protobuf.DoubleValue" ->
        Map.get(fields, "value", 0.0) * 1.0

      "google.protobuf.StringValue" ->
        Map.get(fields, "value", "")

      "google.protobuf.BytesValue" ->
        Map.get(fields, "value", "")

      "google.protobuf.Value" ->
        convert_proto_value(fields)

      "google.protobuf.Struct" ->
        convert_proto_struct(fields)

      "google.protobuf.ListValue" ->
        convert_proto_list(fields)

      "google.protobuf.Any" ->
        # Auto-unpack Any bindings to their inner message
        Celixir.Proto.unpack_any(fields)

      _ ->
        {:cel_struct, type_name, fields}
    end
  end

  defp convert_proto_value(fields) do
    cond do
      Map.has_key?(fields, "null_value") -> nil
      Map.has_key?(fields, "bool_value") -> Map.get(fields, "bool_value")
      Map.has_key?(fields, "number_value") -> Map.get(fields, "number_value") * 1.0
      Map.has_key?(fields, "string_value") -> Map.get(fields, "string_value")
      Map.has_key?(fields, "list_value") -> convert_proto_list(Map.get(fields, "list_value"))
      Map.has_key?(fields, "struct_value") -> convert_proto_struct(Map.get(fields, "struct_value"))
      true -> nil
    end
  end

  defp convert_proto_struct(fields) do
    case Map.get(fields, "fields") do
      m when is_map(m) -> Map.new(m, fn {k, v} -> {k, convert_proto_value(v)} end)
      _ -> %{}
    end
  end

  defp convert_proto_list(fields) do
    case Map.get(fields, "values") do
      l when is_list(l) -> Enum.map(l, &convert_proto_value/1)
      _ -> []
    end
  end

  def assert_value_match(nil, _actual, _expr), do: :ok

  def assert_value_match({:null, _}, actual, expr) do
    assert(actual == nil, "#{expr}: expected null, got #{inspect(actual)}")
  end

  def assert_value_match({:bool, expected}, actual, expr) do
    assert(actual == expected, "#{expr}: expected #{expected}, got #{inspect(actual)}")
  end

  def assert_value_match({:int64, expected}, actual, expr) do
    actual_int =
      case actual do
        {:cel_int, v} -> v
        v when is_integer(v) -> v
        _ -> actual
      end

    assert(actual_int == expected, "#{expr}: expected int #{expected}, got #{inspect(actual)}")
  end

  def assert_value_match({:uint64, expected}, actual, expr) do
    actual_uint =
      case actual do
        {:cel_uint, v} -> v
        v when is_integer(v) -> v
        _ -> actual
      end

    assert(actual_uint == expected, "#{expr}: expected uint #{expected}, got #{inspect(actual)}")
  end

  def assert_value_match({:double, expected}, actual, expr) when is_float(actual) do
    assert(
      abs(expected - actual) < 1.0e-10 or (expected == 0.0 and actual == 0.0),
      "#{expr}: expected double #{expected}, got #{actual}"
    )
  end

  def assert_value_match({:double, expected}, actual, expr) when is_atom(actual) do
    assert(actual == expected, "#{expr}: expected #{expected}, got #{inspect(actual)}")
  end

  def assert_value_match({:string, expected}, actual, expr) do
    assert(actual == expected, "#{expr}: expected #{inspect(expected)}, got #{inspect(actual)}")
  end

  def assert_value_match({:bytes, expected}, actual, expr) do
    actual_bytes =
      case actual do
        {:cel_bytes, b} -> b
        b -> b
      end

    assert(
      actual_bytes == expected,
      "#{expr}: expected bytes #{inspect(expected)}, got #{inspect(actual)}"
    )
  end

  def assert_value_match({:list, expected_items}, actual, expr) when is_list(actual) do
    assert(
      length(expected_items) == length(actual),
      "#{expr}: list length mismatch: expected #{length(expected_items)}, got #{length(actual)}"
    )

    expected_items
    |> Enum.zip(actual)
    |> Enum.each(fn {e, a} -> assert_value_match(e, a, expr) end)
  end

  def assert_value_match({:map, expected_entries}, actual, expr) when is_map(actual) do
    expected_map = Map.new(expected_entries, fn {k, v} -> {convert_value(k), v} end)

    assert(
      map_size(expected_map) == map_size(actual),
      "#{expr}: map size mismatch: expected #{map_size(expected_map)}, got #{map_size(actual)}"
    )

    Enum.each(expected_map, fn {k, expected_v} ->
      actual_v = Map.get(actual, k)
      assert_value_match(expected_v, actual_v, expr)
    end)
  end

  def assert_value_match({:type, expected_type}, actual, expr) do
    actual_type =
      case actual do
        {:cel_type, name} -> name
        a when is_atom(a) -> Atom.to_string(a)
        _ -> inspect(actual)
      end

    assert(
      actual_type == expected_type,
      "#{expr}: expected type #{expected_type}, got #{actual_type}"
    )
  end

  def assert_value_match({:object, type_name, expected_fields}, actual, expr) do
    case actual do
      {:cel_struct, actual_type, actual_fields} ->
        assert(
          actual_type == type_name or String.ends_with?(actual_type, "." <> type_name),
          "#{expr}: expected struct type #{type_name}, got #{actual_type}"
        )

        Enum.each(expected_fields, fn {k, v} ->
          assert(Map.has_key?(actual_fields, k), "#{expr}: expected field #{k} not found in struct")
          actual_v = Map.get(actual_fields, k)
          assert_proto_field_match(k, v, actual_v, expr)
        end)

      _ ->
        converted = convert_value({:object, type_name, expected_fields})
        assert(actual == converted, "#{expr}: expected #{inspect(converted)}, got #{inspect(actual)}")
    end
  end

  def assert_value_match(expected, actual, expr) do
    flunk("#{expr}: unhandled value match — expected #{inspect(expected)}, got #{inspect(actual)}")
  end

  defp assert_proto_field_match(field_name, expected, actual, expr) do
    if proto_value_matches?(expected, actual) do
      :ok
    else
      assert(false, "#{expr}: field #{field_name}: expected #{inspect(expected)}, got #{inspect(actual)}")
    end
  end

  defp proto_value_matches?(expected, actual) when expected == actual, do: true

  # Match expected plain map against actual {:cel_struct, _, fields} (e.g. packed Any)
  defp proto_value_matches?(%{} = expected, {:cel_struct, _type, actual_fields}) when map_size(expected) > 0 do
    Enum.all?(expected, fn {k, v} ->
      actual_v = Map.get(actual_fields, k)
      proto_value_matches?(v, actual_v)
    end)
  end

  defp proto_value_matches?(%{"value" => inner}, actual),
    do: normalize_for_compare(actual) == normalize_for_compare(inner)

  defp proto_value_matches?(%{} = e, _actual) when map_size(e) == 0, do: true
  defp proto_value_matches?(%{"bool_value" => v}, actual), do: actual == v
  defp proto_value_matches?(%{"number_value" => v}, actual), do: actual == v * 1.0
  defp proto_value_matches?(%{"string_value" => v}, actual), do: actual == v
  defp proto_value_matches?(%{"null_value" => _}, actual), do: actual == nil

  defp proto_value_matches?(%{"values" => expected_vals}, actual) when is_list(actual) do
    length(expected_vals) == length(actual) and
      expected_vals |> Enum.zip(actual) |> Enum.all?(fn {e, a} -> proto_value_matches?(e, a) end)
  end

  defp proto_value_matches?(%{"fields" => expected_fields}, actual) when is_map(actual) do
    map_size(expected_fields) == map_size(actual) and
      Enum.all?(expected_fields, fn {k, v} ->
        Map.has_key?(actual, k) and proto_value_matches?(v, Map.get(actual, k))
      end)
  end

  defp proto_value_matches?(%{"list_value" => lv}, actual) when is_list(actual), do: proto_value_matches?(lv, actual)
  defp proto_value_matches?(%{"struct_value" => sv}, actual) when is_map(actual), do: proto_value_matches?(sv, actual)

  defp proto_value_matches?(expected, actual) when is_list(expected) and is_list(actual) do
    length(expected) == length(actual) and
      expected |> Enum.zip(actual) |> Enum.all?(fn {e, a} -> proto_value_matches?(e, a) end)
  end

  defp proto_value_matches?(expected, actual), do: normalize_for_compare(actual) == normalize_for_compare(expected)

  defp normalize_for_compare({:cel_int, v}), do: v
  defp normalize_for_compare({:cel_uint, v}), do: v
  defp normalize_for_compare({:cel_bytes, v}), do: v
  defp normalize_for_compare(v), do: v
end
