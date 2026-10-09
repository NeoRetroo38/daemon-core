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

## Espacio de trabajo por repositorio

La app macOS permite seleccionar cada repositorio del catálogo con un clic. Su
vista mantiene cuatro superficies locales y de solo lectura:

- **Métricas:** recuento acotado de archivos, líneas, tamaño, lenguajes y
  capacidades detectadas, omitiendo `.git`, builds y dependencias vendorizadas.
- **Pruebas:** comprobaciones de estructura para API, backend, frontend y Cubo,
  más una sonda HTTP limitada a `127.0.0.1:8765`. No se invoca shell.
- **Mapa 3D:** visualización SceneKit de la distribución tecnológica. Blender y
  Ableton se detectan como herramientas creativas instaladas, pero no se lanzan
  ni controlan desde el runtime.
- **Identidades mínimas:** si el repositorio contiene login y persistencia,
  Daemon puede proyectar exclusivamente `displayName` desde el almacén local
  autorizado. Correo, IDs, roles, hashes, sesiones y credenciales se descartan.
- **Agente:** Daemon conserva una identidad fija y responde con herramientas
  declaradas y datos medidos. Ver [CONTROL_PLANE.md](CONTROL_PLANE.md) para el
  motor de herramientas, los niveles de acción, Clod y Cube Link.

Desde oct. 2026 la ejecución ya no es solo lectura: toda acción pasa por el
catálogo de herramientas y por `daemon_policy_evaluate` en el núcleo C++, con
niveles READ / WRITE / SERVICE / NETWORK / DESTRUCTIVE (ver CONTROL_PLANE.md).

La UI puede representar estas fases desde el mismo esquema, pero cada tarjeta
debe mostrar `verificado`, `no disponible` o `no verificado` y la hora de la
observación. Tráfico agregado no debe contener payloads, secretos ni tokens.
