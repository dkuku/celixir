defmodule Celixir.EncodeTest do
  use ExUnit.Case

  alias Celixir.Types.Optional

  describe "encode/1" do
    test "integers become cel_int" do
      assert Celixir.encode(42) == {:cel_int, 42}
      assert Celixir.encode(0) == {:cel_int, 0}
      assert Celixir.encode(-5) == {:cel_int, -5}
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
      assert Celixir.encode([1, 2, 3]) == [{:cel_int, 1}, {:cel_int, 2}, {:cel_int, 3}]
      assert Celixir.encode(["a", 1]) == ["a", {:cel_int, 1}]
    end

    test "maps are recursively encoded" do
      assert Celixir.encode(%{"a" => 1}) == %{"a" => {:cel_int, 1}}
      assert Celixir.encode(%{1 => "x"}) == %{{:cel_int, 1} => "x"}
    end

    test "optional with value" do
      assert Celixir.encode({:optional, 42}) == %Optional{has_value: true, value: {:cel_int, 42}}
    end

    test "optional none" do
      assert Celixir.encode(:optional_none) == %Optional{has_value: false}
    end

    test "nested structures" do
      input = %{"list" => [1, 2], "nested" => %{"x" => 3}}
      expected = %{"list" => [{:cel_int, 1}, {:cel_int, 2}], "nested" => %{"x" => {:cel_int, 3}}}
      assert Celixir.encode(input) == expected
    end
  end

  describe "encode_uint/1" do
    test "encodes as cel_uint" do
      assert Celixir.encode_uint(42) == {:cel_uint, 42}
      assert Celixir.encode_uint(0) == {:cel_uint, 0}
    end
  end

  describe "encode_bytes/1" do
    test "encodes as cel_bytes" do
      assert Celixir.encode_bytes(<<1, 2, 3>>) == {:cel_bytes, <<1, 2, 3>>}
      assert Celixir.encode_bytes("hello") == {:cel_bytes, "hello"}
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
