# Celixir

A pure Elixir implementation of Google's [Common Expression Language (CEL)](https://cel.dev/).

CEL is a non-Turing-complete expression language designed for simplicity, speed, and safety. It is commonly used in security policies, protocol buffers, Firebase rules, and configuration validation.

## Installation

```elixir
def deps do
  [
    {:celixir, "~> 0.2.0"}
  ]
end
```

## Quick Start

```elixir
# Simple expressions
Celixir.eval!("1 + 2")                          # => 3
Celixir.eval!("'hello' + ' ' + 'world'")        # => "hello world"

# Variable bindings
Celixir.eval!("age >= 18", %{age: 21})          # => true

# Complex expressions
Celixir.eval!(
  "request.method == 'GET' && resource.public",
  %{request: %{method: "GET"}, resource: %{public: true}}
)
# => true

# Comprehensions
Celixir.eval!("[1, 2, 3].filter(x, x > 1)")     # => [2, 3]
Celixir.eval!("[1, 2, 3].map(x, x * 2)")        # => [2, 4, 6]
Celixir.eval!("[1, 2, 3].all(x, x > 0)")        # => true
```

## Compile Once, Evaluate Many

For hot paths, compile the expression once and evaluate with different bindings:

```elixir
{:ok, program} = Celixir.compile("user.role == 'admin' && request.method in ['PUT', 'DELETE']")

Celixir.Program.eval(program, %{
  user: %{role: "admin"},
  request: %{method: "DELETE"}
})
# => {:ok, true}
```

## Create Reusable Functions

Compile a CEL expression into a plain anonymous function you can pass around:

```elixir
validator = Celixir.to_fun!("age >= 18 && status == 'active'")

validator.(%{age: 25, status: "active"})   # => {:ok, true}
validator.(%{age: 15, status: "active"})   # => {:ok, false}

# Use in pipelines, pass to other modules, store in config
rules = %{
  can_edit:   Celixir.to_fun!("user.role in ['admin', 'editor']"),
  is_active:  Celixir.to_fun!("user.status == 'active'")
}

rules.can_edit.(%{user: %{role: "admin"}})  # => {:ok, true}
```

## Load Expressions from Files

Store CEL expressions in files for config-driven rule engines:

```elixir
# rules/access_policy.cel contains: user.role == 'admin' || resource.public
{:ok, program} = Celixir.load_file("rules/access_policy.cel")

Celixir.Program.eval(program, %{user: %{role: "viewer"}, resource: %{public: true}})
# => {:ok, true}
```

## Custom Functions

Extend CEL with your own functions written in Elixir. Custom functions receive
plain Elixir values (unwrapped from CEL internal types) and should return plain
Elixir values.

### Basic function

```elixir
env = Celixir.Environment.new(%{name: "world"})
      |> Celixir.Environment.put_function("greet", fn name -> "Hello, #{name}!" end)

Celixir.eval!("greet(name)", env)
# => "Hello, world!"
```

### Multi-argument functions

```elixir
env = Celixir.Environment.new()
      |> Celixir.Environment.put_function("clamp", fn val, lo, hi ->
        val |> max(lo) |> min(hi)
      end)

Celixir.eval!("clamp(150, 0, 100)", env)
# => 100
```

### Using module functions

```elixir
defmodule MyFunctions do
  def factorial(0), do: 1
  def factorial(n) when n > 0, do: n * factorial(n - 1)
end

env = Celixir.Environment.new()
      |> Celixir.Environment.put_function("factorial", &MyFunctions.factorial/1)

Celixir.eval!("factorial(5)", env)
# => 120
```

### Namespaced functions

Use dot-separated names to organize functions into logical groups:

```elixir
env = Celixir.Environment.new()
      |> Celixir.Environment.put_function("str.reverse", fn s ->
        s |> String.graphemes() |> Enum.reverse() |> Enum.join()
      end)
      |> Celixir.Environment.put_function("str.repeat", fn s, n ->
        String.duplicate(s, n)
      end)

Celixir.eval!(~S|str.reverse("hello")|, env)
# => "olleh"

Celixir.eval!(~S|str.repeat("ab", 3)|, env)
# => "ababab"
```

### Building a function library with `defcel`

Use `Celixir.API` to define function libraries declaratively:

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

Celixir.eval!("mymath.abs(-42)", env)
# => 42

Celixir.eval!("mymath.clamp(150, 0, 100)", env)
# => 100
```

Multiple API modules can be composed on the same environment:

```elixir
env =
  Celixir.Environment.new(%{price: 100})
  |> MyApp.CelMath.register()
  |> MyApp.CelFormatting.register()
```

### Private environment data

Store opaque data on the environment for use in custom functions, without
exposing it as a CEL variable:

```elixir
env =
  Celixir.Environment.new()
  |> Celixir.Environment.put_private(:api_key, "secret-123")
  |> Celixir.Environment.put_function("fetch", fn url ->
    # api_key is accessible from Elixir but not from CEL expressions
    # ...
  end)
```

### Using with `Celixir.Program` (compile once, evaluate many)

```elixir
env = Celixir.Environment.new()
      |> Celixir.Environment.put_function("discount", fn price, pct -> price * (1 - pct) end)

{:ok, program} = Celixir.compile("discount(price, 0.1)")

Celixir.Program.eval(program, env |> Celixir.Environment.put_variable("price", 100))
# => {:ok, 90.0}

Celixir.Program.eval(program, env |> Celixir.Environment.put_variable("price", 50))
# => {:ok, 45.0}
```

## Extensions

Celixir ships optional extension modules that mirror the `ext.*` packages from
[cel-go](https://github.com/google/cel-go/tree/master/ext). Each module exposes
a `register/1` function you pipe into your environment to activate.

```elixir
env =
  Celixir.Environment.new()
  |> Celixir.Ext.Math.register()
  |> Celixir.Ext.Strings.register()
  |> Celixir.Ext.Lists.register()
  |> Celixir.Ext.Sets.register()
  |> Celixir.Ext.Encoders.register()
  |> Celixir.Ext.Regex.register()
```

### `Celixir.Ext.Math`

Numeric and bitwise functions under the `math.*` namespace.

```elixir
env = Celixir.Environment.new() |> Celixir.Ext.Math.register()

Celixir.eval!("math.sqrt(16.0)", env)          # => 4.0
Celixir.eval!("math.ceil(1.2)", env)           # => 2.0
Celixir.eval!("math.abs(-7)", env)             # => 7
Celixir.eval!("math.isNaN(1.0/0.0)", env)      # => false
Celixir.eval!("math.greatest(1, 3, 2)", env)   # => 3
Celixir.eval!("math.least([5, 1, 3])", env)    # => 1
Celixir.eval!("math.bitAnd(0b1010, 0b1100)", env) # => 8
```

| Function | Description |
|---|---|
| `math.ceil(double)` | ceiling |
| `math.floor(double)` | floor |
| `math.round(double)` | round (ties away from zero) |
| `math.trunc(double)` | truncate fractional part |
| `math.abs(int\|uint\|double)` | absolute value |
| `math.sign(int\|uint\|double)` | -1, 0, or 1 |
| `math.sqrt(int\|uint\|double)` | square root (NaN for negative) |
| `math.isNaN(double)` | true if NaN |
| `math.isInf(double)` | true if ±Inf |
| `math.isFinite(double)` | true if neither NaN nor Inf |
| `math.bitAnd(int, int)` | bitwise AND |
| `math.bitOr(int, int)` | bitwise OR |
| `math.bitXor(int, int)` | bitwise XOR |
| `math.bitNot(int)` | bitwise NOT |
| `math.bitShiftLeft(int, int)` | left shift |
| `math.bitShiftRight(int, int)` | right shift |
| `math.greatest(args...)` | variadic max |
| `math.least(args...)` | variadic min |

### `Celixir.Ext.Strings`

Additional string functions.

```elixir
env = Celixir.Environment.new() |> Celixir.Ext.Strings.register()

Celixir.eval!(~s|strings.quote("hello\nworld")|, env)
# => "\"hello\\nworld\""
```

| Function | Description |
|---|---|
| `strings.quote(string)` | wrap in double quotes with Go-style escaping |

### `Celixir.Ext.Lists`

Extra list operations and the `sortBy`/`transformMapEntry` comprehension macros.

```elixir
env = Celixir.Environment.new() |> Celixir.Ext.Lists.register()

Celixir.eval!("lists.range(5)", env)                       # => [0, 1, 2, 3, 4]
Celixir.eval!("[1, 2, 1, 3].distinct()", env)              # => [1, 2, 3]
Celixir.eval!("[1, 2, 3].first()", env)                    # => optional(1)
Celixir.eval!("[1, 2, 3].last()", env)                     # => optional(3)
Celixir.eval!("[1, [2, [3]]].flatten(2)", env)             # => [1, 2, 3]

# sortBy macro
Celixir.eval!(~s|[{"b": 2}, {"a": 1}].sortBy(x, x.key)|, env)

# transformMapEntry macro
Celixir.eval!(~s|{"a": 1, "b": 2}.transformMapEntry(k, v, {k: v * 10})|, env)
```

| Function | Description |
|---|---|
| `lists.range(n)` | `[0, 1, ..., n-1]` |
| `list.distinct()` | deduplicate preserving order |
| `list.first()` | optional first element |
| `list.last()` | optional last element |
| `list.flatten(depth)` | flatten to given depth |
| `list.sortBy(var, key_expr)` | sort by computed key (macro) |
| `map.transformMapEntry(k, v, transform [, filter])` | transform map entries (macro) |

### `Celixir.Ext.Sets`

Set-theoretic operations on lists treated as sets.

```elixir
env = Celixir.Environment.new() |> Celixir.Ext.Sets.register()

Celixir.eval!("sets.contains([1,2,3], [2,3])", env)       # => true
Celixir.eval!("sets.equivalent([1,2], [2,1])", env)       # => true
Celixir.eval!("sets.intersects([1,2], [2,3])", env)       # => true
```

| Function | Description |
|---|---|
| `sets.contains(list, list)` | true if first list contains all elements of second |
| `sets.equivalent(list, list)` | true if lists contain the same elements (order-independent) |
| `sets.intersects(list, list)` | true if lists share at least one element |

### `Celixir.Ext.Encoders`

Base64 encoding and decoding.

```elixir
env = Celixir.Environment.new() |> Celixir.Ext.Encoders.register()

Celixir.eval!("base64.encode(b'hello')", env)    # => "aGVsbG8="
Celixir.eval!("base64.decode('aGVsbG8=')", env) # => b"hello"
```

| Function | Description |
|---|---|
| `base64.encode(bytes)` | encode bytes to base64 string |
| `base64.decode(string)` | decode base64 string to bytes (error if invalid) |

### `Celixir.Ext.Regex`

Regular expression functions under the `regex.*` namespace.

```elixir
env = Celixir.Environment.new() |> Celixir.Ext.Regex.register()

Celixir.eval!(~s|regex.replace("hello world", "hello", "hi")|, env)
# => "hi world"

Celixir.eval!(~s|regex.replace("aabbcc", "[a-z]", "x", 3)|, env)
# => "xxxbcc"

Celixir.eval!(~s|regex.extract("item-A", "item-(\\w+)").value()|, env)
# => "A"

Celixir.eval!(~s|regex.extractAll("id:1, id:2", "id:\\d+")|, env)
# => ["id:1", "id:2"]
```

| Function | Description |
|---|---|
| `regex.replace(target, pattern, replacement)` | replace all matches |
| `regex.replace(target, pattern, replacement, count)` | replace first N matches (0=keep, <0=all) |
| `regex.extract(target, pattern)` | optional first match or first capture group |
| `regex.extractAll(target, pattern)` | list of all matches or capture groups |

> Use `\N` for backreferences in replacements. `$N`-style references are not supported.

## Compile-Time Sigil

Parse expressions at compile time for zero runtime parsing cost:

```elixir
import Celixir.Sigil

ast = ~CEL|request.method == "GET"|
Celixir.eval_ast(ast, %{request: %{method: "GET"}})
# => {:ok, true}
```

## Supported Features

### Types
`int`, `uint`, `double`, `bool`, `string`, `bytes`, `list`, `map`, `null`, `timestamp`, `duration`, `optional`, `type`

### Operators
- Arithmetic: `+`, `-`, `*`, `/`, `%`
- Comparison: `==`, `!=`, `<`, `<=`, `>`, `>=`
- Logical: `&&`, `||`, `!` (with short-circuit error absorption)
- Ternary: `? :`
- Membership: `in`

### Standard Functions
- **String**: `contains`, `startsWith`, `endsWith`, `matches`, `size`, `charAt`, `indexOf`, `lastIndexOf`, `lowerAscii`, `upperAscii`, `replace`, `split`, `substring`, `trim`, `join`, `reverse`
- **Math**: `math.least`, `math.greatest`, `math.ceil`, `math.floor`, `math.round`, `math.abs`, `math.sign`, `math.isNaN`, `math.isInf`, `math.isFinite`
- **Lists**: `size`, `sort`, `slice`, `flatten`, `reverse`, `lists.range`
- **Sets**: `sets.contains`, `sets.intersects`, `sets.equivalent`
- **Type conversions**: `int()`, `uint()`, `double()`, `string()`, `bool()`, `bytes()`, `timestamp()`, `duration()`, `dyn()`, `type()`
- **Encoding**: `base64.encode()`, `base64.decode()`

### Comprehension Macros
`all`, `exists`, `exists_one`, `filter`, `map`, `transformList`, `transformMap`, `sortBy`, `transformMapEntry`

### Optional Values
`optional.of()`, `optional.none()`, `optional.ofNonZeroValue()`, `.hasValue()`, `.value()`, `.orValue()`, `.or()`

### Protobuf Integration
Field access, `has()` presence checks, and automatic well-known type conversion via `Celixir.ProtobufAdapter`.

### Static Type Checking
Optional pre-evaluation type validation:

```elixir
{:ok, ast} = Celixir.parse("x + 1")
:ok = Celixir.Checker.check(ast, %{"x" => :int})
{:error, _} = Celixir.Checker.check(ast, %{"x" => :string})
```

## CEL Spec Conformance

Celixir passes 2400/2427 (99%) of the upstream [cel-spec](https://github.com/google/cel-spec) conformance tests across 30 test suites covering arithmetic, strings, lists, comparisons, logic, macros, conversions, timestamps, protobuf field access, namespaces, optionals, type deductions, and more.

The extension modules (`Celixir.Ext.*`) mirror the `ext.*` packages from cel-go and are covered by an additional 100+ tests.

## License

Apache-2.0
