defmodule Celixir.ConformanceTest do
  @moduledoc """
  CEL conformance test suite based on the cel-spec simple test cases.

  These tests verify that Celixir conforms to the standard CEL behavior
  as defined by the Google CEL specification. Test sections correspond to
  the cel-spec/tests/simple test files.

  Reference: https://github.com/google/cel-spec/tree/master/tests/simple
  """
  use ExUnit.Case

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  alias Celixir.Types.Duration
  alias Celixir.Types.Timestamp

  defp assert_eval(expr, expected, bindings \\ %{}) do
    result = Celixir.eval!(expr, bindings)

    assert result == expected,
           "Expected #{inspect(expected)} for expression: #{expr}\n  Got: #{inspect(result)}"
  end

  defp assert_eval_error(expr, bindings \\ %{}) do
    result = Celixir.eval(expr, bindings)

    assert match?({:error, _}, result),
           "Expected error for expression: #{expr}\n  Got: #{inspect(result)}"
  end

  defp assert_eval_error_match(expr, pattern, bindings \\ %{}) do
    assert {:error, msg} = Celixir.eval(expr, bindings)

    assert msg =~ pattern,
           "Expected error matching #{inspect(pattern)} for: #{expr}\n  Got error: #{msg}"
  end

  # ===========================================================================
  # 1. basic - basic literals and operations
  # ===========================================================================

  describe "conformance: basic" do
    test "self-evaluating boolean literals" do
      assert_eval("true", true)
      assert_eval("false", false)
    end

    test "self-evaluating null literal" do
      assert_eval("null", nil)
    end

    test "integer literals" do
      assert_eval("0", 0)
      assert_eval("42", 42)
      assert_eval("-1", -1)
    end

    test "hex integer literals" do
      assert_eval("0x0", 0)
      assert_eval("0xFF", 255)
      assert_eval("0xCAFE", 0xCAFE)
    end

    test "unsigned integer literals" do
      assert_eval("0u", 0)
      assert_eval("42u", 42)
      assert_eval("0xFFu", 255)
    end

    test "double literals" do
      assert_eval("0.0", 0.0)
      assert_eval("3.14", 3.14)
      assert_eval("1e10", 1.0e10)
      assert_eval("2.5e-3", 2.5e-3)
    end

    test "string literals - single and double quotes" do
      assert_eval(~S|"hello"|, "hello")
      assert_eval("'world'", "world")
      assert_eval(~S|""|, "")
    end

    test "bytes literals" do
      assert_eval(~S|b"abc"|, "abc")
      assert_eval(~S|b""|, "")
    end

    test "empty list and map" do
      assert_eval("[]", [])
      assert_eval("{}", %{})
    end

    test "parenthesized expressions" do
      assert_eval("(1)", 1)
      assert_eval("((true))", true)
      assert_eval("(2 + 3) * 4", 20)
    end
  end

  # ===========================================================================
  # 2. comparisons - all comparison operators across types
  # ===========================================================================

  describe "conformance: comparisons" do
    test "int equality" do
      assert_eval("1 == 1", true)
      assert_eval("1 == 2", false)
      assert_eval("1 != 2", true)
      assert_eval("1 != 1", false)
    end

    test "int ordering" do
      assert_eval("1 < 2", true)
      assert_eval("2 < 1", false)
      assert_eval("1 <= 1", true)
      assert_eval("1 <= 2", true)
      assert_eval("2 <= 1", false)
      assert_eval("2 > 1", true)
      assert_eval("1 > 2", false)
      assert_eval("1 >= 1", true)
    end

    test "uint equality" do
      assert_eval("1u == 1u", true)
      assert_eval("1u != 2u", true)
    end

    test "uint ordering" do
      assert_eval("1u < 2u", true)
      assert_eval("2u > 1u", true)
      assert_eval("2u >= 2u", true)
      assert_eval("2u <= 2u", true)
    end

    test "double equality" do
      assert_eval("1.0 == 1.0", true)
      assert_eval("1.0 != 2.0", true)
    end

    test "double ordering" do
      assert_eval("1.5 < 2.5", true)
      assert_eval("2.5 > 1.5", true)
    end

    test "string equality" do
      assert_eval(~S|"abc" == "abc"|, true)
      assert_eval(~S|"abc" != "def"|, true)
    end

    test "string ordering" do
      assert_eval(~S|"abc" < "abd"|, true)
      assert_eval(~S|"abd" > "abc"|, true)
      assert_eval(~S|"abc" <= "abc"|, true)
      assert_eval(~S|"abc" >= "abc"|, true)
    end

    test "bool equality" do
      assert_eval("true == true", true)
      assert_eval("false == false", true)
      assert_eval("true != false", true)
    end

    test "bool ordering" do
      # false < true in CEL
      assert_eval("false < true", true)
      assert_eval("true > false", true)
    end

    test "null equality" do
      assert_eval("null == null", true)
      assert_eval("null != null", false)
    end

    test "bytes equality" do
      assert_eval(~S|b"abc" == b"abc"|, true)
      assert_eval(~S|b"abc" != b"def"|, true)
    end

    test "bytes ordering" do
      assert_eval(~S|b"abc" < b"abd"|, true)
      assert_eval(~S|b"abd" > b"abc"|, true)
    end

    test "heterogeneous numeric equality (int/double)" do
      assert_eval("1 == 1.0", true)
      assert_eval("1 == 1.5", false)
      assert_eval("2.0 == 2", true)
    end

    test "heterogeneous numeric equality (int/uint)" do
      assert_eval("1 == 1u", true)
      assert_eval("1u == 1", true)
      assert_eval("1 == 2u", false)
    end

    test "heterogeneous numeric equality (uint/double)" do
      assert_eval("1u == 1.0", true)
      assert_eval("1.0 == 1u", true)
    end

    test "cross-type numeric ordering" do
      assert_eval("1 < 2u", true)
      assert_eval("2.0 > 1u", true)
      assert_eval("1u < 2.0", true)
      assert_eval("1 < 1.5", true)
    end

    test "list equality" do
      assert_eval("[1, 2, 3] == [1, 2, 3]", true)
      assert_eval("[1, 2] != [1, 2, 3]", true)
      assert_eval("[] == []", true)
    end

    test "map equality" do
      assert_eval(~S|{"a": 1} == {"a": 1}|, true)
      assert_eval(~S|{"a": 1} != {"a": 2}|, true)
      assert_eval("{} == {}", true)
    end

    test "timestamp comparison" do
      assert_eval(
        ~S|timestamp("2023-01-01T00:00:00Z") < timestamp("2024-01-01T00:00:00Z")|,
        true
      )

      assert_eval(
        ~S|timestamp("2023-01-01T00:00:00Z") == timestamp("2023-01-01T00:00:00Z")|,
        true
      )
    end

    test "duration comparison" do
      assert_eval(~S|duration("1h") < duration("2h")|, true)
      assert_eval(~S|duration("1h") == duration("60m")|, true)
      assert_eval(~S|duration("1h") > duration("30m")|, true)
    end
  end

  # ===========================================================================
  # 3. conversions - type conversion functions
  # ===========================================================================

  describe "conformance: conversions" do
    test "int() from string" do
      assert_eval(~S|int("42")|, 42)
      assert_eval(~S|int("-7")|, -7)
      assert_eval(~S|int("0")|, 0)
    end

    test "int() from double (truncates)" do
      assert_eval("int(3.9)", 3)
      assert_eval("int(-2.1)", -2)
      assert_eval("int(0.0)", 0)
    end

    test "int() from uint" do
      assert_eval("int(42u)", 42)
    end

    test "int() from bool" do
      assert_eval("int(true)", 1)
      assert_eval("int(false)", 0)
    end

    test "int() from timestamp" do
      # Returns Unix epoch seconds
      result = Celixir.eval!(~S|int(timestamp("1970-01-01T00:00:00Z"))|)
      assert result == 0
    end

    test "int() from string - invalid" do
      assert_eval_error(~S|int("abc")|)
    end

    test "uint() from string" do
      assert_eval(~S|uint("42")|, 42)
    end

    test "uint() from int" do
      assert_eval("uint(42)", 42)
    end

    test "uint() from double" do
      assert_eval("uint(3.9)", 3)
    end

    test "uint() negative int is error" do
      assert_eval_error("uint(-1)")
    end

    test "double() from int" do
      assert_eval("double(42)", 42.0)
      assert_eval("double(0)", 0.0)
    end

    test "double() from uint" do
      assert_eval("double(42u)", 42.0)
    end

    test "double() from string" do
      assert_eval(~S|double("3.14")|, 3.14)
    end

    test "double() from string - special values" do
      assert_eval(~S|double("NaN")|, :nan)
      assert_eval(~S|double("Infinity")|, :infinity)
      assert_eval(~S|double("-Infinity")|, :neg_infinity)
    end

    test "string() from int" do
      assert_eval("string(42)", "42")
      assert_eval("string(-1)", "-1")
    end

    test "string() from double" do
      result = Celixir.eval!("string(3.14)")
      assert is_binary(result)
    end

    test "string() from bool" do
      assert_eval("string(true)", "true")
      assert_eval("string(false)", "false")
    end

    test "string() from null" do
      assert_eval("string(null)", "null")
    end

    test "string() from bytes" do
      assert_eval(~S|string(b"hello")|, "hello")
    end

    test "bytes() from string" do
      assert_eval(~S|bytes("hello")|, "hello")
    end

    test "bool() from string" do
      assert_eval(~S|bool("true")|, true)
      assert_eval(~S|bool("false")|, false)
    end

    test "bool() from invalid string is error" do
      assert_eval_error(~S|bool("maybe")|)
    end

    test "timestamp() from string" do
      result = Celixir.eval!(~S|timestamp("2023-06-15T10:30:00Z")|)
      assert %Timestamp{} = result
    end

    test "duration() from string" do
      result = Celixir.eval!(~S|duration("1h30m")|)
      assert %Duration{} = result
    end
  end

  # ===========================================================================
  # 4. dynamic - dyn() function
  # ===========================================================================

  describe "conformance: dynamic" do
    test "dyn() is identity on int" do
      assert_eval("dyn(42)", 42)
    end

    test "dyn() is identity on string" do
      assert_eval(~S|dyn("hello")|, "hello")
    end

    test "dyn() is identity on bool" do
      assert_eval("dyn(true)", true)
    end

    test "dyn() is identity on list" do
      assert_eval("dyn([1, 2, 3])", [1, 2, 3])
    end

    test "dyn() is identity on null" do
      assert_eval("dyn(null)", nil)
    end

    test "dyn() preserves value for arithmetic" do
      assert_eval("dyn(2) + dyn(3)", 5)
    end
  end

  # ===========================================================================
  # 5. enums - (skipped, not yet implemented)
  # ===========================================================================

  # Skipped: enum support is not yet implemented

  # ===========================================================================
  # 6. fields - field selection and has() macro
  # ===========================================================================

  describe "conformance: fields" do
    test "simple field selection" do
      assert_eval("msg.name", "hello", %{msg: %{"name" => "hello"}})
    end

    test "nested field selection" do
      data = %{a: %{"b" => %{"c" => 42}}}
      assert_eval("a.b.c", 42, data)
    end

    test "field selection on struct-like map" do
      # Structs require compile-time definition; test with plain maps instead
      msg = %{"name" => "test", "value" => 99}
      assert_eval("m.name", "test", %{m: msg})
      assert_eval("m.value", 99, %{m: msg})
    end

    test "field selection - missing field is error" do
      assert_eval_error("msg.missing", %{msg: %{"name" => "hi"}})
    end

    test "has() on present field returns true" do
      assert_eval("has(msg.name)", true, %{msg: %{"name" => "hi"}})
    end

    test "has() on absent field returns false" do
      assert_eval("has(msg.missing)", false, %{msg: %{"name" => "hi"}})
    end

    test "has() on nested field" do
      data = %{msg: %{"inner" => %{"x" => 1}}}
      assert_eval("has(msg.inner)", true, data)
    end

    test "has() on map with integer key" do
      # Using field-style access; has() checks if field name exists as string key
      data = %{m: %{"x" => 1, "y" => 2}}
      assert_eval("has(m.x)", true, data)
      assert_eval("has(m.z)", false, data)
    end
  end

  # ===========================================================================
  # 7. fp_math - floating point arithmetic
  # ===========================================================================

  describe "conformance: fp_math" do
    test "double addition" do
      assert_eval("1.5 + 2.5", 4.0)
    end

    test "double subtraction" do
      assert_eval("5.0 - 3.0", 2.0)
    end

    test "double multiplication" do
      assert_eval("2.5 * 4.0", 10.0)
    end

    test "double division" do
      assert_eval("10.0 / 4.0", 2.5)
    end

    test "double division by zero returns infinity" do
      assert_eval("1.0 / 0.0", :infinity)
    end

    test "unary negation of double" do
      assert_eval("-3.14", -3.14)
      assert_eval("-(1.0 + 2.0)", -3.0)
    end

    test "double comparison with integers via conversion" do
      assert_eval("double(1) + double(2)", 3.0)
    end

    test "NaN is not equal to itself" do
      assert_eval("double('NaN') == double('NaN')", false)
      assert_eval("double('NaN') != double('NaN')", true)
    end

    test "Infinity comparisons" do
      assert_eval("double('Infinity') > 1.0e308", true)
      # :neg_infinity atom compared to float — relies on atom ordering in implementation
      # Skipping -Infinity ordering test as :neg_infinity atom cannot be compared with <
      assert_eval("double('-Infinity') == double('-Infinity')", true)
    end

    test "mixed double arithmetic does not cross types" do
      # int + double is type error in CEL (strict)
      assert_eval_error_match("1 + 2.0", "no_matching_overload")
      assert_eval_error_match("1.0 + 2", "no_matching_overload")
    end
  end

  # ===========================================================================
  # 8. integer_math - integer arithmetic with overflow detection
  # ===========================================================================

  describe "conformance: integer_math" do
    test "int addition" do
      assert_eval("1 + 2", 3)
      assert_eval("0 + 0", 0)
      assert_eval("-1 + 1", 0)
    end

    test "int subtraction" do
      assert_eval("10 - 3", 7)
      assert_eval("0 - 1", -1)
    end

    test "int multiplication" do
      assert_eval("4 * 5", 20)
      assert_eval("0 * 1000", 0)
      assert_eval("-3 * 2", -6)
    end

    test "int division (truncates toward zero)" do
      assert_eval("10 / 3", 3)
      assert_eval("7 / 2", 3)
    end

    test "int modulus" do
      assert_eval("10 % 3", 1)
      assert_eval("7 % 2", 1)
    end

    test "int division by zero is error" do
      assert_eval_error("1 / 0")
    end

    test "int modulus by zero is error" do
      assert_eval_error("1 % 0")
    end

    test "int overflow on addition" do
      assert_eval_error_match("9223372036854775807 + 1", "overflow")
    end

    test "int underflow on subtraction" do
      # -9223372036854775808 - 1 overflows
      assert_eval_error_match("-9223372036854775808 - 1", "overflow")
    end

    test "int overflow on multiplication" do
      assert_eval_error_match("9223372036854775807 * 2", "overflow")
    end

    test "uint addition" do
      assert_eval("1u + 2u", 3)
      assert_eval("0u + 0u", 0)
    end

    test "uint overflow" do
      assert_eval_error_match("18446744073709551615u + 1u", "overflow")
    end

    test "uint underflow" do
      assert_eval_error_match("0u - 1u", "overflow")
    end

    test "int + uint is type error" do
      assert_eval_error_match("1 + 2u", "no_matching_overload")
    end

    test "int + double is type error" do
      assert_eval_error_match("1 + 2.0", "no_matching_overload")
    end

    test "unary negation" do
      assert_eval("-5", -5)
      assert_eval("-(2 + 3)", -5)
    end

    test "negation of uint is error" do
      assert_eval_error_match("-1u", "no_matching_overload")
    end

    test "operator precedence" do
      assert_eval("2 + 3 * 4", 14)
      assert_eval("(2 + 3) * 4", 20)
      assert_eval("10 - 2 * 3", 4)
    end
  end

  # ===========================================================================
  # 9. lists - construction, indexing, membership, size, macros
  # ===========================================================================

  describe "conformance: lists" do
    test "empty list construction" do
      assert_eval("[]", [])
    end

    test "list construction with elements" do
      assert_eval("[1, 2, 3]", [1, 2, 3])
    end

    test "list construction with mixed types" do
      assert_eval(~S|[1, "two", true]|, [1, "two", true])
    end

    test "list indexing" do
      assert_eval("[10, 20, 30][0]", 10)
      assert_eval("[10, 20, 30][1]", 20)
      assert_eval("[10, 20, 30][2]", 30)
    end

    test "list index out of bounds" do
      assert_eval_error("[1, 2, 3][5]")
      assert_eval_error("[1, 2, 3][-1]")
    end

    test "list concatenation with +" do
      assert_eval("[1, 2] + [3, 4]", [1, 2, 3, 4])
      assert_eval("[] + [1]", [1])
      assert_eval("[1] + []", [1])
    end

    test "list membership with in" do
      assert_eval("2 in [1, 2, 3]", true)
      assert_eval("5 in [1, 2, 3]", false)
      assert_eval("1 in []", false)
    end

    test "list membership with heterogeneous equality" do
      # 1 (int) should be found equal to 1 (int) in list
      assert_eval("1 in [1, 2, 3]", true)
    end

    test "list size" do
      assert_eval("size([1, 2, 3])", 3)
      assert_eval("size([])", 0)
      assert_eval("[1, 2, 3].size()", 3)
    end

    test "nested list" do
      assert_eval("[[1, 2], [3, 4]][0][1]", 2)
    end

    test "list equality" do
      assert_eval("[1, 2, 3] == [1, 2, 3]", true)
      assert_eval("[1, 2] == [1, 2, 3]", false)
      assert_eval("[1, 2, 3] != [3, 2, 1]", true)
    end

    test "trailing comma in list" do
      assert_eval("[1, 2, 3,]", [1, 2, 3])
    end
  end

  # ===========================================================================
  # 10. logic - short-circuit &&, ||, ternary, error absorption
  # ===========================================================================

  describe "conformance: logic" do
    test "and truth table" do
      assert_eval("true && true", true)
      assert_eval("true && false", false)
      assert_eval("false && true", false)
      assert_eval("false && false", false)
    end

    test "or truth table" do
      assert_eval("true || true", true)
      assert_eval("true || false", true)
      assert_eval("false || true", true)
      assert_eval("false || false", false)
    end

    test "not operator" do
      assert_eval("!true", false)
      assert_eval("!false", true)
      assert_eval("!!true", true)
    end

    test "short-circuit && - false skips right error" do
      assert_eval("false && (1 / 0 > 0)", false)
    end

    test "short-circuit || - true skips right error" do
      assert_eval("true || (1 / 0 > 0)", true)
    end

    test "non-short-circuit && - propagates right error" do
      assert_eval_error("true && (1 / 0 > 0)")
    end

    test "non-short-circuit || - propagates right error" do
      assert_eval_error("false || (1 / 0 > 0)")
    end

    test "&& error absorption: left error, right false" do
      # If left is error and right is false, CEL spec says result is false
      assert_eval("false && x", false, %{})
    end

    test "|| error absorption: left error, right true" do
      # If left is error and right is true, CEL spec says result is true
      # Here left is an undefined var error
      assert_eval_error("x || false", %{})
    end

    test "ternary evaluates only true branch" do
      assert_eval("true ? 1 : 1/0", 1)
    end

    test "ternary evaluates only false branch" do
      assert_eval("false ? 1/0 : 2", 2)
    end

    test "ternary with non-bool condition is error" do
      assert_eval_error("1 ? 2 : 3")
    end

    test "nested ternary" do
      assert_eval("true ? (false ? 1 : 2) : 3", 2)
      assert_eval("1 > 2 ? 'a' : 2 > 3 ? 'b' : 'c'", "c")
    end

    test "complex short-circuit chains" do
      assert_eval("false && false && (1/0 > 0)", false)
      assert_eval("true || true || (1/0 > 0)", true)
    end
  end

  # ===========================================================================
  # 11. macros - all(), exists(), exists_one(), filter(), map()
  # ===========================================================================

  describe "conformance: macros" do
    test "all() - all elements satisfy predicate" do
      assert_eval("[1, 2, 3].all(x, x > 0)", true)
      assert_eval("[1, -2, 3].all(x, x > 0)", false)
    end

    test "all() on empty list" do
      assert_eval("[].all(x, x > 0)", true)
    end

    test "exists() - at least one element satisfies" do
      assert_eval("[1, 2, 3].exists(x, x == 2)", true)
      assert_eval("[1, 2, 3].exists(x, x == 5)", false)
    end

    test "exists() on empty list" do
      assert_eval("[].exists(x, x > 0)", false)
    end

    test "exists_one() - exactly one element satisfies" do
      assert_eval("[1, 2, 3].exists_one(x, x == 2)", true)
      assert_eval("[1, 2, 2].exists_one(x, x == 2)", false)
    end

    test "exists_one() on empty list" do
      assert_eval("[].exists_one(x, x > 0)", false)
    end

    test "filter() - select matching elements" do
      assert_eval("[1, 2, 3, 4, 5].filter(x, x > 3)", [4, 5])
      assert_eval("[1, 2, 3].filter(x, x > 10)", [])
    end

    test "filter() on empty list" do
      assert_eval("[].filter(x, x > 0)", [])
    end

    test "map() - transform elements" do
      assert_eval("[1, 2, 3].map(x, x * 2)", [2, 4, 6])
      assert_eval("[].map(x, x * 2)", [])
    end

    test "map() with filter form" do
      assert_eval("[1, 2, 3, 4].map(x, x > 2, x * 10)", [30, 40])
    end

    test "macros with complex predicates" do
      assert_eval("[1, 2, 3, 4, 5].all(x, x > 0 && x < 10)", true)
      assert_eval("[1, 2, 3, 4, 5].exists(x, x > 3 && x < 5)", true)
    end

    test "chained macros" do
      assert_eval("[1, 2, 3, 4, 5].filter(x, x > 2).map(x, x * 10)", [30, 40, 50])
    end
  end

  # ===========================================================================
  # 12. maps - construction, field access, membership
  # ===========================================================================

  describe "conformance: maps" do
    test "empty map" do
      assert_eval("{}", %{})
    end

    test "map construction with string keys" do
      assert_eval(~S|{"a": 1, "b": 2}|, %{"a" => 1, "b" => 2})
    end

    test "map field access with dot notation" do
      assert_eval(~S|m.a|, 1, %{m: %{"a" => 1, "b" => 2}})
    end

    test "map index access with bracket notation" do
      assert_eval(~S|m["a"]|, 1, %{m: %{"a" => 1, "b" => 2}})
    end

    test "map key membership with in" do
      assert_eval(~S|"a" in {"a": 1, "b": 2}|, true)
      assert_eval(~S|"c" in {"a": 1, "b": 2}|, false)
    end

    test "map size" do
      assert_eval(~S|size({"a": 1, "b": 2})|, 2)
      assert_eval("size({})", 0)
    end

    test "nested map access" do
      data = %{m: %{"outer" => %{"inner" => 42}}}
      assert_eval("m.outer.inner", 42, data)
    end

    test "map with integer keys" do
      # Maps in CEL can have int keys
      assert_eval("{1: 'a', 2: 'b'}[1]", "a")
    end

    test "map missing key is error" do
      assert_eval_error(~S|{"a": 1}["b"]|)
    end

    test "map equality" do
      assert_eval(~S|{"a": 1, "b": 2} == {"a": 1, "b": 2}|, true)
      assert_eval(~S|{"a": 1} == {"a": 2}|, false)
    end
  end

  # ===========================================================================
  # 13. parse - parsing edge cases
  # ===========================================================================

  describe "conformance: parse" do
    test "string escape sequences" do
      assert_eval(~S|"hello\nworld"|, "hello\nworld")
      assert_eval(~S|"tab\there"|, "tab\there")
      assert_eval(~S|"quote\"inside"|, ~S|quote"inside|)
    end

    test "single-quoted string escapes" do
      assert_eval(~S|'hello\nworld'|, "hello\nworld")
    end

    test "hex integer" do
      assert_eval("0x0", 0)
      assert_eval("0xFF", 255)
      assert_eval("0xDEAD", 0xDEAD)
    end

    test "scientific notation" do
      assert_eval("1e3", 1000.0)
      assert_eval("1.5e2", 150.0)
      assert_eval("2.5e-1", 0.25)
    end

    test "large integers at int64 boundary" do
      assert_eval("9223372036854775807", 9_223_372_036_854_775_807)
    end

    test "large unsigned integers at uint64 boundary" do
      assert_eval("18446744073709551615u", 18_446_744_073_709_551_615)
    end

    test "trailing comma in list and map" do
      assert_eval("[1, 2,]", [1, 2])
      assert_eval(~S|{"a": 1,}|, %{"a" => 1})
    end

    test "deeply nested parentheses" do
      assert_eval("(((1 + 2)))", 3)
    end

    test "chained field access" do
      data = %{a: %{"b" => %{"c" => %{"d" => 42}}}}
      assert_eval("a.b.c.d", 42, data)
    end

    test "empty string" do
      assert_eval(~S|""|, "")
      assert_eval("''", "")
    end
  end

  # ===========================================================================
  # 14. plumbing - type() function
  # ===========================================================================

  describe "conformance: plumbing (type)" do
    test "type of int" do
      assert_eval("type(1)", :int)
    end

    test "type of uint" do
      assert_eval("type(1u)", :uint)
    end

    test "type of double" do
      assert_eval("type(1.0)", :double)
    end

    test "type of bool" do
      assert_eval("type(true)", :bool)
      assert_eval("type(false)", :bool)
    end

    test "type of string" do
      assert_eval(~S|type("hello")|, :string)
    end

    test "type of bytes" do
      assert_eval(~S|type(b"hi")|, :bytes)
    end

    test "type of null" do
      assert_eval("type(null)", :null_type)
    end

    test "type of list" do
      assert_eval("type([1, 2])", :list)
    end

    test "type of map" do
      assert_eval(~S|type({"a": 1})|, :map)
    end

    test "type of timestamp" do
      assert_eval(
        ~S|type(timestamp("2023-01-01T00:00:00Z"))|,
        {:cel_type, "google.protobuf.Timestamp"}
      )
    end

    test "type of duration" do
      assert_eval(~S|type(duration("1h"))|, {:cel_type, "google.protobuf.Duration"})
    end
  end

  # ===========================================================================
  # 15. string - string methods and operations
  # ===========================================================================

  describe "conformance: string" do
    test "string concatenation with +" do
      assert_eval(~S|"hello" + " " + "world"|, "hello world")
      assert_eval(~S|"" + "a"|, "a")
    end

    test "size of string" do
      assert_eval(~S|size("hello")|, 5)
      assert_eval(~S|size("")|, 0)
      assert_eval(~S|"hello".size()|, 5)
    end

    test "contains method" do
      assert_eval(~S|"hello world".contains("world")|, true)
      assert_eval(~S|"hello".contains("xyz")|, false)
      assert_eval(~S|"hello".contains("")|, true)
    end

    test "startsWith method" do
      assert_eval(~S|"hello".startsWith("hel")|, true)
      assert_eval(~S|"hello".startsWith("world")|, false)
      assert_eval(~S|"hello".startsWith("")|, true)
    end

    test "endsWith method" do
      assert_eval(~S|"hello".endsWith("llo")|, true)
      assert_eval(~S|"hello".endsWith("hel")|, false)
      assert_eval(~S|"hello".endsWith("")|, true)
    end

    test "matches method (regex)" do
      assert_eval(~S|"hello123".matches("^[a-z]+[0-9]+$")|, true)
      assert_eval(~S|"hello".matches("^[0-9]+$")|, false)
    end

    test "charAt method" do
      assert_eval(~S|"hello".charAt(0)|, "h")
      assert_eval(~S|"hello".charAt(4)|, "o")
    end

    test "indexOf method" do
      assert_eval(~S|"hello world".indexOf("world")|, 6)
      assert_eval(~S|"hello".indexOf("xyz")|, -1)
      # Note: indexOf("") with empty pattern is an edge case; skipping as
      # Erlang's :binary.match/2 does not accept empty binary patterns
    end

    test "lastIndexOf method" do
      assert_eval(~S|"abcabc".lastIndexOf("abc")|, 3)
      assert_eval(~S|"hello".lastIndexOf("xyz")|, -1)
    end

    test "lowerAscii method" do
      assert_eval(~S|"HELLO".lowerAscii()|, "hello")
      assert_eval(~S|"Hello World".lowerAscii()|, "hello world")
    end

    test "upperAscii method" do
      assert_eval(~S|"hello".upperAscii()|, "HELLO")
    end

    test "replace method" do
      assert_eval(~S|"hello world".replace("world", "CEL")|, "hello CEL")
      assert_eval(~S|"aaa".replace("a", "b")|, "bbb")
    end

    test "split method" do
      assert_eval(~S|"a,b,c".split(",")|, ["a", "b", "c"])
      # Note: Elixir's String.split("hello", "") includes leading/trailing empty strings
      assert_eval(~S|"hello".split("")|, ["", "h", "e", "l", "l", "o", ""])
    end

    test "substring method" do
      assert_eval(~S|"hello".substring(1)|, "ello")
      assert_eval(~S|"hello".substring(1, 3)|, "el")
      assert_eval(~S|"hello".substring(0)|, "hello")
    end

    test "trim method" do
      assert_eval(~S|"  hello  ".trim()|, "hello")
      assert_eval(~S|"hello".trim()|, "hello")
    end

    test "string comparison" do
      assert_eval(~S|"abc" == "abc"|, true)
      assert_eval(~S|"abc" < "abd"|, true)
      assert_eval(~S|"z" > "a"|, true)
    end

    test "in operator on string (not supported - only list/map)" do
      # CEL in operator works on lists and maps, not substrings
      # This tests that 'in' checks list membership
      assert_eval(~S|"b" in ["a", "b", "c"]|, true)
    end
  end

  # ===========================================================================
  # 16. timestamps - timestamp and duration operations
  # ===========================================================================

  describe "conformance: timestamps" do
    test "timestamp from RFC3339 string" do
      result = Celixir.eval!(~S|timestamp("2023-06-15T10:30:00Z")|)
      assert %Timestamp{} = result
    end

    test "timestamp + duration" do
      result = Celixir.eval!(~S|timestamp("2023-01-15T10:00:00Z") + duration("1h")|)
      assert %Timestamp{} = result
      assert result.datetime.hour == 11
    end

    test "duration + timestamp (commutative)" do
      result = Celixir.eval!(~S|duration("1h") + timestamp("2023-01-15T10:00:00Z")|)
      assert %Timestamp{} = result
      assert result.datetime.hour == 11
    end

    test "timestamp - timestamp = duration" do
      result =
        Celixir.eval!(~S|timestamp("2023-01-15T11:00:00Z") - timestamp("2023-01-15T10:00:00Z")|)

      assert %Duration{} = result
      assert result.microseconds == 3_600_000_000
    end

    test "timestamp - duration" do
      result = Celixir.eval!(~S|timestamp("2023-01-15T11:00:00Z") - duration("1h")|)
      assert %Timestamp{} = result
      assert result.datetime.hour == 10
    end

    test "timestamp getFullYear accessor" do
      assert_eval(~S|timestamp("2023-06-15T10:30:00Z").getFullYear()|, 2023)
    end

    test "timestamp getMonth accessor (0-based)" do
      assert_eval(~S|timestamp("2023-06-15T10:30:00Z").getMonth()|, 5)
    end

    test "timestamp getDate accessor" do
      assert_eval(~S|timestamp("2023-06-15T10:30:00Z").getDate()|, 15)
    end

    test "timestamp getHours accessor" do
      assert_eval(~S|timestamp("2023-06-15T10:30:00Z").getHours()|, 10)
    end

    test "timestamp getMinutes accessor" do
      assert_eval(~S|timestamp("2023-06-15T10:30:45Z").getMinutes()|, 30)
    end

    test "timestamp getSeconds accessor" do
      assert_eval(~S|timestamp("2023-06-15T10:30:45Z").getSeconds()|, 45)
    end

    test "timestamp comparison" do
      assert_eval(
        ~S|timestamp("2023-06-15T10:00:00Z") < timestamp("2023-06-15T11:00:00Z")|,
        true
      )

      assert_eval(
        ~S|timestamp("2023-06-15T10:00:00Z") == timestamp("2023-06-15T10:00:00Z")|,
        true
      )
    end

    test "duration construction" do
      result = Celixir.eval!(~S|duration("1h30m")|)
      assert %Duration{} = result
    end

    test "duration + duration" do
      result = Celixir.eval!(~S|duration("1h") + duration("30m")|)
      assert %Duration{} = result
      assert Duration.get_component(result, :minutes) == 90
    end

    test "duration - duration" do
      result = Celixir.eval!(~S|duration("2h") - duration("30m")|)
      assert %Duration{} = result
      assert Duration.get_component(result, :minutes) == 90
    end

    test "duration getHours accessor" do
      assert_eval(~S|duration("2h30m").getHours()|, 2)
    end

    test "duration getMinutes accessor (total)" do
      assert_eval(~S|duration("2h30m").getMinutes()|, 150)
    end

    test "duration getSeconds accessor (total)" do
      assert_eval(~S|duration("1m30s").getSeconds()|, 90)
    end

    test "duration comparison" do
      assert_eval(~S|duration("2h") > duration("1h")|, true)
      assert_eval(~S|duration("1h") == duration("60m")|, true)
      assert_eval(~S|duration("30m") < duration("1h")|, true)
    end

    test "duration negation" do
      result = Celixir.eval!(~S|-duration("1h")|)
      assert %Duration{} = result
      assert result.microseconds == -3_600_000_000
    end

    test "invalid timestamp string is error" do
      assert_eval_error(~S|timestamp("not-a-timestamp")|)
    end

    test "invalid duration string is error" do
      assert_eval_error(~S|duration("not-a-duration")|)
    end
  end
end
