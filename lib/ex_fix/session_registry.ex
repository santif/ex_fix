defmodule ExFix.SessionRegistry do
  @moduledoc """
  Session registry.
  """

  alias ExFix.SessionConfig
  alias ExFix.Session

  ##
  ## Public API
  ##

  @doc """
  Returns the current status of a FIX session
  """
  @callback get_session_status(session_name :: Session.session_name()) :: Session.session_status()

  @doc """
  Starts a FIX session
  """
  @callback start_session(session_name :: Session.session_name(), config :: SessionConfig.t()) ::
              :ok

  @doc """
  Stops a FIX session
  """
  @callback stop_session(session_name :: Session.session_name()) :: :ok

  ##
  ## Callbacks for internal use (calls from a FIX session)
  ##

  @doc """
  Invoked by FIX session, before connecting, to know if it's ok to connect
  """
  @callback session_on_init(session_name :: Session.session_name()) ::
              :ok
              | :wait_to_reconnect
              | {:error, reason :: term()}

  @doc """
  Invoked by FIX session to update its status.
  """
  @callback session_update_status(
              session_name :: Session.session_name(),
              status :: Session.session_status()
            ) :: :ok
end
