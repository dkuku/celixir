if Code.ensure_loaded?(Protobuf) do
  defmodule Celixir.ProtobufAdapter do
    @moduledoc """
    Type adapter for protobuf-elixir generated message structs.

    This module is only compiled when the `protobuf` library is available.

    Enables CEL expressions to work with protobuf messages seamlessly:
    - Field access via dot notation (msg.field_name)
    - has() checks for field presence (respects proto3 field presence)
    - Automatic conversion of well-known types (Timestamp, Duration, wrappers)

    ## Usage

        defmodule MyProto.User do
          use Protobuf, syntax: :proto3
          field :name, 1, type: :string
          field :age, 2, type: :int32
        end

        env = Celixir.Environment.new(%{user: %MyProto.User{name: "alice", age: 30}})
              |> Celixir.Environment.set_type_adapter(Celixir.ProtobufAdapter)

        Celixir.eval!("user.name == 'alice'", env)
    """

    @behaviour Celixir.TypeAdapter

    @impl true
    def native_to_value(%{__struct__: mod} = msg) do
      if protobuf_message?(mod) do
        convert_proto_message(msg)
      else
        msg
      end
    end

    def native_to_value(v), do: v

    @impl true
    def has_field?(%{__struct__: mod} = msg, field) when is_binary(field) do
      if protobuf_message?(mod) do
        atom_field = String.to_existing_atom(field)
        value = Map.get(msg, atom_field)
        value != nil and value != proto_default(mod, atom_field)
      else
        Map.has_key?(msg, String.to_existing_atom(field))
      end
    rescue
      _ -> false
    end

    def has_field?(_, _), do: false

    @impl true
    def get_field(%{__struct__: _mod} = msg, field) when is_binary(field) do
      atom_field = String.to_existing_atom(field)

      if Map.has_key?(msg, atom_field) do
        {:ok, Map.get(msg, atom_field)}
      else
        {:error, "no_such_field: #{field}"}
      end
    rescue
      _ -> {:error, "no_such_field: #{field}"}
    end

    defp protobuf_message?(mod) do
      function_exported?(mod, :__message_props__, 0)
    rescue
      _ -> false
    end

    defp convert_proto_message(msg) do
      mod = msg.__struct__

      cond do
        mod == Google.Protobuf.Timestamp ->
          seconds = Map.get(msg, :seconds, 0)
          nanos = Map.get(msg, :nanos, 0)
          micros = seconds * 1_000_000 + div(nanos, 1000)
          {:ok, dt} = DateTime.from_unix(micros, :microsecond)
          %Celixir.Types.Timestamp{datetime: dt}

        mod == Google.Protobuf.Duration ->
          seconds = Map.get(msg, :seconds, 0)
          nanos = Map.get(msg, :nanos, 0)
          micros = seconds * 1_000_000 + div(nanos, 1000)
          Celixir.Types.Duration.new(micros)

        mod in [
          Google.Protobuf.BoolValue,
          Google.Protobuf.BytesValue,
          Google.Protobuf.DoubleValue,
          Google.Protobuf.FloatValue,
          Google.Protobuf.Int32Value,
          Google.Protobuf.Int64Value,
          Google.Protobuf.StringValue,
          Google.Protobuf.UInt32Value,
          Google.Protobuf.UInt64Value
        ] ->
          Map.get(msg, :value)

        true ->
          msg
      end
    rescue
      _ -> msg
    end

    defp proto_default(mod, field) do
      if function_exported?(mod, :__message_props__, 0) do
        props = mod.__message_props__()
        field_props = Enum.find(props.field_props, fn {_num, fp} -> fp.name_atom == field end)

        case field_props do
          {_num, fp} ->
            cond do
              fp.repeated? -> []
              fp.map? -> %{}
              fp.type == :string -> ""
              fp.type == :bytes -> ""
              fp.type in [:int32, :int64, :sint32, :sint64, :sfixed32, :sfixed64] -> 0
              fp.type in [:uint32, :uint64, :fixed32, :fixed64] -> 0
              fp.type in [:float, :double] -> 0.0
              fp.type == :bool -> false
              fp.enum? -> 0
              true -> nil
            end

          nil ->
            nil
        end
      end
    rescue
      _ -> nil
    end
  end
end
