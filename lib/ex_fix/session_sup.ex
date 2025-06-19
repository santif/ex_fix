defmodule ExFix.SessionSup do
  @moduledoc false
  use DynamicSupervisor

  def start_link(args \\ []) do
    DynamicSupervisor.start_link(__MODULE__, args, name: ExFix.SessionSup)
  end

  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
