defmodule ExFix.FixApplication do
  @moduledoc """
  FIX application behaviour. Declare callbacks to process FIX messages and events
  """

  alias ExFix.Types.Message
  alias ExFix.Types, as: T

  @doc """
  Callback to customize logon message
  """
  @callback before_logon(session_name :: String.t, fields :: [T.fix_field]) ::
    :ok | {:ok, [T.fix_field]} | :stop

  @doc """
  Logon callback
  """
  @callback on_logon(session_name :: String.t, pid :: pid()) :: any()

  @doc """
  Message callback
  """
  @callback on_message(session_name :: String.t, msg_type :: String.t,
    pid :: pid(), msg :: Message.t) :: any()


  @doc """
  Logout callback
  """
  @callback on_logout(session_name :: String.t) :: any()
end