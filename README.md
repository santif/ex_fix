# ExFix

[![Master](https://travis-ci.org/santif/ex_fix.svg?branch=master)](https://travis-ci.org/santif/ex_fix)
[![Hex.pm Version](http://img.shields.io/hexpm/v/ex_fix.svg?style=flat)](https://hex.pm/packages/ex_fix)
[![Coverage Status](https://coveralls.io/repos/github/santif/ex_fix/badge.svg?branch=master)](https://coveralls.io/github/santif/ex_fix?branch=master)

Elixir implementation of FIX Session Protocol FIXT.1.1.
Currently only supports FIX session initiator (buy side).

## Installation

Add `ex_fix` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:ex_fix, "~> 0.1.0"}]
end
```

## Usage

```elixir
defmodule MyFixApplication do
  @behaviour ExFix.FixApplication
  alias ExFix.Types.Message

  def before_logon(_fix_session_name, _fields), do: :ok

  def on_logon(fix_session_name, session_pid) do
    # Logon OK
    # ...
  end

  def on_message(fix_session_name, msg_type, session_pid, %Message{} = msg) do
    # Message received from FIX counterparty
    # ...
  end

  def on_logout(fix_session_name) do
    # ...
  end
end

ExFix.start_session_initiator("mysession", "SENDER", "TARGET", MyFixApplication,
  socket_connect_host: "localhost", socket_connect_port: 9876,
  logon_username: "user1", logon_password: "pwd1", transport_mod: :ssl)
# ...
ExFix.send_message!("mysession", msg_fields)  ## See examples directory
```

## Features

- FIXT.1.1 session protocol implementation (session level messages)
- Message validation: sequence number, length, checksum
- Auto reconnection
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

- Application level:
  - Dictionary based message parse/validation/serialization
  - Automatic generation of parser/validator/serializer from XML dictionary file
  - Repeating groups
- FIX session acceptor
- Multiple hosts configuration, for failover
- Session scheduling (integration with 3rd party job management libraries)
- etc.

## Benchmarks

Elixir can't beat the performance of C/C++, but this library lets you avoid
communication time between an external FIX initiator and the Erlang VM.
In addition, there are fewer dependencies and number of possible failure points.

- HW: Laptop Dell Latitude E5570 Intel(R) Core(TM) i7-6600U CPU @ 2.60GHz 16 GB RAM
- Elixir 1.4.5 / Erlang 19.2
- Parser benchmark: Execution Report with 155 bytes.
- Serializer benchmark: New Order Single with 115 bytes.

```
$ mix bench
...
## ExFixBench
benchmark name                         iterations   average time 
Parse - Stage 1 (without validation)       500000   6.26 µs/op
Parse - Stage 1                            500000   7.64 µs/op
Serialize                                  100000   11.75 µs/op
Parse - Full Msg (without validation)      100000   14.42 µs/op
Parse - Full Msg                           100000   16.23 µs/op
```

## Author

Santiago Fernandez `<santif@gmail.com>`.

## License

Copyright (c) 2017 Matriz S.A. [http://www.matriz.com.ar](http://www.matriz.com.ar)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
