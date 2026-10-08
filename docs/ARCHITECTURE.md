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
