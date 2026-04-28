defmodule Celixir.Ext.Encoders do
  @moduledoc """
  Encoders extension for CEL — mirrors `ext.Encoders()` from cel-go.

  Provides Base64 encoding/decoding functions. Functions are available as
  built-ins and also via explicit registration.

  ## Usage

      env = Celixir.Environment.new() |> Celixir.Ext.Encoders.register()
      Celixir.eval!("base64.encode(b'hello')", env)    # => "aGVsbG8="
      Celixir.eval!("base64.decode('aGVsbG8=')", env) # => b"hello"

  ## Functions

  - `base64.encode(bytes)` — encode bytes to base64 string
  - `base64.decode(string)` — decode base64 string to bytes (error if invalid)
  """

  alias Celixir.Environment

  @doc """
  Registers encoder extension functions into the given environment.
  """
  def register(env \\ Environment.new()) do
    env
    |> Environment.put_function("base64.encode", &encode/1)
    |> Environment.put_function("base64.decode", &decode/1)
  end

  def encode(bytes) when is_binary(bytes), do: Base.encode64(bytes)

  def decode(s) when is_binary(s) do
    case Base.decode64(s) do
      {:ok, bytes} ->
        bytes

      :error ->
        case Base.decode64(s, padding: false) do
          {:ok, bytes} -> bytes
          :error -> raise "base64 decode error: invalid base64 string"
        end
    end
  end
end
