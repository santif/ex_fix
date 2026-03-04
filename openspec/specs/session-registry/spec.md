# Registry de Sesiones

Sistema de tracking de estado de sesiones FIX con soporte para reconexión coordinada.

## Behaviour

### Requirement: Behaviour SessionRegistry

DEBE existir un behaviour `SessionRegistry` con estos callbacks:

**API pública:**
- `get_session_status(session_name)` — retorna el estado actual de la sesión
- `start_session(session_name, config)` — registra e inicia una sesión FIX
- `stop_session(session_name)` — detiene y desregistra una sesión

**API interna (llamada desde workers de sesión):**
- `session_on_init(session_name)` — consulta antes de conectar, retorna `:ok`, `:wait_to_reconnect`, o `{:error, reason}`
- `session_update_status(session_name, status)` — actualiza el estado en tiempo real

### Requirement: Implementación extensible

El sistema DEBE permitir implementaciones custom del registry (ej: basadas en distributed ETS, Redis, etc.) mediante el behaviour.

## Estados de sesión

### Requirement: Estados tracked

El registry DEBE rastrear estos estados:

| Estado | Significado |
|--------|-------------|
| `:connecting` | Sesión registrada, intentando logon |
| `:connected` | Logon exitoso, recibiendo datos |
| `:disconnecting` | Cierre en progreso |
| `:disconnected` | Desconectada normalmente, sin reconexión |
| `:reconnecting` | Conexión perdida, pendiente de reconexión |

### Requirement: Transiciones de estado

Las transiciones DEBEN seguir este flujo:

```
start_session() → :connecting
                      ↓
              logon exitoso → :connected
                                  ↓
                      cierre graceful → :disconnecting → :disconnected
                      error/cierre     → :reconnecting
```

El estado default para sesiones no registradas DEBE ser `:disconnected`.

## Implementación por defecto (ETS)

### Requirement: Storage en ETS

La implementación por defecto DEBE usar una tabla ETS pública y nombrada (`:ex_fix_registry`) para almacenar pares `{session_name, status}`.

### Requirement: Monitoreo de procesos

La implementación por defecto DEBE monitorear los procesos de SessionWorker y actualizar estados automáticamente:

- Terminación normal (`:normal`) → `:disconnected`, eliminar del registro
- Terminación anormal (`:econnrefused`, `:closed`, etc.) → `:reconnecting`

## Coordinación de reconexión

### Requirement: Control de inicio via session_on_init

Cuando un SessionWorker inicia, DEBE consultar al registry via `session_on_init/1`:

- Si el estado es `:connecting` → retornar `:ok` (inicio inmediato)
- Si el estado es `:disconnecting` → retornar `{:error, :disconnected}` (rechazar)
- En cualquier otro estado → retornar `:wait_to_reconnect` (esperar `reconnect_interval`)

Esto DEBE prevenir intentos de reconexión concurrentes o prematuros.

## Supervisión

### Requirement: DynamicSupervisor

El sistema DEBE usar un `DynamicSupervisor` (SessionSup) con estrategia `:one_for_one` para supervisar los SessionWorkers. Los workers DEBEN ser `:transient` (solo reiniciados ante terminación anormal).

### Requirement: Naming de procesos

Cada SessionWorker DEBE registrarse como proceso nombrado con el formato `:ex_fix_session_{name}` para permitir lookups directos.

## Limpieza

### Requirement: Cleanup en stop

Al detener una sesión, el registry DEBE:

- Eliminar la entrada del almacenamiento
- Detener el SessionWorker gracefully
- Manejar el caso donde el worker ya no existe sin errores
