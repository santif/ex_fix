# Transport

## Purpose

Transport abstraction layer for network communication with FIX counterparties.

## Requirements

### Requirement: Duck-typed contract

The system MUST accept any transport module that implements three functions:

- `connect(host, port, options)` — returns `{:ok, client}` or `{:error, reason}`
- `send(client, data)` — sends binary data over the connection
- `close(client)` — closes the connection

There is no formal behaviour; the contract is fulfilled by duck typing. The `:gen_tcp` and `:ssl` Erlang/OTP modules fulfill this contract natively.

#### Scenario: Compatible module
- **WHEN** a module that implements `connect/3`, `send/2`, and `close/1` is configured
- **THEN** the system accepts it as a valid transport

### Requirement: Per-session configurable transport

Each session MUST be able to configure its transport independently via:

- `transport_mod` — transport module (default: `:gen_tcp`)
- `transport_options` — additional options passed to `connect/3`

The system MUST prepend `[mode: :binary]` to user options before connecting.

#### Scenario: Custom transport options
- **WHEN** `transport_options: [verify: :verify_peer]` is configured
- **THEN** `[mode: :binary, verify: :verify_peer]` is passed to `connect/3`

### Requirement: TCP support

The system MUST support plain TCP connections via `:gen_tcp` as the default transport.

#### Scenario: Default TCP connection
- **WHEN** `transport_mod` is not specified
- **THEN** `:gen_tcp` is used for the connection

### Requirement: SSL/TLS support

The system MUST support SSL/TLS connections via `:ssl`, accepting all standard `:ssl.connect/3` options in `transport_options` (certificates, peer verification, etc.).

#### Scenario: SSL connection
- **WHEN** `transport_mod: :ssl` is configured
- **THEN** an SSL/TLS connection is established

### Requirement: Asynchronous I/O

The system MUST receive network data as process messages (`:tcp` or `:ssl` tuples), following the BEAM asynchronous model. It MUST NOT make blocking calls to read data.

#### Scenario: Asynchronous TCP reception
- **WHEN** data arrives over a TCP connection
- **THEN** the process receives a `{:tcp, socket, data}` message

#### Scenario: Asynchronous SSL reception
- **WHEN** data arrives over an SSL connection
- **THEN** the process receives a `{:ssl, socket, data}` message

### Requirement: Disconnection detection

The system MUST detect disconnections via `:tcp_closed` or `:ssl_closed` messages from the transport and terminate the session worker with reason `:closed`.

#### Scenario: TCP disconnection
- **WHEN** the TCP connection is closed
- **THEN** the process receives `{:tcp_closed, socket}` and the worker terminates with reason `:closed`

### Requirement: Connection error

If `connect/3` returns `{:error, reason}`, the system MUST:

- Log the error
- Terminate the SessionWorker with the error reason
- Update the state in the registry to `:reconnecting`

#### Scenario: Connection error
- **WHEN** `connect/3` returns `{:error, :econnrefused}`
- **THEN** the error is logged, the worker terminates, and the registry marks `:reconnecting`

### Requirement: Disconnection during operation

If the connection closes unexpectedly, the system MUST:

- Terminate the SessionWorker with reason `:closed`
- Update the state in the registry to `:reconnecting`

#### Scenario: Unexpected close
- **WHEN** the connection closes during normal operation
- **THEN** the worker terminates with reason `:closed` and the registry marks `:reconnecting`

### Requirement: Partial TCP messages

The system MUST handle TCP fragmentation:

- Maintain a buffer (`extra_bytes`) with incomplete data between receptions
- Concatenate new data with the buffer before parsing
- Support multiple FIX messages in a single TCP segment

#### Scenario: TCP fragmentation
- **WHEN** a FIX message arrives in two separate TCP segments
- **THEN** partial bytes are buffered and processed upon completion

### Requirement: Continuous processing

When a TCP segment contains multiple FIX messages, the system MUST process them sequentially until all available data is exhausted, without waiting for new network data.

#### Scenario: Multiple messages in one segment
- **WHEN** a TCP segment contains 3 complete FIX messages
- **THEN** all 3 are processed sequentially without waiting for new data

### Requirement: Mockable transport

The duck-typed contract MUST allow injecting a test transport that:

- Simulates connections without a real network
- Captures sent messages for verification
- Allows injecting reception data and disconnection events

#### Scenario: Test with mock transport
- **WHEN** a mock module is configured as `transport_mod`
- **THEN** the session works without a real network and messages are capturable
