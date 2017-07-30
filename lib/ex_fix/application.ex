defmodule ExFix.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(ExFix.SessionRegistry, []),
      supervisor(ExFix.SessionSup, []),
    ]

    opts = [strategy: :rest_for_one, name: ExFix.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
