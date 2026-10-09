# Daemon: coordinación, no motor

```text
Repos locales explícitos
      │ observación Git de solo lectura
      ▼
GitAdapter ──► daemon_core (C++20) ──► snapshot estructurado
                       │                       │
                       │ frontera C            │ JSON
                       ▼                       ▼
                Swift / SwiftUI            daemon CLI
                       │
               macOS: estado local
               iOS: lectura/importación, sin shell

choisys API ──► neos-cube canónico (motor separado)
               nunca forma parte de daemon_core
```

El core recibe datos y devuelve estado/política. No conoce vistas ni ejecuta UI.
Las aplicaciones no duplican la observación ni la lógica del núcleo.
Los datos no observados conservan un estado explícito desconocido.

El servicio remoto de control y launchd no se instalan en esta unidad.
Se posponen hasta justificar autenticación, permisos y necesidad real.
La instantánea histórica del Cubo presente en este repo no se utiliza en el nuevo build.

## Plano de control local por fases

1. **Catálogo y evidencia Git (implementado):** múltiples rutas explícitas,
   persistencia local, snapshot único, latencia de observación y estado verificable.
2. **Topología declarada:** inventario con identificadores estables para Mac,
   Cubo, APIs y dispositivos. Declarado no equivale a conectado.
3. **Telemetría de red:** colectores separados para sockets/bytes/errores con
   timestamp, origen y caducidad. Ningún dato se eleva a `healthy` por inferencia.
4. **Mantenimiento del Cubo:** diagnósticos de solo lectura primero; cualquier
   acción mutable necesita allowlist, autenticación y confirmación explícita.
5. **Flujos creativos:** Blender y Ableton producen artefactos versionables o
   exportados; no se convierten en dependencias del runtime de Daemon.

La UI puede representar estas fases desde el mismo esquema, pero cada tarjeta
debe mostrar `verificado`, `no disponible` o `no verificado` y la hora de la
observación. Tráfico agregado no debe contener payloads, secretos ni tokens.
