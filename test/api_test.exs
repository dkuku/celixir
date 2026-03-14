defmodule Celixir.APITest do
  use ExUnit.Case

  defmodule MathAPI do
    use Celixir.API, scope: "mymath"

    defcel abs(x) do
      Kernel.abs(x)
    end

    defcel clamp(val, lo, hi) do
      val |> max(lo) |> min(hi)
    end

    defcel double(x) do
      x * 2
    end
  end

  defmodule UnscopedAPI do
    use Celixir.API

    defcel greet(name) do
      "Hello, #{name}!"
    end

    defcel add(a, b) do
      a + b
    end
  end

  describe "scoped API" do
    test "registers functions with scope prefix" do
      env = MathAPI.register()
      assert {:ok, 5} = Celixir.eval("mymath.abs(-5)", env)
    end

    test "clamp function works" do
      env = MathAPI.register()
      assert {:ok, 100} = Celixir.eval("mymath.clamp(150, 0, 100)", env)
      assert {:ok, 0} = Celixir.eval("mymath.clamp(-10, 0, 100)", env)
      assert {:ok, 50} = Celixir.eval("mymath.clamp(50, 0, 100)", env)
    end

    test "double function works" do
      env = MathAPI.register()
      assert {:ok, 10} = Celixir.eval("mymath.double(5)", env)
    end

    test "can combine with variables" do
      env = MathAPI.register(Celixir.Environment.new(%{x: -42}))
      assert {:ok, 42} = Celixir.eval("mymath.abs(x)", env)
    end

    test "__cel_functions__ returns function list" do
      funcs = MathAPI.__cel_functions__()
      assert {"abs", 1} in funcs
      assert {"clamp", 3} in funcs
      assert {"double", 1} in funcs
    end

    test "__cel_scope__ returns scope" do
      assert MathAPI.__cel_scope__() == "mymath"
    end
  end

  describe "unscoped API" do
    test "registers functions without prefix" do
      env = UnscopedAPI.register()
      assert {:ok, "Hello, world!"} = Celixir.eval("greet('world')", env)
    end

    test "add function" do
      env = UnscopedAPI.register()
      assert {:ok, 7} = Celixir.eval("add(3, 4)", env)
    end

    test "__cel_scope__ returns nil" do
      assert UnscopedAPI.__cel_scope__() == nil
    end
  end

  describe "composing APIs" do
    test "can register multiple APIs on same environment" do
      env =
        Celixir.Environment.new(%{val: -7})
        |> MathAPI.register()
        |> UnscopedAPI.register()

      assert {:ok, 7} = Celixir.eval("mymath.abs(val)", env)
      assert {:ok, "Hello, world!"} = Celixir.eval("greet('world')", env)
    end
  end
end
