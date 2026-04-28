# Changelog

## v0.3.0 (2026-04-28)

### Features

- **Native-type simplification**: Removed `{:cel_int, v}`, `{:cel_uint, v}`, and `{:cel_bytes, v}` tagged-tuple wrappers throughout the evaluator and public API. Integers, unsigned integers, and bytes are now plain Elixir integers and binaries.
  - Integer arithmetic uses Elixir bigints — no overflow errors beyond int64
  - `int + uint` and mixed-type integer arithmetic now work without explicit conversion
  - `type(1u)` returns `:int` (merged with int); `type(b"hi")` returns `:string` (merged with string)
  - `encode_uint/1` and `encode_bytes/1` are now identity functions (values already in native form)

- **Compiled evaluation path** (`Celixir.Compiler`): CEL expressions compiled via `Celixir.compile/1` and `Celixir.to_fun/1` are now translated to Elixir quoted ASTs and compiled to native BEAM functions via `Code.eval_quoted/3`. This eliminates the per-call tree-walking overhead for repeated evaluations.
  - `Celixir.Program` now stores a compiled function alongside the AST; `Program.eval/2` calls it directly
  - `Celixir.to_fun/1` uses the compiled path
  - The tree-walking evaluator (`Celixir.Evaluator`) remains as the direct `eval/2` path and as the fallback if compilation fails
  - `Celixir.Compiler.Runtime` provides the runtime support library for compiled programs (logical op error absorption, comprehension evaluation, field/index access, function dispatch)

### Breaking changes

- Strict int64/uint64 overflow is no longer enforced — expressions like `9223372036854775807 + 1` now return a bigint instead of an error
- `type(1u)` returns `:int` not `:uint`; `type(b"hello")` returns `:string` not `:bytes`

## v0.2.0 (2026-04-21)

### Features

- `Celixir.to_fun/1` and `to_fun!/1` — compile a CEL expression into a plain anonymous function
- `Celixir.load_file/1` and `load_file!/1` — load and compile CEL expressions from files
- `Celixir.API` module with `defcel` macro — declarative way to define CEL function libraries with scoped namespaces
- `Celixir.Environment.put_private/3`, `get_private/2`, `get_private!/2`, `delete_private/2` — private storage on environments for custom function context
- `Celixir.encode/1`, `encode_uint/1`, `encode_bytes/1` — convert Elixir values to CEL internal types (inverse of `unwrap/1`)
- **`Celixir.Ext.Math`** — math extension functions: `math.ceil`, `math.floor`, `math.round`, `math.trunc`, `math.sqrt`, `math.isNaN`, `math.isInf`, `math.isFinite`; bit operations (`math.bitAnd`, `math.bitOr`, `math.bitXor`, `math.bitNot`, `math.bitShiftLeft`, `math.bitShiftRight`); variadic `math.greatest` and `math.least`
- **`Celixir.Ext.Strings`** — strings extension: `strings.quote` (Go-style escape-and-quote)
- **`Celixir.Ext.Lists`** — list extension functions: `lists.range`, `list.distinct`, `list.first` (optional), `list.last` (optional), `list.flatten(depth)`, `list.sortBy(key)`, `list.transformMapEntry(key, value [, filter])`
- **`Celixir.Ext.Sets`** — set extension functions: `sets.contains`, `sets.equivalent`, `sets.intersects`
- **`Celixir.Ext.Encoders`** — base64 encoding: `base64.encode`, `base64.decode`
- **`Celixir.Ext.Regex`** — regular expression functions: `regex.replace` (with optional count), `regex.extract` (returns optional), `regex.extractAll`
- All extension modules follow the `register/1` opt-in pattern — pipe them into an environment to activate
- New comprehension macros: `sortBy` and `transformMapEntry`

## v0.1.0 (2026-03-12)

Initial release.

### Features

- Full CEL expression parsing, evaluation, and compilation
- Types: int, uint, double, bool, string, bytes, list, map, null, timestamp, duration, optional, type
- Operators: arithmetic, comparison, logical (with short-circuit error absorption), ternary, membership
- Standard functions: string, math, list, set, type conversion, encoding
- Comprehension macros: all, exists, exists_one, filter, map, transformList, transformMap
- Optional values: optional.of, optional.none, optional.ofNonZeroValue, hasValue, value, orValue, or
- Compile-once/evaluate-many via `Celixir.Program`
- Compile-time sigil `~CEL` for zero-cost parsed ASTs
- Custom function registration via `Celixir.Environment`
- Static type checking via `Celixir.Checker`
- Protobuf integration via `Celixir.ProtobufAdapter` (field access, has() checks, well-known type conversion)
- 99% cel-spec conformance (380/384 tests)
