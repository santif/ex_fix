# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

ExFix is an Elixir implementation of the FIX (Financial Information eXchange) Session Protocol FIXT.1.1. It only supports session initiator mode (buy-side). Published on hex.pm (v0.2.9), Apache 2.0 license. Zero runtime dependencies — only Erlang/OTP primitives.

---

## How You Must Work: OpenSpec-Driven Development

This project uses **OpenSpec** for spec-driven development. All code changes — features, refactors, and non-trivial fixes — must flow through `openspec/`. Treat `openspec/` as the single source of truth for requirements, active changes, and implementation plans.

**You must never make code changes directly from chat.** If a user asks to "just edit the code" or "quickly patch this", refuse and guide them into the proper OpenSpec flow.

### Workflow

1. **Always read `openspec/config.yaml` before starting work** — it contains project context, conventions, and rules for proposals/specs/design/tasks.
2. **For any requested change:**
   - If an appropriate change exists under `openspec/changes/`, work only through its `proposal.md` and `tasks.md`.
   - If no change exists, create one using `/opsx:propose` before touching any code.
3. **The OpenSpec loop:**
   - **Propose** → Capture *what* and *why* in `openspec/changes/<change-id>/proposal.md`
   - **Tasks** → Break implementation into steps in `tasks.md`
   - **Apply** → Implement tasks via `/opsx:apply`, marking complete as you go
   - **Archive** → Once verified, archive via `/opsx:archive`

### Commands

- `/opsx:propose` — Create a new change with proposal and tasks
- `/opsx:apply` — Implement tasks from an existing change's `tasks.md`
- `/opsx:explore` — Think through ideas, investigate problems, clarify requirements
- `/opsx:archive` — Archive a completed change

### Rules (Mandatory)

- **No bypassing OpenSpec.** You cannot apply non-trivial code changes without a change folder under `openspec/changes/`.
- **Specs over chat.** If chat instructions contradict `openspec/specs/` or an active change, follow the written specs and highlight the discrepancy.
- **Prefer minimal change.** Change only what the tasks require; no opportunistic refactors unless explicitly included.
- **Backwards compatibility.** This is a library on hex.pm — consider impact on existing behaviours (`SessionHandler`, `Dictionary`, `SessionRegistry`).
- **Specs stay in sync.** Never silently diverge from specs. If you need to deviate, update the spec/proposal first.

### Schema: Lightweight

This project uses the `lightweight` schema for fixes, refactors, and minor improvements: `proposal.md` → `tasks.md` (no design document). Each task should be completable in < 2 hours, include test tasks, and specify affected files.

---

## Build & Test Commands

```bash
mix compile              # Compile
mix test                 # Run all tests
mix test test/session_test.exs                    # Single test file
mix test test/session_test.exs:42                 # Single test by line
mix test --only tag_name                          # Tests by tag
mix credo                # Lint
mix dialyzer             # Static type checking (slow first run)
mix docs                 # Generate ExDoc documentation
mix bench -d 2           # Run benchmarks
```

Requires Elixir ~> 1.18, Erlang/OTP 27.

---

## Architecture

### Supervision Tree

```
ExFix.Application (Supervisor, rest_for_one)
├── ExFix.DefaultSessionRegistry (GenServer, ETS-backed)
└── ExFix.SessionSup (DynamicSupervisor)
    └── ExFix.SessionWorker (GenServer, one per session)
```

### Key Modules & Layers

**Public API** — `ExFix` (`lib/ex_fix.ex`): Three functions: `start_session_initiator/5`, `send_message!/2`, `stop_session/2`. Builds a `SessionConfig` and delegates to the registry.

**Session Protocol FSM** — `ExFix.Session` (`lib/ex_fix/session.ex`): Pure functional state machine. Takes a `%Session{}` struct + input, returns `{result_tag, messages_to_send, updated_session}` where `result_tag` is `:ok | :continue | :resend | :logout | :stop`. Handles all FIX session-level messages (Logon, Heartbeat, TestRequest, ResendRequest, Reject, SequenceReset, Logout). **No side effects** — the caller (`SessionWorker`) handles I/O.

**Session Worker** — `ExFix.SessionWorker` (`lib/ex_fix/session_worker.ex`): GenServer that owns the TCP/SSL socket. Receives network data, feeds it to `Session`, sends outgoing messages, manages heartbeat timers. Registered as `:"ex_fix_session_#{name}"`.

**Session Registry** — `ExFix.SessionRegistry` (behaviour) / `ExFix.DefaultSessionRegistry` (default impl): Tracks session lifecycle status via ETS. Monitors session worker processes for crash detection and reconnection. The registry module is injectable per-session.

**Parser** — `ExFix.Parser` (`lib/ex_fix/parser.ex`): Two-phase parsing. `parse1/4` extracts frame, validates checksum/length, identifies the "subject" field. `parse2/1` completes field parsing. This split lets the network process quickly route messages by subject to dedicated worker processes.

**Messages** — `InMessage` (received, fields as `[{tag_string, value_string}]`) and `OutMessage` (outgoing, built with `new/1` + `set_field/3`). Fields are FIX tag numbers as strings (e.g., `"35"` for MsgType, `"49"` for SenderCompID).

### Session Handler Behaviour

Users implement `ExFix.SessionHandler` with 4 callbacks: `on_logon/2`, `on_logout/2`, `on_app_message/4`, `on_session_message/4`. The `env` parameter is a user-provided map from config. `on_app_message` receives partially-parsed messages (`complete: false`) — call `Parser.parse2(msg)` to finish parsing.

### Session Status Types

Two distinct status domains:
- **Protocol status** (`Session.session_status`): `:offline | :connecting | :online | :disconnecting | :disconnected` — used within `Session` FSM
- **Registry status** (`Session.registry_status`): adds `:connected | :reconnecting` — used by `DefaultSessionRegistry` and `SessionWorker.terminate/2`

### Data Flow (Incoming)

```
Socket → SessionWorker.handle_info(:tcp/:ssl) → handle_data/2
  → Session.handle_incoming_data/2 → Parser.parse1/4
    → Session.process_valid_message/4 → Session.process_incoming_message/5
      → returns {result_tag, msgs_to_send, session}
  → SessionWorker sends msgs via transport, updates state
```

### App Config

Config keys in `config/config.exs` (compile-time via `Application.compile_env`):
- `warning_on_garbled_messages` (boolean)
- `session_registry` (module)
- `default_dictionary` (module)
- `logout_timeout` (ms, default 2000, set to 20 in test)
- `rx_heartbeat_tolerance` (float multiplier, default 1.2)

---

## Test Infrastructure

Tests use mock transport (`TestTransport`), test handler (`FixDummySessionHandler`), and test registry (`TestSessionRegistry`) defined in `test/test_helper.exs`. The mock transport simulates socket communication via process messages. Helper `msg/1` converts pipe-delimited strings to FIX binary (e.g., `msg("8=FIXT.1.1|9=5|...")`).

---

## Conventions

- FIX field tags are always strings, not integers (e.g., `"35"` not `35`)
- Fields stored as keyword-like tuples: `{tag_string, value_string}`
- Module attributes for FIX constants: `@msg_type_logon "A"`, `@field_text "58"`
- Performance-critical functions use `@compile {:inline, ...}`
- ETS used for out-queue (ordered_set, private per session) and registry (public, named)
- Extension via behaviours (`SessionHandler`, `Dictionary`, `SessionRegistry`), not protocols
- Pre-existing compiler warnings in `session.ex` (struct update typing) are not regressions
- Code and commit language: English
