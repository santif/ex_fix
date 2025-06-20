defmodule ExFix.SessionSupTest do
  use ExUnit.Case

  test "start_link when already started" do
    assert {:error, {:already_started, _}} = ExFix.SessionSup.start_link([])
  end

  test "dynamic supervisor can start child" do
    {:ok, pid} = DynamicSupervisor.start_child(ExFix.SessionSup, {Task, fn -> :timer.sleep(10) end})
    assert is_pid(pid)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 50
  end
end
