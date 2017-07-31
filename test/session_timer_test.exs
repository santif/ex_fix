defmodule ExFix.SessionTimerTest do
  use ExUnit.Case

  alias ExFix.SessionTimer

  test "SessionTimer test" do
    timer = SessionTimer.setup_timer("timer1", 50)
    send(timer, :msg)
    assert_receive {:timeout, "timer1"}, 150
  end
end
