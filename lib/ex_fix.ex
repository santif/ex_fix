defmodule ExFix do
  @moduledoc """
  Elixir implementation of FIX Session Protocol FIXT.1.1.

  `ExFix` module responsibilities:
  - start/stop FIX sessions
  - send messages to FIX counterparty
  - retrieve status of a FIX session

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

  ## Options:
   - hostname: Hostname or IP of FIX Acceptor ("server")
   - port: TCP port (integer)
   - username: Username, in plain text
   - password: Password, in plain text
   - dictionary: Module that implements callbacks of ExFix.Dictionary. By default is ExFix.DefaultDictionary
   - log_incoming_msg: Boolean indicating if received messages will be logged, using `Logger`
   - log_outgoing_msg: Boolean indicating if sent messages will be logged, using `Logger`
   - default_applverid: String that specifies value of field `1137 (DefaultApplVerID)`
   - logon_encrypt_method: TBD
   - heart_bt_int: TBD
   - max_output_buf_count: TBD
   - reconnect_interval: TBD
   - reset_on_logon: TBD
   - validate_incoming_message: Validate checksum (field 10) of received messages?
   - transport_mod: Socket implementation (`:gen_tcp`, `:ssl` or another module with the same interface)
   - transport_options: Socket options
   - env: TBD
  """

  @spec start_session_initiator(String.t, String.t, String.t, SessionHandler, list()) :: :ok
  def start_session_initiator(session_name, sender_comp_id, target_comp_id,
      session_handler, opts \\ []) do
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
    session_registry = opts[:session_registry] || @session_registry
    session_registry.start_session(session_name, config)
  end

  @doc """
  Sends a FIX message to counterparty. This functions returns when the message is put on the wire.

  If session not exist, connection is not estabished, or session is not online and "logged in",
  an exception is raised.

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

  If session not exist, an exception is raised.

  Same parameters of `send_message!()`
  """
  def send_message_async!(out_message, session_name) do
    SessionWorker.send_message_async!(session_name, out_message)
  end

  @doc """
  Sends a list of messages. The session initiator will manage to send all the messages in an
  efficient way, possibly in many chunks.

  If session not exist, an exception is raised.
  """
  @spec send_messages_async!([OutMessage.t], Session.session_name) :: :ok | no_return
  def send_messages_async!(out_messages, session_name) do
    SessionWorker.send_messages_async(session_name, out_messages)
  end

  @doc """
  Stops a FIX session.

  Send a Logout message to FIX acceptor, wait up to 2 seconds for receive a "response"
  and disconnects socket.
  """
  @spec stop_session(Session.session_name, SessionRegistry | nil) :: :ok | no_return
  def stop_session(session_name, registry \\ nil) do
    session_registry = registry || @session_registry
    session_registry.stop_session(session_name)
  end
end
