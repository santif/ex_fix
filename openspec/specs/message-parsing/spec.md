# Parsing y Serialización de Mensajes FIX

Sistema de parsing en dos fases y serialización de mensajes del protocolo FIX (FIXT.1.1).

## Parsing en dos fases

### Requirement: Parse fase 1 (extracción de headers)

La fase 1 (`parse1`) DEBE extraer del mensaje binario:

- BeginString (tag 8) — DEBE ser exactamente `FIXT.1.1`
- BodyLength (tag 9) — tamaño del cuerpo en bytes
- Checksum (tag 10) — suma módulo 256 de todos los bytes previos
- MsgType (tag 35) — tipo de mensaje
- MsgSeqNum (tag 34) — número de secuencia
- PossDupFlag (tag 43) — flag de posible duplicado
- Campos de subject definidos por el Dictionary (si aplica)

La fase 1 DEBE detenerse una vez extraídos los headers y campos de subject, dejando el resto del mensaje sin parsear en `rest_msg`.

### Requirement: Parse fase 2 (parsing completo)

La fase 2 (`parse2`) DEBE completar el parsing de todos los campos restantes del mensaje. Si el mensaje ya está completo (fase 1 parseó todo), DEBE ser idempotente.

### Requirement: Parse combinado

DEBE existir una función `parse/4` que encadene ambas fases para parsing sincrónico completo.

### Requirement: Soporte de RawData (tags 95/96)

Si el mensaje contiene tag 95 (RawDataLength), el parser DEBE:

- Extraer la longitud declarada
- Leer exactamente esa cantidad de bytes del tag 96 (RawData)
- Preservar el contenido binario sin modificar (puede contener SOH)

Si los bytes no coinciden con la longitud declarada, DEBE marcar el mensaje como `:garbled`.

## Validación en parsing

### Requirement: Validación de BeginString

El parser DEBE verificar que el BeginString sea exactamente `FIXT.1.1`. Si no coincide, DEBE marcar el mensaje con `error_reason: :begin_string_error`.

### Requirement: Validación de checksum

Si la validación está habilitada, el parser DEBE:

- Calcular la suma módulo 256 de todos los bytes previos al campo checksum
- Comparar con el valor recibido en tag 10 (3 dígitos)

Si no coincide, DEBE marcar el mensaje como `:garbled`.

### Requirement: Validación de BodyLength

El parser DEBE verificar que el valor de tag 9 coincida con el tamaño real del cuerpo del mensaje. Si no coincide, DEBE marcar como `:garbled`.

### Requirement: Validación de número de secuencia

Si se proporciona un `expected_seqnum`:

- Si coincide: procesar normalmente
- Si es mayor al esperado: marcar con `error_reason: :unexpected_seqnum` (el mensaje se parsea igualmente para poder encolarlo)
- Si es menor: dejarlo al manejo de la capa de sesión

### Requirement: Validación configurable

La validación de checksum y body length DEBE poder deshabilitarse via `validate_incoming_message: false`.

## Mensajes de entrada (InMessage)

### Requirement: Estructura de InMessage

Un mensaje entrante parseado DEBE contener:

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `valid` | boolean | true si la validación estructural pasó |
| `complete` | boolean | true si todos los campos fueron parseados |
| `msg_type` | string | Tipo de mensaje (tag 35) |
| `subject` | string, lista, o nil | Campo(s) de routing del Dictionary |
| `poss_dup` | boolean | PossDupFlag (tag 43) |
| `fields` | [{tag, value}] | Campos parseados como pares tag-valor |
| `seqnum` | integer | Número de secuencia (tag 34) |
| `rest_msg` | binary | Porción sin parsear (entre fases) |
| `other_msgs` | binary | Siguiente mensaje en el buffer TCP |
| `original_fix_msg` | binary | Mensaje original completo |
| `error_reason` | atom o nil | `:garbled`, `:begin_string_error`, `:unexpected_seqnum` |

### Requirement: Acceso a campos

DEBE existir una función `get_field(msg, tag)` que retorne el valor de un campo por su tag, o nil si no existe.

## Mensajes de salida (OutMessage)

### Requirement: API fluida de construcción

DEBE existir una API para construir mensajes de salida:

```elixir
OutMessage.new("D")
|> OutMessage.set_field("55", "AAPL")
|> OutMessage.set_field("54", "1")
|> OutMessage.set_fields([{"38", 100}, {"40", "2"}])
```

El usuario solo define el tipo de mensaje y los campos de aplicación. Los campos de header (BeginString, BodyLength, MsgSeqNum, SenderCompID, TargetCompID, SendingTime, Checksum) DEBEN ser gestionados automáticamente por el serializador.

## Serialización

### Requirement: Orden de campos

El serializador DEBE generar campos en este orden:

1. BeginString (tag 8): `FIXT.1.1`
2. BodyLength (tag 9): calculado
3. MsgType (tag 35)
4. MsgSeqNum (tag 34)
5. SenderCompID (tag 49)
6. PossDupFlag (tag 43) — solo en retransmisiones
7. SendingTime (tag 52)
8. OrigSendingTime (tag 122) — solo en retransmisiones
9. TargetCompID (tag 56)
10. Campos extra de header y body del usuario
11. Checksum (tag 10): calculado

### Requirement: Cálculo automático de checksum y body length

El serializador DEBE calcular automáticamente:

- **BodyLength**: bytes entre el final de tag 9 y el inicio de tag 10
- **Checksum**: suma módulo 256 de todos los bytes previos a tag 10, formateado como 3 dígitos con ceros a la izquierda

### Requirement: Conversión de tipos

El serializador DEBE convertir automáticamente:

| Tipo Elixir | Formato FIX |
|-------------|-------------|
| string | Latin-1 (desde UTF-8) |
| integer | string decimal |
| float | string con hasta 10 decimales, formato compacto |
| boolean | "Y" / "N" |
| DateTime | `YYYYMMDD-HH:MM:SS.mmm` |
| atom | string |
| nil | string vacío |

### Requirement: Soporte de retransmisión

Al serializar con `resend: true`, el serializador DEBE agregar PossDupFlag="Y" y OrigSendingTime con el timestamp original.

## Dictionary (routing de mensajes)

### Requirement: Behaviour Dictionary

DEBE existir un behaviour `Dictionary` con el callback:

```elixir
@callback subject(msg_type :: String.t()) :: String.t() | {String.t(), String.t()} | nil
```

Que define qué campo(s) de un mensaje se usan como clave de routing.

### Requirement: Patrones de routing soportados

- **Campo único**: `def subject("8"), do: "1"` — extrae un campo como subject
- **Dos campos**: `def subject("y"), do: ["1301", "1300"]` — extrae un par de campos como subject compuesto
- **Sin routing**: `def subject(_), do: nil` — se parsea el mensaje completo en fase 1

### Requirement: Dictionary por defecto

DEBE existir un `DefaultDictionary` que retorne `nil` para todos los tipos de mensaje (sin routing, parsing completo en fase 1).

## Fragmentación TCP

### Requirement: Manejo de mensajes parciales

El parser DEBE soportar datos TCP fragmentados:

- Bufferear bytes incompletos entre recepciones
- Concatenar datos nuevos con el buffer existente antes de parsear
- Soportar múltiples mensajes FIX en un solo segmento TCP

## Performance

### Requirement: Optimización de parsing

Las funciones críticas del parser y serializador DEBEN usar `@compile {:inline, ...}` para reducir overhead de llamadas en el hot path.

El parsing DEBE usar pattern matching binario nativo de Erlang/OTP para extracción zero-copy.
