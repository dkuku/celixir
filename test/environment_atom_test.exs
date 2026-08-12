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

  describe "atom keys vs atom values" do
    test "atom map keys still work for field access (keys not converted)" do
      env = Environment.new(%{user: %{role: :admin}})
      # role key stays atom internally, value becomes string
      assert {:ok, true} = Celixir.eval("user.role == 'admin'", env)
    end
  end
end
