defmodule ExFix.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      {ExFix.DefaultSessionRegistry, []},
      {ExFix.SessionSup, []}
    ]

    opts = [strategy: :rest_for_one, name: ExFix.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
