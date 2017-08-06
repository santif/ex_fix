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
  [{:ex_fix, "~> 0.2.0"}]
end
```

## Usage

```elixir
defmodule MySessionHandler do
  @behaviour ExFix.SessionHandler
  require Logger

  alias ExFix.InMessage
  alias ExFix.OutMessage
  alias ExFix.Parser

  @msg_new_order_single "D"

  @tag_account           "1"
  @tag_cl_ord_id        "11"
  @tag_order_qty        "38"
  @tag_ord_type         "40"
  @tag_price            "44"
  @tag_side             "54"
  @tag_symbol           "55"
  @tag_time_in_force    "59"
  @tag_transact_time    "60"

  @value_side_buy        "1"
  @value_ord_type_limit  "2"

  def on_logon(session_name, _env) do
    ## Buy 10 shares of SYM1 for $1.23 per share

    @msg_new_order_single
    |> OutMessage.new()
    |> OutMessage.set_field(@tag_account, 1234)
    |> OutMessage.set_field(@tag_cl_ord_id, "cod12345")
    |> OutMessage.set_field(@tag_order_qty, 10)
    |> OutMessage.set_field(@tag_ord_type, @value_ord_type_limit)
    |> OutMessage.set_field(@tag_price, 1.23)
    |> OutMessage.set_field(@tag_side, @value_side_buy)
    |> OutMessage.set_field(@tag_symbol, "SYM1")
    |> OutMessage.set_field(@tag_transact_time, DateTime.utc_now())
    |> ExFix.send_message!(session_name)
  end

  def on_app_message(session_name, msg_type, %InMessage{} = msg, _env) do
    Logger.info "App msg received: #{inspect Parser.parse2(msg)}"
  end

  def on_session_message(session_name, msg_type, %InMessage{} = msg, _env) do
    Logger.info "Session msg received: #{inspect Parser.parse2(msg)}"
  end

  def on_logout(_session_id, _env), do: :ok
end

ExFix.start_session_initiator("mysession", "SENDER", "TARGET", MySessionHandler,
  hostname: "localhost", port: 9876, username: "user1", password: "pwd1",
  transport_mod: :ssl)
```

## Features

- FIXT.1.1 session protocol implementation (session level messages)
- Message validation: sequence number, length, checksum
- Auto reconnection (with `ResetSeqNumFlag=Y`)
- SSL compatible
- Session registry
- Two-phase parse of FIX messages


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
- Elixir 1.4.5 / Erlang 20.0
- Parser benchmark: Execution Report with 155 bytes.
- Serializer benchmark: New Order Single with 115 bytes.

```
$ mix bench -d 2
...
## ExFixBench
benchmark name                         iterations   average time
Parse - Stage 1 (without validation)      1000000   5.80 µs/op
Parse - Stage 1                            500000   7.30 µs/op
Serialize                                  500000   12.00 µs/op
Parse - Full Msg (without validation)      200000   15.36 µs/op
Parse - Full Msg                           200000   16.12 µs/op
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
