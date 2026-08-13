# Speed regression check against a recorded baseline.
#
#     mix bench.baseline    # record the current code as the reference
#     mix bench.check       # re-run and fail if anything got slower
#
# The baseline is timings from one machine under one load, so it is only
# meaningful against itself: record it on the code you want to compare to
# (`git stash`, or check out the commit), then apply your change and check.
# bench/baseline.benchee is gitignored for the same reason — a baseline
# committed from one laptop tells another laptop nothing.
#
# Scenarios cover the paths where a regression would otherwise go unnoticed:
# both evaluation strategies, the two binding-normalisation paths, the
# comprehension kinds that have to stay linear, and optional lambdas. They are
# deliberately all Celixir — a pure-Elixir comparison answers a design
# question, not "did this commit make it slower".

alias Benchee.Formatters.Console
alias Celixir.Environment

threshold = 0.3
baseline_path = "bench/baseline.benchee"
mode = if "--save" in System.argv(), do: :save, else: :check

# Overridable so a quick sanity run does not cost a full measurement.
time = String.to_integer(System.get_env("BENCH_TIME", "5"))
warmup = String.to_integer(System.get_env("BENCH_WARMUP", "2"))

{:ok, arith_prog} = Celixir.compile("x * 2 + y")
arith_inputs = %{"x" => 7, "y" => 3}

{:ok, filter_prog} = Celixir.compile("items.filter(x, x > 5)")
{:ok, map_prog} = Celixir.compile("items.map(x, x * 2)")
{:ok, all_prog} = Celixir.compile("items.all(x, x > 0)")
list_inputs = %{"items" => Enum.to_list(1..100)}

{:ok, opt_prog} = Celixir.compile("m[?'role'].optMap(r, r == 'admin').hasValue()")
opt_inputs = %{"m" => %{"role" => "admin"}}

# The two normalisation paths through Environment.new/1: a string-keyed map with
# nothing to encode is bound as-is, while anything else is rebuilt.
string_keyed = for i <- 1..50, into: %{}, do: {"k#{i}", i}
atom_keyed = for i <- 1..50, into: %{}, do: {:"k#{i}", :"v#{i}"}

jobs = %{
  "eval / compiled" => fn -> Celixir.Program.eval(arith_prog, arith_inputs) end,
  "eval / interpreter" => fn -> Celixir.eval("x * 2 + y", arith_inputs) end,
  "comprehension / filter" => fn -> Celixir.Program.eval(filter_prog, list_inputs) end,
  "comprehension / map" => fn -> Celixir.Program.eval(map_prog, list_inputs) end,
  "comprehension / all" => fn -> Celixir.Program.eval(all_prog, list_inputs) end,
  "optional / optMap" => fn -> Celixir.Program.eval(opt_prog, opt_inputs) end,
  "binding / string keys" => fn -> Environment.new(string_keyed) end,
  "binding / atom keys" => fn -> Environment.new(atom_keyed) end
}

common = [time: time, warmup: warmup, memory_time: 0]

case mode do
  :save ->
    Benchee.run(
      jobs,
      common ++
        [
          save: %{path: baseline_path, tag: "baseline"},
          formatters: [{Console, comparison: false}]
        ]
    )

    IO.puts("\nBaseline written to #{baseline_path}")

  :check ->
    if !File.exists?(baseline_path) do
      IO.puts(:stderr, "No baseline at #{baseline_path} — run `mix bench.baseline` first.")
      System.halt(1)
    end

    suite =
      Benchee.run(
        jobs,
        common ++ [load: baseline_path, formatters: [{Console, comparison: false}]]
      )

    # Loaded scenarios carry the tag they were saved under; freshly run ones do not.
    {recorded, current} = Enum.split_with(suite.scenarios, & &1.tag)
    baselines = Map.new(recorded, &{&1.job_name, &1})

    # Median rather than average: a single GC pause during a run should not read
    # as a regression.
    results =
      current
      |> Enum.sort_by(& &1.job_name)
      |> Enum.map(fn scenario ->
        base = Map.fetch!(baselines, scenario.job_name)
        now_median = scenario.run_time_data.statistics.median
        was_median = base.run_time_data.statistics.median
        {scenario.job_name, was_median, now_median, now_median / was_median}
      end)

    IO.puts("\nAgainst baseline (regression threshold: #{round(threshold * 100)}% slower)\n")

    Enum.each(results, fn {name, was, now, ratio} ->
      verdict =
        cond do
          ratio > 1 + threshold -> "REGRESSED"
          ratio < 1 - threshold -> "faster"
          true -> "ok"
        end

      "  ~-26s ~8.2fus -> ~8.2fus  ~5.2fx  ~s"
      |> :io_lib.format([
        name,
        was / 1000,
        now / 1000,
        ratio,
        verdict
      ])
      |> to_string()
      |> IO.puts()
    end)

    regressions = Enum.filter(results, fn {_, _, _, ratio} -> ratio > 1 + threshold end)

    if regressions == [] do
      IO.puts("\nNo regression beyond #{round(threshold * 100)}%.")
    else
      IO.puts(:stderr, "\n#{length(regressions)} scenario(s) regressed beyond #{round(threshold * 100)}%:")

      Enum.each(regressions, fn {name, _, _, ratio} ->
        IO.puts(:stderr, "  #{name} — #{Float.round(ratio, 2)}x slower")
      end)

      System.halt(1)
    end
end
