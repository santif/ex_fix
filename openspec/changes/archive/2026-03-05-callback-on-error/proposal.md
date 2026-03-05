## Why

Applications using ExFix have no programmatic way to react to session-level errors. Connection failures, garbled messages, transport send errors, and heartbeat timeouts are logged via `Logger` but never surfaced to the `SessionHandler` implementation. In financial trading systems, the ability to react to errors (e.g., switch venue, alert operations, adjust order routing) is critical.

## What Changes

- Add an `on_error/4` optional callback to the `ExFix.SessionHandler` behaviour.
- Invoke the callback when session-level errors occur — from `Session` for protocol errors, from `SessionWorker` for transport errors.
- The callback is optional via `@optional_callbacks` — existing handler implementations continue to work without changes.

Error types to surface:
- `:connect_error` — TCP/SSL connection failures
- `:transport_error` — TCP/SSL send failures
- `:garbled_message` — messages that fail checksum or body-length validation
- `:heartbeat_timeout` — counterparty heartbeat not received within tolerance

Note: `:invalid_message` (CompID mismatch, SendingTime accuracy, BeginString error) was considered but excluded. These validation failures are already surfaced to the handler via existing callbacks (`on_session_message` receives the Reject messages, `on_logout` is called for CompID/BeginString errors). Adding a separate `:invalid_message` notification would create redundant double-notification.

## Capabilities

### New Capabilities
- `error-callback`: Optional `on_error/4` callback on `SessionHandler` behaviour for programmatic error notification

### Modified Capabilities
- `transport`: Add `on_error/4` invocation for `:connect_error` and `:transport_error` at transport error sites in `SessionWorker`

## Impact

- **`ExFix.SessionHandler`** — new optional callback added to the behaviour. Non-breaking: existing implementations compile without changes.
- **`ExFix.Session`** — calls `on_error/4` for `:garbled_message` and `:heartbeat_timeout` (follows existing pattern of calling handler callbacks directly).
- **`ExFix.SessionWorker`** — calls `on_error/4` for `:connect_error` and `:transport_error` at transport error sites. Must check if the handler implements the callback before invoking.
- **FIX protocol conformance** — no impact. This is an observability addition, not a protocol change.
- **No new dependencies** — uses only existing OTP primitives.
