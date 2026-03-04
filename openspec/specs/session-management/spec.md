# Gestión de Sesión FIX

## Purpose

Implementación del protocolo de sesión FIXT.1.1 como iniciador (buy-side).

## Requirements

### Requirement: Estados de sesión

La sesión MUST transicionar entre cuatro estados:

- **offline** — estado inicial, sin conexión
- **connecting** — Logon enviado, esperando respuesta
- **online** — sesión activa, lista para mensajes de aplicación
- **disconnecting** — Logout iniciado o recibido, esperando cierre

Flujo principal: `offline → connecting → online → disconnecting → offline`

#### Scenario: Flujo principal de estados
- **WHEN** se inicia una sesión y el logon es exitoso
- **THEN** la sesión transiciona `offline → connecting → online`

#### Scenario: Cierre graceful
- **WHEN** se inicia el cierre de una sesión online
- **THEN** la sesión transiciona `online → disconnecting → offline`

### Requirement: Inicio de sesión

Al iniciar, el sistema MUST conectarse al host/puerto configurado y enviar un mensaje Logon con:

- EncryptMethod (tag 98)
- HeartBtInt (tag 108)
- ResetSeqNumFlag (tag 141), si `reset_on_logon: true`
- Username (tag 553) y Password (tag 554), si están configurados
- DefaultApplVerID (tag 1137)

La sesión transiciona a `:connecting` hasta recibir el Logon de respuesta.

#### Scenario: Logon con credenciales
- **WHEN** se inicia una sesión con `username` y `password` configurados
- **THEN** el mensaje Logon incluye tags 553 y 554

#### Scenario: Logon sin credenciales
- **WHEN** se inicia una sesión sin `username` ni `password`
- **THEN** el mensaje Logon no incluye tags 553 y 554

#### Scenario: Logon con reset de secuencia
- **WHEN** se inicia una sesión con `reset_on_logon: true`
- **THEN** el mensaje Logon incluye ResetSeqNumFlag (tag 141)

### Requirement: Cierre de sesión

El sistema MUST soportar cierre graceful enviando Logout y esperando respuesta.
Si no hay respuesta en 2 segundos, MUST forzar el cierre de la conexión.

Al recibir un Logout no solicitado, MUST responder con Logout y cerrar.

#### Scenario: Cierre graceful con respuesta
- **WHEN** se envía Logout y la contraparte responde con Logout
- **THEN** la conexión se cierra normalmente

#### Scenario: Cierre graceful sin respuesta
- **WHEN** se envía Logout y no hay respuesta en 2 segundos
- **THEN** se fuerza el cierre de la conexión

#### Scenario: Logout no solicitado
- **WHEN** se recibe un Logout sin haberlo iniciado
- **THEN** se responde con Logout y se cierra la conexión

### Requirement: Tipos de mensaje soportados

El sistema MUST procesar estos mensajes a nivel de sesión:

| Tipo | Código | Comportamiento |
|------|--------|----------------|
| Logon | A | Establecer sesión, intercambiar parámetros |
| Heartbeat | 0 | Keep-alive, respuesta a TestRequest |
| TestRequest | 1 | Verificar conectividad, requiere Heartbeat de respuesta |
| ResendRequest | 2 | Solicitar retransmisión de mensajes perdidos |
| Reject | 3 | Rechazo a nivel de sesión |
| SequenceReset | 4 | Ajustar números de secuencia (con/sin gap-fill) |
| Logout | 5 | Terminación de sesión |

Cualquier otro tipo de mensaje MUST ser ruteado al callback `on_app_message` del SessionHandler.

#### Scenario: Mensaje de sesión conocido
- **WHEN** se recibe un mensaje con tipo A, 0, 1, 2, 3, 4 o 5
- **THEN** se procesa a nivel de sesión

#### Scenario: Mensaje de aplicación
- **WHEN** se recibe un mensaje con tipo distinto a los de sesión (ej: "D", "8")
- **THEN** se rutea al callback `on_app_message`

### Requirement: Respuesta automática a TestRequest

Al recibir un TestRequest, el sistema MUST responder automáticamente con un Heartbeat conteniendo el mismo TestReqID (tag 112).

#### Scenario: TestRequest recibido
- **WHEN** se recibe un TestRequest con TestReqID="ABC"
- **THEN** se responde con Heartbeat conteniendo TestReqID="ABC"

### Requirement: Procesamiento de ResendRequest

Al recibir un ResendRequest, el sistema MUST:

- Retransmitir mensajes de aplicación del rango solicitado con PossDupFlag="Y"
- Reemplazar mensajes administrativos (Logon, Heartbeat, TestRequest, etc.) con SequenceReset-GapFill
- Preservar el OrigSendingTime de los mensajes retransmitidos

#### Scenario: ResendRequest de mensajes de aplicación
- **WHEN** se recibe un ResendRequest para un rango que contiene mensajes de aplicación
- **THEN** se retransmiten con PossDupFlag="Y" y OrigSendingTime preservado

#### Scenario: ResendRequest de mensajes administrativos
- **WHEN** se recibe un ResendRequest para un rango que contiene mensajes administrativos
- **THEN** se reemplazan con SequenceReset-GapFill

### Requirement: SequenceReset

El sistema MUST soportar dos variantes:

- **GapFill** (GapFillFlag="Y"): ajusta el número de secuencia esperado sin resetear la sesión
- **Reset** (GapFillFlag="N" o ausente): resetea el número de secuencia esperado a NewSeqNo

MUST rechazar intentos de disminuir el número de secuencia.

#### Scenario: GapFill
- **WHEN** se recibe SequenceReset con GapFillFlag="Y" y NewSeqNo mayor al esperado
- **THEN** se ajusta el número de secuencia esperado a NewSeqNo

#### Scenario: Reset
- **WHEN** se recibe SequenceReset con GapFillFlag="N" y NewSeqNo mayor al esperado
- **THEN** se resetea el número de secuencia esperado a NewSeqNo

#### Scenario: Intento de disminuir secuencia
- **WHEN** se recibe SequenceReset con NewSeqNo menor al esperado
- **THEN** se rechaza el mensaje

### Requirement: Tracking de secuencia

El sistema MUST mantener contadores independientes para mensajes entrantes (`in_lastseq`) y salientes (`out_lastseq`), incrementándolos con cada mensaje procesado/enviado.

#### Scenario: Incremento de secuencia entrante
- **WHEN** se recibe un mensaje válido
- **THEN** `in_lastseq` se incrementa en 1

#### Scenario: Incremento de secuencia saliente
- **WHEN** se envía un mensaje
- **THEN** `out_lastseq` se incrementa en 1

### Requirement: Detección de gaps

Si un mensaje llega con número de secuencia mayor al esperado, el sistema MUST:

- Encolar el mensaje para procesamiento posterior
- Enviar un ResendRequest para el rango faltante

#### Scenario: Gap detectado
- **WHEN** se espera secuencia 5 y llega un mensaje con secuencia 8
- **THEN** se encola el mensaje y se envía ResendRequest para el rango 5-7

### Requirement: Secuencia baja sin PossDupFlag

Si un mensaje llega con número de secuencia menor al esperado y sin PossDupFlag, el sistema MUST enviar Logout con razón "MsgSeqNum too low" y desconectar.

#### Scenario: Secuencia baja sin PossDup
- **WHEN** se espera secuencia 10 y llega un mensaje con secuencia 5 sin PossDupFlag
- **THEN** se envía Logout con razón "MsgSeqNum too low" y se desconecta

### Requirement: Duplicados

Si un mensaje llega con número de secuencia menor al esperado y PossDupFlag="Y", el sistema MUST ignorarlo silenciosamente.

#### Scenario: Duplicado con PossDupFlag
- **WHEN** se espera secuencia 10 y llega un mensaje con secuencia 5 y PossDupFlag="Y"
- **THEN** se ignora el mensaje sin error

### Requirement: Reset on logon

Si `reset_on_logon: true`, el sistema MUST enviar ResetSeqNumFlag en el Logon para resetear ambos contadores al inicio de la sesión.

#### Scenario: Reset habilitado
- **WHEN** se conecta con `reset_on_logon: true`
- **THEN** el Logon incluye ResetSeqNumFlag y ambos contadores se resetean

### Requirement: Heartbeat saliente

El sistema MUST enviar un Heartbeat automáticamente cuando no se ha enviado ningún mensaje durante `heart_bt_int` segundos. El timer se resetea con cada mensaje saliente.

#### Scenario: Timeout de heartbeat saliente
- **WHEN** no se envía ningún mensaje durante `heart_bt_int` segundos
- **THEN** se envía un Heartbeat automáticamente

#### Scenario: Reset del timer por mensaje saliente
- **WHEN** se envía un mensaje de aplicación
- **THEN** el timer de heartbeat saliente se resetea

### Requirement: Monitoreo de heartbeat entrante

El sistema MUST monitorear la recepción de mensajes con una tolerancia de 1.2x el intervalo de heartbeat.

- **Primer timeout**: enviar TestRequest y esperar respuesta
- **Segundo timeout** (sin respuesta al TestRequest): enviar Logout con razón "Data not received" y desconectar

El timer se resetea con cualquier mensaje entrante.

#### Scenario: Primer timeout sin datos
- **WHEN** no se recibe ningún mensaje en 1.2x `heart_bt_int` segundos
- **THEN** se envía un TestRequest

#### Scenario: Segundo timeout sin respuesta
- **WHEN** no se recibe respuesta al TestRequest en 1.2x `heart_bt_int` segundos
- **THEN** se envía Logout con razón "Data not received" y se desconecta

### Requirement: Reconexión automática

El sistema MUST soportar reconexión automática via el supervisor OTP (DynamicSupervisor con estrategia `:one_for_one`). Los workers de sesión son `:transient` (solo reiniciados ante terminación anormal).

#### Scenario: Desconexión anormal
- **WHEN** un SessionWorker termina de forma anormal
- **THEN** el supervisor lo reinicia automáticamente

#### Scenario: Desconexión normal
- **WHEN** un SessionWorker termina normalmente (ej: stop_session)
- **THEN** no se reinicia

### Requirement: Intervalo de reconexión

Antes de reconectar, el sistema MUST esperar `reconnect_interval` segundos (default: 15) para evitar saturar al servidor.

#### Scenario: Espera antes de reconectar
- **WHEN** un SessionWorker se reinicia tras desconexión anormal
- **THEN** espera `reconnect_interval` segundos antes de intentar la reconexión

### Requirement: Validación de SendingTime

Si `validate_sending_time: true`, el sistema MUST verificar que el SendingTime (tag 52) de cada mensaje entrante no difiera del tiempo actual en más de `sending_time_tolerance` segundos (default: 120). Si excede la tolerancia, MUST enviar Reject y Logout.

#### Scenario: SendingTime dentro de tolerancia
- **WHEN** se recibe un mensaje con SendingTime dentro de `sending_time_tolerance`
- **THEN** se procesa normalmente

#### Scenario: SendingTime fuera de tolerancia
- **WHEN** se recibe un mensaje con SendingTime que difiere más de `sending_time_tolerance` segundos
- **THEN** se envía Reject y Logout

#### Scenario: Validación deshabilitada
- **WHEN** `validate_sending_time: false`
- **THEN** no se verifica el SendingTime

### Requirement: Validación de CompID

El sistema MUST verificar que SenderCompID y TargetCompID de cada mensaje coincidan con los valores configurados (invertidos). Si no coinciden en un mensaje de aplicación, MUST enviar Reject con razón "CompID problem" y desconectar.

#### Scenario: CompID correcto
- **WHEN** se recibe un mensaje con SenderCompID y TargetCompID esperados
- **THEN** se procesa normalmente

#### Scenario: CompID incorrecto
- **WHEN** se recibe un mensaje de aplicación con CompID que no coincide
- **THEN** se envía Reject con razón "CompID problem" y se desconecta

### Requirement: Validación de PossDup

Para mensajes con PossDupFlag="Y", el sistema MUST verificar que:

- OrigSendingTime (tag 122) esté presente
- OrigSendingTime <= SendingTime

Si falla, MUST enviar Reject.

#### Scenario: PossDup válido
- **WHEN** se recibe un mensaje con PossDupFlag="Y", OrigSendingTime presente y <= SendingTime
- **THEN** se procesa normalmente

#### Scenario: PossDup sin OrigSendingTime
- **WHEN** se recibe un mensaje con PossDupFlag="Y" sin OrigSendingTime
- **THEN** se envía Reject

#### Scenario: OrigSendingTime > SendingTime
- **WHEN** se recibe un mensaje con PossDupFlag="Y" y OrigSendingTime > SendingTime
- **THEN** se envía Reject

### Requirement: Behaviour extensible

El sistema MUST exponer un behaviour `SessionHandler` con estos callbacks:

- `on_logon(session_name, env)` — sesión establecida
- `on_logout(session_name, env)` — sesión terminada
- `on_session_message(session_name, msg_type, msg, env)` — mensaje de protocolo recibido
- `on_app_message(session_name, msg_type, msg, env)` — mensaje de aplicación recibido

Todos los callbacks reciben el `env` custom definido en la configuración.

#### Scenario: Callback de logon
- **WHEN** la sesión se establece exitosamente
- **THEN** se invoca `on_logon(session_name, env)`

#### Scenario: Callback de mensaje de aplicación
- **WHEN** se recibe un mensaje de aplicación (ej: Execution Report)
- **THEN** se invoca `on_app_message(session_name, msg_type, msg, env)`

### Requirement: Opciones configurables

Cada sesión MUST ser configurable independientemente con:

| Opción | Default | Descripción |
|--------|---------|-------------|
| `hostname` | "localhost" | Host del servidor |
| `port` | 9876 | Puerto |
| `transport_mod` | `:gen_tcp` | `:gen_tcp` o `:ssl` |
| `heart_bt_int` | 60 | Intervalo de heartbeat (segundos) |
| `reset_on_logon` | true | Resetear secuencia al conectar |
| `username` / `password` | nil | Credenciales opcionales |
| `validate_incoming_message` | true | Validar checksum/body length |
| `validate_sending_time` | true | Validar SendingTime |
| `sending_time_tolerance` | 120 | Tolerancia en segundos |
| `reconnect_interval` | 15 | Segundos entre reconexiones |
| `log_incoming_msg` | true | Loguear mensajes entrantes |
| `log_outgoing_msg` | true | Loguear mensajes salientes |
| `time_service` | nil | nil (UTC now), DateTime fijo, o {m, f, a} |
| `max_output_buf_count` | 1000 | Tamaño del buffer de mensajes enviados |
| `env` | %{} | Mapa custom pasado a callbacks |

#### Scenario: Configuración por defecto
- **WHEN** se inicia una sesión sin opciones
- **THEN** se usan todos los valores por defecto de la tabla

#### Scenario: Override parcial
- **WHEN** se inicia una sesión con `heart_bt_int: 30`
- **THEN** se usa 30 para heartbeat y los defaults para el resto
