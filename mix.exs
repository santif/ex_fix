defmodule ExFix.Mixfile do
  use Mix.Project

  def project do
    [app: :ex_fix,
     version: "0.2.1",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: description(),
     package: package(),
     test_coverage: [tool: ExCoveralls],
     preferred_cli_env: ["coveralls": :test, "coveralls.detail": :test,
      "coveralls.post": :test, "coveralls.html": :test],
     docs: [main: "readme",
            extras: ["README.md"]],
     deps: deps()]
  end

  def application do
    [extra_applications: [:logger, :crypto],
     mod: {ExFix.Application, []}]
  end

  defp description do
    """
    Elixir implementation of FIX Session Protocol FIXT.1.1
    """
  end

  defp package do
    [licenses: ["Apache 2"],
     files: ["lib", "mix.exs", "README.md", "LICENSE"],
     maintainers: ["Santiago Fernandez"],
     links: %{"GitHub": "https://github.com/santif/ex_fix"}]
  end

  defp deps do
    [{:calendar, "~> 0.17.3"},
     {:benchfella, "~> 0.3.0"},
     {:ex_doc, "~> 0.14", only: :dev, runtime: false},
     {:excoveralls, "~> 0.7", only: :test},
     {:dialyxir, "~> 0.5", only: [:dev], runtime: false},
     {:credo, "~> 0.8", only: [:dev, :test], runtime: false}]
  end
end
