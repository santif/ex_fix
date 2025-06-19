defmodule ExFix do
  @moduledoc """
  Elixir implementation of FIX Session Protocol FIXT.1.1.
  Currently only supports FIX session initiator (buy side).

  ## Usage

  ```
  defmodule MySessionHandler do
    @behaviour ExFix.SessionHandler
    require Logger

    alias ExFix.InMessage
    alias ExFix.OutMessage
    alias ExFix.Parser

    @msg_new_order_single  "D"

    @field_account         "1"
    @field_cl_ord_id      "11"
    @field_order_qty      "38"
    @field_ord_type       "40"
    @field_price          "44"
    @field_side           "54"
    @field_symbol         "55"
    @field_transact_time  "60"

    @value_side_buy        "1"
    @value_ord_type_limit  "2"

    def on_logon(session_name, _env) do
      spawn fn() ->
        \#\# Buy 10 shares of SYM1 for $1.23 per share

        @msg_new_order_single
        |> OutMessage.new()
        |> OutMessage.set_field(@field_account, 1234)
        |> OutMessage.set_field(@field_cl_ord_id, "cod12345")
        |> OutMessage.set_field(@field_order_qty, 10)
        |> OutMessage.set_field(@field_ord_type, @value_ord_type_limit)
        |> OutMessage.set_field(@field_price, 1.23)
        |> OutMessage.set_field(@field_side, @value_side_buy)
        |> OutMessage.set_field(@field_symbol, "SYM1")
        |> OutMessage.set_field(@field_transact_time, DateTime.utc_now())
        |> ExFix.send_message!(session_name)
      end
    end

    def on_app_message(_session_name, _msg_type, %InMessage{} = msg, _env) do
      Logger.info "App msg received: \#{inspect Parser.parse2(msg)}"
    end

    def on_session_message(_session_name, _msg_type, %InMessage{} = msg, _env) do
      Logger.info "Session msg received: \#{inspect Parser.parse2(msg)}"
    end

    def on_logout(_session_id, _env), do: :ok
  end

  ExFix.start_session_initiator("simulator", "BUY", "SELL", MySessionHandler,
    hostname: "localhost", port: 9876, username: "user1", password: "pwd1",
    transport_mod: :ssl)
  ```
  """

  alias ExFix.Session
  alias ExFix.SessionConfig
  alias ExFix.SessionRegistry
  alias ExFix.SessionWorker
  alias ExFix.OutMessage
  alias ExFix.SessionHandler

  @default_dictionary Application.compile_env(:ex_fix, :default_dictionary, ExFix.DefaultDictionary)
  @session_registry Application.compile_env(:ex_fix, :session_registry, ExFix.DefaultSessionRegistry)

  @doc """
  Starts FIX session initiator
  """
  @spec start_session_initiator(String.t(), String.t(), String.t(), SessionHandler, list()) :: :ok
  def start_session_initiator(
        session_name,
        sender_comp_id,
        target_comp_id,
        session_handler,
        opts \\ []
      ) do
    opts =
      Enum.into(opts, %{
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

    config =
      struct(
        %SessionConfig{
          name: session_name,
          mode: :initiator,
          sender_comp_id: sender_comp_id,
          target_comp_id: target_comp_id,
          session_handler: session_handler
        },
        opts
      )

    session_registry = opts[:session_registry] || @session_registry
    session_registry.start_session(session_name, config)
  end

  @doc """
  Send FIX message to a session
  """
  @spec send_message!(OutMessage.t(), Session.session_name()) :: :ok | no_return
  def send_message!(out_message, session_name) do
    SessionWorker.send_message!(session_name, out_message)
  end

  @doc """
  Stop FIX session
  """
  @spec stop_session(Session.session_name(), SessionRegistry | nil) :: :ok | no_return
  def stop_session(session_name, registry \\ nil) do
    session_registry = registry || @session_registry
    session_registry.stop_session(session_name)
  end
end
