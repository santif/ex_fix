# Transporte

Capa de abstracción de transporte para comunicación de red con contrapartes FIX.

## Interfaz de transporte

### Requirement: Contrato duck-typed

El sistema DEBE aceptar cualquier módulo de transporte que implemente tres funciones:

- `connect(host, port, options)` — retorna `{:ok, client}` o `{:error, reason}`
- `send(client, data)` — envía datos binarios por la conexión
- `close(client)` — cierra la conexión

No existe un behaviour formal; el contrato se cumple por duck typing. Los módulos `:gen_tcp` y `:ssl` de Erlang/OTP cumplen este contrato nativamente.

### Requirement: Transporte configurable por sesión

Cada sesión DEBE poder configurar su transporte independientemente mediante:

- `transport_mod` — módulo de transporte (default: `:gen_tcp`)
- `transport_options` — opciones adicionales pasadas a `connect/3`

El sistema DEBE anteponer `[mode: :binary]` a las opciones del usuario antes de conectar.

## TCP y SSL/TLS

### Requirement: Soporte TCP

El sistema DEBE soportar conexiones TCP planas via `:gen_tcp` como transporte por defecto.

### Requirement: Soporte SSL/TLS

El sistema DEBE soportar conexiones SSL/TLS via `:ssl`, aceptando todas las opciones estándar de `:ssl.connect/3` en `transport_options` (certificados, verificación de peer, etc.).

## Recepción de datos

### Requirement: I/O asincrónico

El sistema DEBE recibir datos de red como mensajes del proceso (`:tcp` o `:ssl` tuples), siguiendo el modelo asincrónico de BEAM. No DEBE hacer llamadas bloqueantes para leer datos.

### Requirement: Detección de desconexión

El sistema DEBE detectar desconexiones via mensajes `:tcp_closed` o `:ssl_closed` del transporte y terminar el worker de sesión con razón `:closed`.

## Manejo de errores

### Requirement: Error de conexión

Si `connect/3` retorna `{:error, reason}`, el sistema DEBE:

- Loguear el error
- Terminar el SessionWorker con la razón del error
- Actualizar el estado en el registry a `:reconnecting`

### Requirement: Desconexión durante operación

Si la conexión se cierra inesperadamente, el sistema DEBE:

- Terminar el SessionWorker con razón `:closed`
- Actualizar el estado en el registry a `:reconnecting`

## Buffering de datos

### Requirement: Mensajes TCP parciales

El sistema DEBE manejar fragmentación TCP:

- Mantener un buffer (`extra_bytes`) con datos incompletos entre recepciones
- Concatenar datos nuevos con el buffer antes de parsear
- Soportar múltiples mensajes FIX en un solo segmento TCP

### Requirement: Procesamiento continuo

Cuando un segmento TCP contiene múltiples mensajes FIX, el sistema DEBE procesarlos secuencialmente hasta agotar los datos disponibles, sin esperar nuevos datos de red.

## Testing

### Requirement: Transporte mockeable

El contrato duck-typed DEBE permitir inyectar un transporte de test que:

- Simule conexiones sin red real
- Capture mensajes enviados para verificación
- Permita inyectar datos de recepción y eventos de desconexión
