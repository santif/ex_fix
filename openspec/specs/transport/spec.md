# Transporte

## Purpose

Capa de abstracción de transporte para comunicación de red con contrapartes FIX.

## Requirements

### Requirement: Contrato duck-typed

El sistema MUST aceptar cualquier módulo de transporte que implemente tres funciones:

- `connect(host, port, options)` — retorna `{:ok, client}` o `{:error, reason}`
- `send(client, data)` — envía datos binarios por la conexión
- `close(client)` — cierra la conexión

No existe un behaviour formal; el contrato se cumple por duck typing. Los módulos `:gen_tcp` y `:ssl` de Erlang/OTP cumplen este contrato nativamente.

#### Scenario: Módulo compatible
- **WHEN** se configura un módulo que implementa `connect/3`, `send/2` y `close/1`
- **THEN** el sistema lo acepta como transporte válido

### Requirement: Transporte configurable por sesión

Cada sesión MUST poder configurar su transporte independientemente mediante:

- `transport_mod` — módulo de transporte (default: `:gen_tcp`)
- `transport_options` — opciones adicionales pasadas a `connect/3`

El sistema MUST anteponer `[mode: :binary]` a las opciones del usuario antes de conectar.

#### Scenario: Opciones de transporte custom
- **WHEN** se configura `transport_options: [verify: :verify_peer]`
- **THEN** se pasa `[mode: :binary, verify: :verify_peer]` a `connect/3`

### Requirement: Soporte TCP

El sistema MUST soportar conexiones TCP planas via `:gen_tcp` como transporte por defecto.

#### Scenario: Conexión TCP por defecto
- **WHEN** no se especifica `transport_mod`
- **THEN** se usa `:gen_tcp` para la conexión

### Requirement: Soporte SSL/TLS

El sistema MUST soportar conexiones SSL/TLS via `:ssl`, aceptando todas las opciones estándar de `:ssl.connect/3` en `transport_options` (certificados, verificación de peer, etc.).

#### Scenario: Conexión SSL
- **WHEN** se configura `transport_mod: :ssl`
- **THEN** se establece una conexión SSL/TLS

### Requirement: I/O asincrónico

El sistema MUST recibir datos de red como mensajes del proceso (`:tcp` o `:ssl` tuples), siguiendo el modelo asincrónico de BEAM. MUST NOT hacer llamadas bloqueantes para leer datos.

#### Scenario: Recepción asincrónica TCP
- **WHEN** llegan datos por una conexión TCP
- **THEN** el proceso recibe un mensaje `{:tcp, socket, data}`

#### Scenario: Recepción asincrónica SSL
- **WHEN** llegan datos por una conexión SSL
- **THEN** el proceso recibe un mensaje `{:ssl, socket, data}`

### Requirement: Detección de desconexión

El sistema MUST detectar desconexiones via mensajes `:tcp_closed` o `:ssl_closed` del transporte y terminar el worker de sesión con razón `:closed`.

#### Scenario: Desconexión TCP
- **WHEN** la conexión TCP se cierra
- **THEN** el proceso recibe `{:tcp_closed, socket}` y el worker termina con razón `:closed`

### Requirement: Error de conexión

Si `connect/3` retorna `{:error, reason}`, el sistema MUST:

- Loguear el error
- Terminar el SessionWorker con la razón del error
- Actualizar el estado en el registry a `:reconnecting`

#### Scenario: Error de conexión
- **WHEN** `connect/3` retorna `{:error, :econnrefused}`
- **THEN** se loguea el error, el worker termina y el registry marca `:reconnecting`

### Requirement: Desconexión durante operación

Si la conexión se cierra inesperadamente, el sistema MUST:

- Terminar el SessionWorker con razón `:closed`
- Actualizar el estado en el registry a `:reconnecting`

#### Scenario: Cierre inesperado
- **WHEN** la conexión se cierra durante operación normal
- **THEN** el worker termina con razón `:closed` y el registry marca `:reconnecting`

### Requirement: Mensajes TCP parciales

El sistema MUST manejar fragmentación TCP:

- Mantener un buffer (`extra_bytes`) con datos incompletos entre recepciones
- Concatenar datos nuevos con el buffer antes de parsear
- Soportar múltiples mensajes FIX en un solo segmento TCP

#### Scenario: Fragmentación TCP
- **WHEN** un mensaje FIX llega en dos segmentos TCP separados
- **THEN** se bufferean los bytes parciales y se procesan al completarse

### Requirement: Procesamiento continuo

Cuando un segmento TCP contiene múltiples mensajes FIX, el sistema MUST procesarlos secuencialmente hasta agotar los datos disponibles, sin esperar nuevos datos de red.

#### Scenario: Múltiples mensajes en un segmento
- **WHEN** un segmento TCP contiene 3 mensajes FIX completos
- **THEN** los 3 se procesan secuencialmente sin esperar nuevos datos

### Requirement: Transporte mockeable

El contrato duck-typed MUST permitir inyectar un transporte de test que:

- Simule conexiones sin red real
- Capture mensajes enviados para verificación
- Permita inyectar datos de recepción y eventos de desconexión

#### Scenario: Test con transporte mock
- **WHEN** se configura un módulo mock como `transport_mod`
- **THEN** la sesión funciona sin red real y los mensajes son capturables
