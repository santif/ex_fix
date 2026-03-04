# Public API

## Purpose

User interface of the `ExFix` module — entry point for starting sessions, sending messages, and stopping FIX sessions.

## Requirements

### Requirement: start_session_initiator signature

The system MUST expose `ExFix.start_session_initiator/5` with the following signature:

```elixir
start_session_initiator(session_name, sender_comp_id, target_comp_id, session_handler, opts \\ [])
```

Where:

| Parameter | Type | Description |
|-----------|------|-------------|
| `session_name` | `String.t()` | Unique name that identifies the session |
| `sender_comp_id` | `String.t()` | CompID of the initiator (buy-side) |
| `target_comp_id` | `String.t()` | CompID of the counterparty (sell-side) |
| `session_handler` | module | Module that implements the `SessionHandler` behaviour |
| `opts` | keyword list | Configuration options (see spec `session-management`) |

#### Scenario: Start with minimal parameters
- **WHEN** `start_session_initiator("sim", "BUY", "SELL", MyHandler)` is invoked
- **THEN** a session starts with default values for all options

#### Scenario: Start with custom options
- **WHEN** `start_session_initiator("sim", "BUY", "SELL", MyHandler, hostname: "remote", port: 5000)` is invoked
- **THEN** a session starts using the provided options and defaults for the rest

### Requirement: Options processing

The function MUST convert the keyword list `opts` to a map, applying default values for all options not provided. Default values are documented in the spec `session-management` (Configuration section).

#### Scenario: Partial options are completed with defaults
- **WHEN** only `hostname: "remote"` is provided in opts
- **THEN** the remaining options (`port`, `heart_bt_int`, etc.) take their default values

### Requirement: SessionConfig construction

The function MUST build a `SessionConfig` struct with:

- `name` — the provided `session_name`
- `mode` — always `:initiator`
- `sender_comp_id`, `target_comp_id`, `session_handler` — from the parameters
- Remaining fields — from the processed options

#### Scenario: Resulting config has correct fields
- **WHEN** `start_session_initiator("sim", "BUY", "SELL", MyHandler)` is invoked
- **THEN** the SessionConfig has `name: "sim"`, `mode: :initiator`, `sender_comp_id: "BUY"`, `target_comp_id: "SELL"`, `session_handler: MyHandler`

### Requirement: Delegation to registry

The function MUST delegate session startup to the configured `SessionRegistry`, invoking `session_registry.start_session(session_name, config)`.

The registry is determined in this priority order:

1. `opts[:session_registry]` if present
2. The default registry configured in `Application.compile_env(:ex_fix, :session_registry)`
3. `ExFix.DefaultSessionRegistry` as final fallback

#### Scenario: Default registry
- **WHEN** `session_registry` is not provided in opts
- **THEN** the application-configured registry or `ExFix.DefaultSessionRegistry` is used

#### Scenario: Custom registry in opts
- **WHEN** `session_registry: MyRegistry` is provided in opts
- **THEN** `MyRegistry` is used to start the session

### Requirement: Initiator mode only

The public API MUST support only the `:initiator` mode (buy-side). There is no support for acceptor mode (sell-side).

#### Scenario: Mode is always initiator
- **WHEN** any session is started via the public API
- **THEN** the SessionConfig has `mode: :initiator`

### Requirement: send_message! signature

The system MUST expose `ExFix.send_message!/2` with the following signature:

```elixir
send_message!(out_message, session_name)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `out_message` | `OutMessage.t()` | Message built with `OutMessage.new/1` and `OutMessage.set_field/3` |
| `session_name` | `Session.session_name()` | Target session name |

#### Scenario: Successful send
- **WHEN** `send_message!(msg, "sim")` is invoked with an active session
- **THEN** it returns `:ok` and the message is queued for sending

### Requirement: Session resolution by name

The function MUST resolve the session by its registered name and delegate to the corresponding `SessionWorker` via `GenServer.call`. If the session does not exist or is not active, it MUST propagate the exception (bang `!` behavior).

#### Scenario: Active session
- **WHEN** a message is sent to a registered and active session
- **THEN** the message is delegated to the corresponding SessionWorker

#### Scenario: Non-existent session
- **WHEN** a message is sent to a session that does not exist
- **THEN** an exception is raised

### Requirement: Synchronous send

`send_message!/2` MUST be a synchronous operation — it returns `:ok` when the message has been queued for sending, or raises an exception if it fails. The caller can use this to detect crashed sessions.

#### Scenario: Caller receives confirmation
- **WHEN** `send_message!/2` is invoked and the worker processes the request
- **THEN** the function returns `:ok` synchronously

### Requirement: stop_session signature

The system MUST expose `ExFix.stop_session/2` with the following signature:

```elixir
stop_session(session_name, registry \\ nil)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `session_name` | `Session.session_name()` | Name of the session to stop |
| `registry` | module or nil | Custom registry; nil uses the default |

#### Scenario: Stop with default registry
- **WHEN** `stop_session("sim")` is invoked
- **THEN** the session is stopped using the default registry

#### Scenario: Stop with custom registry
- **WHEN** `stop_session("sim", MyRegistry)` is invoked
- **THEN** the session is stopped using `MyRegistry`

### Requirement: Stop delegation to registry

The function MUST delegate stopping to the `SessionRegistry`:

- If `registry` is nil, it uses the default registry (same logic as `start_session_initiator`)
- If a module is provided, it uses it directly

It invokes `session_registry.stop_session(session_name)`.

#### Scenario: Correct delegation
- **WHEN** `stop_session("sim")` is invoked
- **THEN** `registry.stop_session("sim")` is called on the corresponding registry

### Requirement: Configurable default dictionary

The module MUST read the default dictionary from `Application.compile_env(:ex_fix, :default_dictionary)`, with fallback to `ExFix.DefaultDictionary`. This is resolved at compile time.

#### Scenario: Dictionary not configured
- **WHEN** `:default_dictionary` is not configured in the application
- **THEN** `ExFix.DefaultDictionary` is used

### Requirement: Configurable default registry

The module MUST read the default registry from `Application.compile_env(:ex_fix, :session_registry)`, with fallback to `ExFix.DefaultSessionRegistry`. This is resolved at compile time.

#### Scenario: Registry not configured
- **WHEN** `:session_registry` is not configured in the application
- **THEN** `ExFix.DefaultSessionRegistry` is used
