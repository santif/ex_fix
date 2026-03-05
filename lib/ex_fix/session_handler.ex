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
              session_name :: Session.session_name(),
              msg_type :: String.t(),
              msg :: InMessage.t(),
              env :: map()
            ) :: any()

  @doc """
  FIX message received (session level). Same arguments of `on_message()`.
  """
  @callback on_session_message(
              session_name :: Session.session_name(),
              msg_type :: String.t(),
              msg :: InMessage.t(),
              env :: map()
            ) :: any()

  @doc """
  Called after a Logon message is received from counterparty
  """
  @callback on_logon(session_name :: Session.session_name(), env :: map()) :: any()

  @doc """
  Called after a Logout message is received from counterparty or after a
  disconnection, which occurs first.
  """
  @callback on_logout(session_name :: Session.session_name(), env :: map()) :: any()

  @doc """
  Called when a session-level error occurs.

  Error types:
  - `:connect_error` — TCP/SSL connection failure. Details: `%{reason: term()}`
  - `:transport_error` — TCP/SSL send failure. Details: `%{reason: term()}`
  - `:garbled_message` — message failed checksum or body-length validation. Details: `%{raw_message: binary()}`
  - `:heartbeat_timeout` — counterparty heartbeat not received within tolerance. Details: `%{}`

  This callback is optional. Handlers that do not implement it will not receive
  error notifications.
  """
  @callback on_error(
              session_name :: Session.session_name(),
              error_type :: atom(),
              details :: map(),
              env :: map()
            ) :: any()

  @optional_callbacks [on_error: 4]
end
