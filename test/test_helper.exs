ExUnit.start()

defmodule ExFix.TestHelper do
  alias ExFix.Serializer
  alias ExFix.Session.MessageToSend

  defmodule FixDummySessionHandler do
    @behaviour ExFix.SessionHandler

    def on_logon(session_name, env) do
      send(self(), {:logon, session_name, env})
    end

    def on_app_message(session_name, msg_type, msg, env) do
      send(self(), {:msg, session_name, msg_type, msg, env})
    end

    def on_session_message(session_name, msg_type, msg, env) do
      send(self(), {:session_msg, session_name, msg_type, msg, env})
    end

    def on_logout(_session_id, _env), do: :ok
  end

  defmodule FixEmptySessionHandler do
    @behaviour ExFix.SessionHandler

    def on_logon(_session_id, _env) do
    end

    def on_app_message(_session_id, _msg_type, _msg, _env) do
    end

    def on_session_message(_session_id, _msg_type, _msg, _env) do
    end

    def on_logout(_session_id, _env), do: :ok
  end

  defmodule TestTransport do
    def connect(_host, _port, options) do
      {:ok, options[:test_pid]}
    end

    def send(conn, data) do
      Process.send(conn, {:data, data}, [])
    end

    def close(_conn), do: :ok

    def receive_data(session_name, data, socket_protocol \\ :tcp) do
      Process.send(:"ex_fix_session_#{session_name}", {socket_protocol, self(), data}, [])
    end

    def receive_msg(session_name, msg) do
      Process.send(:"ex_fix_session_#{session_name}", msg, [])
    end

    def disconnect(session_name, socket_protocol \\ :tcp) do
      Process.send(:"ex_fix_session_#{session_name}", {:"#{socket_protocol}_closed", self()}, [])
    end
  end

  defmodule TestSessionRegistry do
    @moduledoc """
    Session registry for tests
    """

    # @behaviour ExFix.SessionRegistry
    use GenServer

    ##
    ## API
    ##

    def start_link do
      GenServer.start_link(__MODULE__, [], name: __MODULE__)
    end

    def get_session_status(session_name) do
      GenServer.call(__MODULE__, {:get_status, session_name})
    end

    ##
    ## Internal API (functions to use from FIX session genservers)
    ##

    def session_on_init(session_name) do
      GenServer.call(__MODULE__, {:session_on_init, session_name})
    end

    def session_update_status(session_name, status) do
      GenServer.call(__MODULE__, {:session_update_status, session_name, status})
    end

    ##
    ## GenServer callbacks
    ##

    def init([]) do
      {:ok, %{}}
    end

    def handle_call({:get_status, fix_session_name}, _from, state) do
      {:reply, state[fix_session_name] || :connecting, state}
    end

    def handle_call({:start_session, fix_session_name}, _from, state) do
      state = Map.put(state, fix_session_name, :connecting)
      {:reply, :ok, state}
    end

    def handle_call({:stop_session, fix_session_name}, _from, state) do
      state = Map.delete(state, fix_session_name)
      {:reply, :ok, state}
    end

    def handle_call({:session_on_init, fix_session_name}, _from, state) do
      state = Map.put(state, fix_session_name, :connecting)
      {:reply, :ok, state}
    end

    def handle_call({:session_update_status, fix_session_name, status}, _from, state) do
      state = Map.put(state, fix_session_name, status)
      {:reply, :ok, state}
    end
  end

  defmodule InMessageTestDict do
    @behaviour ExFix.Dictionary

    @execution_report_msg_type "8"
    @seclist_msg_type "y"
    @account_field "1"
    @market_id "1301"
    @market_segment_id "1300"

    def subject(@execution_report_msg_type), do: @account_field
    def subject(@seclist_msg_type), do: [@market_id, @market_segment_id]
    def subject(_), do: nil
  end

  @doc """
  Builds test message
  """
  def build_message(
        msg_type,
        seqnum,
        sender,
        target,
        now,
        fields \\ [],
        orig_sending_time \\ nil,
        resend \\ false
      ) do
    Serializer.serialize(
      %MessageToSend{
        seqnum: seqnum,
        msg_type: msg_type,
        sender: sender,
        orig_sending_time: orig_sending_time,
        target: target,
        body: fields
      },
      now,
      resend
    )
  end

  @doc """
  Helper function to construct a FIX message from UTF-8 string
  """
  def msg(data) when is_binary(data) do
    result =
      data
      |> :unicode.characters_to_binary(:utf8, :latin1)
      |> :binary.replace("|", <<1>>, [:global])

    result2 =
      case String.contains?(result, "9=$$$") do
        true ->
          size_val = "#{byte_size(result) - byte_size("8=FIXT.1.1|9=$$$|10=$$$|")}"
          :binary.replace(result, <<1, "9=$$$", 1>>, <<1, "9=", size_val::binary, 1>>)

        false ->
          result
      end

    result3 =
      case String.contains?(result2, "10=$$$") do
        true ->
          cs_val = checksum(result2)
          :binary.replace(result2, <<1, "10=$$$", 1>>, <<1, "10=", cs_val::binary, 1>>)

        false ->
          result2
      end

    result3
  end

  @doc """
  FIX checksum
  """
  def checksum(msg_bin) when is_binary(msg_bin) do
    msg_bin
    |> :binary.split(<<"10=">>)
    |> List.first()
    |> cs()
  end

  ##
  ## Private functions
  ##

  defp cs(value, acc \\ 0)

  defp cs(<<>>, acc) do
    String.pad_leading("#{rem(acc, 256)}", 3, "0")
  end

  defp cs(<<value::binary-size(1), rest::binary>>, acc) do
    cs(rest, acc + :binary.decode_unsigned(value))
  end
end
