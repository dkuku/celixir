defmodule Celixir.Types.Optional do
  @moduledoc """
  CEL optional type — represents a value that may or may not be present.

  Used with optional fields in protobuf messages and the optional library.
  """

  defstruct [:value, has_value: false]

  @type t :: %__MODULE__{
          value: any(),
          has_value: boolean()
        }

  def none, do: %__MODULE__{value: nil, has_value: false}

  def of(value), do: %__MODULE__{value: value, has_value: true}

  def of_non_zero_value(value) do
    if zero_value?(value), do: none(), else: of(value)
  end

  def has_value?(%__MODULE__{has_value: hv}), do: hv

  def value(%__MODULE__{has_value: true, value: v}), do: {:ok, v}
  def value(%__MODULE__{has_value: false}), do: {:error, "optional.none has no value"}

  def or_value(%__MODULE__{has_value: true, value: v}, _default), do: v
  def or_value(%__MODULE__{has_value: false}, default), do: default

  def or_optional(%__MODULE__{has_value: true} = opt, _other), do: opt
  def or_optional(%__MODULE__{has_value: false}, %__MODULE__{} = other), do: other

  defp zero_value?(nil), do: true
  defp zero_value?(false), do: true
  defp zero_value?(0), do: true
  defp zero_value?(v) when is_float(v) and v == 0.0, do: true
  defp zero_value?(""), do: true
  defp zero_value?({:cel_int, 0}), do: true
  defp zero_value?({:cel_uint, 0}), do: true
  defp zero_value?({:cel_bytes, ""}), do: true
  defp zero_value?(l) when is_list(l) and length(l) == 0, do: true
  defp zero_value?(m) when is_map(m) and map_size(m) == 0, do: true

  defp zero_value?({:cel_struct, _type_name, fields}) do
    # A proto message is zero-value if no fields were explicitly provided
    case Map.get(fields, :__provided_fields__) do
      nil -> false
      provided -> MapSet.size(provided) == 0
    end
  end

  defp zero_value?(_), do: false
end
