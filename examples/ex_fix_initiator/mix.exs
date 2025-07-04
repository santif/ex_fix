defmodule ExFixInitiator.Mixfile do
  use Mix.Project

  def project do
    [app: :ex_fix_initiator,
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger, :ssl],
     mod: {ExFixInitiator.Application, []}]
  end

  defp deps do
    [{:ex_fix, path: "../.."}]
  end
end
