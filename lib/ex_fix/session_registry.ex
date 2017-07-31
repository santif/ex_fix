defmodule ExFix.SessionRegistry do
  @moduledoc """
  Session registry
  """
  alias ExFix.Types, as: T

  @callback get_session_status(session_name :: String.t) :: T.session_status()
  @callback start_session(session_name :: String.t, config :: T.SessionConfig.t) :: :ok
  @callback stop_session(session_name :: String.t) :: :ok
  @callback session_on_init(fix_session :: String.t) :: :ok | :wait_to_reconnect |
    {:error, reason :: term()}
  @callback session_update_status(session_name :: String.t,
    status :: T.session_status()) :: :ok
end
