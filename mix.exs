defmodule Celixir.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/celixir/celixir"

  def project do
    [
      app: :celixir,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "A pure Elixir implementation of Google's Common Expression Language (CEL)",
      package: package(),
      docs: docs(),
      name: "Celixir",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support", "test/support/generated"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:protobuf, "~> 0.16", optional: true},
      {:tz, "~> 0.28"},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "Celixir",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}"
    ]
  end
end
