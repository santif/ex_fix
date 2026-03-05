## Context

ExFix surfaces session errors only via `Logger`. Applications have no programmatic way to react to transport failures, garbled messages, or heartbeat timeouts. The `SessionHandler` behaviour has 4 callbacks (`on_logon`, `on_logout`, `on_app_message`, `on_session_message`) — none for errors.

Current error sites:
- `SessionWorker.connect_and_send_logon/2` — `Logger.error` on socket connect failure
- `SessionWorker.do_send_messages/3` — `transport.send` result ignored
- `Session.process_invalid_message/3` — garbled messages logged (if config enabled)
- `Session.handle_timeout/2` — heartbeat timeout triggers logout but no handler notification

## Goals / Non-Goals

**Goals:**
- Add an optional `on_error/4` callback to `SessionHandler`
- Invoke it at all error sites — from `Session` for protocol-level errors, from `SessionWorker` for transport-level errors
- Maintain full backwards compatibility — existing handlers compile and work without changes

**Non-Goals:**
- Error recovery actions (e.g., auto-reconnect based on callback return) — future work
- Replacing `Logger` calls — `on_error` complements logging, doesn't replace it
- Surfacing application-level message errors (business logic) — only session/transport errors

## Decisions

### 1. Optional callback via `@optional_callbacks`

**Choice**: Use `@optional_callbacks [on_error: 4]` on the `SessionHandler` behaviour.

**Alternatives considered**:
- Separate `ErrorHandler` behaviour — adds configuration complexity and a new concept for users. The error is tightly coupled to the session, so extending the existing behaviour is simpler.
- Default implementation via `__using__` macro — ExFix doesn't use `__using__` anywhere, introducing it for one callback would be inconsistent.

**Rationale**: `@optional_callbacks` is idiomatic Elixir, zero breaking changes, and the caller checks with `function_exported?/3`.

### 2. Call site placement: Session for protocol errors, SessionWorker for transport errors

**Choice**: `on_error/4` is called from the same layer where the error originates:
- **`Session`** calls `on_error` for: `:garbled_message`, `:heartbeat_timeout`
- **`SessionWorker`** calls `on_error` for: `:connect_error`, `:transport_error`

```
┌──────────────────┐         ┌────────-─────────┐        ┌──────────────────┐
│     Session      │         │  SessionWorker   │        │  SessionHandler  │
│  (state machine) │         │  (GenServer)     │        │  (user callback) │
│                  │─calls──▶│                  │─calls─▶│ on_error/4       │
│ on_error for:    │         │ on_error for:    │        │                  │
│ :garbled_message │         │ :connect_error   │        └──────────────────┘
│ :heartbeat_timeout         │ :transport_error │
└──────────────────┘         └─────────────-────┘
```

**Rationale**: `Session` already calls handler callbacks directly (`on_session_message` in 8 places, `on_app_message` in 2 places, `on_logon` once, `on_logout` 3 times). It is not a pure FSM — it performs side effects via handler callbacks as part of its message processing. Having `Session` call `on_error` for protocol-level errors follows the established pattern exactly.

Transport errors (`connect_error`, `transport_error`) genuinely originate in `SessionWorker` (socket operations), so they are notified from there.

### 3. Error type atoms + details map

**Choice**: `on_error(session_name, error_type, details, env)` where:
- `error_type` — atom: `:connect_error | :transport_error | :garbled_message | :heartbeat_timeout`
- `details` — map with error-specific context:

| Error Type | Details Map |
|---|---|
| `:connect_error` | `%{reason: term()}` |
| `:transport_error` | `%{reason: term()}` |
| `:garbled_message` | `%{raw_message: binary()}` |
| `:heartbeat_timeout` | `%{}` |

**Alternatives considered**:
- Struct per error type — over-engineering for 4 error types, harder to extend
- Tuple `{error_type, reason}` — less extensible than a map for future fields

### 4. Garbled message notification — direct call from Session

`Session.process_invalid_message/3` handles garbled messages (`:garbled` error reason). It will call `on_error` directly, guarded by `function_exported?/3`, same as how it calls `on_session_message` elsewhere. The `SessionConfig` already contains `session_handler` and `env`, so no new plumbing is needed.

### 5. Heartbeat timeout notification — direct call from Session

`Session.handle_timeout/2` already distinguishes first vs. second RX timeout via `last_test_req_id_sent`:
- First timeout (`last_test_req_id_sent: nil`) → sends TestRequest, returns `{:ok, ...}`
- Second timeout (`last_test_req_id_sent` set) → sends Logout, returns `{:logout, ...}`

The second clause will call `on_error` with `:heartbeat_timeout` before returning `{:logout, ...}`.

### 6. `function_exported?/3` — call each time, no caching

**Choice**: Call `function_exported?(session_handler, :on_error, 4)` at each error site without caching.

**Rationale**: `function_exported?/3` is a BIF that performs a fast module table lookup. Error paths are infrequent (not the hot path), so the overhead is negligible. Caching in `SessionConfig` would add a struct field and constructor change for zero measurable benefit. Both `Session` and `SessionWorker` have access to the handler module via `SessionConfig`.

### 7. `:invalid_message` excluded

The proposal originally listed `:invalid_message` for validation failures (CompID mismatch, SendingTime accuracy, BeginString error). These are excluded because they are already surfaced to the handler via existing callbacks:
- CompID mismatch → `on_logout` + Reject message visible in `on_session_message`
- SendingTime accuracy → Reject message visible in `on_session_message`
- BeginString error → Logout message sent (handler notified via normal flow)

Adding a redundant `:invalid_message` notification would create confusing double-notification. If needed in the future, it can be added as a separate change.

## Risks / Trade-offs

- **[Performance]** `function_exported?/3` check on every error → Mitigation: errors are infrequent (not hot path), and the BIF is fast.
- **[Handler exceptions]** User's `on_error/4` could raise → Mitigation: wrap calls in `try/rescue` with Logger fallback. Same risk exists for other callbacks but hasn't been an issue.
- **[Backwards compat]** New optional callback is non-breaking. Existing code continues to work unchanged.
