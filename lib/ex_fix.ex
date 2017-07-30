defmodule ExFix do
  @moduledoc """
  TODO Documentation for ExFix
  """

  alias ExFix.SessionRegistry
  alias ExFix.Types.SessionConfig
  alias ExFix.Types, as: T

  @default_dictionary Application.get_env(:ex_fix, :default_dictionary)

  @doc """
  Starts FIX session initiator
  """
  def start_session_initiator(session_name, sender_comp_id, target_comp_id,
      fix_application, opts \\ []) do
    config = %SessionConfig{
      name: session_name,
      mode: :initiator,
      sender_comp_id: sender_comp_id,
      target_comp_id: target_comp_id,
      fix_application: fix_application,
      dictionary: opts[:dictionary] || @default_dictionary,
      socket_connect_host: opts[:socket_connect_host] || "localhost",
      socket_connect_port: opts[:socket_connect_port] || 9876,
      logon_username: opts[:logon_username] || nil,
      logon_password: opts[:logon_password] || nil,
      log_incoming_msg: opts[:log_incoming_msg] || true,
      log_outgoing_msg: opts[:log_outgoing_msg] || true,
      default_applverid: opts[:default_applverid] || "9",
      logon_encrypt_method: opts[:logon_encrypt_method] || "0",
      heart_bt_int: opts[:heart_bt_int] || 60,
      max_output_buf_count: opts[:max_output_buf_count] || 1_000,
      reconnect_interval: opts[:reconnect_interval] || 15,
      reset_on_logon: opts[:reset_on_logon] || true,
      validate_incoming_message: opts[:validate_incoming_message] || true,
      transport_mod: opts[:transport_mod] || :gen_tcp,
      transport_options: opts[:transport_options] || [],
      time_service: opts[:time_service] || nil,
    }
    SessionRegistry.start_session(session_name, config)
  end

  @doc """
  Send FIX message to a session
  """
  @spec send_message!(String.t, String.t, [T.fix_field()]) :: :ok
  def send_message!(session_name, msg_type, fields) do
    :ok = ExFix.SessionWorker.send_message(session_name, msg_type, fields)
  end

  @doc """
  Stop FIX session
  """
  def stop_session(session_name) do
    SessionRegistry.stop_session(session_name)
  end
end