defmodule ExFixInitiator do
  @moduledoc """
  Documentation for ExFixInitiator.
  """


  defmodule FixApplication do
    require Logger
    @behaviour ExFix.FixApplication

    alias ExFix.Types.Message

    @tag_account       "1"
    @tag_cl_ord_id     "11"
    @tag_order_qty     "38"
    @tag_ord_type      "40"
    @tag_price         "44"
    @tag_side          "54"
    @tag_symbol        "55"
    @tag_time_in_force "59"
    @tag_transact_time "60"

    def before_logon(_fix_session_name, _fields), do: :ok

    def on_logon(fix_session_name, _pid) do
      Logger.info "[fix.incoming] [#{fix_session_name}] onLogon"
      for x <- 1..10_000 do
        spawn(fn() ->
          fields = [
            {@tag_account, 1234},
            {@tag_cl_ord_id, "cod12345"},
            {@tag_order_qty, 10},
            {@tag_ord_type, "2"},
            {@tag_price, 1.23},
            {@tag_side, "1"},
            {@tag_symbol, "SYM1"},
            {@tag_time_in_force, "0"},
            {@tag_transact_time, DateTime.utc_now},
          ]
          ExFix.send_message!(fix_session_name, "D", fields)
        end)
      end
    end
    def on_message(fix_session_name, _msg_type, _pid, %Message{original_fix_msg:
        original_fix_msg}) do
      Logger.info "[fix.incoming] [#{fix_session_name}] #{original_fix_msg}"
    end
    def on_logout(fix_session_name) do
      Logger.info "[fix.event] [#{fix_session_name}] onLogout"
    end
  end

  def start() do
    ExFix.start_session_initiator("simulator", "BUY", "SELL",
      FixApplication, dictionary: ExFix.DefaultDictionary, transport_mod: :ssl)
  end
end
