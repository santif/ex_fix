defmodule ExFix.DefaultDictionary do
  @moduledoc """
  Simple FIX Dictionary
  """

  @behaviour ExFix.Dictionary

  # def tag_info("MsgSeqNum"),                  do: {"34", :number}
  # def tag_info("SenderCompID"),               do: {"49", :string}
  # def tag_info("TargetCompID"),               do: {"56", :string}
  # def tag_info("EncryptMethod"),              do: {"9", :string}
  # def tag_info("HeartBtInt"),                 do: {"108", :number}
  # def tag_info("ResetSeqNumFlag"),            do: {"34", :boolean}
  # def tag_info("Username"),                   do: {"553", :string}
  # def tag_info("Password"),                   do: {"554", :string}
  # def tag_info("DefaultApplVerID"),           do: {"1407", :string}
  def field_info(value) when is_binary(value),  do: {value, :string}

  def subject("8"), do: "1"
  def subject("W"), do: "55"
  def subject(_), do: nil
end
