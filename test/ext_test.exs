defmodule CelixirExtTest do
  use ExUnit.Case

  alias Celixir.Ext.Encoders
  alias Celixir.Ext.Lists
  alias Celixir.Ext.Math
  alias Celixir.Ext.Regex, as: CelRegex
  alias Celixir.Ext.Sets
  alias Celixir.Ext.Strings

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp eval(expr, bindings \\ %{}) do
    Celixir.eval(expr, bindings)
  end

  defp eval!(expr, bindings \\ %{}) do
    Celixir.eval!(expr, bindings)
  end

  # ---------------------------------------------------------------------------
  # Celixir.Ext.Math
  # ---------------------------------------------------------------------------

  describe "Celixir.Ext.Math.register/1" do
    test "all math functions work after registration" do
      env = Celixir.Environment.new() |> Math.register()
      assert Celixir.eval!("math.sqrt(16.0)", env) == 4.0
      assert Celixir.eval!("math.ceil(1.1)", env) == 2.0
      assert Celixir.eval!("math.floor(1.9)", env) == 1.0
      assert Celixir.eval!("math.round(1.5)", env) == 2.0
      assert Celixir.eval!("math.trunc(1.9)", env) == 1.0
      assert Celixir.eval!("math.isNaN(0.0/0.0)", env) == true
      assert Celixir.eval!("math.isInf(1.0/0.0)", env) == true
      assert Celixir.eval!("math.isFinite(1.0)", env) == true
    end

    test "register/0 uses empty env" do
      env = Math.register()
      assert Celixir.eval!("math.sqrt(4.0)", env) == 2.0
    end
  end

  describe "math.sqrt" do
    test "sqrt of perfect squares" do
      assert eval!("math.sqrt(1.0)") == 1.0
      assert eval!("math.sqrt(4.0)") == 2.0
      assert eval!("math.sqrt(9.0)") == 3.0
      assert eval!("math.sqrt(81)") == 9.0
      assert eval!("math.sqrt(0)") == 0.0
    end

    test "sqrt of non-perfect square" do
      assert eval!("math.sqrt(2.0)") == :math.sqrt(2.0)
    end

    test "sqrt of negative returns NaN" do
      assert eval!("math.isNaN(math.sqrt(-1.0))") == true
      assert eval!("math.isNaN(math.sqrt(-15))") == true
    end

    test "sqrt of NaN is NaN" do
      assert eval!("math.isNaN(math.sqrt(0.0/0.0))") == true
    end

    test "sqrt of +Inf is +Inf" do
      assert eval!("math.sqrt(1.0/0.0)") == :infinity
    end
  end

  # ---------------------------------------------------------------------------
  # Celixir.Ext.Strings
  # ---------------------------------------------------------------------------

  describe "Celixir.Ext.Strings.register/1" do
    test "strings.quote works after registration" do
      env = Celixir.Environment.new() |> Strings.register()
      assert Celixir.eval!(~s|strings.quote("hello")|, env) == ~s("hello")
    end
  end

  describe "strings.quote" do
    test "wraps in double quotes" do
      assert eval!(~s|strings.quote("hello")|) == ~s("hello")
    end

    test "escapes double quotes inside" do
      assert eval!(~S|strings.quote("say \"hi\"")|) == ~s("say \\"hi\\"")
    end

    test "escapes common escape sequences" do
      result = eval!(~s|strings.quote("a\\nb")|)
      assert String.contains?(result, "\\n")
    end

    test "non-ASCII unicode is preserved" do
      assert eval!(~s|strings.quote("café")|) == ~s("café")
    end
  end

  # ---------------------------------------------------------------------------
  # Celixir.Ext.Lists
  # ---------------------------------------------------------------------------

  describe "Celixir.Ext.Lists.register/1" do
    test "functions work after registration" do
      env = Celixir.Environment.new() |> Lists.register()
      assert Celixir.eval!("lists.range(3)", env) == [0, 1, 2]
      assert Celixir.eval!("[1, 2, 2].distinct()", env) == [1, 2]
      assert Celixir.eval!("[1, 2, 3].first().value()", env) == 1
      assert Celixir.eval!("[1, 2, 3].last().value()", env) == 3
    end
  end

  describe "lists.range" do
    test "range(0) is empty" do
      assert eval!("lists.range(0)") == []
    end

    test "range(1) is [0]" do
      assert eval!("lists.range(1)") == [0]
    end

    test "range(5) is [0,1,2,3,4]" do
      assert eval!("lists.range(5)") == [0, 1, 2, 3, 4]
    end

    test "range result length matches argument" do
      assert eval!("lists.range(10).size()") == 10
    end

    test "negative range errors" do
      assert {:error, _} = eval("lists.range(-1)")
    end

    test "range can be used in comprehension" do
      assert eval!("lists.range(3).map(i, i * 2)") == [0, 2, 4]
    end
  end

  describe "list.distinct" do
    test "empty list" do
      assert eval!("[].distinct()") == []
    end

    test "no duplicates" do
      assert eval!("[1, 2, 3].distinct()") == [1, 2, 3]
    end

    test "all duplicates collapses to one" do
      assert eval!("[1, 1, 1].distinct()") == [1]
    end

    test "preserves first occurrence order" do
      assert eval!("[3, 1, 2, 1, 3].distinct()") == [3, 1, 2]
    end

    test "strings" do
      assert eval!(~S|["b", "b", "c", "a", "c"].distinct()|) == ["b", "c", "a"]
    end

    test "mixed types" do
      assert eval!(~S|[1, "b", 2, "b"].distinct()|) == [1, "b", 2]
    end
  end

  describe "list.first" do
    test "non-empty list returns optional with value" do
      assert eval!("[1, 2, 3].first().value()") == 1
      assert eval!("[1, 2, 3].first().hasValue()") == true
    end

    test "empty list returns optional.none" do
      assert eval!("[].first().hasValue()") == false
    end

    test "orValue on empty" do
      assert eval!("[].first().orValue(99)") == 99
    end

    test "first of single-element list" do
      assert eval!("[42].first().value()") == 42
    end

    test "only first element is returned" do
      assert eval!("[10, 20, 30].first().value()") == 10
    end
  end

  describe "list.last" do
    test "non-empty list returns optional with last value" do
      assert eval!("[1, 2, 3].last().value()") == 3
      assert eval!("[1, 2, 3].last().hasValue()") == true
    end

    test "empty list returns optional.none" do
      assert eval!("[].last().hasValue()") == false
    end

    test "orValue fallback" do
      assert eval!(~s|[].last().orValue("test")|) == "test"
    end

    test "last of single-element list" do
      assert eval!("[42].last().value()") == 42
    end

    test "last == first for single element" do
      assert eval!("[5].first().value() == [5].last().value()") == true
    end
  end

  describe "list.flatten with depth" do
    test "depth 0 is identity" do
      assert eval!("[1, [2, 3]].flatten(0)") == [1, [2, 3]]
    end

    test "depth 1 flattens one level" do
      assert eval!("[1, [2, [3, 4]]].flatten(1)") == [1, 2, [3, 4]]
    end

    test "depth 2" do
      assert eval!("[1, [2, [3, [4]]]].flatten(2)") == [1, 2, 3, [4]]
    end

    test "depth >= nesting flattens completely" do
      assert eval!("[1, [2, [3, [4]]]].flatten(3)") == [1, 2, 3, 4]
    end

    test "negative depth errors" do
      assert {:error, _} = eval("[1, [2]].flatten(-1)")
    end

    test "empty list flattened" do
      assert eval!("[].flatten(1)") == []
    end

    test "already-flat list unchanged at depth 1" do
      assert eval!("[1, 2, 3].flatten(1)") == [1, 2, 3]
    end
  end

  describe "list.sortBy" do
    test "sort by element value" do
      assert eval!("[3, 1, 2].sortBy(e, e)") == [1, 2, 3]
    end

    test "sort by negative preserves CEL order" do
      assert eval!("[-1, -3, -2].sortBy(e, e)") == [-3, -2, -1]
    end

    test "sort strings alphabetically" do
      assert eval!(~S|["banana", "apple", "cherry"].sortBy(e, e)|) ==
               ["apple", "banana", "cherry"]
    end

    test "sort by second element of pair" do
      result = eval!("[[1, 10], [2, 1], [3, 5]].sortBy(e, e[1])")
      assert result == [[2, 1], [3, 5], [1, 10]]
    end

    test "sort already-sorted list is stable-ish" do
      assert eval!("[1, 2, 3].sortBy(e, e)") == [1, 2, 3]
    end

    test "sort single element" do
      assert eval!("[42].sortBy(e, e)") == [42]
    end

    test "sort empty list" do
      assert eval!("[].sortBy(e, e)") == []
    end
  end

  # ---------------------------------------------------------------------------
  # Celixir.Ext.Sets
  # ---------------------------------------------------------------------------

  describe "Celixir.Ext.Sets.register/1" do
    test "functions work after registration" do
      env = Celixir.Environment.new() |> Sets.register()
      assert Celixir.eval!("sets.contains([1,2,3],[2,3])", env) == true
      assert Celixir.eval!("sets.equivalent([1,2],[2,1])", env) == true
      assert Celixir.eval!("sets.intersects([1,2],[2,3])", env) == true
    end
  end

  describe "sets.contains" do
    test "empty sublist is always contained" do
      assert eval!("sets.contains([], [])") == true
      assert eval!("sets.contains([1, 2], [])") == true
    end

    test "non-empty list not in empty list" do
      assert eval!("sets.contains([], [1])") == false
    end

    test "subset" do
      assert eval!("sets.contains([1, 2, 3, 4], [2, 3])") == true
    end

    test "non-subset" do
      assert eval!("sets.contains([1, 2], [3])") == false
    end
  end

  describe "sets.equivalent" do
    test "empty lists are equivalent" do
      assert eval!("sets.equivalent([], [])") == true
    end

    test "same elements different order" do
      assert eval!("sets.equivalent([1, 2, 3], [3, 2, 1])") == true
    end

    test "duplicates don't break equivalence" do
      assert eval!("sets.equivalent([1], [1, 1])") == true
    end

    test "different elements not equivalent" do
      assert eval!("sets.equivalent([1, 2], [1, 3])") == false
    end

    test "different sizes not equivalent (no shared element)" do
      assert eval!("sets.equivalent([1, 2], [1, 2, 3])") == false
    end
  end

  describe "sets.intersects" do
    test "empty lists don't intersect" do
      assert eval!("sets.intersects([], [])") == false
      assert eval!("sets.intersects([1], [])") == false
    end

    test "shared element" do
      assert eval!("sets.intersects([1, 2], [2, 3])") == true
    end

    test "disjoint lists" do
      assert eval!("sets.intersects([1, 2], [3, 4])") == false
    end
  end

  # ---------------------------------------------------------------------------
  # Celixir.Ext.Encoders
  # ---------------------------------------------------------------------------

  describe "Celixir.Ext.Encoders.register/1" do
    test "base64 functions work after registration" do
      env = Celixir.Environment.new() |> Encoders.register()
      assert Celixir.eval!(~s|base64.encode("hello")|, env) == "aGVsbG8="
    end
  end

  describe "base64.encode / base64.decode" do
    test "encode bytes" do
      assert eval!(~s|base64.encode(b"hello")|) == "aGVsbG8="
    end

    test "encode string" do
      assert eval!(~s|base64.encode("hello")|) == "aGVsbG8="
    end

    test "decode valid base64 with padding" do
      assert eval!(~s|base64.decode("aGVsbG8=")|) == "hello"
    end

    test "decode valid base64 without padding" do
      assert eval!(~s|base64.decode("aGVsbG8")|) == "hello"
    end

    test "decode invalid base64 errors" do
      assert {:error, _} = eval(~s|base64.decode("not!!base64")|)
    end

    test "round-trip" do
      assert eval!(~s|base64.decode(base64.encode("round trip"))|) == "round trip"
    end
  end

  # ---------------------------------------------------------------------------
  # Celixir.Ext.Regex
  # ---------------------------------------------------------------------------

  describe "Celixir.Ext.Regex.register/1" do
    test "register is a no-op (built-ins always available)" do
      env = Celixir.Environment.new() |> CelRegex.register()
      assert Celixir.eval!(~s|regex.replace("hello", "hello", "hi")|, env) == "hi"
    end
  end

  describe "regex.replace" do
    test "replace all occurrences" do
      assert eval!(~s|regex.replace("hello world hello", "hello", "hi")|) == "hi world hi"
    end

    test "no match returns original" do
      assert eval!(~s|regex.replace("hello", "xyz", "abc")|) == "hello"
    end

    test "count=0 keeps original" do
      assert eval!(~s|regex.replace("banana", "a", "x", 0)|) == "banana"
    end

    test "count=1 replaces first only" do
      assert eval!(~s|regex.replace("banana", "a", "x", 1)|) == "bxnana"
    end

    test "count=2 replaces first two" do
      assert eval!(~s|regex.replace("banana", "a", "x", 2)|) == "bxnxna"
    end

    test "count=-1 replaces all" do
      assert eval!(~s|regex.replace("banana", "a", "x", -1)|) == "bxnxnx"
    end

    test "negative count replaces all" do
      assert eval!(~s|regex.replace("banana", "a", "x", -12)|) == "bxnxnx"
    end

    test "backreference \\\\1 in replacement" do
      assert eval!(~s|regex.replace("foo bar", "(fo)o (ba)r", "\\\\2 \\\\1")|) == "ba fo"
    end

    test "invalid $ replacement errors" do
      assert {:error, _} = eval(~s|regex.replace("test", "(.)", "$2")|)
    end

    test "invalid backslash letter replacement errors" do
      assert {:error, _} = eval(~s|regex.replace("test", "(.)","\\\\a")|)
    end

    test "invalid regex errors" do
      assert {:error, _} = eval(~s|regex.replace("foo", "(", "x")|)
    end

    test "empty replacement clears matches" do
      assert eval!(~s|regex.replace("hello world", "\\\\s+", "")|) == "helloworld"
    end

    test "replace with regex metacharacters in pattern" do
      assert eval!(~s|regex.replace("1+2=3", "\\\\+", "plus")|) == "1plus2=3"
    end
  end

  describe "regex.extract" do
    test "no groups — returns full match as optional" do
      assert eval!(~s|regex.extract("hello world", "hello").value()|) == "hello"
    end

    test "one group — returns captured group" do
      assert eval!(~s|regex.extract("hello world", "hello(.*)").value()|) == " world"
    end

    test "no match returns optional.none" do
      assert eval!(~s|regex.extract("HELLO", "hello").hasValue()|) == false
    end

    test "optional.orValue on no match" do
      assert eval!(~s|regex.extract("HELLO", "hello").orValue("default")|) == "default"
    end

    test "extract named group (still one capture group)" do
      assert eval!(~s|regex.extract("item-A", "item-(\\\\w+)").value()|) == "A"
    end

    test "multiple capture groups errors" do
      assert {:error, _} = eval(~s|regex.extract("user@domain", "(.*)@([^.]*)")|)
    end

    test "invalid regex errors" do
      assert {:error, _} = eval(~s|regex.extract("test", "(")|)
    end
  end

  describe "regex.extractAll" do
    test "returns all full matches" do
      assert eval!(~s|regex.extractAll("id:123, id:456", "id:\\\\d+")|) ==
               ["id:123", "id:456"]
    end

    test "returns empty list when no match" do
      assert eval!(~s|regex.extractAll("id:123", "xyz")|) == []
    end

    test "one capture group returns groups" do
      result = eval!(~s|regex.extractAll("cat bat hat", "[cbh](at)")|)
      assert result == ["at", "at", "at"]
    end

    test "multiple groups errors" do
      assert {:error, _} =
               eval(~s|regex.extractAll("user@domain", "(.*)@([^.]*)")|)
    end

    test "invalid regex errors" do
      assert {:error, _} = eval(~s|regex.extractAll("test", "(")|)
    end
  end

  # ---------------------------------------------------------------------------
  # transformMapEntry
  # ---------------------------------------------------------------------------

  describe "transformMapEntry" do
    test "invert map key-value" do
      result = eval!(~S|{"greeting": "hello"}.transformMapEntry(k, v, {v: k})|)
      assert result == %{"hello" => "greeting"}
    end

    test "list to reverse-index map" do
      result = eval!("[1, 2, 3].transformMapEntry(i, v, {v: i})")
      assert result == %{1 => 0, 2 => 1, 3 => 2}
    end

    test "with filter — only include matching pairs" do
      result = eval!("[1, 2, 3, 4].transformMapEntry(i, v, v % 2 == 0, {v: i})")
      assert result == %{2 => 1, 4 => 3}
    end

    test "empty input produces empty map" do
      assert eval!("{}.transformMapEntry(k, v, {v: k})") == %{}
    end

    test "duplicate key errors" do
      assert {:error, _} =
               eval(~S|{"a": "x", "b": "x"}.transformMapEntry(k, v, {v: k})|)
    end
  end

  # ---------------------------------------------------------------------------
  # Module composition pattern
  # ---------------------------------------------------------------------------

  describe "multiple extensions composed on one environment" do
    test "all extensions work together" do
      env =
        Celixir.Environment.new()
        |> Math.register()
        |> Strings.register()
        |> Lists.register()
        |> Sets.register()
        |> Encoders.register()
        |> CelRegex.register()

      assert Celixir.eval!("math.sqrt(9.0)", env) == 3.0
      assert Celixir.eval!("lists.range(3)", env) == [0, 1, 2]
      assert Celixir.eval!("sets.contains([1,2,3],[2])", env) == true
      assert Celixir.eval!(~s|base64.encode("hi")|, env) == "aGk="
      assert Celixir.eval!(~s|regex.replace("ab","a","x")|, env) == "xb"
    end
  end
end
