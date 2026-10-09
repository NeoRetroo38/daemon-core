# Daemon · control plane local de Scenarys (oct 2026)

> El Cubo mide. choisys utiliza. Scenarys organiza. Daemon observa, conecta y opera. Clod razona y recuerda. Neo decide.

## Arquitectura

```text
                    ┌──────────────── Daemon.app (SwiftUI, macOS) ───────────────┐
 Neo ── chat ──►    │  01 Mapa vivo · 02 Daemon · 03 Clod · 04 Repos · 05 Sistema │
                    │  06 Red · 07 Tecnología · barra de transporte · arranque    │
                    └───────┬──────────────────────────────┬──────────────────────┘
                            │                              │
              Agent (DaemonKit/Agent)            Control (DaemonKit/Control)
   IntentRouter (es, 0 tokens) ─► ToolCatalog ─► ToolExecutor ─► probes / índice
   ClaudeAgent (opcional, READ)   (riesgo, confirmación)          │
   ClodSession (memoria compartida)                               ▼
                                         CommandRunner ──► daemon_policy_evaluate (C++)
                                         (argv, sin shell, entorno mínimo, plazo, tope)
                                                                  │
                     lsof · ps · git · gh · tailscale · ssh · sysctl · brew · npm(check:neon)
                     URLSession / Network.framework (sondas sin cuerpo ni cookies)
```

- **Núcleo C++20** (`src/daemon`, `adapters`): instantánea Git, política de comandos, comprobación de exposición del Cubo y
  redacción. C ABI 0.2.0: `daemon_snapshot_json_many`, `daemon_policy_evaluate`, `daemon_check_exposure`, `daemon_redact`.
- **Control**: `SystemProbe` (sysctl/Mach/IOKit/getifaddrs), `PortProbe` (lsof+ps), `TailnetProbe` (`tailscale status --json`),
  `NetworkProbe` (HTTP/TCP + historial p50/p95/p99), `Topology` (declarada en `~/Library/Application Support/Daemon/topology.json`),
  `EcosystemProbe` (observación paralela, alertas, ruta cliente → frontend → API → DB → Cubo), `ToolchainProbe`,
  `GitInsightsProbe`, `GitHubProbe`, `RepositoryDiscovery`, `RepositoryIndex` (huella SHA-256 de HEAD + estado de trabajo).
- **Agent**: `ToolCatalog` (26 herramientas declaradas con entradas, salida, riesgo y confirmación), `ToolExecutor`,
  `IntentRouter`, `DaemonPersona`, `AgentSession`, `ClaudeAgent` (tool use solo READ), `Clod` (memoria compartida).
- **UI**: `TopologyMap`, `MetricCube`, `AgentChatView`, `ClodChatView`, `TechnologyView`, `Atmosphere` (SFX, arranque, transporte), `Theme`.

## Niveles de acción

| Nivel | Ejemplos | Política |
|---|---|---|
| READ | repo.status, system.ports, network.tailnet, cube.health | automático; el núcleo debe dar `allow` |
| WRITE | repo.tests, daemon.build, daemon.install | orden explícita de Neo o botón; install pide confirmación |
| SERVICE | neon.health, service.stop | orden explícita; stop pide confirmación y solo puertos declarados |
| NETWORK | cube.tunnel.open/close | orden explícita; ssh solo `-N -L 127.0.0.1:…:127.0.0.1:…` |
| DESTRUCTIVE | (ninguna implementada) | siempre confirmación |

Denegaciones permanentes del núcleo (aunque haya aprobación): force-push, reescritura de historia, `sudo`, shells con `-c`,
`rm -rf` amplio, túneles con `-g`, `-R`, `ProxyCommand`/`LocalCommand` o bind fuera de loopback.

## Cubo de Neo y Cube Link

- Contrato: el servicio escucha **solo** en `127.0.0.1:8765` con token Bearer. Daemon lo comprueba en el Mac (lsof +
  `check_exposure`) y en el Desktop (TCP a su IP de tailnet: cerrado = contrato cumplido; abierto = **alerta crítica**).
- **Cualquier programa local** usa `http://127.0.0.1:8765`. Para el Cubo del Desktop, `~/Desktop/scenarys/cube-link.command`
  instala un LaunchAgent (`com.scenarys.cubelink`) con `ssh -N -L 127.0.0.1:8765:127.0.0.1:8765` sobre Tailscale y
  reconexión automática. Apagar: `cube-link.command --off`.
- Requisito en el Desktop: `scripts/windows/enable-openssh-tailnet.ps1 -PublicKey "<clave del Mac>"` (OpenSSH Server,
  regla de firewall solo `100.64.0.0/10`, sin contraseñas, `GatewayPorts no`).
- Medido el 2026-10-09: Desktop en la tailnet, choisys API :3000 y web :8081 responden por MagicDNS, 8765 cerrado por la tailnet,
  22 cerrado (Cube Link pendiente de OpenSSH).

## Clod

Claude dentro de Daemon. Memoria en `~/Desktop/scenarys/clod/` (fuera de Git): `MEMORIA.md`, `bitacora.md`, `buzon/`.
`@daemon …` mide en el mismo hilo; `@claude …` deja un encargo para la próxima sesión de Claude Code. Con API key (Llavero,
servicio `com.scenarys.daemon`) razona con el modelo configurado y solo puede: herramientas READ, preguntar a Daemon,
anotar en la bitácora y escribir en el buzón.

## Tokens

El router local resuelve las preguntas habituales sin LLM. El LLM opcional recibe `context.json` (resumen compacto del índice)
y la última observación en texto; los repos no se releen si la huella Git no cambia (máximo 1 h).

## Dirección de arte

Referencias en `~/Desktop/scenarys/kill-aesthetics`. Se conserva negro/blanco/verde Scenarys y la mono; se añade tinta lila
manga, semitono, grano de imprenta, desregistro riso en titulares, scanlines, líneas cinéticas, esquinas en L y una barra de
transporte (play/pausa de la monitorización, BPM = intervalo, forma de onda de latencias, contador, SFX).
El cubo usa el idioma del visor del Cubo de Neo: `x col`, `y row`, `z phase`, diagonales rojas, recorrido blanco numerado,
«last N runs».

### Pipelines creativos (no son dependencias de runtime)

- **VFX**: `Blender -b -P assets/vfx/render_boot.py` (Workbench, 54 frames RGBA) y `python3 assets/vfx/quantize.py`.
- **SFX**: `python3 assets/sfx/generate_sfx.py` (solo biblioteca estándar). Para refinarlos en Ableton Live, exporta con el
  mismo nombre (44.1 kHz, 16 bit, mono). `scripts/apple-build-macos.sh` los copia a `Contents/Resources`.

## Verificación

```sh
swift test --scratch-path build/apple-spm          # 26 tests (snapshot, control plane, router, cubo, políticas)
cmake -S . -B build/daemon -DCMAKE_OSX_SYSROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk && cmake --build build/daemon && ctest --test-dir build/daemon
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk make test
bash scripts/apple-build-macos.sh && bash scripts/install-daemon-macos.sh
```
