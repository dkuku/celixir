defmodule Celixir.EnvironmentAtomTest do
  use ExUnit.Case

  alias Celixir.Environment
  alias Celixir.Proto.Codec

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

  describe "maps mixing atom and string keys" do
    # normalize_keys/1 decides on the first key the map iterates. Erlang orders
    # atoms before binaries in a small (flatmap) map, so a mixed map under 32
    # entries always led with the atom and took the full conversion. Past 32 the
    # map becomes a hashmap, iteration order goes to hashing, and a mixed map
    # could lead with a binary — which used to skip key conversion entirely and
    # leave the atom-keyed variable unresolvable.
    setup do
      %{big: for(i <- 1..40, into: %{}, do: {"k#{i}", i})}
    end

    test "atom key resolves in a small mixed map" do
      assert {:ok, true} = Celixir.eval("role == 'admin'", %{"x" => 1, :role => :admin})
    end

    test "atom key resolves in a large mixed map", %{big: big} do
      mixed = Map.put(big, :role, :admin)
      assert {:ok, "k38"} = Celixir.eval("k38", %{"k38" => "k38"})
      assert {:ok, true} = Celixir.eval("role == 'admin'", mixed)
      assert {:ok, true} = Celixir.eval("k1 == 1", mixed)
    end

    test "atom key resolves when no value needs encoding", %{big: big} do
      # The rebuild is gated on needs_encoding?/1, which scans keys as well as
      # values — so an atom key alone must be enough to trigger it.
      mixed = Map.put(big, :plain, "no atoms here")
      assert {:ok, true} = Celixir.eval("plain == 'no atoms here'", mixed)
    end

    test "the compiled path agrees with the eval path", %{big: big} do
      mixed = Map.put(big, :role, :admin)
      {:ok, program} = Celixir.compile("role == 'admin'")
      assert {:ok, true} = Celixir.Program.eval(program, mixed)
      assert {:ok, true} = Celixir.Program.eval(program, %{"x" => 1, :role => :admin})
    end

    test "a uniformly string-keyed map is still bound without rebuilding", %{big: big} do
      # The allocation-free fast path: same term back, not a copy.
      assert :erts_debug.same(Environment.new(big).variables, big)
    end
  end

  describe "optional lambdas" do
    # optMap/optFlatMap bind their variable from a value already unwrapped from
    # an Optional, so it has been through the boundary once already. Binding it
    # raw must not change what the expression sees.
    test "optMap sees an encoded value" do
      env = Environment.new(%{m: %{"role" => :admin}})
      assert {:ok, true} = Celixir.eval("m[?'role'].optMap(r, r == 'admin').hasValue()", env)
    end

    test "optFlatMap sees an encoded value" do
      env = Environment.new(%{m: %{"role" => :admin}})
      assert {:ok, "admin"} = Celixir.eval("m[?'role'].optFlatMap(r, optional.of(r)).value()", env)
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

  describe "compiler and proto codec do not leak atoms" do
    test "default :closure compilation creates zero new atoms for dynamic expressions and variables" do
      # Warm up parser/compiler modules first so module-load atoms don't skew the count
      {:ok, warmup} = Celixir.compile("a + b == 2")
      assert {:ok, true} = Celixir.Program.eval(warmup, %{"a" => 1, "b" => 1})

      atoms_before = :erlang.system_info(:atom_count)

      for i <- 1..50 do
        var_a = "dyn_var_alpha_#{i}_#{System.unique_integer([:positive])}"
        var_b = "dyn_var_beta_#{i}_#{System.unique_integer([:positive])}"
        expr = "#{var_a} + #{var_b} == #{i * 2}"

        {:ok, prog} = Celixir.compile(expr)
        assert {:ok, true} = Celixir.Program.eval(prog, %{var_a => i, var_b => i})
        assert catch_error(String.to_existing_atom(var_a))
        assert catch_error(String.to_existing_atom(var_b))
      end

      atoms_after = :erlang.system_info(:atom_count)
      assert atoms_after == atoms_before
    end

    test "strategy: :module (jit: true) works and does not intern variable names as atoms" do
      var_a = "jit_var_alpha_#{System.unique_integer([:positive])}"
      var_b = "jit_var_beta_#{System.unique_integer([:positive])}"
      var_z = "jit_iter_#{System.unique_integer([:positive])}"

      {:ok, prog} =
        Celixir.compile(
          "#{var_a} * #{var_b} + ([1, 2, 3].all(#{var_z}, #{var_z} > 0) ? 1 : 0)",
          jit: true
        )

      assert {:ok, 7} = Celixir.Program.eval(prog, %{var_a => 2, var_b => 3})

      # Variable names and comprehension iterator names are never turned into atoms
      assert catch_error(String.to_existing_atom(var_a))
      assert catch_error(String.to_existing_atom(var_b))
      assert catch_error(String.to_existing_atom(var_z))
    end

    test "nested comprehensions preserve outer iteration variables in both strategies" do
      expr = "[1, 2].map(x, [10, 20].map(y, x + y))"
      {:ok, closure_prog} = Celixir.compile(expr, strategy: :closure)
      {:ok, module_prog} = Celixir.compile(expr, strategy: :module)

      assert {:ok, [[11, 21], [12, 22]]} = Celixir.Program.eval(closure_prog)
      assert {:ok, [[11, 21], [12, 22]]} = Celixir.Program.eval(module_prog)
    end

    test "Proto.Codec.resolve_module does not leak atoms for unknown type names" do
      _ = Codec.resolve_module("google.protobuf.Timestamp")
      atoms_before = :erlang.system_info(:atom_count)

      for i <- 1..50 do
        unknown = "unknown.pkg_#{i}_#{System.unique_integer([:positive])}.Msg"
        assert nil == Codec.resolve_module(unknown)
      end

      assert :erlang.system_info(:atom_count) == atoms_before
    end
  end

  describe "checker optional literals" do
    test "type-checks optional list elements and map entries without FunctionClauseError" do
      {:ok, list_ast} = Celixir.parse("[1, ?optional.of(2)]")
      assert :ok = Celixir.Checker.check(list_ast)
      assert {:list, :int} = Celixir.Checker.infer(list_ast)

      {:ok, map_ast} = Celixir.parse(~s|{"a": 1, ?"b": optional.of(2)}|)
      assert :ok = Celixir.Checker.check(map_ast)
      assert {:map, :string, :int} = Celixir.Checker.infer(map_ast)
    end
  end
end
