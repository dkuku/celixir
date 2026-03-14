# Changelog

## v0.2.0 (unreleased)

### Features

- `Celixir.to_fun/1` and `to_fun!/1` — compile a CEL expression into a plain anonymous function
- `Celixir.load_file/1` and `load_file!/1` — load and compile CEL expressions from files
- `Celixir.API` module with `defcel` macro — declarative way to define CEL function libraries with scoped namespaces
- `Celixir.Environment.put_private/3`, `get_private/2`, `get_private!/2`, `delete_private/2` — private storage on environments for custom function context
- `Celixir.encode/1`, `encode_uint/1`, `encode_bytes/1` — convert Elixir values to CEL internal types (inverse of `unwrap/1`)

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
