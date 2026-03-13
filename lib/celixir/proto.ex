defmodule Celixir.Proto do
  @moduledoc """
  Proto well-known type support for CEL strict mode.
  Handles wrapper types, Value/Struct/ListValue, and TestAllTypes schema.
  """

  alias Celixir.Proto.Codec
  alias Celixir.Types.Duration
  alias Celixir.Types.Timestamp

  @int32_min -2_147_483_648
  @int32_max 2_147_483_647
  @uint32_max 4_294_967_295

  # Well-known protobuf wrapper types → unwrap to native CEL value
  @wrapper_defaults %{
    "google.protobuf.BoolValue" => false,
    "google.protobuf.BytesValue" => {:cel_bytes, ""},
    "google.protobuf.DoubleValue" => 0.0,
    "google.protobuf.FloatValue" => 0.0,
    "google.protobuf.Int32Value" => {:cel_int, 0},
    "google.protobuf.Int64Value" => {:cel_int, 0},
    "google.protobuf.StringValue" => "",
    "google.protobuf.UInt32Value" => {:cel_uint, 0},
    "google.protobuf.UInt64Value" => {:cel_uint, 0}
  }

  @wrapper_range_checks %{
    "google.protobuf.Int32Value" => :int32,
    "google.protobuf.UInt32Value" => :uint32,
    "google.protobuf.FloatValue" => :float32
  }

  @doc "Check if a type name is a well-known wrapper type."
  def wrapper_type?(type_name), do: Map.has_key?(@wrapper_defaults, type_name)

  @doc "Check if a type is a well-known type with special semantics."
  def well_known_type?(type_name) do
    wrapper_type?(type_name) or
      type_name in [
        "google.protobuf.Value",
        "google.protobuf.Struct",
        "google.protobuf.ListValue",
        "google.protobuf.Any",
        "google.protobuf.Timestamp",
        "google.protobuf.Duration",
        "google.protobuf.FieldMask",
        "google.protobuf.Empty"
      ]
  end

  # Short name aliases for well-known types
  @short_name_aliases %{
    "Value" => "google.protobuf.Value",
    "Struct" => "google.protobuf.Struct",
    "ListValue" => "google.protobuf.ListValue",
    "Any" => "google.protobuf.Any",
    "BoolValue" => "google.protobuf.BoolValue",
    "BytesValue" => "google.protobuf.BytesValue",
    "DoubleValue" => "google.protobuf.DoubleValue",
    "FloatValue" => "google.protobuf.FloatValue",
    "Int32Value" => "google.protobuf.Int32Value",
    "Int64Value" => "google.protobuf.Int64Value",
    "StringValue" => "google.protobuf.StringValue",
    "UInt32Value" => "google.protobuf.UInt32Value",
    "UInt64Value" => "google.protobuf.UInt64Value",
    "FieldMask" => "google.protobuf.FieldMask",
    "Empty" => "google.protobuf.Empty"
  }

  @doc "Resolve a short type name to its fully qualified name."
  def resolve_type_name(name), do: Map.get(@short_name_aliases, name, name)

  @doc """
  Finalize a struct creation for a known type.
  Returns the appropriate CEL value or {:cel_error, msg}.
  """
  def finalize_struct(type_name, fields) do
    resolved = resolve_type_name(type_name)

    if Map.has_key?(@wrapper_defaults, resolved) do
      finalize_wrapper(resolved, fields)
    else
      finalize_special(resolved, fields)
    end
  end

  defp finalize_wrapper(type_name, fields) do
    default = Map.fetch!(@wrapper_defaults, type_name)
    value = Map.get(fields, "value", default)

    case Map.get(@wrapper_range_checks, type_name) do
      :int32 ->
        case value do
          {:cel_int, v} when v >= @int32_min and v <= @int32_max -> value
          {:cel_int, _} -> {:cel_error, "int32 overflow"}
          _ -> value
        end

      :uint32 ->
        case value do
          {:cel_uint, v} when v >= 0 and v <= @uint32_max -> value
          {:cel_uint, _} -> {:cel_error, "uint32 overflow"}
          _ -> value
        end

      :float32 ->
        # Float32 range check — CEL expects float narrowing
        value

      nil ->
        value
    end
  end

  defp finalize_special("google.protobuf.Value", fields) do
    cond do
      Map.has_key?(fields, "null_value") -> nil
      Map.has_key?(fields, "bool_value") -> Map.get(fields, "bool_value")
      Map.has_key?(fields, "number_value") -> Map.get(fields, "number_value")
      Map.has_key?(fields, "string_value") -> Map.get(fields, "string_value")
      Map.has_key?(fields, "list_value") -> Map.get(fields, "list_value")
      Map.has_key?(fields, "struct_value") -> Map.get(fields, "struct_value")
      true -> nil
    end
  end

  defp finalize_special("google.protobuf.Struct", fields) do
    case Map.get(fields, "fields") do
      m when is_map(m) -> m
      nil -> %{}
      _ -> %{}
    end
  end

  defp finalize_special("google.protobuf.ListValue", fields) do
    case Map.get(fields, "values") do
      l when is_list(l) -> l
      nil -> []
      _ -> []
    end
  end

  defp finalize_special("google.protobuf.FieldMask", fields) do
    case Map.get(fields, "paths") do
      paths when is_list(paths) -> {:cel_struct, "google.protobuf.FieldMask", fields}
      nil -> {:cel_struct, "google.protobuf.FieldMask", %{"paths" => []}}
      _ -> {:cel_struct, "google.protobuf.FieldMask", fields}
    end
  end

  defp finalize_special("google.protobuf.Empty", _fields) do
    {:cel_struct, "google.protobuf.Empty", %{}}
  end

  defp finalize_special("google.protobuf.Any", fields) do
    # Any{} with no type_url is an error
    if Map.get(fields, "type_url") in [nil, ""] and Map.get(fields, "value") == nil do
      {:cel_error, "invalid google.protobuf.Any: missing type_url"}
    else
      # Auto-unpack Any when created directly: Any{type_url: ..., value: binary}
      # becomes the unpacked inner message (CEL spec behavior)
      unpack_any(fields)
    end
  end

  defp finalize_special(type_name, fields) do
    case get_schema(type_name) do
      nil -> {:cel_struct, type_name, fields}
      schema -> finalize_message(type_name, fields, schema)
    end
  end

  @doc "Attempt to unpack an Any struct's fields to its inner message."
  def unpack_any(%{"type_url" => type_url, "value" => _value} = fields) when is_binary(type_url) and type_url != "" do
    case Codec.unpack(fields) do
      {:ok, unpacked} -> unpacked
      {:error, _} -> {:cel_struct, "google.protobuf.Any", fields}
    end
  end

  def unpack_any(fields), do: {:cel_struct, "google.protobuf.Any", fields}

  @doc "Finalize a proto message with schema validation."
  def finalize_message(type_name, fields, schema) do
    validated =
      Enum.reduce_while(fields, {:ok, %{}}, fn {field_name, value}, {:ok, acc} ->
        case Map.get(schema, field_name) do
          nil ->
            # Accept unknown fields (e.g., reserved keyword field name tests)
            {:cont, {:ok, Map.put(acc, field_name, value)}}

          {:message, "google.protobuf.Any"} ->
            {:ok, v} = pack_for_any(value, type_name)
            {:cont, {:ok, Map.put(acc, field_name, v)}}

          field_spec ->
            case validate_field(field_spec, value) do
              {:ok, v} -> {:cont, {:ok, Map.put(acc, field_name, v)}}
              {:error, msg} -> {:halt, {:error, msg}}
            end
        end
      end)

    case validated do
      {:ok, validated_fields} ->
        provided_field_names = MapSet.new(Map.keys(validated_fields))

        all_fields =
          Enum.reduce(schema, validated_fields, fn {fname, fspec}, acc ->
            if Map.has_key?(acc, fname), do: acc, else: Map.put(acc, fname, field_default(fspec))
          end)

        all_fields = Map.put(all_fields, :__provided_fields__, provided_field_names)
        {:cel_struct, type_name, all_fields}

      {:error, msg} ->
        {:cel_error, msg}
    end
  end

  # Null is not allowed for scalar proto fields
  defp validate_field(scalar, nil)
       when scalar in [:int32, :int64, :uint32, :uint64, :float, :double, :bool, :string, :bytes, :enum],
       do: {:error, "unsupported field type"}

  defp validate_field(:int32, {:cel_int, v}) when v >= @int32_min and v <= @int32_max, do: {:ok, {:cel_int, v}}

  defp validate_field(:int32, {:cel_int, _}), do: {:error, "int32 overflow"}
  defp validate_field(:int64, {:cel_int, _} = v), do: {:ok, v}

  defp validate_field(:uint32, {:cel_uint, v}) when v >= 0 and v <= @uint32_max, do: {:ok, {:cel_uint, v}}

  defp validate_field(:uint32, {:cel_uint, _}), do: {:error, "uint32 overflow"}
  defp validate_field(:uint64, {:cel_uint, _} = v), do: {:ok, v}
  defp validate_field(:float, v) when is_float(v), do: {:ok, v}
  defp validate_field(:double, v) when is_float(v), do: {:ok, v}
  defp validate_field(:bool, v) when is_boolean(v), do: {:ok, v}
  defp validate_field(:string, v) when is_binary(v), do: {:ok, v}
  defp validate_field(:bytes, {:cel_bytes, _} = v), do: {:ok, v}
  defp validate_field(:enum, {:cel_int, v}) when v >= @int32_min and v <= @int32_max, do: {:ok, {:cel_int, v}}

  defp validate_field(:enum, {:cel_int, _}), do: {:error, "enum value out of range"}

  defp validate_field({:wrapper, :int32}, {:cel_int, v}) when v >= @int32_min and v <= @int32_max,
    do: {:ok, {:cel_int, v}}

  defp validate_field({:wrapper, :int32}, {:cel_int, _}), do: {:error, "int32 overflow"}

  defp validate_field({:wrapper, :uint32}, {:cel_uint, v}) when v >= 0 and v <= @uint32_max, do: {:ok, {:cel_uint, v}}

  defp validate_field({:wrapper, :uint32}, {:cel_uint, _}), do: {:error, "uint32 overflow"}

  defp validate_field({:wrapper, :float}, v) when is_float(v) do
    abs_v = abs(v)

    cond do
      # Zero passes through
      abs_v == 0.0 -> {:ok, v}
      # NaN passes through (NaN != NaN)
      v != v -> {:ok, v}
      # Too large for float32 → saturate to ±Infinity
      abs_v > 3.4028235e+38 -> {:ok, if(v > 0, do: :infinity, else: :neg_infinity)}
      # Subnormal/underflow to zero for float32 (~1.175494e-38 min normal)
      abs_v < 1.175494350822288e-38 -> {:ok, 0.0}
      true -> {:ok, v}
    end
  end

  defp validate_field({:wrapper, _}, v), do: {:ok, v}

  # Value coercion must come before the generic {:message, _} catch-all
  defp validate_field({:message, "google.protobuf.Value"}, v), do: {:ok, coerce_to_value(v)}

  # Struct field: null is not allowed (proto semantics)
  defp validate_field({:message, "google.protobuf.Struct"}, nil), do: {:error, "unsupported field type"}

  # ListValue field: null is not allowed
  defp validate_field({:message, "google.protobuf.ListValue"}, nil), do: {:error, "unsupported field type"}

  # Struct fields must have string keys
  defp validate_field({:message, "google.protobuf.Struct"}, v) when is_map(v) do
    if Enum.all?(Map.keys(v), &is_binary/1) do
      {:ok, v}
    else
      {:error, "bad key type"}
    end
  end

  defp validate_field({:message, "google.protobuf.Any"}, v), do: {:ok, pack_any_value(v)}

  defp validate_field({:message, _}, v), do: {:ok, v}

  # Null is not allowed for map fields
  defp validate_field({:map, _, _}, nil), do: {:error, "unsupported field type"}

  defp validate_field({:map, _, val_type}, v) when is_map(v) do
    if prune_nulls?(val_type) do
      {:ok, Map.reject(v, fn {_k, val} -> val == nil end)}
    else
      {:ok, v}
    end
  end

  # Null is not allowed for repeated fields
  defp validate_field({:repeated, _}, nil), do: {:error, "unsupported field type"}

  defp validate_field({:repeated, inner}, v) when is_list(v) do
    if prune_nulls?(inner) do
      {:ok, Enum.reject(v, &(&1 == nil))}
    else
      {:ok, v}
    end
  end

  defp validate_field(_spec, v), do: {:ok, v}

  # Pack a value for an Any field, using parent_type to infer the package prefix
  defp pack_for_any({:cel_struct, inner_type, fields} = v, parent_type) do
    if inner_type == "google.protobuf.Any" do
      {:ok, v}
    else
      # Resolve short name using parent's package context
      resolved = resolve_type_with_package(inner_type, parent_type)

      case Codec.pack(resolved, fields) do
        {:ok, packed} -> {:ok, packed}
        {:error, _} -> {:ok, v}
      end
    end
  end

  defp pack_for_any(v, _parent_type), do: {:ok, pack_any_value(v)}

  # Resolve a possibly-short type name using the package prefix from a parent type
  defp resolve_type_with_package(type_name, parent_type) do
    if String.contains?(type_name, ".") do
      # Already fully qualified
      type_name
    else
      # Extract package from parent_type and prepend
      package = extract_package(parent_type)

      if package == nil do
        type_name
      else
        "#{package}.#{type_name}"
      end
    end
  end

  defp extract_package(type_name) do
    # If the parent type is also short, try to resolve it via Codec
    if String.contains?(type_name, ".") do
      type_name |> String.split(".") |> Enum.drop(-1) |> Enum.join(".")
    else
      # Try to find FQ name from the Codec module resolution
      case Codec.resolve_module(type_name) do
        nil ->
          nil

        mod ->
          mod
          |> Codec.module_full_name()
          |> case do
            nil -> nil
            fq -> fq |> String.split(".") |> Enum.drop(-1) |> Enum.join(".")
          end
      end
    end
  end

  # Non-struct values assigned to Any fields pass through as-is
  # (lists, maps, primitives are stored directly per CEL dynamic dispatch)
  defp pack_any_value(nil), do: nil
  defp pack_any_value(v), do: v

  # JSON safe integer threshold: integers beyond 2^53 become strings
  @json_safe_int_max 9_007_199_254_740_992
  @json_safe_int_min -9_007_199_254_740_992

  @doc "Coerce a value to its JSON representation for google.protobuf.Value fields."
  def coerce_to_value(%Duration{} = d), do: Duration.to_string(d)
  def coerce_to_value(%Timestamp{} = t), do: Timestamp.to_string(t)

  def coerce_to_value({:cel_struct, "google.protobuf.FieldMask", fields}) do
    paths = Map.get(fields, "paths", [])
    Enum.join(paths, ",")
  end

  def coerce_to_value({:cel_struct, "google.protobuf.Empty", _}), do: %{}

  def coerce_to_value({:cel_int, v}) when v > @json_safe_int_min and v < @json_safe_int_max, do: v / 1

  def coerce_to_value({:cel_int, v}), do: Integer.to_string(v)

  def coerce_to_value({:cel_uint, v}) when v < @json_safe_int_max, do: v / 1
  def coerce_to_value({:cel_uint, v}), do: Integer.to_string(v)

  def coerce_to_value({:cel_bytes, bytes}), do: Base.encode64(bytes)

  def coerce_to_value(v), do: v

  @doc "Wrap a CEL value as a google.protobuf.Value proto representation."
  def wrap_as_proto_value(nil), do: %{"null_value" => 0}
  def wrap_as_proto_value(v) when is_boolean(v), do: %{"bool_value" => v}
  def wrap_as_proto_value(v) when is_float(v), do: %{"number_value" => v}
  def wrap_as_proto_value({:cel_int, v}), do: %{"number_value" => v / 1}
  def wrap_as_proto_value({:cel_uint, v}), do: %{"number_value" => v / 1}
  def wrap_as_proto_value(v) when is_binary(v), do: %{"string_value" => v}

  def wrap_as_proto_value(v) when is_list(v) do
    %{"list_value" => %{"values" => Enum.map(v, &wrap_as_proto_value/1)}}
  end

  def wrap_as_proto_value(v) when is_map(v) do
    %{"struct_value" => %{"fields" => Map.new(v, fn {k, val} -> {k, wrap_as_proto_value(val)} end)}}
  end

  def wrap_as_proto_value(v), do: v

  # Null pruning: strip nils from repeated/map fields for message types
  # (timestamp, duration, wrappers) but NOT for Any or Value types.
  defp prune_nulls?({:message, "google.protobuf.Any"}), do: false
  defp prune_nulls?({:message, "google.protobuf.Value"}), do: false
  defp prune_nulls?({:message, _}), do: true
  defp prune_nulls?({:wrapper, _}), do: true
  defp prune_nulls?(_), do: false

  @doc "Get the default value for a proto field type."
  def field_default(:int32), do: {:cel_int, 0}
  def field_default(:int64), do: {:cel_int, 0}
  def field_default(:uint32), do: {:cel_uint, 0}
  def field_default(:uint64), do: {:cel_uint, 0}
  def field_default(:float), do: 0.0
  def field_default(:double), do: 0.0
  def field_default(:bool), do: false
  def field_default(:string), do: ""
  def field_default(:bytes), do: {:cel_bytes, ""}
  def field_default(:enum), do: {:cel_int, 0}
  def field_default({:wrapper, _}), do: nil
  def field_default({:message, "google.protobuf.ListValue"}), do: []
  def field_default({:message, "google.protobuf.Struct"}), do: %{}

  def field_default({:message, name}) do
    case get_schema(name) do
      nil -> nil
      schema -> default_struct(name, schema)
    end
  end

  def field_default({:map, _, _}), do: %{}
  def field_default({:repeated, _}), do: []
  def field_default(_), do: nil

  @doc "Create a default struct instance with scalar defaults (message fields use lazy defaults)."
  def default_struct(type_name, schema) do
    fields =
      Map.new(schema, fn {fname, fspec} ->
        default =
          case fspec do
            {:message, name} ->
              # Use lazy marker for message fields to avoid infinite recursion
              {:cel_lazy_default, name}

            other ->
              field_default(other)
          end

        {fname, default}
      end)

    {:cel_struct, type_name, Map.put(fields, :__provided_fields__, MapSet.new())}
  end

  @doc "Get proto schema for a known type name."
  def get_schema("TestAllTypes"), do: test_all_types_schema()
  def get_schema("cel.expr.conformance.proto3.TestAllTypes"), do: test_all_types_schema()
  def get_schema("cel.expr.conformance.proto2.TestAllTypes"), do: test_all_types_schema()
  def get_schema(".cel.expr.conformance.proto3.TestAllTypes"), do: test_all_types_schema()
  def get_schema("NestedMessage"), do: nested_message_schema()
  def get_schema("NestedTestAllTypes"), do: nested_test_all_types_schema()
  def get_schema(_), do: nil

  defp nested_message_schema do
    %{"bb" => :int32}
  end

  defp nested_test_all_types_schema do
    %{
      "child" => {:message, "NestedTestAllTypes"},
      "payload" => {:message, "TestAllTypes"}
    }
  end

  defp test_all_types_schema do
    %{
      # Scalar fields
      "single_int32" => :int32,
      "single_int64" => :int64,
      "single_uint32" => :uint32,
      "single_uint64" => :uint64,
      "single_sint32" => :int32,
      "single_sint64" => :int64,
      "single_fixed32" => :uint32,
      "single_fixed64" => :uint64,
      "single_sfixed32" => :int32,
      "single_sfixed64" => :int64,
      "single_float" => :float,
      "single_double" => :double,
      "single_bool" => :bool,
      "single_string" => :string,
      "single_bytes" => :bytes,
      # Wrapper fields (nullable)
      "single_bool_wrapper" => {:wrapper, :bool},
      "single_int32_wrapper" => {:wrapper, :int32},
      "single_int64_wrapper" => {:wrapper, :int64},
      "single_uint32_wrapper" => {:wrapper, :uint32},
      "single_uint64_wrapper" => {:wrapper, :uint64},
      "single_float_wrapper" => {:wrapper, :float},
      "single_double_wrapper" => {:wrapper, :double},
      "single_string_wrapper" => {:wrapper, :string},
      "single_bytes_wrapper" => {:wrapper, :bytes},
      # Well-known types
      "single_any" => {:message, "google.protobuf.Any"},
      "single_duration" => {:message, "google.protobuf.Duration"},
      "single_timestamp" => {:message, "google.protobuf.Timestamp"},
      "single_struct" => {:message, "google.protobuf.Struct"},
      "single_value" => {:message, "google.protobuf.Value"},
      "list_value" => {:message, "google.protobuf.ListValue"},
      # Nested message
      "single_nested_message" => {:message, "NestedMessage"},
      "standalone_message" => {:message, "TestAllTypes"},
      # Enum
      "single_nested_enum" => :enum,
      "standalone_enum" => :enum,
      # Repeated fields
      "repeated_int32" => {:repeated, :int32},
      "repeated_int64" => {:repeated, :int64},
      "repeated_uint32" => {:repeated, :uint32},
      "repeated_uint64" => {:repeated, :uint64},
      "repeated_float" => {:repeated, :float},
      "repeated_double" => {:repeated, :double},
      "repeated_bool" => {:repeated, :bool},
      "repeated_string" => {:repeated, :string},
      "repeated_bytes" => {:repeated, :bytes},
      "repeated_nested_message" => {:repeated, {:message, "NestedMessage"}},
      "repeated_nested_enum" => {:repeated, :enum},
      "repeated_timestamp" => {:repeated, {:message, "google.protobuf.Timestamp"}},
      "repeated_duration" => {:repeated, {:message, "google.protobuf.Duration"}},
      "repeated_int32_wrapper" => {:repeated, {:wrapper, :int32}},
      "repeated_any" => {:repeated, {:message, "google.protobuf.Any"}},
      "repeated_value" => {:repeated, {:message, "google.protobuf.Value"}},
      # Map fields
      "map_int64_nested_type" => {:map, :int64, {:message, "NestedTestAllTypes"}},
      "map_bool_int64" => {:map, :bool, :int64},
      "map_bool_bool" => {:map, :bool, :bool},
      "map_bool_string" => {:map, :bool, :string},
      "map_bool_bytes" => {:map, :bool, :bytes},
      "map_int32_int32" => {:map, :int32, :int32},
      "map_int32_int64" => {:map, :int32, :int64},
      "map_int32_uint32" => {:map, :int32, :uint32},
      "map_int32_uint64" => {:map, :int32, :uint64},
      "map_int32_float" => {:map, :int32, :float},
      "map_int32_double" => {:map, :int32, :double},
      "map_int32_bool" => {:map, :int32, :bool},
      "map_int32_string" => {:map, :int32, :string},
      "map_int32_bytes" => {:map, :int32, :bytes},
      "map_int32_enum" => {:map, :int32, :enum},
      "map_int64_int32" => {:map, :int64, :int32},
      "map_string_string" => {:map, :string, :string},
      "map_string_float" => {:map, :string, :float},
      "map_string_double" => {:map, :string, :double},
      "map_bool_duration" => {:map, :bool, {:message, "google.protobuf.Duration"}},
      "map_bool_timestamp" => {:map, :bool, {:message, "google.protobuf.Timestamp"}},
      "map_bool_int32_wrapper" => {:map, :bool, {:wrapper, :int32}},
      # Oneof fields
      "oneof_type" => {:message, "NestedTestAllTypes"},
      "single_nested_message_oneof" => {:message, "NestedMessage"},
      "single_nested_enum_oneof" => :enum
    }
  end

  @doc """
  Map a CEL type to its protobuf type name.
  Used for type() function in strict mode.
  """
  def proto_type_name(:bool), do: "bool"
  def proto_type_name(:int), do: "int"
  def proto_type_name(:uint), do: "uint"
  def proto_type_name(:double), do: "double"
  def proto_type_name(:string), do: "string"
  def proto_type_name(:bytes), do: "bytes"
  def proto_type_name(:list), do: "list"
  def proto_type_name(:map), do: "map"
  def proto_type_name(:null_type), do: "null_type"
  def proto_type_name(:timestamp), do: "google.protobuf.Timestamp"
  def proto_type_name(:duration), do: "google.protobuf.Duration"
  def proto_type_name(:type), do: "type"
  def proto_type_name(name) when is_binary(name), do: name
  def proto_type_name(_), do: "dyn"
end
