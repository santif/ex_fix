defmodule ExFix do
  @moduledoc """
  Elixir implementation of FIX Session Protocol FIXT.1.1.

  `ExFix` module responsibilities:
  - Start/stop FIX sessions
  - Send messages to FIX counterparty
  - Retrieve status of a FIX session

  Currently ExFIX only supports FIX initiator (aka "client"), who sends orders and receives
  execution reports from a FIX acceptor.
  """

  alias ExFix.Session
  alias ExFix.SessionConfig
  alias ExFix.SessionRegistry
  alias ExFix.SessionWorker
  alias ExFix.OutMessage
  alias ExFix.SessionHandler

  @default_dictionary Application.get_env(:ex_fix, :default_dictionary, ExFix.DefaultDictionary)
  @session_registry Application.get_env(:ex_fix, :session_registry, ExFix.DefaultSessionRegistry)

  @doc """
  Starts a FIX session initiator.

  ## Parameters:
   - `session_name`: Name used to uniquely identify a FIX session in your app.
   - `sender_comp_id`: Value of field `49 (SenderCompID)` of sent messages
   - `target_comp_id`: Value of field `56 (TargetCompID)` of sent messages
   - `session_handler`: Module that implements callbacks of ExFix.SessionHandler behavior
   - `opts` see Options section bellow
   - `session_registry`: Module that implements behavior `ExFix.SessionRegistry`. Default: `ExFix.DefaultSessionRegistry`.

  ## Options:
   - `hostname`: Hostname or IP of remote FIX Acceptor. String - default: `"localhost"`.
   - `port`: TCP port. Integer - default: `9876`.
   - `username`: Value of field `553 (Username)`.
   - `password`: Value of field `554 (Password)`.
   - `dictionary`: Module that implements callbacks of ExFix.Dictionary. Default: `DefaultDictionary`
   - `log_incoming_msg`: Log incoming messages? Boolean - default: `true`.
   - `log_outgoing_msg`: Log outgoing messages? Boolean - default: `true`.
   - `default_applverid`: String that specifies value of field `1137 (DefaultApplVerID)`. String - default: `"9"`.
   - `logon_encrypt_method`: Value of field `98 (EncryptMethod)`. String - default: `"0"`.
   - `heart_bt_int`: Value of field `108 (HeartBtInt)`. Integer - default: `60`.
   - `max_output_buf_count`: Maximum number of messages in outbound queue (for resends)
   - `reconnect_interval`: Interval, in seconds, between reconnection attempts. Integer - default: `15`.
   - `reset_on_logon`: Field `141 (ResetSeqNumFlag)` for `Logon` mesage. Boolean - only `true` is
      supported in this version.
   - `validate_incoming_message`: Validate checksum (Field `10`) of received messages? Boolean - default: `true`.
   - `transport_mod`: Socket implementation (`:gen_tcp`, `:ssl` or another module with the same interface). Default: `:ssl`.
   - `transport_options`: Socket options
   - `env`: Map with read-only values that is passed to `SessionHandler` callbacks
  """

  @spec start_session_initiator(String.t, String.t, String.t, SessionHandler, list()) :: :ok
  def start_session_initiator(session_name, sender_comp_id, target_comp_id,
      session_handler, opts \\ [], session_registry \\ nil) do
    opts = Enum.into(opts, %{
      hostname: "localhost",
      port: 9876,
      username: nil,
      password: nil,
      dictionary: @default_dictionary,
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
      time_service: nil,
      env: %{}
    })
    config = struct(%SessionConfig{
      name: session_name,
      mode: :initiator,
      sender_comp_id: sender_comp_id,
      target_comp_id: target_comp_id,
      session_handler: session_handler
    }, opts)

    unless config.reset_on_logon do
      raise ArgumentError, message: "reset_on_logon == true not supported"
    end

    session_registry = session_registry || @session_registry
    session_registry.start_session(session_name, config)
  end

  @doc """
  Sends a FIX message to counterparty. This functions returns when the message is sent.

  An exception is thrown if the session does not exist, the connection is not estabished, or
  the session is not online nor "logged in".

  ## Parameters:
   - `out_message`. See `OutMessage` for more information
   - `session_name`. String with the session's name.
  """
  @spec send_message!(OutMessage.t, Session.session_name) :: :ok | no_return
  def send_message!(out_message, session_name) do
    SessionWorker.send_message!(session_name, out_message)
  end

  @doc """
  Sends a FIX message to counterparty without waiting to check if the message already was sent.

  If the session does not exist, an exception is thrown.

  Same parameters of `send_message!()`
  """
  def send_message_async!(out_message, session_name) do
    SessionWorker.send_message_async!(session_name, out_message)
  end

  @doc """
  Sends a list of messages. The session initiator will send all the messages in an efficient
  way, possibly in many chunks.

  If the session does not exist, an exception is thrown.
  """
  @spec send_messages_async!([OutMessage.t], Session.session_name) :: :ok | no_return
  def send_messages_async!(out_messages, session_name) do
    SessionWorker.send_messages_async!(session_name, out_messages)
  end

  @doc """
  Logout and disconnect.

  If the session does not exist, an exception is thrown.
  """
  @spec stop_session(Session.session_name, SessionRegistry | nil) :: :ok | no_return
  def stop_session(session_name, registry \\ nil) do
    session_registry = registry || @session_registry
    session_registry.stop_session(session_name)
  end
end
