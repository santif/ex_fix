# Session Registry

## Purpose

FIX session state tracking system with support for coordinated reconnection.

## Requirements

### Requirement: SessionRegistry behaviour

There MUST exist a `SessionRegistry` behaviour with these callbacks:

**Public API:**
- `get_session_status(session_name)` — returns the current session state
- `start_session(session_name, config)` — registers and starts a FIX session
- `stop_session(session_name)` — stops and deregisters a session

**Internal API (called from session workers):**
- `session_on_init(session_name)` — queries before connecting, returns `:ok`, `:wait_to_reconnect`, or `{:error, reason}`
- `session_update_status(session_name, status)` — updates the state in real time

#### Scenario: Start and query state
- **WHEN** `start_session("sim", config)` is invoked and then `get_session_status("sim")`
- **THEN** the current session state is returned

### Requirement: Extensible implementation

The system MUST allow custom registry implementations (e.g.: based on distributed ETS, Redis, etc.) via the behaviour.

#### Scenario: Custom registry
- **WHEN** a module that fulfills the `SessionRegistry` behaviour is implemented
- **THEN** it can be used as a registry by configuring `:session_registry`

### Requirement: Tracked states

The registry MUST track these states:

| State | Meaning |
|-------|---------|
| `:connecting` | Session registered, attempting logon |
| `:connected` | Logon successful, receiving data |
| `:disconnecting` | Close in progress |
| `:disconnected` | Disconnected normally, no reconnection |
| `:reconnecting` | Connection lost, pending reconnection |

> **Note:** These are **lifecycle states** tracked by the registry for process management, distinct from the session's internal protocol states (`:offline`, `:connecting`, `:online`, `:disconnecting`) defined in the session-management spec. The two state models serve different purposes: the registry tracks process lifecycle across restarts, while the session FSM tracks protocol state within a single connection.

#### Scenario: State transition
- **WHEN** a session is started and completes the logon
- **THEN** the state transitions from `:connecting` to `:connected`

### Requirement: State transitions

Transitions MUST follow this flow:

```
start_session() → :connecting
                      ↓
              successful logon → :connected
                                     ↓
                      graceful close   → :disconnecting → :disconnected
                      error/close      → :reconnecting
```

The default state for unregistered sessions MUST be `:disconnected`.

#### Scenario: Unregistered session
- **WHEN** the state of an unregistered session is queried
- **THEN** `:disconnected` is returned

#### Scenario: Connection error
- **WHEN** a connected session loses its connection due to an error
- **THEN** the state transitions to `:reconnecting`

### Requirement: ETS storage

The default implementation MUST use a public, named ETS table (`:ex_fix_registry`) to store `{session_name, status}` pairs.

#### Scenario: Data in ETS
- **WHEN** a session is started with the default registry
- **THEN** the state is stored in the `:ex_fix_registry` ETS table

### Requirement: Process monitoring

The default implementation MUST monitor SessionWorker processes and update states automatically:

- Normal termination (`:normal`) → `:disconnected`, remove from registry
- Abnormal termination (`:econnrefused`, `:closed`, etc.) → `:reconnecting`

#### Scenario: Normal worker termination
- **WHEN** a SessionWorker terminates with reason `:normal`
- **THEN** the state changes to `:disconnected` and it is removed from the registry

#### Scenario: Abnormal worker termination
- **WHEN** a SessionWorker terminates with reason `:econnrefused`
- **THEN** the state changes to `:reconnecting`

### Requirement: Startup control via session_on_init

When a SessionWorker starts, it MUST query the registry via `session_on_init/1`:

- If the state is `:connecting` → return `:ok` (immediate start)
- If the state is `:disconnecting` → return `{:error, :disconnected}` (reject)
- In any other state → return `:wait_to_reconnect` (wait for `reconnect_interval`)

This MUST prevent concurrent or premature reconnection attempts.

#### Scenario: Immediate start
- **WHEN** the worker queries `session_on_init` and the state is `:connecting`
- **THEN** `:ok` is returned

#### Scenario: Reconnection with wait
- **WHEN** the worker queries `session_on_init` and the state is `:reconnecting`
- **THEN** `:wait_to_reconnect` is returned

#### Scenario: Rejected start
- **WHEN** the worker queries `session_on_init` and the state is `:disconnecting`
- **THEN** `{:error, :disconnected}` is returned

### Requirement: DynamicSupervisor

The system MUST use a `DynamicSupervisor` (SessionSup) with `:one_for_one` strategy to supervise SessionWorkers. Workers MUST be `:transient` (only restarted on abnormal termination).

#### Scenario: Worker supervision
- **WHEN** a session is started
- **THEN** the SessionWorker is added to the DynamicSupervisor as a `:transient` child

### Requirement: Process naming

Each SessionWorker MUST register as a named process with the format `:ex_fix_session_{name}` to allow direct lookups.

#### Scenario: Named process
- **WHEN** a session with name "sim" is started
- **THEN** the process registers as `:ex_fix_session_sim`

### Requirement: Cleanup on stop

When stopping a session, the registry MUST:

- Remove the entry from storage
- Stop the SessionWorker gracefully
- Handle the case where the worker no longer exists without errors

#### Scenario: Stop of active session
- **WHEN** `stop_session("sim")` is invoked with an active session
- **THEN** it is removed from the registry and the worker is stopped

#### Scenario: Stop of already stopped session
- **WHEN** `stop_session("sim")` is invoked and the worker no longer exists
- **THEN** it is removed from the registry without errors
