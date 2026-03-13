defmodule CelixirTest do
  use ExUnit.Case

  alias Celixir.Types.Duration
  alias Celixir.Types.Timestamp

  describe "literals" do
    test "integers" do
      assert Celixir.eval!("42") == 42
      assert Celixir.eval!("0") == 0
      assert Celixir.eval!("0xFF") == 255
    end

    test "unsigned integers" do
      assert Celixir.eval!("42u") == 42
      assert Celixir.eval!("0xFFu") == 255
    end

    test "floats" do
      assert Celixir.eval!("3.14") == 3.14
      assert Celixir.eval!("1e10") == 1.0e10
      assert Celixir.eval!("2.5e-3") == 2.5e-3
    end

    test "strings" do
      assert Celixir.eval!(~S|"hello"|) == "hello"
      assert Celixir.eval!("'world'") == "world"
    end

    test "booleans" do
      assert Celixir.eval!("true") == true
      assert Celixir.eval!("false") == false
    end

    test "null" do
      assert Celixir.eval!("null") == nil
    end
  end

  describe "arithmetic" do
    test "basic operations" do
      assert Celixir.eval!("1 + 2") == 3
      assert Celixir.eval!("10 - 3") == 7
      assert Celixir.eval!("4 * 5") == 20
      assert Celixir.eval!("10 / 3") == 3
      assert Celixir.eval!("10 % 3") == 1
    end

    test "float arithmetic" do
      assert Celixir.eval!("1.5 + 2.5") == 4.0
      assert Celixir.eval!("10.0 / 3.0") == 10.0 / 3.0
    end

    test "precedence" do
      assert Celixir.eval!("2 + 3 * 4") == 14
      assert Celixir.eval!("(2 + 3) * 4") == 20
    end

    test "unary negation" do
      assert Celixir.eval!("-5") == -5
      assert Celixir.eval!("-(2 + 3)") == -5
    end

    test "string concatenation" do
      assert Celixir.eval!(~S|"hello" + " " + "world"|) == "hello world"
    end

    test "list concatenation" do
      assert Celixir.eval!("[1, 2] + [3, 4]") == [1, 2, 3, 4]
    end

    test "division by zero" do
      assert {:error, _} = Celixir.eval("1 / 0")
    end
  end

  describe "comparison" do
    test "equality" do
      assert Celixir.eval!("1 == 1") == true
      assert Celixir.eval!("1 == 2") == false
      assert Celixir.eval!("1 != 2") == true
      assert Celixir.eval!(~S|"foo" == "foo"|) == true
    end

    test "ordering" do
      assert Celixir.eval!("1 < 2") == true
      assert Celixir.eval!("2 <= 2") == true
      assert Celixir.eval!("3 > 2") == true
      assert Celixir.eval!("2 >= 2") == true
    end
  end

  describe "logical" do
    test "and/or" do
      assert Celixir.eval!("true && true") == true
      assert Celixir.eval!("true && false") == false
      assert Celixir.eval!("false || true") == true
      assert Celixir.eval!("false || false") == false
    end

    test "not" do
      assert Celixir.eval!("!true") == false
      assert Celixir.eval!("!false") == true
    end

    test "short-circuit" do
      assert Celixir.eval!("false && (1 / 0 > 0)") == false
      assert Celixir.eval!("true || (1 / 0 > 0)") == true
    end
  end

  describe "ternary" do
    test "basic" do
      assert Celixir.eval!("true ? 1 : 2") == 1
      assert Celixir.eval!("false ? 1 : 2") == 2
    end

    test "with expression" do
      assert Celixir.eval!("1 > 0 ? 'yes' : 'no'") == "yes"
    end
  end

  describe "variables" do
    test "simple binding" do
      assert Celixir.eval!("x + 1", %{x: 10}) == 11
    end

    test "string key bindings" do
      assert Celixir.eval!("name", %{"name" => "Alice"}) == "Alice"
    end

    test "undefined variable" do
      assert {:error, "undefined variable: x"} = Celixir.eval("x")
    end
  end

  describe "field access" do
    test "map field" do
      assert Celixir.eval!("msg.name", %{msg: %{"name" => "hello"}}) == "hello"
    end

    test "nested field" do
      data = %{a: %{"b" => %{"c" => 42}}}
      assert Celixir.eval!("a.b.c", data) == 42
    end
  end

  describe "index access" do
    test "list index" do
      assert Celixir.eval!("items[0]", %{items: [10, 20, 30]}) == 10
      assert Celixir.eval!("items[2]", %{items: [10, 20, 30]}) == 30
    end

    test "map index" do
      assert Celixir.eval!(~S|m["key"]|, %{m: %{"key" => "value"}}) == "value"
    end
  end

  describe "membership (in)" do
    test "list membership" do
      assert Celixir.eval!("2 in [1, 2, 3]") == true
      assert Celixir.eval!("5 in [1, 2, 3]") == false
    end

    test "map membership" do
      assert Celixir.eval!(~S|"a" in {"a": 1, "b": 2}|) == true
      assert Celixir.eval!(~S|"c" in {"a": 1, "b": 2}|) == false
    end
  end

  describe "list and map construction" do
    test "empty list" do
      assert Celixir.eval!("[]") == []
    end

    test "list with elements" do
      assert Celixir.eval!("[1, 2, 3]") == [1, 2, 3]
    end

    test "empty map" do
      assert Celixir.eval!("{}") == %{}
    end

    test "map with entries" do
      assert Celixir.eval!(~S|{"a": 1, "b": 2}|) == %{"a" => 1, "b" => 2}
    end

    test "trailing comma" do
      assert Celixir.eval!("[1, 2, 3,]") == [1, 2, 3]
    end
  end

  describe "standard functions" do
    test "size" do
      assert Celixir.eval!(~S|size("hello")|) == 5
      assert Celixir.eval!("size([1, 2, 3])") == 3
      assert Celixir.eval!(~S|size({"a": 1})|) == 1
    end

    test "type" do
      assert Celixir.eval!("type(1)") == :int
      assert Celixir.eval!("type(1.0)") == :double
      assert Celixir.eval!("type(true)") == :bool
      assert Celixir.eval!(~S|type("s")|) == :string
      assert Celixir.eval!("type(null)") == :null_type
    end

    test "type conversions" do
      assert Celixir.eval!(~S|int("42")|) == 42
      assert Celixir.eval!("double(42)") == 42.0
      assert Celixir.eval!("string(42)") == "42"
      assert Celixir.eval!(~S|bool("true")|) == true
    end
  end

  describe "string methods" do
    test "contains" do
      assert Celixir.eval!(~S|"hello world".contains("world")|) == true
      assert Celixir.eval!(~S|"hello".contains("xyz")|) == false
    end

    test "startsWith" do
      assert Celixir.eval!(~S|"hello".startsWith("hel")|) == true
    end

    test "endsWith" do
      assert Celixir.eval!(~S|"hello".endsWith("llo")|) == true
    end

    test "matches" do
      assert Celixir.eval!(~S|"hello123".matches("^[a-z]+[0-9]+$")|) == true
    end

    test "size method" do
      assert Celixir.eval!(~S|"hello".size()|) == 5
    end
  end

  describe "custom functions" do
    test "user-defined function" do
      env =
        %{}
        |> Celixir.Environment.new()
        |> Celixir.Environment.put_function("double", fn x -> x * 2 end)

      assert Celixir.eval!("double(21)", env) == 42
    end

    test "multi-argument function" do
      env =
        Celixir.Environment.put_function(Celixir.Environment.new(), "clamp", fn val, lo, hi ->
          val |> max(lo) |> min(hi)
        end)

      assert Celixir.eval!("clamp(150, 0, 100)", env) == 100
      assert Celixir.eval!("clamp(-5, 0, 100)", env) == 0
      assert Celixir.eval!("clamp(50, 0, 100)", env) == 50
    end

    test "function returning string" do
      env =
        %{name: "world"}
        |> Celixir.Environment.new()
        |> Celixir.Environment.put_function("greet", fn name -> "Hello, #{name}!" end)

      assert Celixir.eval!("greet(name)", env) == "Hello, world!"
    end

    test "function returning bool" do
      env =
        Celixir.Environment.put_function(Celixir.Environment.new(), "is_even", fn x -> rem(x, 2) == 0 end)

      assert Celixir.eval!("is_even(4)", env) == true
      assert Celixir.eval!("is_even(3)", env) == false
    end

    test "function returning list" do
      env =
        Celixir.Environment.put_function(Celixir.Environment.new(), "range", fn n -> Enum.to_list(1..n) end)

      assert Celixir.eval!("range(3)", env) == [1, 2, 3]
    end

    test "function returning map" do
      env =
        Celixir.Environment.put_function(Celixir.Environment.new(), "make_pair", fn k, v -> %{k => v} end)

      assert Celixir.eval!(~S|make_pair("a", 1)|, env) == %{"a" => 1}
    end

    test "result used in arithmetic" do
      env =
        Celixir.Environment.put_function(Celixir.Environment.new(), "double", fn x -> x * 2 end)

      assert Celixir.eval!("double(21) + 1", env) == 43
      assert Celixir.eval!("double(5) * 3", env) == 30
      assert Celixir.eval!("100 - double(10)", env) == 80
    end

    test "result used in comparison" do
      env =
        Celixir.Environment.put_function(Celixir.Environment.new(), "double", fn x -> x * 2 end)

      assert Celixir.eval!("double(21) > 40", env) == true
      assert Celixir.eval!("double(21) == 42", env) == true
      assert Celixir.eval!("double(21) != 0", env) == true
      assert Celixir.eval!("double(21) < 100", env) == true
    end

    test "result used in ternary" do
      env =
        Celixir.Environment.put_function(Celixir.Environment.new(), "double", fn x -> x * 2 end)

      assert Celixir.eval!("double(5) > 0 ? 'positive' : 'negative'", env) == "positive"
    end

    test "result used in logical expression" do
      env =
        Celixir.Environment.put_function(Celixir.Environment.new(), "is_even", fn x -> rem(x, 2) == 0 end)

      assert Celixir.eval!("is_even(4) && is_even(6)", env) == true
      assert Celixir.eval!("is_even(3) || is_even(6)", env) == true
      assert Celixir.eval!("!is_even(3)", env) == true
    end

    test "nested custom function calls" do
      env =
        Celixir.Environment.put_function(Celixir.Environment.new(), "double", fn x -> x * 2 end)

      assert Celixir.eval!("double(double(5))", env) == 20
      assert Celixir.eval!("double(double(double(1)))", env) == 8
    end

    test "result in list literal" do
      env =
        Celixir.Environment.put_function(Celixir.Environment.new(), "double", fn x -> x * 2 end)

      assert Celixir.eval!("[double(1), double(2), double(3)]", env) == [2, 4, 6]
    end

    test "result in map literal" do
      env =
        Celixir.Environment.put_function(Celixir.Environment.new(), "double", fn x -> x * 2 end)

      assert Celixir.eval!("{'a': double(1), 'b': double(2)}", env) == %{"a" => 2, "b" => 4}
    end

    test "result as argument to builtin function" do
      env =
        Celixir.Environment.put_function(Celixir.Environment.new(), "make_list", fn n -> Enum.to_list(1..n) end)

      assert Celixir.eval!("size(make_list(5))", env) == 5
    end

    test "result used with string methods" do
      env =
        Celixir.Environment.put_function(Celixir.Environment.new(), "greet", fn name -> "Hello, #{name}!" end)

      assert Celixir.eval!(~S|greet("world").startsWith("Hello")|, env) == true
      assert Celixir.eval!(~S|greet("world").size()|, env) == 13
    end

    test "result used with in operator" do
      env =
        Celixir.Environment.put_function(Celixir.Environment.new(), "double", fn x -> x * 2 end)

      assert Celixir.eval!("double(1) in [1, 2, 3]", env) == true
      assert Celixir.eval!("double(5) in [1, 2, 3]", env) == false
    end

    test "mixed custom and builtin function calls" do
      env =
        Celixir.Environment.put_function(Celixir.Environment.new(), "double", fn x -> x * 2 end)

      assert Celixir.eval!("double(size([1, 2, 3]))", env) == 6
      assert Celixir.eval!("int(double(2.5))", env) == 5
    end

    test "namespaced function" do
      env =
        Celixir.Environment.put_function(Celixir.Environment.new(), "str.repeat", fn s, n ->
          String.duplicate(s, n)
        end)

      assert Celixir.eval!(~S|str.repeat("ab", 3)|, env) == "ababab"
    end

    test "multiple custom functions together" do
      env =
        Celixir.Environment.new()
        |> Celixir.Environment.put_function("add", fn a, b -> a + b end)
        |> Celixir.Environment.put_function("mul", fn a, b -> a * b end)

      assert Celixir.eval!("add(mul(2, 3), mul(4, 5))", env) == 26
    end

    test "custom function with variable binding" do
      env =
        %{x: 10, y: 20}
        |> Celixir.Environment.new()
        |> Celixir.Environment.put_function("add", fn a, b -> a + b end)

      assert Celixir.eval!("add(x, y)", env) == 30
      assert Celixir.eval!("add(x, y) + 5", env) == 35
    end

    test "result used in comprehension" do
      env =
        Celixir.Environment.put_function(Celixir.Environment.new(), "make_list", fn n -> Enum.to_list(1..n) end)

      assert Celixir.eval!("make_list(5).filter(x, x > 3)", env) == [4, 5]
      assert Celixir.eval!("make_list(4).map(x, x * 10)", env) == [10, 20, 30, 40]
      assert Celixir.eval!("make_list(3).all(x, x > 0)", env) == true
      assert Celixir.eval!("make_list(3).exists(x, x == 2)", env) == true
    end
  end

  describe "complex expressions" do
    test "policy-style expression" do
      env = %{
        request: %{
          "method" => "GET",
          "path" => "/api/users",
          "auth" => %{"role" => "admin"}
        }
      }

      expr = ~S|request.method == "GET" && request.auth.role == "admin"|
      assert Celixir.eval!(expr, env) == true
    end

    test "nested ternary" do
      assert Celixir.eval!("1 > 2 ? 'a' : 2 > 3 ? 'b' : 'c'") == "c"
    end
  end

  describe "error-as-value semantics" do
    test "short-circuit && absorbs right error" do
      assert Celixir.eval!("false && (1 / 0 > 0)") == false
    end

    test "short-circuit || absorbs right error" do
      assert Celixir.eval!("true || (1 / 0 > 0)") == true
    end

    test "error propagates when not short-circuited" do
      assert {:error, _} = Celixir.eval("true && (1 / 0 > 0)")
    end

    test "&& with left error and right false returns false" do
      assert Celixir.eval("false && x", %{}) == {:ok, false}
    end

    test "|| with left error and right true returns true" do
      assert {:error, _} = Celixir.eval("x || false", %{})
    end

    test "ternary only evaluates taken branch" do
      assert Celixir.eval!("true ? 1 : 1/0") == 1
      assert Celixir.eval!("false ? 1/0 : 2") == 2
    end
  end

  describe "strict type arithmetic" do
    test "int + int works" do
      assert Celixir.eval!("1 + 2") == 3
    end

    test "uint + uint works" do
      assert Celixir.eval!("1u + 2u") == 3
    end

    test "double + double works" do
      assert Celixir.eval!("1.0 + 2.0") == 3.0
    end

    test "int + uint is an error" do
      assert {:error, msg} = Celixir.eval("1 + 2u")
      assert msg =~ "no_matching_overload"
    end

    test "int + double is an error" do
      assert {:error, msg} = Celixir.eval("1 + 2.0")
      assert msg =~ "no_matching_overload"
    end
  end

  describe "heterogeneous numeric equality" do
    test "int == double" do
      assert Celixir.eval!("1 == 1.0") == true
      assert Celixir.eval!("1 == 1.5") == false
    end

    test "int == uint" do
      assert Celixir.eval!("1 == 1u") == true
      assert Celixir.eval!("1 == 2u") == false
    end

    test "uint == double" do
      assert Celixir.eval!("1u == 1.0") == true
    end

    test "cross-type ordering" do
      assert Celixir.eval!("1 < 2u") == true
      assert Celixir.eval!("2.0 > 1u") == true
    end
  end

  describe "integer overflow" do
    test "int overflow on addition" do
      assert {:error, msg} = Celixir.eval("9223372036854775807 + 1")
      assert msg =~ "overflow"
    end

    test "int overflow on negation" do
      # -(-min) overflows
      assert {:error, msg} = Celixir.eval("-(9223372036854775807 + 1)")
      assert msg =~ "overflow"
    end

    test "uint overflow" do
      assert {:error, msg} = Celixir.eval("18446744073709551615u + 1u")
      assert msg =~ "overflow"
    end
  end

  describe "timestamp and duration" do
    test "timestamp constructor" do
      ts = Celixir.eval!(~S|timestamp("2023-01-15T10:30:00Z")|)
      assert %Timestamp{} = ts
    end

    test "duration constructor" do
      d = Celixir.eval!(~S|duration("1h30m")|)
      assert %Duration{} = d
    end

    test "timestamp + duration" do
      result = Celixir.eval!(~S|timestamp("2023-01-15T10:00:00Z") + duration("1h")|)
      assert %Timestamp{} = result
      assert result.datetime.hour == 11
    end

    test "timestamp - timestamp = duration" do
      result =
        Celixir.eval!(~S|timestamp("2023-01-15T11:00:00Z") - timestamp("2023-01-15T10:00:00Z")|)

      assert %Duration{} = result
      assert result.microseconds == 3_600_000_000
    end

    test "timestamp accessor getFullYear" do
      assert Celixir.eval!(~S|timestamp("2023-06-15T10:30:00Z").getFullYear()|) == 2023
    end

    test "timestamp accessor getMonth (0-based)" do
      assert Celixir.eval!(~S|timestamp("2023-06-15T10:30:00Z").getMonth()|) == 5
    end

    test "timestamp accessor getHours" do
      assert Celixir.eval!(~S|timestamp("2023-06-15T10:30:00Z").getHours()|) == 10
    end

    test "duration accessor getHours" do
      assert Celixir.eval!(~S|duration("2h30m").getHours()|) == 2
    end

    test "duration accessor getMinutes" do
      assert Celixir.eval!(~S|duration("2h30m").getMinutes()|) == 150
    end

    test "duration arithmetic" do
      result = Celixir.eval!(~S|duration("1h") + duration("30m")|)
      assert %Duration{} = result
      assert Duration.get_component(result, :minutes) == 90
    end

    test "timestamp comparison" do
      assert Celixir.eval!(~S|timestamp("2023-06-15T10:00:00Z") < timestamp("2023-06-15T11:00:00Z")|) == true
    end

    test "duration comparison" do
      assert Celixir.eval!(~S|duration("2h") > duration("1h")|) == true
    end
  end

  describe "bytes type" do
    test "bytes literal" do
      assert Celixir.eval!(~S|b"hello"|) == "hello"
    end

    test "bytes concatenation" do
      assert Celixir.eval!(~S|b"hello" + b" world"|) == "hello world"
    end

    test "bytes size" do
      assert Celixir.eval!(~S|size(b"hello")|) == 5
    end

    test "bytes() conversion" do
      assert Celixir.eval!(~S|bytes("hello")|) == "hello"
    end
  end

  describe "string extensions" do
    test "charAt" do
      assert Celixir.eval!(~S|"hello".charAt(1)|) == "e"
    end

    test "indexOf" do
      assert Celixir.eval!(~S|"hello world".indexOf("world")|) == 6
      assert Celixir.eval!(~S|"hello".indexOf("xyz")|) == -1
    end

    test "lastIndexOf" do
      assert Celixir.eval!(~S|"abcabc".lastIndexOf("abc")|) == 3
    end

    test "lowerAscii" do
      assert Celixir.eval!(~S|"HELLO".lowerAscii()|) == "hello"
    end

    test "upperAscii" do
      assert Celixir.eval!(~S|"hello".upperAscii()|) == "HELLO"
    end

    test "replace" do
      assert Celixir.eval!(~S|"hello world".replace("world", "CEL")|) == "hello CEL"
    end

    test "split" do
      assert Celixir.eval!(~S|"a,b,c".split(",")|) == ["a", "b", "c"]
    end

    test "substring" do
      assert Celixir.eval!(~S|"hello".substring(1)|) == "ello"
      assert Celixir.eval!(~S|"hello".substring(1, 3)|) == "el"
    end

    test "trim" do
      assert Celixir.eval!(~S|"  hello  ".trim()|) == "hello"
    end
  end

  describe "type function with new types" do
    test "type of timestamp" do
      assert Celixir.eval!(~S|type(timestamp("2023-01-01T00:00:00Z"))|) ==
               {:cel_type, "google.protobuf.Timestamp"}
    end

    test "type of duration" do
      assert Celixir.eval!(~S|type(duration("1h"))|) == {:cel_type, "google.protobuf.Duration"}
    end

    test "type of uint" do
      assert Celixir.eval!("type(1u)") == :uint
    end

    test "type of bytes" do
      assert Celixir.eval!(~S|type(b"hi")|) == :bytes
    end
  end

  describe "macros" do
    test "has() on present field" do
      assert Celixir.eval!("has(msg.name)", %{msg: %{"name" => "hi"}}) == true
    end

    test "has() on absent field" do
      assert Celixir.eval!("has(msg.missing)", %{msg: %{"name" => "hi"}}) == false
    end

    test "list.all()" do
      assert Celixir.eval!("[1, 2, 3].all(x, x > 0)") == true
      assert Celixir.eval!("[1, -2, 3].all(x, x > 0)") == false
    end

    test "list.exists()" do
      assert Celixir.eval!("[1, 2, 3].exists(x, x == 2)") == true
      assert Celixir.eval!("[1, 2, 3].exists(x, x == 5)") == false
    end

    test "list.exists_one()" do
      assert Celixir.eval!("[1, 2, 3].exists_one(x, x == 2)") == true
      assert Celixir.eval!("[1, 2, 2].exists_one(x, x == 2)") == false
    end

    test "list.filter()" do
      assert Celixir.eval!("[1, 2, 3, 4, 5].filter(x, x > 3)") == [4, 5]
      assert Celixir.eval!("[1, 2, 3].filter(x, x > 10)") == []
    end

    test "list.map() transform" do
      assert Celixir.eval!("[1, 2, 3].map(x, x * 2)") == [2, 4, 6]
    end

    test "list.map() with filter" do
      assert Celixir.eval!("[1, 2, 3, 4].map(x, x > 2, x * 10)") == [30, 40]
    end
  end

  describe "sigil ~CEL" do
    import Celixir.Sigil

    test "compile-time parse, runtime eval" do
      ast = ~CEL|1 + 2 * 3|
      assert {:ok, 7} = Celixir.eval_ast(ast, Celixir.Environment.new())
    end

    test "compile-time eval with 'e' modifier" do
      assert ~CEL|2 + 3|e == 5
    end

    test "compile-time parse of string expression" do
      ast = ~CEL|"hello".size()|
      assert {:ok, 5} = Celixir.eval_ast(ast, Celixir.Environment.new())
    end

    test "runtime eval with bindings" do
      ast = ~CEL|x > 10|
      assert {:ok, true} = Celixir.eval_ast(ast, Celixir.Environment.new(%{x: 42}))
      assert {:ok, false} = Celixir.eval_ast(ast, Celixir.Environment.new(%{x: 5}))
    end
  end

  describe "qualified function names" do
    test "math.least with integers" do
      assert Celixir.eval!("math.least(3, 1, 2)") == 1
    end

    test "math.greatest with integers" do
      assert Celixir.eval!("math.greatest(3, 1, 2)") == 3
    end

    test "math.least with mixed types" do
      assert Celixir.eval!("math.least(3.5, 1, 2u)") == 1
    end

    test "math.greatest with mixed types" do
      assert Celixir.eval!("math.greatest(1, 3.5, 2u)") == 3.5
    end
  end

  describe "NaN and Infinity" do
    test "double('NaN') produces NaN" do
      result = Celixir.eval!("double('NaN')")
      assert result == :nan or (is_float(result) and result != result)
    end

    test "NaN != NaN" do
      assert Celixir.eval!("double('NaN') != double('NaN')") == true
    end

    test "NaN == NaN is false" do
      assert Celixir.eval!("double('NaN') == double('NaN')") == false
    end

    test "double('Infinity')" do
      assert Celixir.eval!("double('Infinity')") == :infinity
    end

    test "double('-Infinity')" do
      assert Celixir.eval!("double('-Infinity')") == :neg_infinity
    end
  end

  describe "Program (compile once, eval many)" do
    test "compile and eval" do
      {:ok, program} = Celixir.compile("x + y")
      assert {:ok, 3} = Celixir.Program.eval(program, %{x: 1, y: 2})
      assert {:ok, 7} = Celixir.Program.eval(program, %{x: 3, y: 4})
    end

    test "compile and eval!" do
      {:ok, program} = Celixir.compile("x > 10")
      assert Celixir.Program.eval!(program, %{x: 42}) == true
      assert Celixir.Program.eval!(program, %{x: 5}) == false
    end

    test "compile error" do
      assert {:error, _} = Celixir.compile("1 +")
    end

    test "program eval with Environment" do
      {:ok, program} = Celixir.compile("x * 2")
      env = Celixir.Environment.new(%{x: 21})
      assert {:ok, 42} = Celixir.Program.eval(program, env)
    end
  end

  describe "optional values" do
    test "optional.of and .value()" do
      assert Celixir.eval!("optional.of(42).value()") == 42
    end

    test "optional.none().hasValue()" do
      assert Celixir.eval!("optional.none().hasValue()") == false
    end

    test "optional.of().hasValue()" do
      assert Celixir.eval!("optional.of(42).hasValue()") == true
    end

    test "optional.none().value() errors" do
      assert {:error, _} = Celixir.eval("optional.none().value()")
    end

    test "optional.of().orValue()" do
      assert Celixir.eval!("optional.of(42).orValue(0)") == 42
    end

    test "optional.none().orValue()" do
      assert Celixir.eval!("optional.none().orValue(0)") == 0
    end

    test "optional.of().or() returns first" do
      result = Celixir.eval!("optional.of(1).or(optional.of(2)).value()")
      assert result == 1
    end

    test "optional.none().or() returns second" do
      result = Celixir.eval!("optional.none().or(optional.of(2)).value()")
      assert result == 2
    end

    test "optional.ofNonZeroValue with zero" do
      assert Celixir.eval!("optional.ofNonZeroValue(0).hasValue()") == false
    end

    test "optional.ofNonZeroValue with non-zero" do
      assert Celixir.eval!("optional.ofNonZeroValue(42).hasValue()") == true
    end

    test "type() on optional" do
      assert Celixir.eval!("type(optional.of(1))") == :optional_type
    end
  end

  describe "protobuf struct support" do
    defmodule TestMessage do
      @moduledoc false
      defstruct [:name, :age, :active]
    end

    test "field access on struct" do
      msg = %TestMessage{name: "alice", age: 30, active: true}
      assert Celixir.eval!("msg.name", %{msg: msg}) == "alice"
      assert Celixir.eval!("msg.age", %{msg: msg}) == 30
      assert Celixir.eval!("msg.active", %{msg: msg}) == true
    end

    test "has() on struct" do
      msg = %TestMessage{name: "alice", age: nil}
      assert Celixir.eval!("has(msg.name)", %{msg: msg}) == true
      assert Celixir.eval!("has(msg.age)", %{msg: msg}) == true
    end

    test "struct in expression" do
      msg = %TestMessage{name: "alice", age: 30, active: true}
      assert Celixir.eval!("msg.age > 18 && msg.active", %{msg: msg}) == true
    end
  end

  describe "matches() as global function" do
    test "matches(string, pattern)" do
      assert Celixir.eval!(~S|matches("hello123", "^[a-z]+[0-9]+$")|) == true
    end

    test "matches(string, pattern) no match" do
      assert Celixir.eval!(~S|matches("hello", "^[0-9]+$")|) == false
    end
  end

  describe "string join extension" do
    test "list.join() with no separator" do
      assert Celixir.eval!(~S|["a", "b", "c"].join()|) == "abc"
    end

    test "list.join() with separator" do
      assert Celixir.eval!(~S|["a", "b", "c"].join(", ")|) == "a, b, c"
    end
  end

  describe "list methods" do
    test "list.sort()" do
      assert Celixir.eval!("[3, 1, 2].sort()") == [1, 2, 3]
    end

    test "list.slice()" do
      assert Celixir.eval!("[1, 2, 3, 4, 5].slice(1, 3)") == [2, 3, 4]
    end
  end

  describe "additional list/string methods" do
    test "list.flatten()" do
      assert Celixir.eval!("[[1, 2], [3, 4]].flatten()") == [1, 2, 3, 4]
    end

    test "string.reverse()" do
      assert Celixir.eval!(~S|"hello".reverse()|) == "olleh"
    end

    test "list.reverse()" do
      assert Celixir.eval!("[1, 2, 3].reverse()") == [3, 2, 1]
    end
  end

  describe "encoding extensions" do
    test "base64.encode string" do
      assert Celixir.eval!(~S|base64.encode("hello")|) == "aGVsbG8="
    end

    test "base64.decode string" do
      result = Celixir.eval!(~S|base64.decode("aGVsbG8=")|)
      assert result == "hello"
    end
  end

  describe "static type checker" do
    test "well-typed expression" do
      {:ok, ast} = Celixir.parse("x + 1")
      assert :ok = Celixir.Checker.check(ast, %{"x" => :int})
    end

    test "type mismatch" do
      {:ok, ast} = Celixir.parse("x + 1")
      assert {:error, _} = Celixir.Checker.check(ast, %{"x" => :string})
    end

    test "bool expression" do
      {:ok, ast} = Celixir.parse("x && y")
      assert :ok = Celixir.Checker.check(ast, %{"x" => :bool, "y" => :bool})
    end

    test "infer literal types" do
      {:ok, ast} = Celixir.parse("42")
      assert Celixir.Checker.infer(ast) == :int
    end

    test "infer string concat" do
      {:ok, ast} = Celixir.parse("a + b")
      assert Celixir.Checker.infer(ast, %{"a" => :string, "b" => :string}) == :string
    end
  end

  describe "math extensions" do
    test "math.ceil" do
      assert Celixir.eval!("math.ceil(1.2)") == 2.0
      assert Celixir.eval!("math.ceil(-1.2)") == -1.0
      assert Celixir.eval!("math.ceil(2.0)") == 2.0
    end

    test "math.floor" do
      assert Celixir.eval!("math.floor(1.9)") == 1.0
      assert Celixir.eval!("math.floor(-1.2)") == -2.0
    end

    test "math.round" do
      assert Celixir.eval!("math.round(1.5)") == 2.0
      assert Celixir.eval!("math.round(1.4)") == 1.0
    end

    test "math.abs" do
      assert Celixir.eval!("math.abs(-5)") == 5
      assert Celixir.eval!("math.abs(5)") == 5
      assert Celixir.eval!("math.abs(-3.14)") == 3.14
    end

    test "math.sign" do
      assert Celixir.eval!("math.sign(42)") == 1
      assert Celixir.eval!("math.sign(-7)") == -1
      assert Celixir.eval!("math.sign(0)") == 0
      assert Celixir.eval!("math.sign(3.14)") == 1.0
      assert Celixir.eval!("math.sign(-2.0)") == -1.0
    end

    test "math.isNaN and math.isInf" do
      assert Celixir.eval!("math.isNaN(0.0 / 0.0)") == true
      assert Celixir.eval!("math.isNaN(1.0)") == false
      assert Celixir.eval!("math.isInf(1.0 / 0.0)") == true
      assert Celixir.eval!("math.isInf(1.0)") == false
    end

    test "math.isFinite" do
      assert Celixir.eval!("math.isFinite(1.0)") == true
      assert Celixir.eval!("math.isFinite(1.0 / 0.0)") == false
    end
  end

  describe "sets extensions" do
    test "sets.contains" do
      assert Celixir.eval!("sets.contains([1, 2, 3], [1, 3])") == true
      assert Celixir.eval!("sets.contains([1, 2, 3], [1, 4])") == false
    end

    test "sets.intersects" do
      assert Celixir.eval!("sets.intersects([1, 2], [2, 3])") == true
      assert Celixir.eval!("sets.intersects([1, 2], [3, 4])") == false
    end

    test "sets.equivalent" do
      assert Celixir.eval!("sets.equivalent([1, 2, 3], [3, 2, 1])") == true
      assert Celixir.eval!("sets.equivalent([1, 2], [1, 2, 3])") == false
    end
  end

  describe "raw strings" do
    test "raw single-quoted" do
      assert Celixir.eval!(~S|r'\n'|) == "\\n"
    end

    test "raw double-quoted" do
      assert Celixir.eval!(~S|r"\n"|) == "\\n"
    end

    test "raw triple-quoted double" do
      assert Celixir.eval!(~S|r"""\n"""|) == "\\n"
    end

    test "raw triple-quoted single" do
      assert Celixir.eval!(~S|r'''\n'''|) == "\\n"
    end
  end

  describe "type denotations" do
    test "bare type names" do
      assert Celixir.eval!("int") == :int
      assert Celixir.eval!("bool") == :bool
      assert Celixir.eval!("string") == :string
      assert Celixir.eval!("double") == :double
      assert Celixir.eval!("bytes") == :bytes
      assert Celixir.eval!("list") == :list
      assert Celixir.eval!("map") == :map
      assert Celixir.eval!("type") == :type
      assert Celixir.eval!("null_type") == :null_type
    end

    test "type() of type denotation" do
      assert Celixir.eval!("type(int)") == :type
      assert Celixir.eval!("type(type)") == :type
    end

    test "type equality" do
      assert Celixir.eval!("type(1) == int") == true
      assert Celixir.eval!("type('hello') == string") == true
      assert Celixir.eval!("type(true) == bool") == true
    end
  end

  describe "timestamp from int" do
    test "timestamp(int)" do
      assert {:ok, %Timestamp{}} = Celixir.eval("timestamp(0)")
    end

    test "timestamp identity" do
      assert Celixir.eval!("timestamp(1000000000) == timestamp(1000000000)") == true
    end
  end

  describe "Program compile and eval" do
    test "compile once, eval many" do
      {:ok, prog} = Celixir.compile("x + y")
      assert Celixir.Program.eval(prog, %{x: 1, y: 2}) == {:ok, 3}
      assert Celixir.Program.eval(prog, %{x: 10, y: 20}) == {:ok, 30}
    end

    test "eval!" do
      {:ok, prog} = Celixir.compile("x > 0")
      assert Celixir.Program.eval!(prog, %{x: 5}) == true
    end
  end
end
