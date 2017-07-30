# ExFix

[![Master](https://travis-ci.org/santif/ex_fix.svg?branch=master)](https://travis-ci.org/santif/ex_fix)
[![Hex.pm Version](http://img.shields.io/hexpm/v/ex_fix.svg?style=flat)](https://hex.pm/packages/ex_fix)
[![Coverage Status](https://coveralls.io/repos/github/santif/ex_fix/badge.svg?branch=master)](https://coveralls.io/github/santif/ex_fix?branch=master)

FIX Session Protocol (FIXT.1.1) implementation in Elixir.
Currently only supports FIX Initiator (buy side).

## Installation

Add `ex_fix` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:ex_fix, "~> 0.1.0"}]
end
```

## Two phase parse

This library allows to parse the FIX message until certain tags are found. At that
point it is possible to send the message to another process (example, a Book process,
Account process, etc) to complete the parse and execute business logic.

As can be seen in the benchmarks below, two-phase parse allows to substantially
decrease the time spent in the network client process.

## To Do list

This is a work in progress. Here is a list of some pending tasks, PRs are allowed.

- Dictionary based message validation/parse/serialization
- Automatic generation of parser/validator/serializer from XML dictionary file
- FIX Acceptor
- Multiple hosts configuration, for failover
- Etc

## Benchmarks

Elixir can't beat the performance of C/C++, but this library allows to avoid
communication time between an external FIX initiator and the Erlang VM.
In addition, there are fewer dependencies and number of failure points.

- HW: Laptop Dell Latitude E5570 Intel(R) Core(TM) i7-6600U CPU @ 2.60GHz 16 GB RAM
- Parse benchmark: Execution Report with 155 bytes.
- Serialize benchmark: New Order Single with 115 bytes.

```
$ mix bench
...
## ExFixBench
benchmark name                         iterations   average time
Parse - Stage 1 (without validation)       500000   6.41 µs/op
Parse - Stage 1                            500000   7.85 µs/op
Serialize                                  100000   12.28 µs/op
Parse - Full Msg (without validation)      100000   15.11 µs/op
Parse - Full Msg                           100000   15.95 µs/op
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
