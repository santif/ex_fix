## 1. SessionHandler behaviour

- [x] 1.1 Add `on_error/4` callback and `@optional_callbacks` declaration to `ExFix.SessionHandler` (`lib/ex_fix/session_handler.ex`). Include `@doc` and `@callback` spec.

## 2. Session — garbled message notification

- [x] 2.1 In `Session.process_invalid_message/3` (garbled clause, `lib/ex_fix/session.ex`), add a guarded call to `session_handler.on_error(session_name, :garbled_message, %{raw_message: msg.original_fix_msg}, env)`. Guard with `function_exported?(session_handler, :on_error, 4)`. Wrap in `try/rescue` with `Logger.error` fallback.

## 3. Session — heartbeat timeout notification

- [x] 3.1 In `Session.handle_timeout/2` second RX clause (`last_test_req_id_sent` is set, `lib/ex_fix/session.ex`), add a guarded call to `session_handler.on_error(session_name, :heartbeat_timeout, %{}, env)` before returning `{:logout, ...}`. Guard and rescue same as 2.1.

## 4. SessionWorker — transport error notifications

- [x] 4.1 Add private `maybe_notify_error/4` helper to `SessionWorker` (`lib/ex_fix/session_worker.ex`) that checks `function_exported?(session_handler, :on_error, 4)` and calls handler's `on_error/4` wrapped in `try/rescue`.
- [x] 4.2 Call `maybe_notify_error` with `:connect_error` in `connect_and_send_logon/2` on `{:error, reason}` (`lib/ex_fix/session_worker.ex`).
- [x] 4.3 Check `transport.send` return value in `do_send_messages/3` and call `maybe_notify_error` with `:transport_error` on `{:error, reason}` (`lib/ex_fix/session_worker.ex`).

## 5. Test helpers

- [x] 5.1 Add `on_error/4` implementation to `FixDummySessionHandler` in `test/test_helper.exs` that sends `{:on_error, error_type, details}` to the test process (via `env.test_pid` or similar).
- [x] 5.2 Create a second test handler `FixDummySessionHandlerNoError` without `on_error/4` to test the optional callback path (`test/test_helper.exs`).
- [x] 5.3 Extend `TestTransport` with a configurable error mode (implemented as separate FailConnectTransport/FailSendTransport modules in session_worker_test.exs instead, as process dictionary doesn't work cross-process) (e.g., `send/2` returns `{:error, reason}` when a flag is set via process dictionary or agent) to enable testing `:transport_error` dispatch.

## 6. Tests

- [x] 6.1 Test that a handler implementing `on_error/4` receives `:garbled_message` when a garbled FIX message is processed (`test/session_test.exs`).
- [x] 6.2 Test that a handler NOT implementing `on_error/4` does not crash on garbled messages (`test/session_test.exs`).
- [x] 6.3 Test that `:connect_error` is dispatched when `transport.connect` fails (`test/session_worker_test.exs`).
- [x] 6.4 Test that `:transport_error` is dispatched when `transport.send` returns an error (`test/session_worker_test.exs`).
- [x] 6.5 Test that `:heartbeat_timeout` is dispatched on second consecutive RX timeout (`test/session_test.exs`).
- [x] 6.6 Test that `on_error/4` exceptions are rescued and logged without crashing the session (`test/session_test.exs` or `test/session_worker_test.exs`).
- [x] 6.7 Run `mix credo` and `mix dialyzer` to verify no new warnings.
