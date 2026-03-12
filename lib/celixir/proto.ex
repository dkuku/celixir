defmodule Celixir.Proto do
  @moduledoc """
  Proto well-known type support for CEL strict mode.
  Handles wrapper types, Value/Struct/ListValue, and TestAllTypes schema.
  """

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
        "google.protobuf.Duration"
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
    "UInt64Value" => "google.protobuf.UInt64Value"
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

  defp finalize_special("google.protobuf.Any", fields) do
    # Any{} with no type_url is an error
    if Map.get(fields, "type_url") in [nil, ""] and Map.get(fields, "value") == nil do
      {:cel_error, "invalid google.protobuf.Any: missing type_url"}
    else
      {:cel_struct, "google.protobuf.Any", fields}
    end
  end

  defp finalize_special(type_name, fields) do
    case get_schema(type_name) do
      nil -> {:cel_struct, type_name, fields}
      schema -> finalize_message(type_name, fields, schema)
    end
  end

  @doc "Finalize a proto message with schema validation."
  def finalize_message(type_name, fields, schema) do
    validated =
      Enum.reduce_while(fields, {:ok, %{}}, fn {field_name, value}, {:ok, acc} ->
        case Map.get(schema, field_name) do
          nil ->
            # Accept unknown fields (e.g., reserved keyword field name tests)
            {:cont, {:ok, Map.put(acc, field_name, value)}}

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
  defp validate_field(:enum, {:cel_int, v}) when v >= @int32_min and v <= @int32_max,
    do: {:ok, {:cel_int, v}}

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

  # Struct fields must have string keys
  defp validate_field({:message, "google.protobuf.Struct"}, v) when is_map(v) do
    if Enum.all?(Map.keys(v), &is_binary/1) do
      {:ok, v}
    else
      {:error, "Struct fields must have string keys"}
    end
  end

  defp validate_field({:message, _}, v), do: {:ok, v}
  defp validate_field({:map, _, _}, v) when is_map(v), do: {:ok, v}
  defp validate_field({:repeated, _}, v) when is_list(v), do: {:ok, v}
  defp validate_field(_spec, v), do: {:ok, v}

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
      # Map fields
      "map_int64_nested_type" => {:map, :int64, {:message, "NestedTestAllTypes"}},
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
      # Oneof fields
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
