# fprof profile of the compiled hot paths.
# Run with: MIX_ENV=dev mix run bench/fprof_profile.exs

alias Celixir.{Environment, Program}

{:ok, arith_prog}  = Celixir.compile("x * 2 + y")
{:ok, str_prog}    = Celixir.compile("name.startsWith('hello') && name.endsWith('world')")
{:ok, filter_prog} = Celixir.compile("items.filter(x, x > 5)")

arith_env  = Environment.new(%{x: 7, y: 3})
str_env    = Environment.new(%{name: "hello world"})
filter_env = Environment.new(%{items: Enum.to_list(1..20)})

IO.puts("\n=== fprof: arith compiled ===\n")
Benchee.run(
  %{"arith / compiled" => fn -> arith_prog.fun.(arith_env) end},
  time: 1, warmup: 1, memory_time: 0,
  profile_after: {:fprof, [sort: :own, callers: true]}
)

IO.puts("\n=== fprof: string compiled ===\n")
Benchee.run(
  %{"string / compiled" => fn -> str_prog.fun.(str_env) end},
  time: 1, warmup: 1, memory_time: 0,
  profile_after: {:fprof, [sort: :own, callers: true]}
)

IO.puts("\n=== fprof: filter compiled ===\n")
Benchee.run(
  %{"filter / compiled" => fn -> filter_prog.fun.(filter_env) end},
  time: 1, warmup: 1, memory_time: 0,
  profile_after: {:fprof, [sort: :own, callers: true]}
)
