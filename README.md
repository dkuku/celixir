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

```elixir
env = Celixir.Environment.new(%{name: "world"})
      |> Celixir.Environment.put_function("greet", fn name -> "Hello, #{name}!" end)

Celixir.eval!("greet(name)", env)
# => "Hello, world!"
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

Celixir passes 380/384 (99%) of the official [cel-spec](https://github.com/google/cel-spec) conformance tests across 8 test suites: basic, integer_math, fp_math, string, lists, macros, conversions, and plumbing.

## License

Apache-2.0
