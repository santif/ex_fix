defmodule ExFix.SessionSup do
  @moduledoc false
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: ExFix.SessionSup)
  end

  def init(_args) do
    children = [
      {ExFix.SessionWorker, [], restart: :transient}
    ]

    Supervisor.init(children, strategy: :simple_one_for_one)
  end
end
