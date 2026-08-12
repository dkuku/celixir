# Changelog

## v0.4.0 (2026-08-12)

### Security

- **Variable bindings no longer create atoms.** `Environment` now stores `variables` and `locals` as `%{String.t() => any()}`. Previously every distinct variable key, and every distinct identifier in a compiled expression, was interned with `String.to_atom/1` — so binding untrusted data (JSON payloads, Ecto JSON columns, external APIs) could exhaust the BEAM atom table and crash the VM unrecoverably. Binding 500 attacker-chosen keys created 500 permanent atoms; it now creates none.
  - The compiler assigns each free variable a positional atom (`:__cel_var_0__`, `:__cel_var_1__`, …) instead of interning the CEL identifier, so the atom count is bounded by variables-per-expression rather than by the variety of identifiers seen.

  Thanks to [@bruce](https://github.com/bruce) for reporting and implementing this ([#6](https://github.com/dkuku/celixir/pull/6)).

  > **Note**
  > `Celixir.compile/1` still creates one module and one atom per call, so compiling a stream of distinct untrusted *expressions* remains an atom sink. Cache compiled programs by expression text if expressions are user-supplied.

### Features

- **Atoms are encoded to CEL strings at the boundary.** `Environment.new/1`, `put_variable/3`, `put_local/3` and `put_locals_bulk/2` now convert atoms to strings, recursing through lists and through both the keys and values of plain maps, so `%{role: :admin}` matches `role == 'admin'`. `nil`, `true`, `false` and the numeric sentinels `:nan`, `:infinity`, `:neg_infinity` are preserved as CEL null/bool/number. Integer and boolean map keys are preserved (CEL map keys are int/uint/bool/string). Structs are left untouched for the type adapter.
- **`Celixir.encode/1` is now the single definition of that encoding**, and `Environment` delegates to it. Previously the two disagreed: `Celixir.encode(:admin)` returned `:admin` while `Environment.new(%{x: :admin})` stored `"admin"`.
- **String-keyed maps are a first-class input.** `Celixir.eval("severity == 'high'", %{"severity" => "high"})` works directly, and is now the faster path: a string-keyed map containing nothing that needs encoding is bound as-is, with no key conversion and no rebuild. Atom-keyed maps continue to work.
- **`:collect_list` comprehension kind** — `filter`/`map` comprehensions build their result with prepend + reverse instead of repeated appends, making them O(n) rather than O(n²).
- **Compiled path optimizations** — free variables are pattern-matched directly out of the environment struct in the function head and inlined into the body, eliminating a map lookup per reference. Comprehension bodies are compiled to closures taking their arguments positionally.
- Compiled programs propagate errors by raising `Celixir.EvalError` and rescuing at the top of `eval/1`, rather than threading `{:error, _}` tuples through every intermediate operation.

### Breaking changes

- `Environment.variables` and `Environment.locals` are keyed by strings, not atoms. Code that reads these fields directly (e.g. `Map.fetch(env.variables, :name)`) must use string keys. The public `Environment` API — `new/1`, `put_variable/3`, `get_variable/2`, `local?/2` — is unaffected and still accepts atoms.
- Atoms in bindings are converted to strings, as keys and as values. `Environment.new(%{role: :admin})` previously stored `:admin` and compared unequal to every CEL string; it now stores `"admin"`. Comparisons against CEL literals now succeed where they previously failed.
- `Celixir.encode/1` converts atoms to strings rather than passing them through, and recurses into map keys. Code relying on it to return atoms unchanged must special-case them.

### Fixed

- **Atom-keyed nested maps answer consistently.** Given `%{p: %{admin: true}}`, `p.admin` resolved but `p['admin']` raised `key "admin" not found in map` and `'admin' in p` returned `false`, because only field access had an atom fallback. Encoding keys at the boundary makes indexing, membership and comprehension agree with field access.

### Known issues

- Maps mixing atom and string keys are normalized based on the first key encountered, so one of the two key types may not resolve. Erlang's iteration order makes this depend on map size. Use a single key type per binding map.
- Structs are not encoded, so atoms inside them reach expressions as atoms and compare unequal to CEL strings. This applies whether a field is read directly or iterated. Register a type adapter for structs whose contents need to be visible to CEL.

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
