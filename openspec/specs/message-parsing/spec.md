# FIX Message Parsing and Serialization

## Purpose

Two-phase parsing system and serialization of FIX protocol messages (FIXT.1.1).

## Requirements

### Requirement: Phase 1 parse (header extraction)

Phase 1 (`parse1`) MUST extract from the binary message:

- BeginString (tag 8) — MUST be exactly `FIXT.1.1`
- BodyLength (tag 9) — body size in bytes
- Checksum (tag 10) — modulo 256 sum of all preceding bytes
- MsgType (tag 35) — message type
- MsgSeqNum (tag 34) — sequence number
- PossDupFlag (tag 43) — possible duplicate flag
- Subject fields defined by the Dictionary (if applicable)

Phase 1 MUST stop once the headers and subject fields have been extracted, leaving the rest of the message unparsed in `rest_msg`.

#### Scenario: Successful phase 1 parse
- **WHEN** `parse1` is invoked with a valid binary FIX message
- **THEN** headers and subject fields are extracted, leaving the rest in `rest_msg`

### Requirement: Phase 2 parse (complete parsing)

Phase 2 (`parse2`) MUST complete the parsing of all remaining fields in the message. If the message is already complete (phase 1 parsed everything), it MUST be idempotent.

#### Scenario: Phase 2 completes remaining fields
- **WHEN** `parse2` is invoked on an InMessage with pending `rest_msg`
- **THEN** all remaining fields are parsed and `complete` is set to true

#### Scenario: Phase 2 idempotent
- **WHEN** `parse2` is invoked on an already complete InMessage
- **THEN** the message does not change

### Requirement: Combined parse

There MUST exist a `parse/4` function that chains both phases for complete synchronous parsing.

#### Scenario: Complete parse in a single call
- **WHEN** `parse` is invoked with a binary FIX message
- **THEN** an InMessage with all fields parsed is returned

### Requirement: RawData support (tags 95/96)

If the message contains tag 95 (RawDataLength), the parser MUST:

- Extract the declared length
- Read exactly that number of bytes from tag 96 (RawData)
- Preserve the binary content unmodified (may contain SOH)

If the bytes do not match the declared length, it MUST mark the message as `:garbled`.

#### Scenario: Valid RawData
- **WHEN** a message with tag 95=5 and tag 96 with exactly 5 bytes is parsed
- **THEN** the binary content of tag 96 is preserved

#### Scenario: RawData with incorrect length
- **WHEN** a message with tag 95 whose length does not match tag 96 is parsed
- **THEN** the message is marked as `:garbled`

### Requirement: BeginString validation

The parser MUST verify that BeginString is exactly `FIXT.1.1`. If it does not match, it MUST mark the message with `error_reason: :begin_string_error`.

#### Scenario: Correct BeginString
- **WHEN** a message with BeginString="FIXT.1.1" is parsed
- **THEN** it is processed normally

#### Scenario: Incorrect BeginString
- **WHEN** a message with BeginString other than "FIXT.1.1" is parsed
- **THEN** it is marked with `error_reason: :begin_string_error`

### Requirement: Checksum validation

If validation is enabled, the parser MUST:

- Calculate the modulo 256 sum of all bytes preceding the checksum field
- Compare with the value received in tag 10 (3 digits)

If they do not match, it MUST mark the message as `:garbled`.

#### Scenario: Correct checksum
- **WHEN** a message with a checksum matching the calculation is parsed
- **THEN** it is processed normally

#### Scenario: Incorrect checksum
- **WHEN** a message with a checksum that does not match is parsed
- **THEN** it is marked as `:garbled`

### Requirement: BodyLength validation

The parser MUST verify that the value of tag 9 matches the actual body size of the message. If it does not match, it MUST mark it as `:garbled`.

#### Scenario: Correct BodyLength
- **WHEN** tag 9 matches the actual body size
- **THEN** it is processed normally

#### Scenario: Incorrect BodyLength
- **WHEN** tag 9 does not match the actual body size
- **THEN** it is marked as `:garbled`

### Requirement: Sequence number validation

The parser MUST validate the sequence number if an `expected_seqnum` is provided:

- If it matches: process normally
- If greater than expected: mark with `error_reason: :unexpected_seqnum` (the message is still parsed so it can be queued)
- If less: leave it to the session layer handling

#### Scenario: Expected sequence
- **WHEN** a message with a sequence number equal to the expected one is parsed
- **THEN** it is processed normally

#### Scenario: Sequence greater than expected
- **WHEN** a message with a sequence number greater than expected is parsed
- **THEN** it is marked with `error_reason: :unexpected_seqnum` but the content is still parsed

### Requirement: Configurable validation

Checksum and body length validation MUST be disableable via `validate_incoming_message: false`.

#### Scenario: Validation disabled
- **WHEN** parsing with `validate_incoming_message: false`
- **THEN** checksum and body length are not verified

### Requirement: InMessage structure

A parsed incoming message MUST contain:

| Field | Type | Description |
|-------|------|-------------|
| `valid` | boolean | true if structural validation passed |
| `complete` | boolean | true if all fields were parsed |
| `msg_type` | string | Message type (tag 35) |
| `subject` | string, list, or nil | Routing field(s) from the Dictionary |
| `poss_dup` | boolean | PossDupFlag (tag 43) |
| `fields` | [{tag, value}] | Parsed fields as tag-value pairs |
| `seqnum` | integer | Sequence number (tag 34) |
| `rest_msg` | binary | Unparsed portion (between phases) |
| `other_msgs` | binary | Next message in the TCP buffer |
| `original_fix_msg` | binary | Complete original message |
| `error_reason` | atom or nil | `:garbled`, `:begin_string_error`, `:unexpected_seqnum` |

#### Scenario: Valid and complete InMessage
- **WHEN** a valid FIX message is parsed with both phases
- **THEN** `valid` is true, `complete` is true, and all fields are populated

### Requirement: Field access

There MUST exist a `get_field(msg, tag)` function that returns the value of a field by its tag, or nil if it does not exist.

#### Scenario: Existing field
- **WHEN** `get_field(msg, "55")` is invoked
- **THEN** the value of the Symbol field is returned

#### Scenario: Non-existent field
- **WHEN** `get_field(msg, "999")` is invoked for a tag that does not exist in the message
- **THEN** nil is returned

### Requirement: Fluent construction API

There MUST exist an API for building outgoing messages:

```elixir
OutMessage.new("D")
|> OutMessage.set_field("55", "AAPL")
|> OutMessage.set_field("54", "1")
|> OutMessage.set_fields([{"38", 100}, {"40", "2"}])
```

The user only defines the message type and application fields. The header fields (BeginString, BodyLength, MsgSeqNum, SenderCompID, TargetCompID, SendingTime, Checksum) MUST be managed automatically by the serializer.

#### Scenario: Application message construction
- **WHEN** an OutMessage is built with `new("D")` and fields are added
- **THEN** a struct with the message type and user-defined fields is generated

### Requirement: Field order

The serializer MUST generate fields in this order:

1. BeginString (tag 8): `FIXT.1.1`
2. BodyLength (tag 9): calculated
3. MsgType (tag 35)
4. MsgSeqNum (tag 34)
5. SenderCompID (tag 49)
6. PossDupFlag (tag 43) — only on retransmissions
7. SendingTime (tag 52)
8. OrigSendingTime (tag 122) — only on retransmissions
9. TargetCompID (tag 56)
10. Extra header and user body fields
11. Checksum (tag 10): calculated

#### Scenario: Correct order in serialization
- **WHEN** an OutMessage is serialized
- **THEN** header fields appear in the specified order, followed by user fields and the checksum

### Requirement: Automatic checksum and body length calculation

The serializer MUST automatically calculate:

- **BodyLength**: bytes between the end of tag 9 and the start of tag 10
- **Checksum**: modulo 256 sum of all bytes preceding tag 10, formatted as 3 digits with leading zeros

#### Scenario: Automatic calculation
- **WHEN** an OutMessage is serialized
- **THEN** BodyLength and Checksum are calculated correctly without user intervention

### Requirement: Type conversion

The serializer MUST automatically convert:

| Elixir Type | FIX Format |
|-------------|------------|
| string | Latin-1 (from UTF-8) |
| integer | decimal string |
| float | string with up to 10 decimals, compact format |
| boolean | "Y" / "N" |
| DateTime | `YYYYMMDD-HH:MM:SS.mmm` |
| atom | string |
| nil | empty string |

#### Scenario: DateTime conversion
- **WHEN** a field with value `~U[2024-01-15 10:30:00.123Z]` is serialized
- **THEN** it is converted to `"20240115-10:30:00.123"`

#### Scenario: Boolean conversion
- **WHEN** a field with value `true` is serialized
- **THEN** it is converted to `"Y"`

### Requirement: Retransmission support

When serializing with `resend: true`, the serializer MUST add PossDupFlag="Y" and OrigSendingTime with the original timestamp.

#### Scenario: Message retransmission
- **WHEN** a message is serialized with `resend: true`
- **THEN** PossDupFlag="Y" and OrigSendingTime are included

### Requirement: Dictionary behaviour

There MUST exist a `Dictionary` behaviour with the callback:

```elixir
@callback subject(msg_type :: String.t()) :: String.t() | {String.t(), String.t()} | nil
```

Which defines which field(s) of a message are used as routing key.

#### Scenario: Dictionary with routing field
- **WHEN** the Dictionary returns `"1"` for a msg_type
- **THEN** tag 1 is extracted as the message subject in phase 1

### Requirement: Supported routing patterns

The Dictionary MUST support these routing patterns:

- **Single field**: `def subject("8"), do: "1"` — extracts one field as subject
- **Two fields**: `def subject("y"), do: ["1301", "1300"]` — extracts a pair of fields as composite subject
- **No routing**: `def subject(_), do: nil` — the message is fully parsed in phase 1

#### Scenario: Single field routing
- **WHEN** the Dictionary returns a string for a msg_type
- **THEN** that field is extracted as subject

#### Scenario: Two-field routing
- **WHEN** the Dictionary returns a list of two strings for a msg_type
- **THEN** both fields are extracted as composite subject

#### Scenario: No routing
- **WHEN** the Dictionary returns nil
- **THEN** the message is fully parsed in phase 1

### Requirement: Default dictionary

There MUST exist a `DefaultDictionary` that returns `nil` for all message types (no routing, complete parsing in phase 1).

#### Scenario: DefaultDictionary
- **WHEN** the DefaultDictionary is used
- **THEN** all messages are fully parsed in phase 1

### Requirement: Partial message handling

The parser MUST support fragmented TCP data:

- Buffer incomplete bytes between receptions
- Concatenate new data with the existing buffer before parsing
- Support multiple FIX messages in a single TCP segment

#### Scenario: Message fragmented across two TCP segments
- **WHEN** a FIX message arrives split across two TCP segments
- **THEN** bytes from the first segment are buffered and parsing completes upon receiving the second

#### Scenario: Multiple messages in one segment
- **WHEN** a TCP segment contains two complete FIX messages
- **THEN** both messages are parsed correctly

### Requirement: Parsing optimization

Critical parser and serializer functions MUST use `@compile {:inline, ...}` to reduce call overhead in the hot path.

Parsing MUST use native Erlang/OTP binary pattern matching for zero-copy extraction.

#### Scenario: Critical functions inlined
- **WHEN** parsing and serialization modules are compiled
- **THEN** functions marked with `@compile {:inline, ...}` are inlined
