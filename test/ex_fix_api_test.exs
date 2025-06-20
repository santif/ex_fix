defmodule ExFix.ApiTest do
  use ExUnit.Case

  alias ExFix.SessionConfig
  alias ExFix.TestHelper.FixEmptySessionHandler

  defmodule CaptureRegistry do
    @behaviour ExFix.SessionRegistry

    def get_session_status(_), do: :disconnected

    def start_session(name, %SessionConfig{} = config) do
      send(self(), {:start_session, name, config})
      :ok
    end

    def stop_session(name) do
      send(self(), {:stop_session, name})
      :ok
    end

    def session_on_init(_), do: :ok
    def session_update_status(_, _), do: :ok
  end

  test "start_session_initiator builds config and delegates" do
    ExFix.start_session_initiator(
      "test_sess",
      "S",
      "T",
      FixEmptySessionHandler,
      session_registry: CaptureRegistry,
      hostname: "myhost",
      port: 12_345,
      log_incoming_msg: false
    )

    assert_receive {:start_session, "test_sess", config}
    assert %SessionConfig{name: "test_sess", sender_comp_id: "S", target_comp_id: "T"} = config
    assert config.hostname == "myhost"
    assert config.port == 12_345
    assert config.log_incoming_msg == false

    ExFix.stop_session("test_sess", CaptureRegistry)
    assert_receive {:stop_session, "test_sess"}
  end

  test "start_session_initiator uses defaults" do
    ExFix.start_session_initiator("defaults", "S", "T", FixEmptySessionHandler, session_registry: CaptureRegistry)

    assert_receive {:start_session, "defaults", config}
    assert config.hostname == "localhost"
    assert config.port == 9876
    assert config.log_incoming_msg == true
    assert config.transport_mod == :gen_tcp
  end
end
