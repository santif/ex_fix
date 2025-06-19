defmodule ExFix.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ex_fix,
      version: "0.2.8",
      elixir: "~> 1.18",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto], mod: {ExFix.Application, []}]
  end

  defp description do
    """
    Elixir implementation of FIX Session Protocol FIXT.1.1
    """
  end

  defp package do
    [
      licenses: ["Apache 2"],
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["Santiago Fernandez"],
      links: %{GitHub: "https://github.com/santif/ex_fix"}
    ]
  end

  defp deps do
    [
      {:benchfella, "~> 0.3.5", only: :dev},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:dialyxir, "~> 1.3", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
