defmodule ExFix do
  @moduledoc """
  Elixir implementation of FIX Session Protocol FIXT.1.1.
  Currently only supports FIX session initiator (buy side).

  ## Usage

  ```
  defmodule MyFixApplication do
    @behaviour ExFix.FixApplication
    require Logger

    alias ExFix.Types.Message
    alias ExFix.Parser

    @msg_new_order_single "D"

    def on_logon(fix_session_name, session_pid) do
      fields = []  # See examples directory
      ExFix.send_message!(session_pid, @msg_new_order_single, fields)
    end

    def on_message(fix_session_name, msg_type, session_pid, %Message{} = msg) do
      Logger.info "Msg received: \#{inspect msg = Parser.parse2(msg)}"
    end

    def before_logon(_fix_session_name, _fields), do: :ok
    def on_logout(_fix_session_name), do: :ok
  end

  ExFix.start_session_initiator("mysession", "SENDER", "TARGET", MyFixApplication,
    socket_connect_host: "localhost", socket_connect_port: 9876,
    logon_username: "user1", logon_password: "pwd1", transport_mod: :ssl)
  ```
  """

  alias ExFix.Types.SessionConfig
  alias ExFix.SessionWorker
  alias ExFix.Types, as: T

  @default_dictionary Application.get_env(:ex_fix, :default_dictionary)
  @session_registry Application.get_env(:ex_fix, :session_registry)

  @doc """
  Starts FIX session initiator
  """
  def start_session_initiator(session_name, sender_comp_id, target_comp_id,
      fix_application, opts \\ []) do
    opts = Enum.into(opts, %{
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
      time_service: nil,
    })
    config = struct(%SessionConfig{
      name: session_name,
      mode: :initiator,
      sender_comp_id: sender_comp_id,
      target_comp_id: target_comp_id,
      fix_application: fix_application,
      dictionary: @default_dictionary,
    }, opts)
    @session_registry.start_session(session_name, config)
  end

  @doc """
  Send FIX message to a session
  """
  @spec send_message!(String.t, String.t, [T.fix_field()]) :: :ok
  def send_message!(session_name, msg_type, fields) do
    :ok = SessionWorker.send_message(session_name, msg_type, fields)
  end

  @doc """
  Stop FIX session
  """
  def stop_session(session_name) do
    @session_registry.stop_session(session_name)
  end
end
