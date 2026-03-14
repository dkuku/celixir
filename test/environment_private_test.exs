defmodule Celixir.EnvironmentPrivateTest do
  use ExUnit.Case

  alias Celixir.Environment

  describe "put_private/3 and get_private/2" do
    test "stores and retrieves a value" do
      env = Environment.new() |> Environment.put_private(:key, "value")
      assert {:ok, "value"} = Environment.get_private(env, :key)
    end

    test "returns :error for missing key" do
      env = Environment.new()
      assert :error = Environment.get_private(env, :missing)
    end

    test "supports string keys" do
      env = Environment.new() |> Environment.put_private("api_key", "secret")
      assert {:ok, "secret"} = Environment.get_private(env, "api_key")
    end

    test "overwrites existing value" do
      env =
        Environment.new()
        |> Environment.put_private(:key, "old")
        |> Environment.put_private(:key, "new")

      assert {:ok, "new"} = Environment.get_private(env, :key)
    end

    test "multiple private keys" do
      env =
        Environment.new()
        |> Environment.put_private(:a, 1)
        |> Environment.put_private(:b, 2)

      assert {:ok, 1} = Environment.get_private(env, :a)
      assert {:ok, 2} = Environment.get_private(env, :b)
    end
  end

  describe "get_private!/2" do
    test "returns value when key exists" do
      env = Environment.new() |> Environment.put_private(:key, 42)
      assert 42 = Environment.get_private!(env, :key)
    end

    test "raises KeyError when key missing" do
      env = Environment.new()
      assert_raise KeyError, fn -> Environment.get_private!(env, :missing) end
    end
  end

  describe "delete_private/2" do
    test "removes a private key" do
      env =
        Environment.new()
        |> Environment.put_private(:key, "value")
        |> Environment.delete_private(:key)

      assert :error = Environment.get_private(env, :key)
    end

    test "no-op for missing key" do
      env = Environment.new() |> Environment.delete_private(:nope)
      assert :error = Environment.get_private(env, :nope)
    end
  end

  describe "private data is not visible to CEL" do
    test "private keys are not accessible as variables" do
      env =
        Environment.new(%{x: 10})
        |> Environment.put_private(:secret, "hidden")

      assert {:ok, 10} = Celixir.eval("x", env)
      assert {:error, _} = Celixir.eval("secret", env)
    end
  end

  describe "private data in custom functions" do
    test "custom function can close over env with private data" do
      env =
        Environment.new()
        |> Environment.put_private(:multiplier, 3)

      multiplier = Environment.get_private!(env, :multiplier)

      env = Environment.put_function(env, "scale", fn x -> x * multiplier end)

      assert {:ok, 15} = Celixir.eval("scale(5)", env)
    end
  end
end
