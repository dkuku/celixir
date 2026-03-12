if Code.ensure_loaded?(Protobuf) do
  defmodule Celixir.Proto.Codec do
    @moduledoc """
    Protobuf binary codec for Any type support.

    This module is only compiled when the `protobuf` library is available.
    It provides encode/decode functions for converting between CEL struct
    representations and protobuf binary format, enabling google.protobuf.Any
    pack/unpack operations.
    """

    # Maps CEL type names to their compiled protobuf modules.
    # Users can register additional modules via register_module/2.
    @type_registry %{}

    @doc """
    Returns true if the protobuf codec is available.
    """
    def available?, do: true

    @doc """
    Encode a CEL struct value to protobuf binary format.

    Takes a CEL type name and fields map, resolves the protobuf module,
    and encodes to binary wire format.
    """
    def encode(type_name, fields) when is_binary(type_name) and is_map(fields) do
      case resolve_module(type_name) do
        nil -> {:error, "unknown proto type: #{type_name}"}
        mod -> do_encode(mod, fields)
      end
    end

    @doc """
    Decode protobuf binary to a CEL struct value.

    Takes a type_url and binary value, resolves the protobuf module,
    and decodes to a `{:cel_struct, type_name, fields}` tuple.
    """
    def decode(type_url, binary) when is_binary(type_url) and is_binary(binary) do
      type_name = type_name_from_url(type_url)

      case resolve_module(type_name) do
        nil -> {:error, "unknown proto type: #{type_name}"}
        mod -> do_decode(mod, type_name, binary)
      end
    end

    @doc """
    Pack a CEL struct into a google.protobuf.Any representation.

    Returns `{:cel_struct, "google.protobuf.Any", %{"type_url" => ..., "value" => ...}}`.
    """
    def pack(type_name, fields) when is_binary(type_name) and is_map(fields) do
      case resolve_module(type_name) do
        nil ->
          {:error, "unknown proto type: #{type_name}"}

        mod ->
          # Use the module's full_name for the type_url (resolves short names)
          fq_name = module_full_name(mod) || type_name

          case do_encode(mod, fields) do
            {:ok, binary} ->
              {:ok,
               {:cel_struct, "google.protobuf.Any",
                %{
                  "type_url" => "type.googleapis.com/#{fq_name}",
                  "value" => {:cel_bytes, binary}
                }}}

            error ->
              error
          end
      end
    end

    @doc "Get the fully-qualified protobuf name from a compiled module."
    def module_full_name(mod) do
      if function_exported?(mod, :full_name, 0) do
        mod.full_name()
      end
    rescue
      _ -> nil
    end

    @doc """
    Unpack a google.protobuf.Any to its contained CEL struct.
    """
    def unpack(%{"type_url" => type_url, "value" => value}) when is_binary(type_url) do
      binary =
        case value do
          {:cel_bytes, b} -> b
          b when is_binary(b) -> b
        end

      decode(type_url, binary)
    end

    def unpack(_), do: {:error, "invalid Any: missing type_url or value"}

    @doc """
    Extract the fully-qualified type name from a type_url.
    """
    def type_name_from_url(type_url) do
      case String.split(type_url, "/", parts: 2) do
        [_, type_name] -> type_name
        _ -> type_url
      end
    end

    @doc """
    Resolve a CEL type name to a compiled protobuf module.
    """
    def resolve_module(type_name) do
      # First check static registry
      case Map.get(@type_registry, type_name) do
        nil -> resolve_module_dynamic(type_name)
        mod -> mod
      end
    end

    # Try to resolve by converting the proto package name to an Elixir module name.
    # e.g. "cel.expr.conformance.proto3.TestAllTypes" -> Cel.Expr.Conformance.Proto3.TestAllTypes
    defp resolve_module_dynamic(type_name) do
      try_resolve_module(type_name) ||
        try_resolve_with_prefixes(type_name)
    end

    defp try_resolve_module(type_name) do
      module =
        type_name
        |> String.split(".")
        |> Enum.map_join(".", &Macro.camelize/1)
        |> then(&Module.concat([String.to_atom(&1)]))

      if Code.ensure_loaded?(module) and function_exported?(module, :__message_props__, 0) do
        module
      end
    rescue
      _ -> nil
    end

    # For short names like "TestAllTypes", try known package prefixes
    @known_prefixes [
      "cel.expr.conformance.proto2",
      "cel.expr.conformance.proto3"
    ]

    defp try_resolve_with_prefixes(type_name) do
      if String.contains?(type_name, ".") do
        nil
      else
        Enum.find_value(@known_prefixes, fn prefix ->
          try_resolve_module("#{prefix}.#{type_name}")
        end)
      end
    end

    defp do_encode(mod, fields) do
      struct = cel_fields_to_proto_struct(mod, fields)
      {:ok, Protobuf.encode(struct)}
    rescue
      e -> {:error, "encode error: #{Exception.message(e)}"}
    end

    defp do_decode(mod, type_name, binary) do
      decoded = Protobuf.decode(binary, mod)
      {:ok, proto_struct_to_cel(decoded, type_name)}
    rescue
      e -> {:error, "decode error: #{Exception.message(e)}"}
    end

    # Convert CEL fields map (string keys, CEL values) to a protobuf struct
    defp cel_fields_to_proto_struct(mod, fields) do
      props = mod.__message_props__()

      # Build a lookup from string field name to {atom, field_prop}
      field_lookup =
        for {_num, fp} <- props.field_props, into: %{} do
          {Atom.to_string(fp.name_atom), fp}
        end

      atom_fields =
        for {str_key, value} <- fields,
            is_binary(str_key),
            not match?({:cel_lazy_default, _}, value),
            value != nil,
            fp = Map.get(field_lookup, str_key),
            fp != nil,
            not cel_zero_value?(value, fp),
            into: %{} do
          {fp.name_atom, cel_value_to_proto(value, fp)}
        end

      struct(mod, atom_fields)
    end

    # Check if a CEL value is the zero/default for a proto field
    defp cel_zero_value?({:cel_int, 0}, _fp), do: true
    defp cel_zero_value?({:cel_uint, 0}, _fp), do: true
    defp cel_zero_value?({:cel_bytes, ""}, _fp), do: true
    defp cel_zero_value?(v, _fp) when is_float(v) and v == 0.0, do: true
    defp cel_zero_value?(false, _fp), do: true
    defp cel_zero_value?("", fp), do: fp.type == :string
    defp cel_zero_value?([], _fp), do: true
    defp cel_zero_value?(m, _fp) when is_map(m) and map_size(m) == 0, do: true

    # Default struct with no provided fields = not set
    defp cel_zero_value?({:cel_struct, _, fields}, _fp) do
      case Map.get(fields, :__provided_fields__) do
        %MapSet{} = pf -> MapSet.size(pf) == 0
        _ -> false
      end
    end

    defp cel_zero_value?(_, _), do: false

    defp cel_value_to_proto({:cel_int, v}, _fp), do: v
    defp cel_value_to_proto({:cel_uint, v}, _fp), do: v
    defp cel_value_to_proto({:cel_bytes, v}, _fp), do: v

    defp cel_value_to_proto({:cel_struct, _type, fields}, fp) when not is_nil(fp),
      do: cel_fields_to_proto_struct(fp.type, fields)

    defp cel_value_to_proto(v, _fp), do: v

    # Convert a decoded protobuf struct to CEL representation
    defp proto_struct_to_cel(%{__struct__: mod} = msg, type_name) do
      props = mod.__message_props__()

      fields =
        for {_num, fp} <- props.field_props,
            value = Map.get(msg, fp.name_atom),
            value != nil and value != proto_zero(fp),
            into: %{} do
          {Atom.to_string(fp.name_atom), proto_value_to_cel(value, fp)}
        end

      {:cel_struct, type_name, fields}
    end

    defp proto_zero(fp) do
      cond do
        fp.repeated? -> []
        fp.map? -> %{}
        fp.type in [:int32, :int64, :sint32, :sint64, :sfixed32, :sfixed64] -> 0
        fp.type in [:uint32, :uint64, :fixed32, :fixed64] -> 0
        fp.type in [:float, :double] -> 0.0
        fp.type == :bool -> false
        fp.type == :string -> ""
        fp.type == :bytes -> <<>>
        fp.enum? -> enum_zero(fp.type)
        true -> nil
      end
    end

    # Get the zero value atom for an enum type
    defp enum_zero({:enum, enum_mod}), do: enum_zero(enum_mod)

    defp enum_zero(enum_mod) when is_atom(enum_mod) do
      if Code.ensure_loaded?(enum_mod) and function_exported?(enum_mod, :mapping, 0) do
        enum_mod.mapping()
        |> Enum.find(fn {_k, v} -> v == 0 end)
        |> case do
          {k, _} -> k
          nil -> 0
        end
      else
        0
      end
    rescue
      _ -> 0
    end

    defp enum_zero(_), do: 0

    defp proto_value_to_cel(value, fp) do
      cond do
        fp.type in [:int32, :int64, :sint32, :sint64, :sfixed32, :sfixed64] -> value
        fp.type in [:uint32, :uint64, :fixed32, :fixed64] -> value
        fp.type in [:float, :double] -> value * 1.0
        fp.type == :bytes -> {:cel_bytes, value}
        fp.repeated? -> Enum.map(value, &proto_value_to_cel(&1, %{fp | repeated?: false}))
        is_atom(fp.type) -> value
        true -> value
      end
    end
  end
else
  defmodule Celixir.Proto.Codec do
    @moduledoc """
    Stub module when protobuf library is not available.
    All operations return errors indicating protobuf is required.
    """

    def available?, do: false
    def encode(_type_name, _fields), do: {:error, "protobuf library not available"}
    def decode(_type_url, _binary), do: {:error, "protobuf library not available"}
    def pack(_type_name, _fields), do: {:error, "protobuf library not available"}
    def unpack(_fields), do: {:error, "protobuf library not available"}
    def type_name_from_url(url), do: url |> String.split("/", parts: 2) |> List.last()
    def resolve_module(_type_name), do: nil
    def module_full_name(_mod), do: nil
  end
end
