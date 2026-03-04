# Registry de Sesiones

## Purpose

Sistema de tracking de estado de sesiones FIX con soporte para reconexión coordinada.

## Requirements

### Requirement: Behaviour SessionRegistry

MUST existir un behaviour `SessionRegistry` con estos callbacks:

**API pública:**
- `get_session_status(session_name)` — retorna el estado actual de la sesión
- `start_session(session_name, config)` — registra e inicia una sesión FIX
- `stop_session(session_name)` — detiene y desregistra una sesión

**API interna (llamada desde workers de sesión):**
- `session_on_init(session_name)` — consulta antes de conectar, retorna `:ok`, `:wait_to_reconnect`, o `{:error, reason}`
- `session_update_status(session_name, status)` — actualiza el estado en tiempo real

#### Scenario: Inicio y consulta de estado
- **WHEN** se invoca `start_session("sim", config)` y luego `get_session_status("sim")`
- **THEN** se retorna el estado actual de la sesión

### Requirement: Implementación extensible

El sistema MUST permitir implementaciones custom del registry (ej: basadas en distributed ETS, Redis, etc.) mediante el behaviour.

#### Scenario: Registry custom
- **WHEN** se implementa un módulo que cumple el behaviour `SessionRegistry`
- **THEN** se puede usar como registry configurando `:session_registry`

### Requirement: Estados tracked

El registry MUST rastrear estos estados:

| Estado | Significado |
|--------|-------------|
| `:connecting` | Sesión registrada, intentando logon |
| `:connected` | Logon exitoso, recibiendo datos |
| `:disconnecting` | Cierre en progreso |
| `:disconnected` | Desconectada normalmente, sin reconexión |
| `:reconnecting` | Conexión perdida, pendiente de reconexión |

#### Scenario: Transición de estados
- **WHEN** se inicia una sesión y completa el logon
- **THEN** el estado transiciona de `:connecting` a `:connected`

### Requirement: Transiciones de estado

Las transiciones MUST seguir este flujo:

```
start_session() → :connecting
                      ↓
              logon exitoso → :connected
                                  ↓
                      cierre graceful → :disconnecting → :disconnected
                      error/cierre     → :reconnecting
```

El estado default para sesiones no registradas MUST ser `:disconnected`.

#### Scenario: Sesión no registrada
- **WHEN** se consulta el estado de una sesión no registrada
- **THEN** se retorna `:disconnected`

#### Scenario: Error de conexión
- **WHEN** una sesión conectada pierde la conexión por error
- **THEN** el estado transiciona a `:reconnecting`

### Requirement: Storage en ETS

La implementación por defecto MUST usar una tabla ETS pública y nombrada (`:ex_fix_registry`) para almacenar pares `{session_name, status}`.

#### Scenario: Datos en ETS
- **WHEN** se inicia una sesión con el registry por defecto
- **THEN** el estado se almacena en la tabla ETS `:ex_fix_registry`

### Requirement: Monitoreo de procesos

La implementación por defecto MUST monitorear los procesos de SessionWorker y actualizar estados automáticamente:

- Terminación normal (`:normal`) → `:disconnected`, eliminar del registro
- Terminación anormal (`:econnrefused`, `:closed`, etc.) → `:reconnecting`

#### Scenario: Terminación normal del worker
- **WHEN** un SessionWorker termina con razón `:normal`
- **THEN** el estado cambia a `:disconnected` y se elimina del registro

#### Scenario: Terminación anormal del worker
- **WHEN** un SessionWorker termina con razón `:econnrefused`
- **THEN** el estado cambia a `:reconnecting`

### Requirement: Control de inicio via session_on_init

Cuando un SessionWorker inicia, MUST consultar al registry via `session_on_init/1`:

- Si el estado es `:connecting` → retornar `:ok` (inicio inmediato)
- Si el estado es `:disconnecting` → retornar `{:error, :disconnected}` (rechazar)
- En cualquier otro estado → retornar `:wait_to_reconnect` (esperar `reconnect_interval`)

Esto MUST prevenir intentos de reconexión concurrentes o prematuros.

#### Scenario: Inicio inmediato
- **WHEN** el worker consulta `session_on_init` y el estado es `:connecting`
- **THEN** se retorna `:ok`

#### Scenario: Reconexión con espera
- **WHEN** el worker consulta `session_on_init` y el estado es `:reconnecting`
- **THEN** se retorna `:wait_to_reconnect`

#### Scenario: Inicio rechazado
- **WHEN** el worker consulta `session_on_init` y el estado es `:disconnecting`
- **THEN** se retorna `{:error, :disconnected}`

### Requirement: DynamicSupervisor

El sistema MUST usar un `DynamicSupervisor` (SessionSup) con estrategia `:one_for_one` para supervisar los SessionWorkers. Los workers MUST ser `:transient` (solo reiniciados ante terminación anormal).

#### Scenario: Supervisión de workers
- **WHEN** se inicia una sesión
- **THEN** el SessionWorker se agrega al DynamicSupervisor como child `:transient`

### Requirement: Naming de procesos

Cada SessionWorker MUST registrarse como proceso nombrado con el formato `:ex_fix_session_{name}` para permitir lookups directos.

#### Scenario: Proceso nombrado
- **WHEN** se inicia una sesión con nombre "sim"
- **THEN** el proceso se registra como `:ex_fix_session_sim`

### Requirement: Cleanup en stop

Al detener una sesión, el registry MUST:

- Eliminar la entrada del almacenamiento
- Detener el SessionWorker gracefully
- Manejar el caso donde el worker ya no existe sin errores

#### Scenario: Stop de sesión activa
- **WHEN** se invoca `stop_session("sim")` con una sesión activa
- **THEN** se elimina del registro y se detiene el worker

#### Scenario: Stop de sesión ya detenida
- **WHEN** se invoca `stop_session("sim")` y el worker ya no existe
- **THEN** se elimina del registro sin errores
