defmodule ExFix.DefaultFixApplication do
  @moduledoc """
  FIX application - default implementation
  """

  require Logger
  @behaviour ExFix.FixApplication

  alias ExFix.Types.Message

  def before_logon(_fix_session_name, _fields), do: :ok

  def on_logon(fix_session_name, _pid) do
    Logger.info "[fix.incoming] [#{fix_session_name}] onLogon"
  end

  def on_message(fix_session_name, _msg_type, _pid, %Message{original_fix_msg: original_fix_msg}) do
    Logger.info "[fix.incoming] [#{fix_session_name}] #{original_fix_msg}"
  end

  def on_logout(fix_session_name) do
    Logger.info "[fix.event] [#{fix_session_name}] onLogout"
  end
end