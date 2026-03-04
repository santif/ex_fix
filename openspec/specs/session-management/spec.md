# FIX Session Management

## Purpose

Implementation of the FIXT.1.1 session protocol as initiator (buy-side).

## Requirements

### Requirement: Session states

The session MUST transition between four states:

- **offline** — initial state, no connection
- **connecting** — Logon sent, awaiting response
- **online** — active session, ready for application messages
- **disconnecting** — Logout initiated or received, awaiting close

Main flow: `offline → connecting → online → disconnecting → offline`

> **Note:** These are the **internal protocol states** of the `Session` state machine. The `SessionRegistry` tracks a separate set of **lifecycle states** (`:connecting`, `:connected`, `:disconnecting`, `:disconnected`, `:reconnecting`) — see the session-registry spec. The two state models serve different purposes: protocol FSM vs process lifecycle tracking.

#### Scenario: Main state flow
- **WHEN** a session is started and the logon is successful
- **THEN** the session transitions `offline → connecting → online`

#### Scenario: Graceful close
- **WHEN** closing of an online session is initiated
- **THEN** the session transitions `online → disconnecting → offline`

### Requirement: Session startup

On startup, the system MUST connect to the configured host/port and send a Logon message with:

- EncryptMethod (tag 98)
- HeartBtInt (tag 108)
- ResetSeqNumFlag (tag 141), if `reset_on_logon: true`
- Username (tag 553) and Password (tag 554), if configured
- DefaultApplVerID (tag 1137)

The session transitions to `:connecting` until the response Logon is received.

#### Scenario: Logon with credentials
- **WHEN** a session is started with `username` and `password` configured
- **THEN** the Logon message includes tags 553 and 554

#### Scenario: Logon without credentials
- **WHEN** a session is started without `username` or `password`
- **THEN** the Logon message does not include tags 553 and 554

#### Scenario: Logon with sequence reset
- **WHEN** a session is started with `reset_on_logon: true`
- **THEN** the Logon message includes ResetSeqNumFlag (tag 141)

### Requirement: Session close

The system MUST support graceful close by sending Logout and awaiting a response.
If there is no response within 2 seconds, it MUST force-close the connection.

Upon receiving an unsolicited Logout, it MUST respond with Logout and close.

#### Scenario: Graceful close with response
- **WHEN** Logout is sent and the counterparty responds with Logout
- **THEN** the connection closes normally

#### Scenario: Graceful close without response
- **WHEN** Logout is sent and there is no response within 2 seconds
- **THEN** the connection is force-closed

#### Scenario: Unsolicited Logout
- **WHEN** a Logout is received without having initiated one
- **THEN** a Logout is sent in response and the connection is closed

### Requirement: Supported message types

The system MUST process these messages at the session level:

| Type | Code | Behavior |
|------|------|----------|
| Logon | A | Establish session, exchange parameters |
| Heartbeat | 0 | Keep-alive, response to TestRequest |
| TestRequest | 1 | Verify connectivity, requires Heartbeat response |
| ResendRequest | 2 | Request retransmission of lost messages |
| Reject | 3 | Session-level rejection |
| SequenceReset | 4 | Adjust sequence numbers (with/without gap-fill) |
| Logout | 5 | Session termination |

Any other message type MUST be routed to the `on_app_message` callback of the SessionHandler.

#### Scenario: Known session message
- **WHEN** a message with type A, 0, 1, 2, 3, 4, or 5 is received
- **THEN** it is processed at the session level

#### Scenario: Application message
- **WHEN** a message with a type other than the session types is received (e.g.: "D", "8")
- **THEN** it is routed to the `on_app_message` callback

### Requirement: Automatic TestRequest response

Upon receiving a TestRequest, the system MUST automatically respond with a Heartbeat containing the same TestReqID (tag 112).

#### Scenario: TestRequest received
- **WHEN** a TestRequest with TestReqID="ABC" is received
- **THEN** a Heartbeat containing TestReqID="ABC" is sent in response

### Requirement: ResendRequest processing

Upon receiving a ResendRequest, the system MUST:

- Retransmit application messages from the requested range with PossDupFlag="Y"
- Replace administrative messages (Logon, Heartbeat, TestRequest, etc.) with SequenceReset-GapFill
- Preserve the OrigSendingTime of retransmitted messages

#### Scenario: ResendRequest for application messages
- **WHEN** a ResendRequest is received for a range containing application messages
- **THEN** they are retransmitted with PossDupFlag="Y" and preserved OrigSendingTime

#### Scenario: ResendRequest for administrative messages
- **WHEN** a ResendRequest is received for a range containing administrative messages
- **THEN** they are replaced with SequenceReset-GapFill

### Requirement: SequenceReset

The system MUST support two variants:

- **GapFill** (GapFillFlag="Y"): adjusts the expected sequence number without resetting the session
- **Reset** (GapFillFlag="N" or absent): resets the expected sequence number to NewSeqNo

MUST reject attempts to decrease the sequence number.

#### Scenario: GapFill
- **WHEN** a SequenceReset with GapFillFlag="Y" and NewSeqNo greater than expected is received
- **THEN** the expected sequence number is adjusted to NewSeqNo

#### Scenario: Reset
- **WHEN** a SequenceReset with GapFillFlag="N" and NewSeqNo greater than expected is received
- **THEN** the expected sequence number is reset to NewSeqNo

#### Scenario: Attempt to decrease sequence
- **WHEN** a SequenceReset with NewSeqNo less than expected is received
- **THEN** the message is rejected

### Requirement: Sequence tracking

The system MUST maintain independent counters for incoming (`in_lastseq`) and outgoing (`out_lastseq`) messages, incrementing them with each processed/sent message.

#### Scenario: Incoming sequence increment
- **WHEN** a valid message is received
- **THEN** `in_lastseq` is incremented by 1

#### Scenario: Outgoing sequence increment
- **WHEN** a message is sent
- **THEN** `out_lastseq` is incremented by 1

### Requirement: Gap detection

If a message arrives with a sequence number greater than expected, the system MUST:

- Queue the message for later processing
- Send a ResendRequest for the missing range

#### Scenario: Gap detected
- **WHEN** sequence 5 is expected and a message with sequence 8 arrives
- **THEN** the message is queued and a ResendRequest is sent for range 5-7

### Requirement: Low sequence without PossDupFlag

If a message arrives with a sequence number less than expected and without PossDupFlag, the system MUST send Logout with reason "MsgSeqNum too low" and disconnect.

#### Scenario: Low sequence without PossDup
- **WHEN** sequence 10 is expected and a message with sequence 5 arrives without PossDupFlag
- **THEN** Logout is sent with reason "MsgSeqNum too low" and the connection is closed

### Requirement: Duplicates

If a message arrives with a sequence number less than expected and PossDupFlag="Y", the system MUST silently ignore it.

#### Scenario: Duplicate with PossDupFlag
- **WHEN** sequence 10 is expected and a message with sequence 5 and PossDupFlag="Y" arrives
- **THEN** the message is ignored without error

### Requirement: Reset on logon

If `reset_on_logon: true`, the system MUST send ResetSeqNumFlag in the Logon to reset both counters at session start.

#### Scenario: Reset enabled
- **WHEN** connecting with `reset_on_logon: true`
- **THEN** the Logon includes ResetSeqNumFlag and both counters are reset

### Requirement: Outgoing heartbeat

The system MUST automatically send a Heartbeat when no message has been sent for `heart_bt_int` seconds. The timer resets with each outgoing message.

#### Scenario: Outgoing heartbeat timeout
- **WHEN** no message is sent for `heart_bt_int` seconds
- **THEN** a Heartbeat is sent automatically

#### Scenario: Timer reset by outgoing message
- **WHEN** an application message is sent
- **THEN** the outgoing heartbeat timer is reset

### Requirement: Incoming heartbeat monitoring

The system MUST monitor message reception with a tolerance of 1.2x the heartbeat interval.

- **First timeout**: send TestRequest and await response
- **Second timeout** (no response to TestRequest): send Logout with reason "Data not received" and disconnect

The timer resets with any incoming message.

#### Scenario: First timeout without data
- **WHEN** no message is received within 1.2x `heart_bt_int` seconds
- **THEN** a TestRequest is sent

#### Scenario: Second timeout without response
- **WHEN** no response to the TestRequest is received within 1.2x `heart_bt_int` seconds
- **THEN** Logout is sent with reason "Data not received" and the connection is closed

### Requirement: Automatic reconnection

The system MUST support automatic reconnection via the OTP supervisor (DynamicSupervisor with `:one_for_one` strategy). Session workers are `:transient` (only restarted on abnormal termination).

#### Scenario: Abnormal disconnection
- **WHEN** a SessionWorker terminates abnormally
- **THEN** the supervisor restarts it automatically

#### Scenario: Normal disconnection
- **WHEN** a SessionWorker terminates normally (e.g.: stop_session)
- **THEN** it is not restarted

### Requirement: Reconnection interval

Before reconnecting, the system MUST wait `reconnect_interval` seconds (default: 15) to avoid overwhelming the server.

#### Scenario: Wait before reconnecting
- **WHEN** a SessionWorker restarts after abnormal disconnection
- **THEN** it waits `reconnect_interval` seconds before attempting reconnection

### Requirement: SendingTime validation

If `validate_sending_time: true`, the system MUST verify that the SendingTime (tag 52) of each incoming message does not differ from the current time by more than `sending_time_tolerance` seconds (default: 120). If it exceeds the tolerance, it MUST send Reject and Logout.

#### Scenario: SendingTime within tolerance
- **WHEN** a message with SendingTime within `sending_time_tolerance` is received
- **THEN** it is processed normally

#### Scenario: SendingTime outside tolerance
- **WHEN** a message with SendingTime differing by more than `sending_time_tolerance` seconds is received
- **THEN** Reject and Logout are sent

#### Scenario: Validation disabled
- **WHEN** `validate_sending_time: false`
- **THEN** SendingTime is not verified

### Requirement: CompID validation

The system MUST verify that SenderCompID and TargetCompID of each message match the configured values (reversed). If they do not match on an application message, it MUST send Reject with reason "CompID problem" and disconnect.

#### Scenario: Correct CompID
- **WHEN** a message with expected SenderCompID and TargetCompID is received
- **THEN** it is processed normally

#### Scenario: Incorrect CompID
- **WHEN** an application message with non-matching CompID is received
- **THEN** Reject is sent with reason "CompID problem" and the connection is closed

### Requirement: PossDup validation

For messages with PossDupFlag="Y", the system MUST verify that:

- OrigSendingTime (tag 122) is present
- OrigSendingTime <= SendingTime

If it fails, it MUST send Reject.

#### Scenario: Valid PossDup
- **WHEN** a message with PossDupFlag="Y", OrigSendingTime present and <= SendingTime is received
- **THEN** it is processed normally

#### Scenario: PossDup without OrigSendingTime
- **WHEN** a message with PossDupFlag="Y" without OrigSendingTime is received
- **THEN** Reject is sent

#### Scenario: OrigSendingTime > SendingTime
- **WHEN** a message with PossDupFlag="Y" and OrigSendingTime > SendingTime is received
- **THEN** Reject is sent

### Requirement: Extensible behaviour

The system MUST expose a `SessionHandler` behaviour with these callbacks:

- `on_logon(session_name, env)` — session established
- `on_logout(session_name, env)` — session terminated
- `on_session_message(session_name, msg_type, msg, env)` — protocol message received
- `on_app_message(session_name, msg_type, msg, env)` — application message received

All callbacks receive the custom `env` defined in the configuration.

#### Scenario: Logon callback
- **WHEN** the session is established successfully
- **THEN** `on_logon(session_name, env)` is invoked

#### Scenario: Application message callback
- **WHEN** an application message is received (e.g.: Execution Report)
- **THEN** `on_app_message(session_name, msg_type, msg, env)` is invoked

### Requirement: Configurable options

Each session MUST be independently configurable with:

| Option | Default | Description |
|--------|---------|-------------|
| `hostname` | "localhost" | Server host |
| `port` | 9876 | Port |
| `transport_mod` | `:gen_tcp` | `:gen_tcp` or `:ssl` |
| `heart_bt_int` | 60 | Heartbeat interval (seconds) |
| `reset_on_logon` | true | Reset sequence on connect |
| `username` / `password` | nil | Optional credentials |
| `validate_incoming_message` | true | Validate checksum/body length |
| `validate_sending_time` | true | Validate SendingTime |
| `sending_time_tolerance` | 120 | Tolerance in seconds |
| `reconnect_interval` | 15 | Seconds between reconnections |
| `log_incoming_msg` | true | Log incoming messages |
| `log_outgoing_msg` | true | Log outgoing messages |
| `time_service` | nil | nil (UTC now), fixed DateTime, or {m, f, a} |
| `max_output_buf_count` | 1000 | Size of sent messages buffer |
| `env` | %{} | Custom map passed to callbacks |
| `default_applverid` | `"9"` | DefaultApplVerID (tag 1137) sent in Logon |
| `logon_encrypt_method` | `"0"` | EncryptMethod (tag 98) sent in Logon |
| `dictionary` | `ExFix.DefaultDictionary` | Dictionary module for message routing |
| `transport_options` | `[]` | Extra options passed to transport `connect/3` |

#### Scenario: Default configuration
- **WHEN** a session is started without options
- **THEN** all default values from the table are used

#### Scenario: Partial override
- **WHEN** a session is started with `heart_bt_int: 30`
- **THEN** 30 is used for heartbeat and defaults for the rest
