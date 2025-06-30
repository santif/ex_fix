defmodule ExFix.SessionConfig do
  @moduledoc """
  FIX session configuration
  """

  @enforce_keys [:name, :mode, :session_handler, :sender_comp_id, :target_comp_id]
  defstruct name: nil,
            mode: :initiator,
            session_handler: nil,
            dictionary: ExFix.DefaultDictionary,
            sender_comp_id: nil,
            target_comp_id: nil,
            hostname: "localhost",
            port: 9876,
            username: nil,
            password: nil,
            log_incoming_msg: true,
            log_outgoing_msg: true,
            default_applverid: "9",
            logon_encrypt_method: "0",
            heart_bt_int: 60,
            max_output_buf_count: 1_000,
            reconnect_interval: 15,
            reset_on_logon: true,
            validate_incoming_message: true,
            validate_sending_time: true,
            transport_mod: :gen_tcp,
            transport_options: [],
            time_service: nil,
            env: %{}

  @type t :: %__MODULE__{}
end
