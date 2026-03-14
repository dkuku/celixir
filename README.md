# Celixir

A pure Elixir implementation of Google's [Common Expression Language (CEL)](https://cel.dev/).

CEL is a non-Turing-complete expression language designed for simplicity, speed, and safety. It is commonly used in security policies, protocol buffers, Firebase rules, and configuration validation.

## Installation

```elixir
def deps do
  [
    {:celixir, "~> 0.1.0"}
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
`all`, `exists`, `exists_one`, `filter`, `map`

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

## License

Apache-2.0
