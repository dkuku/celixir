defmodule Celixir.EnvironmentAtomTest do
  use ExUnit.Case

  alias Celixir.Environment

  describe "atom values in env bindings" do
    test "top-level atom is converted to string" do
      env = Environment.new(%{role: :admin})
      assert {:ok, true} = Celixir.eval("role == 'admin'", env)
      assert {:ok, false} = Celixir.eval("role == 'user'", env)
    end

    test "atom inside nested map is converted" do
      env = Environment.new(%{user: %{role: :admin, name: "alice"}})
      assert {:ok, true} = Celixir.eval("user.role == 'admin'", env)
      assert {:ok, true} = Celixir.eval("user.name == 'alice'", env)
    end

    test "deeply nested atom is converted" do
      env = Environment.new(%{a: %{b: %{c: :deep}}})
      assert {:ok, true} = Celixir.eval("a.b.c == 'deep'", env)
    end

    test "atoms inside lists are converted" do
      env = Environment.new(%{tags: [:red, :green, :blue]})
      assert {:ok, true} = Celixir.eval("tags[0] == 'red'", env)
      assert {:ok, true} = Celixir.eval("tags == ['red', 'green', 'blue']", env)
      assert {:ok, true} = Celixir.eval("'green' in tags", env)
    end

    test "atoms in list of maps" do
      env = Environment.new(%{users: [%{role: :admin}, %{role: :user}]})
      assert {:ok, true} = Celixir.eval("users[0].role == 'admin'", env)
      assert {:ok, true} = Celixir.eval("users[1].role == 'user'", env)
    end

    test "put_variable converts atom value" do
      env = Environment.put_variable(Environment.new(), :status, :active)
      assert {:ok, true} = Celixir.eval("status == 'active'", env)
    end

    test "put_variable converts atoms in nested structures" do
      env = Environment.put_variable(Environment.new(), :user, %{role: :admin, perms: [:read, :write]})

      assert {:ok, true} = Celixir.eval("user.role == 'admin'", env)
      assert {:ok, true} = Celixir.eval("user.perms == ['read', 'write']", env)
    end

    test "put_local converts atom value" do
      env = Environment.put_local(Environment.new(), :current_role, :admin)
      assert {:ok, true} = Celixir.eval("current_role == 'admin'", env)
    end
  end

  describe "reserved atoms are preserved" do
    test "nil maps to CEL null" do
      env = Environment.new(%{x: nil})
      assert {:ok, true} = Celixir.eval("x == null", env)
    end

    test "true/false stay booleans" do
      env = Environment.new(%{t: true, f: false})
      assert {:ok, true} = Celixir.eval("t", env)
      assert {:ok, false} = Celixir.eval("f", env)
      assert {:ok, true} = Celixir.eval("t && !f", env)
    end

    test "nil inside nested map is preserved" do
      env = Environment.new(%{user: %{deleted_at: nil}})
      assert {:ok, true} = Celixir.eval("user.deleted_at == null", env)
    end

    test "booleans inside list are preserved" do
      env = Environment.new(%{flags: [true, false, true]})
      assert {:ok, true} = Celixir.eval("flags[0]", env)
      assert {:ok, false} = Celixir.eval("flags[1]", env)
    end
  end

  describe "non-atom values are unchanged" do
    test "strings, ints, floats pass through" do
      env = Environment.new(%{s: "hi", i: 42, f: 1.5})
      assert {:ok, true} = Celixir.eval("s == 'hi' && i == 42 && f == 1.5", env)
    end

    test "structs are left for the type adapter" do
      # Range is a built-in Elixir struct; it should survive encoding untouched.
      env = Environment.new(%{r: 1..5})
      {:ok, r} = Map.fetch(env.variables, "r")
      assert r == 1..5
    end
  end

  describe "atom map keys" do
    test "atom keys are encoded, so every access path agrees" do
      env = Environment.new(%{user: %{role: :admin}})

      assert {:ok, true} = Celixir.eval("user.role == 'admin'", env)
      assert {:ok, true} = Celixir.eval("user['role'] == 'admin'", env)
      assert {:ok, true} = Celixir.eval("'role' in user", env)
      assert {:ok, ["role"]} = Celixir.eval("user.map(k, k)", env)
    end

    test "non-atom map keys keep their type" do
      # CEL map keys are int/uint/bool/string; only atoms have no counterpart.
      env = Environment.new(%{"m" => %{1 => :a, true => :b}})
      assert {:ok, true} = Celixir.eval("m[1] == 'a'", env)
      assert {:ok, true} = Celixir.eval("m[true] == 'b'", env)
    end
  end

  describe "binding keys that are neither atoms nor strings" do
    test "integer and charlist keys are stringified" do
      assert Environment.new(%{1 => 5}).variables == %{"1" => 5}
      assert Environment.new(%{~c"cl" => 5}).variables == %{"cl" => 5}
      assert Environment.put_variable(Environment.new(), 1, 5).variables == %{"1" => 5}
    end
  end

  describe "comprehensions stay linear" do
    # Comprehension accumulators grow with each iteration. Encoding one on every
    # step made map/filter quadratic: 8k items took 373ms against 1ms without.
    #
    # n is tuned against measurement, not extrapolation. With the bug present
    # this eval takes 2.0s at 30k (228ms/911ms/2015ms at 10k/20k/30k); without
    # it, ~10ms. A 1s timeout sits between them with 100x headroom on the linear
    # side. Larger n is not better: past ~50k the quadratic case allocates hard
    # enough to starve ExUnit's timeout, hanging the suite instead of failing.
    @tag timeout: 1_000
    test "map over a large list does not degrade quadratically" do
      items = Enum.to_list(1..30_000)
      assert {:ok, result} = Celixir.eval("items.map(x, x * 2)", %{"items" => items})
      assert length(result) == 30_000
    end

    # The predicate keeps every item on purpose: the cost is driven by how large
    # the accumulator grows, so a selective filter would stay under the timeout
    # even with the bug present and guard nothing.
    @tag timeout: 1_000
    test "filter over a large list does not degrade quadratically" do
      items = Enum.to_list(1..30_000)
      assert {:ok, result} = Celixir.eval("items.filter(x, x > 0)", %{"items" => items})
      assert length(result) == 30_000
    end
  end
end
