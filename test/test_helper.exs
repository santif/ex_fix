ExUnit.start()

defmodule ExFix.TestHelper do

  alias ExFix.Serializer
  alias ExFix.Types.MessageToSend
  alias ExFix.DefaultDictionary, as: Dictionary

  defmodule FixDummyApplication do
    @behaviour ExFix.FixApplication

    def on_logon(fix_session, pid) do
      send(pid, {:logon, fix_session})
    end

    def on_message(fix_session, msg_type, pid, msg) do
      send(pid, {:msg, fix_session, msg_type, msg})
    end

    def on_logout(_fix_session), do: :ok

    def now(date_time), do: date_time
  end

  defmodule FixEmptyApplication do
    @behaviour ExFix.FixApplication

    def on_logon(_fix_session, _pid) do
    end

    def on_message(_fix_session, _msg_type, _pid, _msg) do
    end

    def on_logout(_fix_session), do: :ok
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
      Process.send(:"ex_fix_session_#{session_name}",
        {socket_protocol, self(), data}, [])
    end

    def receive_msg(session_name, msg) do
      Process.send(:"ex_fix_session_#{session_name}", msg, [])
    end

    def disconnect(session_name, socket_protocol \\ :tcp) do
      Process.send(:"ex_fix_session_#{session_name}",
        {:"#{socket_protocol}_closed", self()}, [])
    end
  end

  @doc """
  Builds test message
  """
  # build_message(@msg_type_new_order_single, 12, "SELLSIDE", "BUYSIDE",
  #     @t_plus_1, [{@field_account, "1234"}, {@field_last_px, 1.23}])
  def build_message(msg_type, seqnum, sender, target, now, fields \\ [], orig_sending_time \\ nil, resend \\ false) do
    fields = for {field_name, value} <- fields do
      {field, _} = Dictionary.tag_info(field_name)
      {field, value}
    end
    Serializer.serialize(%MessageToSend{seqnum: seqnum,
      msg_type: msg_type,
      sender: sender,
      orig_sending_time: orig_sending_time,
      target: target,
      body: fields}, now, resend)
  end

  @doc """
  Helper function to construct a FIX message from UTF-8 string
  """
  def msg(data) when is_binary(data) do
    result = data
    |> :unicode.characters_to_binary(:utf8, :latin1)
    |> :binary.replace("|", << 1 >>, [:global])

    result2 = case String.contains?(result, "9=$$$")do
      true ->
        size_val = "#{byte_size(result) - byte_size("8=FIXT.1.1|9=$$$|10=$$$|")}"
        :binary.replace(result, <<1, "9=$$$", 1>>, <<1, "9=", size_val::binary(), 1>>)
      false ->
        result
    end

    result3 = case String.contains?(result2, "10=$$$") do
      true ->
        cs_val = checksum(result2)
        :binary.replace(result2, <<1, "10=$$$", 1>>, <<1, "10=", cs_val::binary(), 1>>)
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
  defp cs(<< value::binary-size(1), rest::binary() >>, acc) do
    cs(rest, acc + :binary.decode_unsigned(value))
  end
end
