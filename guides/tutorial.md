# CEL Tutorial

This guide introduces the [Common Expression Language (CEL)](https://cel.dev/)
and how to use it from Elixir with Celixir.

CEL is a non-Turing-complete expression language designed for simplicity, speed,
and safety. For the full language specification see the
[CEL Language Definition](https://github.com/google/cel-spec/blob/master/doc/langdef.md)
and the [CEL Introduction](https://github.com/google/cel-spec/blob/master/doc/intro.md).

## Literals and Arithmetic

CEL supports integers, floats (doubles), booleans, strings, bytes, null, lists, and maps.

```cel
42              // integer
3.14            // double
true            // boolean
"hello"         // string (double quotes)
'hello'         // string (single quotes)
null            // null value
b"\xff"         // bytes literal
```

Arithmetic works as you'd expect:

```cel
1 + 2 * 3       // 7
10 / 3           // 3  (integer division)
10.0 / 3.0       // 3.333...
10 % 3           // 1
```

```elixir
iex> Celixir.eval!("1 + 2 * 3")
7

iex> Celixir.eval!("10 % 3")
1
```

## Strings

Strings support concatenation with `+` and have many built-in methods:

```cel
"hello" + " " + "world"         // "hello world"
"hello world".contains("world") // true
"hello".startsWith("hel")       // true
"HELLO".lowerAscii()            // "hello"
"a,b,c".split(",")              // ["a", "b", "c"]
"hello".size()                  // 5
"hello".reverse()               // "olleh"
"  padded  ".trim()             // "padded"
"hello".substring(1, 3)         // "el"
```

Regex matching is available with `matches`:

```cel
"test@example.com".matches("[a-z]+@[a-z]+\\.[a-z]+")  // true
```

```elixir
iex> Celixir.eval!("'hello' + ' ' + 'world'")
"hello world"

iex> Celixir.eval!("'banana'.replace('a', 'o')")
"bonono"
```

## Variables

Expressions become useful when you pass in data as variables:

```elixir
iex> Celixir.eval!("age >= 18", %{age: 21})
true

iex> Celixir.eval!(
...>   "user.role == 'admin' && request.method == 'DELETE'",
...>   %{user: %{role: "admin"}, request: %{method: "DELETE"}}
...> )
true
```

Map field access uses dot notation. Nested maps are traversed naturally:

```cel
request.headers.content_type == "application/json"
```

## Comparison and Logic

```cel
1 < 2            // true
"abc" == "abc"   // true
"a" != "b"       // true
```

Logical operators `&&`, `||`, and `!` short-circuit. This means if one side of
`||` is `true`, an error on the other side is absorbed:

```cel
true || 1/0 > 0   // true  (error absorbed)
false && 1/0 > 0  // false (error absorbed)
```

The ternary operator selects between two values:

```cel
age >= 18 ? "adult" : "minor"
```

```elixir
iex> Celixir.eval!("true || 1/0 > 0")
true

iex> Celixir.eval!("x > 10 ? 'big' : 'small'", %{x: 42})
"big"
```

## Lists and Maps

Lists and maps are first-class values:

```cel
[1, 2, 3].size()          // 3
[3, 1, 2].sort()          // [1, 2, 3]
[1, [2, 3], [4]].flatten() // [1, 2, 3, 4]
{"key": "value"}.key      // "value"
"key" in {"key": 1}       // true
```

The `in` operator checks membership in lists and map keys:

```cel
3 in [1, 2, 3]            // true
"name" in {"name": "Ada"} // true
```

```elixir
iex> Celixir.eval!("[3, 1, 2].sort()")
[1, 2, 3]

iex> Celixir.eval!("'key' in m && m.key == 42", %{m: %{"key" => 42}})
true
```

## Comprehensions (Macros)

CEL provides macros for working with collections:

```cel
[1, 2, 3, 4, 5].filter(x, x > 2)    // [3, 4, 5]
[1, 2, 3].map(x, x * x)             // [1, 4, 9]
[1, 2, 3].all(x, x > 0)             // true
[1, 2, 3].exists(x, x == 2)         // true
[1, 2, 3, 2].exists_one(x, x == 2)  // false (two matches)
```

```elixir
iex> Celixir.eval!("[1, 2, 3, 4, 5].filter(x, x > 2)")
[3, 4, 5]

iex> Celixir.eval!("[1, 2, 3].map(x, x * x)")
[1, 4, 9]
```

## Type Conversions

Convert between types with built-in conversion functions:

```cel
int("42")          // 42
double(42)         // 42.0
string(3.14)       // "3.14"
bool("true")       // true
```

Check a value's type with `type()`:

```cel
type(42)           // int
type("hello")      // string
type([1, 2])       // list
```

```elixir
iex> Celixir.eval!("int('42') + 8")
50

iex> Celixir.eval!("type(42)")
:int
```

## Timestamps and Durations

CEL has native support for timestamps and durations:

```cel
timestamp("2024-01-15T10:30:00Z")                          // a timestamp
duration("1h30m")                                           // a duration
timestamp("2024-01-15T10:30:00Z") + duration("1h30m")      // timestamp arithmetic
duration("1h") + duration("30m") == duration("90m")         // true
```

Extract components from timestamps:

```cel
timestamp("2024-01-15T10:30:00Z").getHours()     // 10
timestamp("2024-01-15T10:30:00Z").getDayOfWeek()  // 1 (Monday)
```

```elixir
iex> Celixir.eval!("duration('1h') + duration('30m') == duration('90m')")
true
```

## Math Functions

```cel
math.least(3, 1, 2)     // 1
math.greatest(3, 1, 2)  // 3
math.ceil(1.2)           // 2
math.floor(1.8)          // 1
math.round(1.5)          // 2
math.abs(-42)            // 42
math.sign(-3.14)         // -1.0
```

```elixir
iex> Celixir.eval!("math.abs(-42)")
42
```

## Optional Values

Optionals help you safely handle missing data without errors:

```cel
optional.of("hello").hasValue()    // true
optional.none().orValue("default") // "default"
```

Optional chaining with `?` accesses fields that might not exist:

```cel
{"a": 1}.?b.orValue(0)            // 0  (b doesn't exist)
{"a": 1}.?a.orValue(0)            // 1
```

```elixir
iex> Celixir.eval!("optional.none().orValue('default')")
"default"

iex> Celixir.eval!("{'a': 1}.?b.orValue(0)")
0
```

## Compile Once, Evaluate Many

For performance-sensitive paths, parse the expression once and evaluate it
repeatedly with different bindings:

```elixir
{:ok, program} = Celixir.compile("price * (1.0 - discount)")

Celixir.Program.eval(program, %{price: 100.0, discount: 0.1})
# => {:ok, 90.0}

Celixir.Program.eval(program, %{price: 50.0, discount: 0.2})
# => {:ok, 40.0}
```

## Custom Functions

Extend CEL with your own Elixir functions:

```elixir
env =
  Celixir.Environment.new(%{name: "world"})
  |> Celixir.Environment.put_function("greet", fn name ->
    "Hello, #{name}!"
  end)

Celixir.eval!("greet(name)", env)
# => "Hello, world!"
```

Namespaced functions keep things organized:

```elixir
env =
  Celixir.Environment.new()
  |> Celixir.Environment.put_function("str.slugify", fn s ->
    s |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
  end)

Celixir.eval!(~S|str.slugify("Hello World!")|, env)
# => "hello-world"
```

### Function Libraries with `defcel`

For larger projects, define function libraries declaratively with `Celixir.API`:

```elixir
defmodule MyApp.CelMath do
  use Celixir.API, scope: "mymath"

  defcel abs(x) do
    Kernel.abs(x)
  end

  defcel clamp(val, lo, hi) do
    val |> max(lo) |> min(hi)
  end
end

env = Celixir.Environment.new() |> MyApp.CelMath.register()
Celixir.eval!("mymath.clamp(150, 0, 100)", env)
# => 100
```

Omit the `:scope` option to register functions without a namespace prefix:

```elixir
defmodule MyApp.Helpers do
  use Celixir.API

  defcel greet(name) do
    "Hello, #{name}!"
  end
end
```

## Reusable Functions

Compile a CEL expression into a plain anonymous function:

```elixir
validator = Celixir.to_fun!("age >= 18 && status == 'active'")

validator.(%{age: 25, status: "active"})   # => {:ok, true}
validator.(%{age: 15, status: "active"})   # => {:ok, false}
```

This is useful when you want to pass CEL logic into higher-order functions
like `Enum.filter/2` or store it in a map of named rules.

## Loading Expressions from Files

Store CEL expressions in external files for config-driven workflows:

```elixir
# rules/access_policy.cel contains:
#   user.role == 'admin' || resource.public

{:ok, program} = Celixir.load_file("rules/access_policy.cel")
Celixir.Program.eval(program, %{user: %{role: "viewer"}, resource: %{public: true}})
# => {:ok, true}

# Bang variant raises on error
program = Celixir.load_file!("rules/access_policy.cel")
```

## Compile-Time Sigil

Parse expressions at compile time for zero runtime parsing cost:

```elixir
import Celixir.Sigil

ast = ~CEL|request.size < 1024 && request.content_type == "application/json"|

Celixir.eval_ast(ast, %{
  request: %{size: 512, content_type: "application/json"}
})
# => {:ok, true}
```

## Error Handling

CEL uses error-as-value semantics. Errors don't crash — they propagate and can
be absorbed by short-circuit logic:

```elixir
# Division by zero returns an error tuple
Celixir.eval("1 / 0")
# => {:error, "division by zero"}

# But short-circuit logic absorbs the error
Celixir.eval("1/0 > 5 || true")
# => {:ok, true}

# Use eval! to raise on errors
Celixir.eval!("1 + 2")
# => 3
```

## Practical Example: Policy Engine

CEL shines as a rule engine where non-technical users define business logic:

```elixir
# Define policies as CEL expressions
policies = [
  {"admin_access", "user.role == 'admin'"},
  {"own_resource", "user.id == resource.owner_id"},
  {"public_read", "request.method == 'GET' && resource.public"}
]

# Compile once at startup
compiled =
  Enum.map(policies, fn {name, expr} ->
    {:ok, program} = Celixir.compile(expr)
    {name, program}
  end)

# Evaluate against each request
context = %{
  user: %{role: "editor", id: 42},
  resource: %{owner_id: 42, public: false},
  request: %{method: "PUT"}
}

Enum.map(compiled, fn {name, program} ->
  {:ok, result} = Celixir.Program.eval(program, context)
  {name, result}
end)
# => [{"admin_access", false}, {"own_resource", true}, {"public_read", false}]
```
