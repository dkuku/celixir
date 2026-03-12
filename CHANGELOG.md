# Changelog

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
