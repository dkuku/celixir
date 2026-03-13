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

### Building a function library

Group related functions into a module that configures an environment:

```elixir
defmodule MyApp.CelLibrary do
  alias Celixir.Environment

  def register(env \\ Environment.new()) do
    env
    |> Environment.put_function("slugify", &slugify/1)
    |> Environment.put_function("format.currency", &format_currency/2)
    |> Environment.put_function("format.percent", &format_percent/1)
  end

  defp slugify(s) do
    s |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
  end

  defp format_currency(amount, currency) do
    "#{currency} #{:erlang.float_to_binary(amount / 1.0, decimals: 2)}"
  end

  defp format_percent(ratio) do
    "#{round(ratio * 100)}%"
  end
end

env = MyApp.CelLibrary.register()
      |> Celixir.Environment.put_variable("title", "Hello World!")

Celixir.eval!(~S|slugify(title)|, env)
# => "hello-world"

Celixir.eval!(~S|format.currency(29.9, "USD")|, env)
# => "USD 29.90"
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
