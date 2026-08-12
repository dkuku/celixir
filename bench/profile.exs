# Profile the compiled vs interpreter hot paths.
# Run with: mix run bench/profile.exs

alias Celixir.{Environment, Program}

bindings = %{x: 7, y: 3}
env = Environment.new(bindings)

{:ok, arith_prog}  = Celixir.compile("x * 2 + y")
{:ok, str_prog}    = Celixir.compile("name.startsWith('hello') && name.endsWith('world')")
{:ok, filter_prog} = Celixir.compile("items.filter(x, x > 5)")

str_bindings    = %{name: "hello world"}
str_env         = Environment.new(str_bindings)
filter_bindings = %{items: Enum.to_list(1..20)}
filter_env      = Environment.new(filter_bindings)

IO.puts("\n=== Profiling compiled path (tprof) ===\n")

Benchee.run(
  %{
    "arith  / compiled"  => fn -> arith_prog.fun.(env) end,
    "string / compiled"  => fn -> str_prog.fun.(str_env) end,
    "filter / compiled"  => fn -> filter_prog.fun.(filter_env) end,
    "arith  / interp"    => fn -> Celixir.eval("x * 2 + y", env) end,
    "filter / interp"    => fn -> Celixir.eval("items.filter(x, x > 5)", filter_env) end,
  },
  time: 1,
  warmup: 1,
  memory_time: 0,
  profile_after: {:tprof, [type: :time]}
)
