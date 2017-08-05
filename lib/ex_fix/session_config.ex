defmodule ExFix.SessionConfig do
  @moduledoc """
  FIX session configuration
  """

  @enforce_keys [:name, :mode, :fix_application, :dictionary,
    :sender_comp_id, :target_comp_id]
  defstruct name: nil,
    mode: :initiator,
    fix_application: nil,
    dictionary: nil,
    sender_comp_id: nil,
    target_comp_id: nil,
    socket_connect_host: "localhost",
    socket_connect_port: 9876,
    logon_username: nil,
    logon_password: nil,
    log_incoming_msg: true,
    log_outgoing_msg: true,
    default_applverid: "9",
    logon_encrypt_method: "0",
    heart_bt_int: 60,
    max_output_buf_count: 1_000,
    reconnect_interval: 15,
    reset_on_logon: true,
    validate_incoming_message: true,
    transport_mod: :gen_tcp,
    transport_options: [],
    time_service: nil

  @type t :: %__MODULE__{}

end
