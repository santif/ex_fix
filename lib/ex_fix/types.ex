defmodule ExFix.Types do
  @moduledoc """
  ExFix types
  """

  alias ExFix.Types.MessageToSend
  alias ExFix.Types.Message
  alias ExFix.Types.SessionConfig
  alias ExFix.Session

  @type fix_field() :: {String.t, any()}
  @type session_status() :: :offline | :connecting | :online | :disconnecting
  @type session_result() :: {:ok, [MessageToSend.t], Session.t}
    | {:resend, [MessageToSend.t], Session.t}
    | {:logout, [MessageToSend.t], Session.t}
    | {:stop, Session.t}
  @type session_in_queue() :: [Message.t]

  defmodule MessageToSend do
    @moduledoc false
    alias ExFix.Types.MessageToSend

    @type t :: %MessageToSend{}
    defstruct seqnum: 0,
      msg_type: nil,
      sender: nil,
      orig_sending_time: nil,
      target: nil,
      extra_header: [],
      body: []
  end

  defmodule Message do
    @moduledoc false
    alias ExFix.Types.Message

    @type t :: %Message{}
    defstruct valid: false,
      complete: false,
      msg_type: nil,
      subject: nil,
      poss_dup: false,
      fields: [],
      seqnum: nil,
      rest_msg: "",
      other_msgs: "",
      original_fix_msg: nil,
      error_reason: nil
  end

  defmodule SessionConfig do
    @moduledoc """
    FIX session configuration
    """

    alias ExFix.Types.SessionConfig

    @type t :: %SessionConfig{}
    @enforce_keys [:name, :mode, :fix_application, :dictionary, :sender_comp_id,
      :target_comp_id]

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
  end
end
