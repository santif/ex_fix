# Parsing y Serialización de Mensajes FIX

## Purpose

Sistema de parsing en dos fases y serialización de mensajes del protocolo FIX (FIXT.1.1).

## Requirements

### Requirement: Parse fase 1 (extracción de headers)

La fase 1 (`parse1`) MUST extraer del mensaje binario:

- BeginString (tag 8) — MUST ser exactamente `FIXT.1.1`
- BodyLength (tag 9) — tamaño del cuerpo en bytes
- Checksum (tag 10) — suma módulo 256 de todos los bytes previos
- MsgType (tag 35) — tipo de mensaje
- MsgSeqNum (tag 34) — número de secuencia
- PossDupFlag (tag 43) — flag de posible duplicado
- Campos de subject definidos por el Dictionary (si aplica)

La fase 1 MUST detenerse una vez extraídos los headers y campos de subject, dejando el resto del mensaje sin parsear en `rest_msg`.

#### Scenario: Parse fase 1 exitoso
- **WHEN** se invoca `parse1` con un mensaje FIX binario válido
- **THEN** se extraen los headers y campos de subject, dejando el resto en `rest_msg`

### Requirement: Parse fase 2 (parsing completo)

La fase 2 (`parse2`) MUST completar el parsing de todos los campos restantes del mensaje. Si el mensaje ya está completo (fase 1 parseó todo), MUST ser idempotente.

#### Scenario: Parse fase 2 completa campos restantes
- **WHEN** se invoca `parse2` sobre un InMessage con `rest_msg` pendiente
- **THEN** se parsean todos los campos restantes y `complete` se marca como true

#### Scenario: Parse fase 2 idempotente
- **WHEN** se invoca `parse2` sobre un InMessage ya completo
- **THEN** el mensaje no cambia

### Requirement: Parse combinado

MUST existir una función `parse/4` que encadene ambas fases para parsing sincrónico completo.

#### Scenario: Parse completo en una llamada
- **WHEN** se invoca `parse` con un mensaje FIX binario
- **THEN** se retorna un InMessage con todos los campos parseados

### Requirement: Soporte de RawData (tags 95/96)

Si el mensaje contiene tag 95 (RawDataLength), el parser MUST:

- Extraer la longitud declarada
- Leer exactamente esa cantidad de bytes del tag 96 (RawData)
- Preservar el contenido binario sin modificar (puede contener SOH)

Si los bytes no coinciden con la longitud declarada, MUST marcar el mensaje como `:garbled`.

#### Scenario: RawData válido
- **WHEN** se parsea un mensaje con tag 95=5 y tag 96 con exactamente 5 bytes
- **THEN** se preserva el contenido binario del tag 96

#### Scenario: RawData con longitud incorrecta
- **WHEN** se parsea un mensaje con tag 95 cuya longitud no coincide con tag 96
- **THEN** se marca el mensaje como `:garbled`

### Requirement: Validación de BeginString

El parser MUST verificar que el BeginString sea exactamente `FIXT.1.1`. Si no coincide, MUST marcar el mensaje con `error_reason: :begin_string_error`.

#### Scenario: BeginString correcto
- **WHEN** se parsea un mensaje con BeginString="FIXT.1.1"
- **THEN** se procesa normalmente

#### Scenario: BeginString incorrecto
- **WHEN** se parsea un mensaje con BeginString distinto de "FIXT.1.1"
- **THEN** se marca con `error_reason: :begin_string_error`

### Requirement: Validación de checksum

Si la validación está habilitada, el parser MUST:

- Calcular la suma módulo 256 de todos los bytes previos al campo checksum
- Comparar con el valor recibido en tag 10 (3 dígitos)

Si no coincide, MUST marcar el mensaje como `:garbled`.

#### Scenario: Checksum correcto
- **WHEN** se parsea un mensaje con checksum que coincide con el cálculo
- **THEN** se procesa normalmente

#### Scenario: Checksum incorrecto
- **WHEN** se parsea un mensaje con checksum que no coincide
- **THEN** se marca como `:garbled`

### Requirement: Validación de BodyLength

El parser MUST verificar que el valor de tag 9 coincida con el tamaño real del cuerpo del mensaje. Si no coincide, MUST marcar como `:garbled`.

#### Scenario: BodyLength correcto
- **WHEN** tag 9 coincide con el tamaño real del cuerpo
- **THEN** se procesa normalmente

#### Scenario: BodyLength incorrecto
- **WHEN** tag 9 no coincide con el tamaño real del cuerpo
- **THEN** se marca como `:garbled`

### Requirement: Validación de número de secuencia

El parser MUST validar el número de secuencia si se proporciona un `expected_seqnum`:

- Si coincide: procesar normalmente
- Si es mayor al esperado: marcar con `error_reason: :unexpected_seqnum` (el mensaje se parsea igualmente para poder encolarlo)
- Si es menor: dejarlo al manejo de la capa de sesión

#### Scenario: Secuencia esperada
- **WHEN** se parsea un mensaje con número de secuencia igual al esperado
- **THEN** se procesa normalmente

#### Scenario: Secuencia mayor a la esperada
- **WHEN** se parsea un mensaje con número de secuencia mayor al esperado
- **THEN** se marca con `error_reason: :unexpected_seqnum` pero se parsea el contenido

### Requirement: Validación configurable

La validación de checksum y body length MUST poder deshabilitarse via `validate_incoming_message: false`.

#### Scenario: Validación deshabilitada
- **WHEN** se parsea con `validate_incoming_message: false`
- **THEN** no se verifican checksum ni body length

### Requirement: Estructura de InMessage

Un mensaje entrante parseado MUST contener:

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

#### Scenario: InMessage válido y completo
- **WHEN** se parsea un mensaje FIX válido con ambas fases
- **THEN** `valid` es true, `complete` es true, y todos los campos están poblados

### Requirement: Acceso a campos

MUST existir una función `get_field(msg, tag)` que retorne el valor de un campo por su tag, o nil si no existe.

#### Scenario: Campo existente
- **WHEN** se invoca `get_field(msg, "55")`
- **THEN** se retorna el valor del campo Symbol

#### Scenario: Campo inexistente
- **WHEN** se invoca `get_field(msg, "999")` para un tag que no existe en el mensaje
- **THEN** se retorna nil

### Requirement: API fluida de construcción

MUST existir una API para construir mensajes de salida:

```elixir
OutMessage.new("D")
|> OutMessage.set_field("55", "AAPL")
|> OutMessage.set_field("54", "1")
|> OutMessage.set_fields([{"38", 100}, {"40", "2"}])
```

El usuario solo define el tipo de mensaje y los campos de aplicación. Los campos de header (BeginString, BodyLength, MsgSeqNum, SenderCompID, TargetCompID, SendingTime, Checksum) MUST ser gestionados automáticamente por el serializador.

#### Scenario: Construcción de mensaje de aplicación
- **WHEN** se construye un OutMessage con `new("D")` y se agregan campos
- **THEN** se genera un struct con el tipo de mensaje y los campos definidos por el usuario

### Requirement: Orden de campos

El serializador MUST generar campos en este orden:

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

#### Scenario: Orden correcto en serialización
- **WHEN** se serializa un OutMessage
- **THEN** los campos del header aparecen en el orden especificado, seguidos de los campos del usuario y el checksum

### Requirement: Cálculo automático de checksum y body length

El serializador MUST calcular automáticamente:

- **BodyLength**: bytes entre el final de tag 9 y el inicio de tag 10
- **Checksum**: suma módulo 256 de todos los bytes previos a tag 10, formateado como 3 dígitos con ceros a la izquierda

#### Scenario: Cálculo automático
- **WHEN** se serializa un OutMessage
- **THEN** BodyLength y Checksum se calculan correctamente sin intervención del usuario

### Requirement: Conversión de tipos

El serializador MUST convertir automáticamente:

| Tipo Elixir | Formato FIX |
|-------------|-------------|
| string | Latin-1 (desde UTF-8) |
| integer | string decimal |
| float | string con hasta 10 decimales, formato compacto |
| boolean | "Y" / "N" |
| DateTime | `YYYYMMDD-HH:MM:SS.mmm` |
| atom | string |
| nil | string vacío |

#### Scenario: Conversión de DateTime
- **WHEN** se serializa un campo con valor `~U[2024-01-15 10:30:00.123Z]`
- **THEN** se convierte a `"20240115-10:30:00.123"`

#### Scenario: Conversión de boolean
- **WHEN** se serializa un campo con valor `true`
- **THEN** se convierte a `"Y"`

### Requirement: Soporte de retransmisión

Al serializar con `resend: true`, el serializador MUST agregar PossDupFlag="Y" y OrigSendingTime con el timestamp original.

#### Scenario: Retransmisión de mensaje
- **WHEN** se serializa un mensaje con `resend: true`
- **THEN** se incluyen PossDupFlag="Y" y OrigSendingTime

### Requirement: Behaviour Dictionary

MUST existir un behaviour `Dictionary` con el callback:

```elixir
@callback subject(msg_type :: String.t()) :: String.t() | {String.t(), String.t()} | nil
```

Que define qué campo(s) de un mensaje se usan como clave de routing.

#### Scenario: Dictionary con campo de routing
- **WHEN** el Dictionary retorna `"1"` para un msg_type
- **THEN** se extrae el tag 1 como subject del mensaje en fase 1

### Requirement: Patrones de routing soportados

El Dictionary MUST soportar estos patrones de routing:

- **Campo único**: `def subject("8"), do: "1"` — extrae un campo como subject
- **Dos campos**: `def subject("y"), do: ["1301", "1300"]` — extrae un par de campos como subject compuesto
- **Sin routing**: `def subject(_), do: nil` — se parsea el mensaje completo en fase 1

#### Scenario: Routing con campo único
- **WHEN** el Dictionary retorna un string para un msg_type
- **THEN** se extrae ese campo como subject

#### Scenario: Routing con dos campos
- **WHEN** el Dictionary retorna una lista de dos strings para un msg_type
- **THEN** se extraen ambos campos como subject compuesto

#### Scenario: Sin routing
- **WHEN** el Dictionary retorna nil
- **THEN** se parsea el mensaje completo en fase 1

### Requirement: Dictionary por defecto

MUST existir un `DefaultDictionary` que retorne `nil` para todos los tipos de mensaje (sin routing, parsing completo en fase 1).

#### Scenario: DefaultDictionary
- **WHEN** se usa el DefaultDictionary
- **THEN** todos los mensajes se parsean completamente en fase 1

### Requirement: Manejo de mensajes parciales

El parser MUST soportar datos TCP fragmentados:

- Bufferear bytes incompletos entre recepciones
- Concatenar datos nuevos con el buffer existente antes de parsear
- Soportar múltiples mensajes FIX en un solo segmento TCP

#### Scenario: Mensaje fragmentado en dos segmentos TCP
- **WHEN** un mensaje FIX llega dividido en dos segmentos TCP
- **THEN** se bufferean los bytes del primer segmento y se completa el parsing al recibir el segundo

#### Scenario: Múltiples mensajes en un segmento
- **WHEN** un segmento TCP contiene dos mensajes FIX completos
- **THEN** ambos mensajes se parsean correctamente

### Requirement: Optimización de parsing

Las funciones críticas del parser y serializador MUST usar `@compile {:inline, ...}` para reducir overhead de llamadas en el hot path.

El parsing MUST usar pattern matching binario nativo de Erlang/OTP para extracción zero-copy.

#### Scenario: Funciones críticas inlined
- **WHEN** se compilan los módulos de parsing y serialización
- **THEN** las funciones marcadas con `@compile {:inline, ...}` se inlinean
