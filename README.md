# ExFIX

[![Master](https://travis-ci.org/santif/ex_fix.svg?branch=master)](https://travis-ci.org/santif/ex_fix)
[![Coverage Status](https://coveralls.io/repos/github/santif/ex_fix/badge.svg?branch=master)](https://coveralls.io/github/santif/ex_fix?branch=master)
[![Tokei](https://tokei.rs/b1/github/santif/ex_fix?category=code)](https://tokei.rs/b1/github/santif/ex_fix?category=code)
[![Hex.pm Version](http://img.shields.io/hexpm/v/ex_fix.svg?style=flat)](https://hex.pm/packages/ex_fix)
[![Ebert](https://ebertapp.io/github/santif/ex_fix.svg)](https://ebertapp.io/github/santif/ex_fix)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

**Warning:** This library is under active development and the API is subject to change.

Elixir implementation of FIX Session Protocol FIXT.1.1.
Currently only supports FIX session initiator (buy side).

## Installation

Add `ex_fix` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:ex_fix, "~> 0.2.1"}]
end
```

## Features

- FIXT.1.1 session protocol implementation (session level messages)
- Message validation: sequence number, length, checksum
- Auto reconnection (with `ResetSeqNumFlag=Y`)
- SSL compatible
- Session registry
- Two-phase parse of FIX messages

## Usage

```elixir
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
      ## Buy 10 shares of SYM1 for $1.23 per share

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
    Logger.info "App msg received: #{inspect Parser.parse2(msg)}"
  end

  def on_session_message(_session_name, _msg_type, %InMessage{} = msg, _env) do
    Logger.info "Session msg received: #{inspect Parser.parse2(msg)}"
  end

  def on_logout(_session_id, _env), do: :ok
end

ExFix.start_session_initiator("simulator", "BUY", "SELL", MySessionHandler,
  hostname: "localhost", port: 9876, username: "user1", password: "pwd1",
  transport_mod: :ssl)
```

#### Output

```
[debug] Starting FIX session: [simulator]
[debug] [simulator] Trying to connect to localhost:9876...
[info]  [fix.outgoing] [simulator] 8=FIXT.1.1^A9=94^A35=A^A34=1^A49=BUY^A52=20170806-20:25:24.194^A56=SELL^A98=0^A108=60^A141=Y^A553=user1^A554=pwd1^A1137=9^A10=012^A
[info]  [fix.incoming] [simulator] 8=FIXT.1.1^A9=75^A35=A^A34=1^A49=SELL^A52=20170806-20:25:24.196^A56=BUY^A98=0^A108=60^A141=Y^A1137=9^A10=234^A
[info]  Session msg received: %ExFix.InMessage{complete: true, error_reason: nil, fields: [{"35", "A"}, {"34", "1"}, {"49", "SELL"}, {"52", "20170806-20:25:24.196"}, {"56", "BUY"}, {"98", "0"}, {"108", "60"}, {"141", "Y"}, {"1137", "9"}], msg_type: "A", original_fix_msg: <<56, 61, 70, 73, 88, 84, 46, 49, 46, 49, 1, 57, 61, 55, 53, 1, 51, 53, 61, 65, 1, 51, 52, 61, 49, 1, 52, 57, 61, 83, 69, 76, 76, 1, 53, 50, 61, 50, 48, 49, 55, 48, 56, 48, 54, ...>>, other_msgs: "", poss_dup: false, rest_msg: "", seqnum: 1, subject: nil, valid: true}
[info]  session_update_status [simulator] - Status: :connected
[info]  [fix.outgoing] [simulator] 8=FIXT.1.1^A9=126^A35=D^A34=2^A49=BUY^A52=20170806-20:25:24.202^A56=SELL^A1=1234^A11=cod12345^A38=10^A40=2^A44=1.23^A54=1^A55=SYM1^A60=20170806-20:25:24.202^A10=081^A
[info]  [fix.incoming] [simulator] 8=FIXT.1.1^A9=118^A35=8^A34=2^A49=SELL^A52=20170806-20:25:24.203^A56=BUY^A1=1234^A6=1.23^A14=10^A17=2^A31=1.23^A37=2^A39=2^A54=1^A55=SYM1^A150=2^A151=0^A10=151^A
[info]  App msg received: %ExFix.InMessage{complete: true, error_reason: nil, fields: [{"35", "8"}, {"34", "2"}, {"49", "SELL"}, {"52", "20170806-20:25:24.203"}, {"56", "BUY"}, {"1", "1234"}, {"6", "1.23"}, {"14", "10"}, {"17", "2"}, {"31", "1.23"}, {"37", "2"}, {"39", "2"}, {"54", "1"}, {"55", "SYM1"}, {"150", "2"}, {"151", "0"}], msg_type: "8", original_fix_msg: <<56, 61, 70, 73, 88, 84, 46, 49, 46, 49, 1, 57, 61, 49, 49, 56, 1, 51, 53, 61, 56, 1, 51, 52, 61, 50, 1, 52, 57, 61, 83, 69, 76, 76, 1, 53, 50, 61, 50, 48, 49, 55, 48, 56, 48, ...>>, other_msgs: "", poss_dup: false, rest_msg: "", seqnum: 2, subject: nil, valid: true}
```

## Two-phase parse

This library allows to parse the FIX message until certain tags are found. At that
point it is possible to send the message to another process (for example, a Book process,
Account process, etc) to complete the parse and execute business logic specifically for
the message's `subject`.

As can be seen in the benchmarks below, the two-phase parse substantially decreases
the time spent in the network client process.

## To Do list

This is a work in progress. Here is a list of some pending tasks, PRs are welcome.

- Documentation and more examples
- Session Logon with `ResetSeqNumFlag=N`.
- Multiple hosts configuration, for failover
- Socket client optimizations
- Application level:
  - Dictionary based message parse/validation/serialization
  - Automatic generation of parser/validator/serializer from XML dictionary file
  - Repeating groups
- FIX session acceptor
- Session scheduling (integration with 3rd party job management libraries)
- etc.

## Benchmarks

Elixir can't beat the performance of C/C++, but this library lets you avoid
communication time between an external FIX initiator and the Erlang VM.
In addition, there are fewer dependencies and number of possible failure points.

- HW: Laptop Dell Latitude E5570 Intel(R) Core(TM) i7-6600U CPU @ 2.60GHz 16 GB RAM
- Elixir 1.5.1 / Erlang 19.2
- Parser benchmark: Execution Report with 155 bytes.
- Serializer benchmark: New Order Single with 115 bytes.

```
$ mix bench -d 2
...
## ExFixBench
benchmark name                         iterations   average time
Parse - Stage 1 (without validation)      1000000   5.25 µs/op
Parse - Stage 1                            500000   6.88 µs/op
Serialize                                  500000   11.66 µs/op
Parse - Full Msg (without validation)      500000   13.58 µs/op
Parse - Full Msg                           500000   15.31 µs/op
```

## Maintainer

Santiago Fernandez `<santif@gmail.com>`

## License

Copyright (c) 2017 Matriz S.A.
[http://www.matriz.com.ar](http://www.matriz.com.ar)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
