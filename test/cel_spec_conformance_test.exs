# Dynamically generate one test module per textproto file for parallel execution.
#
# Each module uses `async: true` so ExUnit runs them concurrently.

alias Celixir.Conformance.TextprotoParser

testdata_dir = Path.join([__DIR__, "cel_spec", "testdata"])
skip_tests = Celixir.CelSpecHelpers.skip_tests()

for file <- Path.wildcard(Path.join(testdata_dir, "*.textproto")) do
  file_content = File.read!(file)
  file_data = TextprotoParser.parse(file_content)
  file_name = file_data.name || Path.basename(file, ".textproto")

  module_suffix =
    file_name
    |> String.split("_")
    |> Enum.map_join(&String.capitalize/1)

  module_name = Module.concat(Celixir.CelSpec, module_suffix)

  defmodule module_name do
    use ExUnit.Case, async: true

    import Celixir.CelSpecHelpers, only: [run_cel_spec_test: 3]

    for section <- file_data.sections,
        {test, tidx} <- Enum.with_index(section.tests) do
      skip? =
        MapSet.member?(skip_tests, {file_name, section.name, test.name}) or
          test[:check_only] == true

      if skip? do
        @tag :skip
      end

      @tag :cel_spec
      test "[#{section.name}] #{test.name}##{tidx}" do
        test_data = unquote(Macro.escape(test))
        file_name = unquote(file_name)
        section_name = unquote(section.name)
        skip? = unquote(skip?)

        if skip? do
          :ok
        else
          run_cel_spec_test(file_name, section_name, test_data)
        end
      end
    end
  end
end
