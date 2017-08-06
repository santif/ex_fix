defmodule ExFix.SessionHandler do
  @moduledoc """
  FIX Session Handler behaviour. Declare callbacks to process received FIX messages
  and session events.
  """

  alias ExFix.InMessage
  alias ExFix.Session

  @doc """
  Callback - FIX message received (application level).

  This function receives:
  - session id (String or PID), example: "simulator"
  - message type (String)
    see [here](http://www.onixs.biz/fix-dictionary/5.0.SP2/msgs_by_msg_type.html)
    for a complete list of FIX 5.0 SP2 message types.
  - msg - InMessage struct with message. If `msg.complete == false`, it is needed to call:
    ```
    msg = ExFix.Parser.parse2(msg)
    ```
  - env - Map sent to `ExFix.start_session_initiator()`.
  """
  @callback on_app_message(
    session_name :: Session.session_name,
    msg_type :: String.t,
    msg :: InMessage.t,
    env :: map()) :: none()

  @doc """
  FIX message received (session level). Same arguments of `on_message()`.
  """
  @callback on_session_message(
    session_name :: Session.session_name,
    msg_type :: String.t,
    msg :: InMessage.t,
    env :: map()) :: none()

  @doc """
  Called after a Logon message is received from counterparty
  """
  @callback on_logon(
    session_name :: Session.session_name,
    env :: map()) :: none()

  @doc """
  Called after a Logout message is received from counterparty or after a
  disconnection, which occurs first.
  """
  @callback on_logout(
    session_name :: Session.session_name,
    env :: map()) :: none()
end