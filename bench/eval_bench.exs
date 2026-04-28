# Benchmark: CEL evaluation paths vs equivalent pure Elixir
#
# Three subjects compared for each expression:
#   interpreter  — Celixir.eval/2  (parse + tree-walk every call)
#   compiled     — Celixir.Program.eval/2  (parse+compile once, BEAM fn each call)
#   pure_elixir  — plain Elixir anonymous function doing the same work
#
# Run with:  mix run bench/eval_bench.exs

alias Celixir.Environment

# ── Scenario 1: simple arithmetic ────────────────────────────────────────────
arith_expr = "x * 2 + y"
{:ok, arith_prog} = Celixir.compile(arith_expr)
arith_inputs = %{x: 7, y: 3}
arith_elixir = fn %{x: x, y: y} -> x * 2 + y end

# ── Scenario 2: string method ─────────────────────────────────────────────────
str_expr = "name.startsWith('hello') && name.endsWith('world')"
{:ok, str_prog} = Celixir.compile(str_expr)
str_inputs = %{name: "hello world"}
str_elixir = fn %{name: n} -> String.starts_with?(n, "hello") and String.ends_with?(n, "world") end

# ── Scenario 3: comprehension (all) ───────────────────────────────────────────
comp_expr = "items.all(x, x > 0)"
{:ok, comp_prog} = Celixir.compile(comp_expr)
comp_inputs = %{items: Enum.to_list(1..20)}
comp_elixir = fn %{items: items} -> Enum.all?(items, &(&1 > 0)) end

# ── Scenario 4: ternary + comparison ─────────────────────────────────────────
tern_expr = "score >= 90 ? 'A' : score >= 80 ? 'B' : 'C'"
{:ok, tern_prog} = Celixir.compile(tern_expr)
tern_inputs = %{score: 85}
tern_elixir = fn %{score: s} ->
  cond do
    s >= 90 -> "A"
    s >= 80 -> "B"
    true -> "C"
  end
end

# ── Scenario 5: filter comprehension ──────────────────────────────────────────
filter_expr = "items.filter(x, x > 5)"
{:ok, filter_prog} = Celixir.compile(filter_expr)
filter_inputs = %{items: Enum.to_list(1..20)}
filter_elixir = fn %{items: items} -> Enum.filter(items, &(&1 > 5)) end

IO.puts("""
\n====================================================================
 Celixir benchmark  —  interpreter vs compiled vs pure Elixir
====================================================================
""")

Benchee.run(
  %{
    # --- Arithmetic ---
    "arith / interpreter" => fn -> Celixir.eval(arith_expr, arith_inputs) end,
    "arith / compiled" => fn -> Celixir.Program.eval(arith_prog, arith_inputs) end,
    "arith / pure_elixir" => fn -> arith_elixir.(arith_inputs) end,

    # --- String methods ---
    "string / interpreter" => fn -> Celixir.eval(str_expr, str_inputs) end,
    "string / compiled" => fn -> Celixir.Program.eval(str_prog, str_inputs) end,
    "string / pure_elixir" => fn -> str_elixir.(str_inputs) end,

    # --- Comprehension: all ---
    "all / interpreter" => fn -> Celixir.eval(comp_expr, comp_inputs) end,
    "all / compiled" => fn -> Celixir.Program.eval(comp_prog, comp_inputs) end,
    "all / pure_elixir" => fn -> comp_elixir.(comp_inputs) end,

    # --- Ternary / comparison ---
    "ternary / interpreter" => fn -> Celixir.eval(tern_expr, tern_inputs) end,
    "ternary / compiled" => fn -> Celixir.Program.eval(tern_prog, tern_inputs) end,
    "ternary / pure_elixir" => fn -> tern_elixir.(tern_inputs) end,

    # --- Filter comprehension ---
    "filter / interpreter" => fn -> Celixir.eval(filter_expr, filter_inputs) end,
    "filter / compiled" => fn -> Celixir.Program.eval(filter_prog, filter_inputs) end,
    "filter / pure_elixir" => fn -> filter_elixir.(filter_inputs) end
  },
  time: 5,
  warmup: 2,
  memory_time: 2,
  formatters: [
    {Benchee.Formatters.Console,
     comparison: true,
     extended_statistics: false}
  ]
)
