# API Pública

## Purpose

Interfaz de usuario del módulo `ExFix` — entry point para iniciar sesiones, enviar mensajes y detener sesiones FIX.

## Requirements

### Requirement: Firma de start_session_initiator

El sistema MUST exponer `ExFix.start_session_initiator/5` con la siguiente firma:

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

#### Scenario: Inicio con parámetros mínimos
- **WHEN** se invoca `start_session_initiator("sim", "BUY", "SELL", MyHandler)`
- **THEN** se inicia una sesión con los valores por defecto para todas las opciones

#### Scenario: Inicio con opciones custom
- **WHEN** se invoca `start_session_initiator("sim", "BUY", "SELL", MyHandler, hostname: "remote", port: 5000)`
- **THEN** se inicia una sesión usando las opciones proporcionadas y defaults para el resto

### Requirement: Procesamiento de opciones

La función MUST convertir la keyword list `opts` a un mapa, aplicando valores por defecto para todas las opciones no proporcionadas. Los valores por defecto están documentados en la spec `session-management` (sección Configuración).

#### Scenario: Opciones parciales se completan con defaults
- **WHEN** se proporciona solo `hostname: "remote"` en opts
- **THEN** las demás opciones (`port`, `heart_bt_int`, etc.) toman sus valores por defecto

### Requirement: Construcción del SessionConfig

La función MUST construir un struct `SessionConfig` con:

- `name` — el `session_name` proporcionado
- `mode` — siempre `:initiator`
- `sender_comp_id`, `target_comp_id`, `session_handler` — de los parámetros
- Resto de campos — de las opciones procesadas

#### Scenario: Config resultante tiene campos correctos
- **WHEN** se invoca `start_session_initiator("sim", "BUY", "SELL", MyHandler)`
- **THEN** el SessionConfig tiene `name: "sim"`, `mode: :initiator`, `sender_comp_id: "BUY"`, `target_comp_id: "SELL"`, `session_handler: MyHandler`

### Requirement: Delegación al registry

La función MUST delegar el inicio de la sesión al `SessionRegistry` configurado, invocando `session_registry.start_session(session_name, config)`.

El registry se determina en este orden de prioridad:

1. `opts[:session_registry]` si está presente
2. El registry por defecto configurado en `Application.compile_env(:ex_fix, :session_registry)`
3. `ExFix.DefaultSessionRegistry` como fallback final

#### Scenario: Registry por defecto
- **WHEN** no se proporciona `session_registry` en opts
- **THEN** se usa el registry configurado en la aplicación o `ExFix.DefaultSessionRegistry`

#### Scenario: Registry custom en opts
- **WHEN** se proporciona `session_registry: MyRegistry` en opts
- **THEN** se usa `MyRegistry` para iniciar la sesión

### Requirement: Solo modo iniciador

La API pública MUST soportar únicamente el modo `:initiator` (buy-side). No existe soporte para modo acceptor (sell-side).

#### Scenario: Modo siempre initiator
- **WHEN** se inicia cualquier sesión via la API pública
- **THEN** el SessionConfig tiene `mode: :initiator`

### Requirement: Firma de send_message!

El sistema MUST exponer `ExFix.send_message!/2` con la siguiente firma:

```elixir
send_message!(out_message, session_name)
```

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `out_message` | `OutMessage.t()` | Mensaje construido con `OutMessage.new/1` y `OutMessage.set_field/3` |
| `session_name` | `Session.session_name()` | Nombre de la sesión destino |

#### Scenario: Envío exitoso
- **WHEN** se invoca `send_message!(msg, "sim")` con una sesión activa
- **THEN** retorna `:ok` y el mensaje es encolado para envío

### Requirement: Resolución de sesión por nombre

La función MUST resolver la sesión por su nombre registrado y delegar al `SessionWorker` correspondiente via `GenServer.call`. Si la sesión no existe o no está activa, MUST propagar la excepción (comportamiento bang `!`).

#### Scenario: Sesión activa
- **WHEN** se envía un mensaje a una sesión registrada y activa
- **THEN** el mensaje se delega al SessionWorker correspondiente

#### Scenario: Sesión inexistente
- **WHEN** se envía un mensaje a una sesión que no existe
- **THEN** se lanza una excepción

### Requirement: Envío sincrónico

`send_message!/2` MUST ser una operación sincrónica — retorna `:ok` cuando el mensaje fue encolado para envío, o lanza una excepción si falla. El caller puede usar esto para detectar sesiones caídas.

#### Scenario: Caller recibe confirmación
- **WHEN** se invoca `send_message!/2` y el worker procesa la petición
- **THEN** la función retorna `:ok` de forma sincrónica

### Requirement: Firma de stop_session

El sistema MUST exponer `ExFix.stop_session/2` con la siguiente firma:

```elixir
stop_session(session_name, registry \\ nil)
```

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `session_name` | `Session.session_name()` | Nombre de la sesión a detener |
| `registry` | módulo o nil | Registry custom; nil usa el por defecto |

#### Scenario: Stop con registry por defecto
- **WHEN** se invoca `stop_session("sim")`
- **THEN** se detiene la sesión usando el registry por defecto

#### Scenario: Stop con registry custom
- **WHEN** se invoca `stop_session("sim", MyRegistry)`
- **THEN** se detiene la sesión usando `MyRegistry`

### Requirement: Delegación de stop al registry

La función MUST delegar la detención al `SessionRegistry`:

- Si `registry` es nil, usa el registry por defecto (misma lógica que `start_session_initiator`)
- Si se proporciona un módulo, lo usa directamente

Invoca `session_registry.stop_session(session_name)`.

#### Scenario: Delegación correcta
- **WHEN** se invoca `stop_session("sim")`
- **THEN** se llama a `registry.stop_session("sim")` en el registry correspondiente

### Requirement: Dictionary por defecto configurable

El módulo MUST leer el dictionary por defecto desde `Application.compile_env(:ex_fix, :default_dictionary)`, con fallback a `ExFix.DefaultDictionary`. Esto se resuelve en tiempo de compilación.

#### Scenario: Dictionary no configurado
- **WHEN** no se configura `:default_dictionary` en la aplicación
- **THEN** se usa `ExFix.DefaultDictionary`

### Requirement: Registry por defecto configurable

El módulo MUST leer el registry por defecto desde `Application.compile_env(:ex_fix, :session_registry)`, con fallback a `ExFix.DefaultSessionRegistry`. Esto se resuelve en tiempo de compilación.

#### Scenario: Registry no configurado
- **WHEN** no se configura `:session_registry` en la aplicación
- **THEN** se usa `ExFix.DefaultSessionRegistry`
