defmodule Celixir.EncodeTest do
  use ExUnit.Case

  alias Celixir.Types.Optional

  describe "encode/1" do
    test "integers pass through" do
      assert Celixir.encode(42) == 42
      assert Celixir.encode(0) == 0
      assert Celixir.encode(-5) == -5
    end

    test "strings pass through" do
      assert Celixir.encode("hello") == "hello"
    end

    test "floats pass through" do
      assert Celixir.encode(3.14) == 3.14
    end

    test "booleans pass through" do
      assert Celixir.encode(true) == true
      assert Celixir.encode(false) == false
    end

    test "nil passes through" do
      assert Celixir.encode(nil) == nil
    end

    test "lists are recursively encoded" do
      assert Celixir.encode([1, 2, 3]) == [1, 2, 3]
      assert Celixir.encode(["a", 1]) == ["a", 1]
    end

    test "maps are recursively encoded" do
      assert Celixir.encode(%{"a" => 1}) == %{"a" => 1}
      assert Celixir.encode(%{1 => "x"}) == %{1 => "x"}
    end

    test "atoms become strings" do
      assert Celixir.encode(:admin) == "admin"
      assert Celixir.encode([:red, :green]) == ["red", "green"]
    end

    test "atoms are encoded as map keys and as map values" do
      assert Celixir.encode(%{role: :admin}) == %{"role" => "admin"}
      assert Celixir.encode(%{a: %{b: [:c]}}) == %{"a" => %{"b" => ["c"]}}
    end

    test "atoms carrying CEL meaning are preserved" do
      assert Celixir.encode(nil) == nil
      assert Celixir.encode(true) == true
      assert Celixir.encode(false) == false
      assert Celixir.encode(:nan) == :nan
      assert Celixir.encode(:infinity) == :infinity
      assert Celixir.encode(:neg_infinity) == :neg_infinity
      assert Celixir.encode(%{nil => 1, true => 2}) == %{nil => 1, true => 2}
    end

    test "non-atom map keys keep their type" do
      # CEL map keys are int/uint/bool/string — only atoms have no counterpart.
      assert Celixir.encode(%{1 => :a, "b" => :c}) == %{1 => "a", "b" => "c"}
    end

    test "structs are left for the type adapter" do
      assert Celixir.encode(1..5) == 1..5
    end

    test "a value needing no encoding is returned unchanged" do
      map = %{"a" => 1, "b" => [2, 3]}
      refute Celixir.needs_encoding?(map)
      assert Celixir.encode(map) === map
    end

    test "needs_encoding? detects atoms at any depth" do
      assert Celixir.needs_encoding?(:admin)
      assert Celixir.needs_encoding?(%{"a" => %{"b" => [:c]}})
      assert Celixir.needs_encoding?(%{role: "admin"})
      refute Celixir.needs_encoding?(%{"a" => [1, nil, true]})
      refute Celixir.needs_encoding?(1..5)
    end

    test "agrees with Environment binding" do
      env = Celixir.Environment.new(%{role: :admin, tags: [:a]})
      assert env.variables == Celixir.encode(%{"role" => :admin, "tags" => [:a]})
    end

    test "optional with value" do
      assert Celixir.encode({:optional, 42}) == %Optional{has_value: true, value: 42}
    end

    test "optional none" do
      assert Celixir.encode(:optional_none) == %Optional{has_value: false}
    end

    test "nested structures" do
      input = %{"list" => [1, 2], "nested" => %{"x" => 3}}
      assert Celixir.encode(input) == input
    end
  end

  describe "roundtrip encode/unwrap" do
    test "unwrap(encode(v)) == v for simple values" do
      for val <- [42, "hello", 3.14, true, false, nil] do
        assert Celixir.unwrap(Celixir.encode(val)) == val
      end
    end

    test "roundtrip for lists" do
      assert Celixir.unwrap(Celixir.encode([1, 2, 3])) == [1, 2, 3]
    end

    test "roundtrip for maps" do
      assert Celixir.unwrap(Celixir.encode(%{"a" => 1})) == %{"a" => 1}
    end

    test "roundtrip for optional" do
      assert Celixir.unwrap(Celixir.encode({:optional, 5})) == {:optional, 5}
      assert Celixir.unwrap(Celixir.encode(:optional_none)) == :optional_none
    end
  end
end
