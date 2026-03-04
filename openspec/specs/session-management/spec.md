# Gestión de Sesión FIX

Implementación del protocolo de sesión FIXT.1.1 como iniciador (buy-side).

## Ciclo de vida

### Requirement: Estados de sesión

La sesión DEBE transicionar entre cuatro estados:

- **offline** — estado inicial, sin conexión
- **connecting** — Logon enviado, esperando respuesta
- **online** — sesión activa, lista para mensajes de aplicación
- **disconnecting** — Logout iniciado o recibido, esperando cierre

Flujo principal: `offline → connecting → online → disconnecting → offline`

### Requirement: Inicio de sesión

Al iniciar, el sistema DEBE conectarse al host/puerto configurado y enviar un mensaje Logon con:

- EncryptMethod (tag 98)
- HeartBtInt (tag 108)
- ResetSeqNumFlag (tag 141), si `reset_on_logon: true`
- Username (tag 553) y Password (tag 554), si están configurados
- DefaultApplVerID (tag 1137)

La sesión transiciona a `:connecting` hasta recibir el Logon de respuesta.

### Requirement: Cierre de sesión

El sistema DEBE soportar cierre graceful enviando Logout y esperando respuesta.
Si no hay respuesta en 2 segundos, DEBE forzar el cierre de la conexión.

Al recibir un Logout no solicitado, DEBE responder con Logout y cerrar.

## Mensajes de sesión

### Requirement: Tipos de mensaje soportados

El sistema DEBE procesar estos mensajes a nivel de sesión:

| Tipo | Código | Comportamiento |
|------|--------|----------------|
| Logon | A | Establecer sesión, intercambiar parámetros |
| Heartbeat | 0 | Keep-alive, respuesta a TestRequest |
| TestRequest | 1 | Verificar conectividad, requiere Heartbeat de respuesta |
| ResendRequest | 2 | Solicitar retransmisión de mensajes perdidos |
| Reject | 3 | Rechazo a nivel de sesión |
| SequenceReset | 4 | Ajustar números de secuencia (con/sin gap-fill) |
| Logout | 5 | Terminación de sesión |

Cualquier otro tipo de mensaje DEBE ser ruteado al callback `on_app_message` del SessionHandler.

### Requirement: Respuesta automática a TestRequest

Al recibir un TestRequest, el sistema DEBE responder automáticamente con un Heartbeat conteniendo el mismo TestReqID (tag 112).

### Requirement: Procesamiento de ResendRequest

Al recibir un ResendRequest, el sistema DEBE:

- Retransmitir mensajes de aplicación del rango solicitado con PossDupFlag="Y"
- Reemplazar mensajes administrativos (Logon, Heartbeat, TestRequest, etc.) con SequenceReset-GapFill
- Preservar el OrigSendingTime de los mensajes retransmitidos

### Requirement: SequenceReset

El sistema DEBE soportar dos variantes:

- **GapFill** (GapFillFlag="Y"): ajusta el número de secuencia esperado sin resetear la sesión
- **Reset** (GapFillFlag="N" o ausente): resetea el número de secuencia esperado a NewSeqNo

DEBE rechazar intentos de disminuir el número de secuencia.

## Números de secuencia

### Requirement: Tracking de secuencia

El sistema DEBE mantener contadores independientes para mensajes entrantes (`in_lastseq`) y salientes (`out_lastseq`), incrementándolos con cada mensaje procesado/enviado.

### Requirement: Detección de gaps

Si un mensaje llega con número de secuencia mayor al esperado, el sistema DEBE:

- Encolar el mensaje para procesamiento posterior
- Enviar un ResendRequest para el rango faltante

### Requirement: Secuencia baja sin PossDupFlag

Si un mensaje llega con número de secuencia menor al esperado y sin PossDupFlag, el sistema DEBE enviar Logout con razón "MsgSeqNum too low" y desconectar.

### Requirement: Duplicados

Si un mensaje llega con número de secuencia menor al esperado y PossDupFlag="Y", el sistema DEBE ignorarlo silenciosamente.

### Requirement: Reset on logon

Si `reset_on_logon: true`, el sistema DEBE enviar ResetSeqNumFlag en el Logon para resetear ambos contadores al inicio de la sesión.

## Heartbeat y timeouts

### Requirement: Heartbeat saliente

El sistema DEBE enviar un Heartbeat automáticamente cuando no se ha enviado ningún mensaje durante `heart_bt_int` segundos. El timer se resetea con cada mensaje saliente.

### Requirement: Monitoreo de heartbeat entrante

El sistema DEBE monitorear la recepción de mensajes con una tolerancia de 1.2x el intervalo de heartbeat.

- **Primer timeout**: enviar TestRequest y esperar respuesta
- **Segundo timeout** (sin respuesta al TestRequest): enviar Logout con razón "Data not received" y desconectar

El timer se resetea con cualquier mensaje entrante.

## Reconexión

### Requirement: Reconexión automática

El sistema DEBE soportar reconexión automática via el supervisor OTP (DynamicSupervisor con estrategia `:one_for_one`). Los workers de sesión son `:transient` (solo reiniciados ante terminación anormal).

### Requirement: Intervalo de reconexión

Antes de reconectar, el sistema DEBE esperar `reconnect_interval` segundos (default: 15) para evitar saturar al servidor.

## Validación

### Requirement: Validación de SendingTime

Si `validate_sending_time: true`, el sistema DEBE verificar que el SendingTime (tag 52) de cada mensaje entrante no difiera del tiempo actual en más de `sending_time_tolerance` segundos (default: 120). Si excede la tolerancia, DEBE enviar Reject y Logout.

### Requirement: Validación de CompID

El sistema DEBE verificar que SenderCompID y TargetCompID de cada mensaje coincidan con los valores configurados (invertidos). Si no coinciden en un mensaje de aplicación, DEBE enviar Reject con razón "CompID problem" y desconectar.

### Requirement: Validación de PossDup

Para mensajes con PossDupFlag="Y", el sistema DEBE verificar que:

- OrigSendingTime (tag 122) esté presente
- OrigSendingTime <= SendingTime

Si falla, DEBE enviar Reject.

## Callbacks del SessionHandler

### Requirement: Behaviour extensible

El sistema DEBE exponer un behaviour `SessionHandler` con estos callbacks:

- `on_logon(session_name, env)` — sesión establecida
- `on_logout(session_name, env)` — sesión terminada
- `on_session_message(session_name, msg_type, msg, env)` — mensaje de protocolo recibido
- `on_app_message(session_name, msg_type, msg, env)` — mensaje de aplicación recibido

Todos los callbacks reciben el `env` custom definido en la configuración.

## Configuración

### Requirement: Opciones configurables

Cada sesión DEBE ser configurable independientemente con:

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
