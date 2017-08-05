defmodule ExFixInitiator do
  @moduledoc """
  Documentation for ExFixInitiator.
  """

  defmodule FixApplication do
    @moduledoc false
    require Logger
    @behaviour ExFix.FixApplication

    alias ExFix.OutMessage
    alias ExFix.InMessage

    @tag_account         1
    @tag_cl_ord_id      11
    @tag_order_qty      38
    @tag_ord_type       40
    @tag_price          44
    @tag_side           54
    @tag_symbol         55
    @tag_time_in_force  59
    @tag_transact_time  60

    def on_logon(session_id, _env) do
      Logger.info fn -> "[fix.incoming] [#{session_id}] onLogon" end
      for _x <- 1..10_000 do
        spawn(fn() ->
          out_msg = "D"
          |> OutMessage.new()
          |> OutMessage.set_field(@tag_account, 1234)
          |> OutMessage.set_field(@tag_cl_ord_id, "cod12345")
          |> OutMessage.set_field(@tag_order_qty, 10)
          |> OutMessage.set_field(@tag_ord_type, "2")
          |> OutMessage.set_field(@tag_price, 1.23)
          |> OutMessage.set_field(@tag_side, "1")
          |> OutMessage.set_field(@tag_symbol, "SYM1")
          |> OutMessage.set_field(@tag_time_in_force, "0")
          |> OutMessage.set_field(@tag_transact_time, DateTime.utc_now())
          |> ExFix.send_message!(session_id)
        end)
      end
    end
    def on_message(session_id, _msg_type, %InMessage{original_fix_msg: original_fix_msg}, _env) do
      Logger.info fn -> "[fix.incoming] [#{session_id}] #{original_fix_msg}" end
    end
    def on_admin_message(session_id, _msg_type, %InMessage{original_fix_msg: original_fix_msg}, _env) do
      Logger.info fn -> "[fix.incoming] [#{session_id}] #{original_fix_msg}" end
    end
    def on_logout(session_id, _env) do
      Logger.info fn -> "[fix.event] [#{session_id}] onLogout" end
    end
  end

  def start() do
    ExFix.start_session_initiator("simulator", "BUY", "SELL",
      FixApplication, dictionary: ExFix.DefaultDictionary, transport_mod: :ssl)
  end
end
