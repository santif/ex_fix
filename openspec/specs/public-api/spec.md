# API Pública

Interfaz de usuario del módulo `ExFix` — entry point para iniciar sesiones, enviar mensajes y detener sesiones FIX.

## Inicio de sesión

### Requirement: Firma de start_session_initiator

El sistema DEBE exponer `ExFix.start_session_initiator/5` con la siguiente firma:

```elixir
start_session_initiator(session_name, sender_comp_id, target_comp_id, session_handler, opts \\ [])
```

Donde:

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `session_name` | `String.t()` | Nombre único que identifica la sesión |
| `sender_comp_id` | `String.t()` | CompID del iniciador (buy-side) |
| `target_comp_id` | `String.t()` | CompID de la contraparte (sell-side) |
| `session_handler` | módulo | Módulo que implementa el behaviour `SessionHandler` |
| `opts` | keyword list | Opciones de configuración (ver spec `session-management`) |

### Requirement: Procesamiento de opciones

La función DEBE convertir la keyword list `opts` a un mapa, aplicando valores por defecto para todas las opciones no proporcionadas. Los valores por defecto están documentados en la spec `session-management` (sección Configuración).

### Requirement: Construcción del SessionConfig

La función DEBE construir un struct `SessionConfig` con:

- `name` — el `session_name` proporcionado
- `mode` — siempre `:initiator`
- `sender_comp_id`, `target_comp_id`, `session_handler` — de los parámetros
- Resto de campos — de las opciones procesadas

### Requirement: Delegación al registry

La función DEBE delegar el inicio de la sesión al `SessionRegistry` configurado, invocando `session_registry.start_session(session_name, config)`.

El registry se determina en este orden de prioridad:

1. `opts[:session_registry]` si está presente
2. El registry por defecto configurado en `Application.compile_env(:ex_fix, :session_registry)`
3. `ExFix.DefaultSessionRegistry` como fallback final

### Requirement: Solo modo iniciador

La API pública DEBE soportar únicamente el modo `:initiator` (buy-side). No existe soporte para modo acceptor (sell-side).

## Envío de mensajes

### Requirement: Firma de send_message!

El sistema DEBE exponer `ExFix.send_message!/2` con la siguiente firma:

```elixir
send_message!(out_message, session_name)
```

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `out_message` | `OutMessage.t()` | Mensaje construido con `OutMessage.new/1` y `OutMessage.set_field/3` |
| `session_name` | `Session.session_name()` | Nombre de la sesión destino |

### Requirement: Resolución de sesión por nombre

La función DEBE resolver la sesión por su nombre registrado y delegar al `SessionWorker` correspondiente via `GenServer.call`. Si la sesión no existe o no está activa, DEBE propagar la excepción (comportamiento bang `!`).

### Requirement: Envío sincrónico

`send_message!/2` DEBE ser una operación sincrónica — retorna `:ok` cuando el mensaje fue encolado para envío, o lanza una excepción si falla. El caller puede usar esto para detectar sesiones caídas.

## Detención de sesión

### Requirement: Firma de stop_session

El sistema DEBE exponer `ExFix.stop_session/2` con la siguiente firma:

```elixir
stop_session(session_name, registry \\ nil)
```

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `session_name` | `Session.session_name()` | Nombre de la sesión a detener |
| `registry` | módulo o nil | Registry custom; nil usa el por defecto |

### Requirement: Delegación de stop al registry

La función DEBE delegar la detención al `SessionRegistry`:

- Si `registry` es nil, usa el registry por defecto (misma lógica que `start_session_initiator`)
- Si se proporciona un módulo, lo usa directamente

Invoca `session_registry.stop_session(session_name)`.

## Configuración global

### Requirement: Dictionary por defecto configurable

El módulo DEBE leer el dictionary por defecto desde `Application.compile_env(:ex_fix, :default_dictionary)`, con fallback a `ExFix.DefaultDictionary`. Esto se resuelve en tiempo de compilación.

### Requirement: Registry por defecto configurable

El módulo DEBE leer el registry por defecto desde `Application.compile_env(:ex_fix, :session_registry)`, con fallback a `ExFix.DefaultSessionRegistry`. Esto se resuelve en tiempo de compilación.
