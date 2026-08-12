alias Celixir.Environment

arith_expr = "x * 2 + y"
{:ok, arith_prog} = Celixir.compile(arith_expr)
arith_inputs = %{x: 7, y: 3}
arith_elixir = fn %{x: x, y: y} -> x * 2 + y end

filter_expr = "items.filter(x, x > 5)"
{:ok, filter_prog} = Celixir.compile(filter_expr)
filter_inputs = %{items: Enum.to_list(1..20)}
filter_elixir = fn %{items: items} -> Enum.filter(items, &(&1 > 5)) end

comp_expr = "items.all(x, x > 0)"
{:ok, comp_prog} = Celixir.compile(comp_expr)
comp_inputs = %{items: Enum.to_list(1..20)}
comp_elixir = fn %{items: items} -> Enum.all?(items, &(&1 > 0)) end

str_expr = "name.startsWith('hello') && name.endsWith('world')"
{:ok, str_prog} = Celixir.compile(str_expr)
str_inputs = %{name: "hello world"}

tern_expr = "score >= 90 ? 'A' : score >= 80 ? 'B' : 'C'"
{:ok, tern_prog} = Celixir.compile(tern_expr)
tern_inputs = %{score: 85}
tern_elixir = fn %{score: s} ->
  cond do s >= 90 -> "A"; s >= 80 -> "B"; true -> "C" end
end

Benchee.run(
  %{
    "arith / compiled"      => fn -> Celixir.Program.eval(arith_prog, arith_inputs) end,
    "arith / pure_elixir"   => fn -> {:ok, arith_elixir.(arith_inputs)} end,
    "filter / compiled"     => fn -> Celixir.Program.eval(filter_prog, filter_inputs) end,
    "filter / pure_elixir"  => fn -> {:ok, filter_elixir.(filter_inputs)} end,
    "all / compiled"        => fn -> Celixir.Program.eval(comp_prog, comp_inputs) end,
    "all / pure_elixir"     => fn -> {:ok, comp_elixir.(comp_inputs)} end,
    "string / compiled"     => fn -> Celixir.Program.eval(str_prog, str_inputs) end,
    "ternary / compiled"    => fn -> Celixir.Program.eval(tern_prog, tern_inputs) end,
    "ternary / pure_elixir" => fn -> {:ok, tern_elixir.(tern_inputs)} end,
  },
  time: 3,
  warmup: 1,
  memory_time: 0,
  formatters: [{Benchee.Formatters.Console, comparison: true}]
)
