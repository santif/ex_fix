defmodule ExFixInitiator do
  @moduledoc """
  Documentation for ExFixInitiator.
  """


  defmodule FixApplication do
    require Logger
    @behaviour ExFix.FixApplication

    alias ExFix.Types.Message

    def before_logon(_fix_session_name, _fields), do: :ok

    def on_logon(fix_session_name, _pid) do
      Logger.info "[fix.incoming] [#{fix_session_name}] onLogon"
      for x <- 1..10_000 do
        spawn(fn() ->
          fields = [
            {"1", 1234},           # Account
            {"11", "cod12345"},    # ClOrdID
            {"38", 10},            # OrderQty
            {"40", "2"},           # OrdType
            {"44", 1.23},          # Price
            {"54", "1"},           # Side
            {"55", "SYM1"},        # Symbol
            {"59", "0"},           # TimeInForce
            {"60", DateTime.utc_now}, # TransactTime
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
      FixApplication, [dictionary: ExFix.DefaultDictionary])
  end
end
