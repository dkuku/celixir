defmodule Celixir.StringKeysTest do
  use ExUnit.Case, async: true

  alias Celixir.Environment

  describe "Celixir.eval/2 with string-keyed maps" do
    test "simple variable lookup" do
      assert {:ok, "high"} = Celixir.eval("severity", %{"severity" => "high"})
    end

    test "comparison expression" do
      assert {:ok, true} = Celixir.eval("severity == 'high' && count > 2", %{"severity" => "high", "count" => 3})
    end

    test "arithmetic" do
      assert {:ok, 15} = Celixir.eval("x * y + z", %{"x" => 2, "y" => 5, "z" => 5})
    end

    test "string functions" do
      assert {:ok, true} = Celixir.eval("name.startsWith('hello')", %{"name" => "hello world"})
    end

    test "ternary" do
      assert {:ok, "big"} = Celixir.eval("x > 10 ? 'big' : 'small'", %{"x" => 42})
    end

    test "list operations" do
      assert {:ok, 3} = Celixir.eval("items.size()", %{"items" => [1, 2, 3]})
    end

    test "map access" do
      assert {:ok, "bar"} = Celixir.eval("data['foo']", %{"data" => %{"foo" => "bar"}})
    end

    test "nested map field access" do
      assert {:ok, 42} = Celixir.eval("config.timeout", %{"config" => %{"timeout" => 42}})
    end

    test "undefined variable returns error" do
      assert {:error, "undefined variable: missing"} = Celixir.eval("missing", %{"other" => 1})
    end
  end

  describe "backward compatibility with atom-keyed maps" do
    test "atom-keyed map still works" do
      assert {:ok, true} = Celixir.eval("severity == 'high'", %{severity: "high"})
    end

    test "mixed usage in sequence" do
      expr = "x + y"
      assert {:ok, 3} = Celixir.eval(expr, %{x: 1, y: 2})
      assert {:ok, 7} = Celixir.eval(expr, %{"x" => 3, "y" => 4})
    end
  end

  describe "Environment.new/1 with string keys" do
    test "accepts string-keyed map directly" do
      env = Environment.new(%{"name" => "alice", "age" => 30})
      assert {:ok, "alice"} = Environment.get_variable(env, "name")
      assert {:ok, 30} = Environment.get_variable(env, "age")
    end

    test "accepts atom-keyed map (backward compatible)" do
      env = Environment.new(%{name: "bob"})
      assert {:ok, "bob"} = Environment.get_variable(env, "name")
    end

    test "empty map" do
      env = Environment.new(%{})
      assert :error = Environment.get_variable(env, "x")
    end
  end

  describe "Environment.put_variable/3 with string names" do
    test "string name" do
      env = Environment.put_variable(Environment.new(), "score", 100)
      assert {:ok, 100} = Environment.get_variable(env, "score")
    end

    test "atom name (backward compatible)" do
      env = Environment.put_variable(Environment.new(), :score, 100)
      assert {:ok, 100} = Environment.get_variable(env, "score")
    end
  end

  describe "comprehensions with string-keyed variables" do
    test "filter" do
      assert {:ok, [3, 4, 5]} =
               Celixir.eval("[1, 2, 3, 4, 5].filter(x, x > 2)", %{})
    end

    test "map" do
      assert {:ok, [2, 4, 6]} =
               Celixir.eval("[1, 2, 3].map(x, x * 2)", %{})
    end

    test "exists with string-keyed variable" do
      assert {:ok, true} =
               Celixir.eval("items.exists(x, x > threshold)", %{"items" => [1, 2, 3], "threshold" => 2})
    end

    test "all with string-keyed variable" do
      assert {:ok, true} =
               Celixir.eval("scores.all(s, s >= min_score)", %{"scores" => [80, 90, 95], "min_score" => 70})
    end
  end

  describe "custom functions with string-keyed variables" do
    test "custom function receives string-keyed variable values" do
      env =
        %{"name" => "world"}
        |> Environment.new()
        |> Environment.put_function("greet", fn name -> "Hello, #{name}!" end)

      assert {:ok, "Hello, world!"} = Celixir.eval("greet(name)", env)
    end
  end

  describe "Celixir.Program.eval/2 with string-keyed bindings" do
    test "compiled program with string keys" do
      {:ok, program} = Celixir.compile("x * 2 + y")
      assert {:ok, 11} = Celixir.Program.eval(program, %{"x" => 5, "y" => 1})
      assert {:ok, 23} = Celixir.Program.eval(program, %{"x" => 10, "y" => 3})
    end

    test "compiled program with atom keys (backward compatible)" do
      {:ok, program} = Celixir.compile("x + y")
      assert {:ok, 3} = Celixir.Program.eval(program, %{x: 1, y: 2})
    end

    test "compiled program reusable across key types" do
      {:ok, program} = Celixir.compile("a > b")
      assert {:ok, true} = Celixir.Program.eval(program, %{a: 5, b: 3})
      assert {:ok, false} = Celixir.Program.eval(program, %{"a" => 1, "b" => 10})
    end
  end

  describe "to_fun!/1 with string-keyed maps" do
    test "accepts string-keyed map" do
      fun = Celixir.to_fun!("age >= 18 && status == 'active'")
      assert {:ok, true} = fun.(%{"age" => 25, "status" => "active"})
      assert {:ok, false} = fun.(%{"age" => 15, "status" => "active"})
    end

    test "accepts atom-keyed map (backward compatible)" do
      fun = Celixir.to_fun!("x + 1")
      assert {:ok, 11} = fun.(%{x: 10})
    end
  end

  describe "container resolution with string-keyed variables" do
    test "resolves qualified names against string-keyed variables" do
      env =
        %{"com.example.x" => 42}
        |> Environment.new()
        |> Environment.set_container("com.example")

      assert {:ok, 42} = Celixir.eval("x", env)
    end

    test "falls back to unqualified name" do
      env =
        %{"x" => 99}
        |> Environment.new()
        |> Environment.set_container("com.example")

      assert {:ok, 99} = Celixir.eval("x", env)
    end
  end
end
