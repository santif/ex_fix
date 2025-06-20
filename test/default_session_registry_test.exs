defmodule ExFix.DefaultSessionRegistryTest do
  use ExUnit.Case

  alias ExFix.DefaultSessionRegistry

  test "session_on_init replies according to status" do
    table = :ex_fix_registry
    :ets.delete_all_objects(table)

    assert {:error, :notfound} = DefaultSessionRegistry.session_on_init("s1")

    DefaultSessionRegistry.session_update_status("s2", :connecting)
    assert :ok = DefaultSessionRegistry.session_on_init("s2")

    DefaultSessionRegistry.session_update_status("s3", :connected)
    assert :wait_to_reconnect = DefaultSessionRegistry.session_on_init("s3")

    DefaultSessionRegistry.session_update_status("s4", :disconnecting)
    assert {:error, :disconnected} = DefaultSessionRegistry.session_on_init("s4")
  end

  test "handles process DOWN messages" do
    table = :ex_fix_registry
    :ets.delete_all_objects(table)

    DefaultSessionRegistry.session_update_status("dn1", :connecting)
    :ok = DefaultSessionRegistry.session_on_init("dn1")
    state = :sys.get_state(DefaultSessionRegistry)
    ref1 = Enum.find_value(state.monitor_map, fn {ref, name} -> if name == "dn1", do: ref end)
    send(DefaultSessionRegistry, {:DOWN, ref1, :process, self(), :normal})
    Process.sleep(10)
    assert DefaultSessionRegistry.get_session_status("dn1") == :disconnected

    DefaultSessionRegistry.session_update_status("dn2", :connecting)
    :ok = DefaultSessionRegistry.session_on_init("dn2")
    state = :sys.get_state(DefaultSessionRegistry)
    ref2 = Enum.find_value(state.monitor_map, fn {ref, name} -> if name == "dn2", do: ref end)
    send(DefaultSessionRegistry, {:DOWN, ref2, :process, self(), :shutdown})
    Process.sleep(10)
    assert DefaultSessionRegistry.get_session_status("dn2") == :reconnecting
  end
end
