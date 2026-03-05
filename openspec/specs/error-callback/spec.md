## ADDED Requirements

### Requirement: Optional on_error callback in SessionHandler

The `ExFix.SessionHandler` behaviour SHALL define an optional callback `on_error/4` with the signature:

```elixir
@callback on_error(
  session_name :: Session.session_name(),
  error_type :: atom(),
  details :: map(),
  env :: map()
) :: any()
```

The callback SHALL be declared with `@optional_callbacks [on_error: 4]`. Handlers that do not implement it SHALL continue to compile and function without changes.

#### Scenario: Handler implements on_error
- **GIVEN** a `SessionHandler` module that implements `on_error/4`
- **WHEN** a session-level error occurs
- **THEN** the system SHALL invoke `on_error/4` with the session name, error type atom, details map, and env

#### Scenario: Handler does not implement on_error
- **GIVEN** a `SessionHandler` module that does not implement `on_error/4`
- **WHEN** a session-level error occurs
- **THEN** the system SHALL NOT raise an error and SHALL continue normal operation

#### Scenario: on_error raises an exception
- **GIVEN** a `SessionHandler` whose `on_error/4` raises an exception
- **WHEN** the callback is invoked
- **THEN** the system SHALL rescue the exception, log it via `Logger.error`, and continue normal session operation

### Requirement: Error type and details contract

Each error notification SHALL include an `error_type` atom and a `details` map. The guaranteed details keys per error type are:

| Error Type | Details Map | Source |
|---|---|---|
| `:connect_error` | `%{reason: term()}` | `SessionWorker` |
| `:transport_error` | `%{reason: term()}` | `SessionWorker` |
| `:garbled_message` | `%{raw_message: binary()}` | `Session` |
| `:heartbeat_timeout` | `%{}` | `Session` |

### Requirement: Transport connect error notification

The system SHALL invoke `on_error/4` with error type `:connect_error` when a TCP/SSL connection attempt fails.

#### Scenario: TCP connection refused
- **GIVEN** a session configured to connect to a host
- **WHEN** `transport_mod.connect/3` returns `{:error, reason}`
- **THEN** `SessionWorker` SHALL invoke `on_error(session_name, :connect_error, %{reason: reason}, env)`
- **AND** the existing `Logger.error` call SHALL remain

### Requirement: Transport send error notification

The system SHALL invoke `on_error/4` with error type `:transport_error` when sending data over the socket fails.

#### Scenario: Send fails on closed socket
- **GIVEN** an active session with an established connection
- **WHEN** `transport.send(client, data)` returns `{:error, reason}`
- **THEN** `SessionWorker` SHALL invoke `on_error(session_name, :transport_error, %{reason: reason}, env)`
- **AND** the system SHALL log the error via `Logger.error`

### Requirement: Garbled message notification

The system SHALL invoke `on_error/4` with error type `:garbled_message` when a garbled FIX message is received.

#### Scenario: Message fails checksum validation
- **GIVEN** an active session receiving data
- **WHEN** the parser returns an `InMessage` with `error_reason: :garbled`
- **THEN** `Session.process_invalid_message/3` SHALL invoke `on_error(session_name, :garbled_message, %{raw_message: binary}, env)` directly (same pattern as existing `on_session_message` calls)
- **AND** the existing garbled-message warning behavior (controlled by `warning_on_garbled_messages` config) SHALL remain unchanged

#### Scenario: Message fails body length validation
- **GIVEN** an active session receiving data
- **WHEN** the parser returns an `InMessage` with `error_reason: :garbled` due to body length mismatch
- **THEN** `Session.process_invalid_message/3` SHALL invoke `on_error(session_name, :garbled_message, %{raw_message: binary}, env)`

### Requirement: Heartbeat timeout notification

The system SHALL invoke `on_error/4` with error type `:heartbeat_timeout` when the counterparty fails to respond within the heartbeat tolerance and a logout is initiated.

#### Scenario: No data received after test request
- **GIVEN** an active session where `last_test_req_id_sent` is not nil (a TestRequest was already sent on the first timeout)
- **WHEN** the RX timer fires again (second consecutive timeout), triggering `Session.handle_timeout/2` to return `{:logout, ...}`
- **THEN** `Session.handle_timeout/2` SHALL invoke `on_error(session_name, :heartbeat_timeout, %{}, env)` before returning the logout result
- **AND** the system SHALL proceed with its existing logout behavior

### Requirement: Callback guard via function_exported?

Before invoking `on_error/4`, the system SHALL check `function_exported?(session_handler, :on_error, 4)`. This check SHALL be performed at each call site without caching, as error paths are infrequent.
