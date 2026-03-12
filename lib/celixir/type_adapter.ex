defmodule Celixir.TypeAdapter do
  @moduledoc """
  Behaviour for plugging custom type adapters into the CEL evaluator.

  Type adapters allow Celixir to work with custom data types like protobuf
  messages, providing field access, has() semantics, and type conversions.

  ## Usage

      defmodule MyProtobufAdapter do
        @behaviour Celixir.TypeAdapter

        @impl true
        def native_to_value(msg) when is_struct(msg) do
          Map.from_struct(msg)
        end
        def native_to_value(v), do: v

        @impl true
        def has_field?(msg, field) when is_struct(msg) do
          atom_field = String.to_existing_atom(field)
          Map.has_key?(msg, atom_field) and Map.get(msg, atom_field) != nil
        rescue
          ArgumentError -> false
        end
        def has_field?(_, _), do: false
      end

      env = Celixir.Environment.new(%{msg: my_proto_msg})
            |> Celixir.Environment.set_type_adapter(MyProtobufAdapter)
  """

  @doc "Convert a native value to a CEL-compatible value"
  @callback native_to_value(any()) :: any()

  @doc "Check if a value has a specific field (for has() macro)"
  @callback has_field?(any(), String.t()) :: boolean()

  @doc "Get a field from a value"
  @callback get_field(any(), String.t()) :: {:ok, any()} | {:error, String.t()}

  @optional_callbacks [get_field: 2]
end
