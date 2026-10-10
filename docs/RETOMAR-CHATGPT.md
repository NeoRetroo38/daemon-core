# Cómo retomar Daemon (para ChatGPT / Codex u otro agente) · 9 oct 2026

Léelo entero antes de tocar nada. Después lee `AGENTS.md`, `docs/CONTROL_PLANE.md` y, en el Mac, `~/Desktop/scenarys/clod/MEMORIA.md`.

## 1. Qué es esto en 30 segundos
- **Daemon** es la app nativa de macOS (SwiftUI + núcleo C++20) que sirve de *control plane* local del ecosistema **Scenarys**.
  Observa repos, puertos, procesos, Tailscale, choisys, Neon y el **Cubo de Neo**, y actúa solo mediante herramientas declaradas.
- Dueño y criterio final: **Neo** (GitHub `NeoRetroo38`). Él revisa y fusiona desde GitHub Mobile.
- Dos agentes dentro de la app: **Daemon** (mide, voz local sin tokens o LLM opcional) y **Clod** (Claude: razona, recuerda, coordina).

## 2. Reglas que no se rompen
1. El Cubo de Neo escucha **solo en 127.0.0.1:8765** con token Bearer. Nunca LAN, Tailscale Serve/Funnel ni Internet.
   Entre máquinas, **túnel SSH** sobre Tailscale (Cube Link). No reimplementes su lógica fuera de C++.
2. Nada de secretos en Git, logs o respuestas (tokens, `DATABASE_URL`, contraseñas). Usuarios: solo nombre visible.
3. Commits **sin `Co-Authored-By` ni firmas de IA**. Ramas `codex/<tema>` o `claude/<tema>`. Sin force-push. Todo cambio es una PR
   asignada a `NeoRetroo38`; fusionar es solo de Neo (ver `AGENTS.md`).
4. Gana la máquina: medido ahora > código > Git > GitHub > endpoints > docs > inferencia. Evidencia: verificado / parcial / no verificado.
5. Acciones con riesgo pasan por `daemon_policy_evaluate` (C++). No añadas una «shell libre» al agente: añade una herramienta al catálogo.

## 3. Dónde está cada cosa
| Qué | Mac | Desktop (Windows, `DESKTOP-DGJSRGV`) |
|---|---|---|
| Workspace | `~/Desktop/scenarys` | el que use Neo en el PC |
| daemon-core (privado) | `~/Desktop/scenarys/daemon-core` | clonar `NeoRetroo38/daemon-core` |
| choisys | `~/Desktop/scenarys/choisys/repo` | sirve API :3000 y web :8081 por la tailnet |
| Cubo de Neo | `~/Desktop/scenarys/cubo-de-neo/repo` (`neos-cube`) | servicio 127.0.0.1:8765 (token en `C:\Users\Admin\daemon.codex.env.local`) |
| Memoria compartida | `~/Desktop/scenarys/clod/` (MEMORIA, bitácora, buzón) | — |
| Manual de la shell | Notas de iCloud: «Manual de la shell de Mac — stack Scenarys» + «… — anexo Daemon» | — |
| Docs del ecosistema | iCloud `scenarys/daemon/` (copias de CONTROL_PLANE y AVANCES) | — |
| Coordinación | GitHub `daemon-core`: issue **#10** (Mac ↔ Desktop), issue **#1** (prompt maestro) | igual |

Topología medida: Mac, Desktop (MagicDNS `desktop-dgjsrgv.<tailnet>.ts.net`) e iPhone en la tailnet; las IPs, con `tailscale status` (no se publican: el repo es público).

## 4. Estado al cerrar esta sesión
- **Fusionado en main (PR #9)**: gate de políticas C++ (C ABI 0.2.0), capa Control, 26 herramientas, mapa vivo, cubo 3D con el
  idioma del Cubo, Clod con memoria, Sistema/Red/Tecnología, SFX (`assets/sfx`), arranque con Blender (`assets/vfx`), Cube Link.
- **Rama `claude/agent-conversation`** (PR siguiente): chats tipo LLM (respuesta que se escribe en streaming, pasos de herramienta
  plegables, markdown, burbujas, voz natural de Daemon `Agent/DaemonVoice.swift`, seguimiento «¿y daemon-core?», streaming SSE real
  si hay API key), arreglo del bloqueo del escaneo de repos (presupuesto de 10 s, conteo de líneas sobre bytes, escaneos compartidos),
  `scripts/cube-link.command` versionado. 28 tests Swift.
- **Rama `claude/runtime-topology`** (encima de la anterior): el mapa vivo es **topología de ejecución**, no de archivos.
  Modelo en `apple/DaemonKit/Runtime/` (`RuntimeTopology`, `RuntimeMapView`, `RuntimeInspector`). Regla: un repositorio no es un
  nodo por existir en disco; solo se dibuja lo que corre (Daemon, listeners medidos del Mac, servicios del Desktop por Serve,
  Cubo aislado con salud «desconocida», externos). Los repos son procedencia (`source`) y solo aparecen con
  «Mostrar procedencia del código». Estados: VERIFICADO / DEGRADADO / NO DISPONIBLE / DESCONOCIDO.
- **Pendiente**:
  1. Desktop: activar OpenSSH solo para la tailnet → `scripts/windows/enable-openssh-tailnet.ps1 -PublicKey "<clave del Mac>"`;
     luego en el Mac `~/Desktop/scenarys/cube-link.command` (pide el usuario de Windows y lo guarda en `topology.json`).
  2. Verificar que el Cubo del Desktop escucha solo en 127.0.0.1 (`Get-NetTCPConnection -LocalPort 8765 -State Listen`).
  3. Build iOS (`apple/DaemonIOSApp`) sin verificar.
  4. API key de Anthropic en Daemon › Ajustes (Llavero) para que Clod razone y Daemon redacte con el LLM; sin ella todo funciona en local.

## 5. Retomar en el Mac
```sh
cd ~/Desktop/scenarys/daemon-core
git fetch --all --prune && git status -sb          # ¿en qué rama estás? ¿cambios sin commit?
gh pr list --state open && gh issue view 10 --comments
swift test --scratch-path build/apple-spm          # 28 tests
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
cmake -S . -B build/daemon -DCMAKE_OSX_SYSROOT=$SDK && cmake --build build/daemon && ctest --test-dir build/daemon
SDKROOT=$SDK make test                              # tests del Cubo
bash scripts/apple-build-macos.sh && bash scripts/install-daemon-macos.sh && open /Applications/Daemon.app
```
O con doble clic: `~/Desktop/scenarys/terminar-daemon.command` (tests + build + instalación + push de la rama + PR).

Trampas conocidas del Mac:
- El SDK 27 de las Command Line Tools rompe el enlazador: usa el **SDK 26.5** (ya lo hacen los scripts).
- Tailscale es la versión App Store: la CLI es `/Applications/Tailscale.app/Contents/MacOS/Tailscale` (alias `tailscale` en `~/.zshrc`)
  y **necesita `TERM`** o falla con «CLIError error 3».
- La app solo puede hacer HTTP a la tailnet por **nombre `*.ts.net`** (excepción ATS en `Info.plist`), no por IP literal.
- Leer iCloud o Notas desde la Terminal dispara avisos de privacidad de macOS: Neo tiene que aceptarlos.
- Runner opcional para agentes remotos: `~/Desktop/scenarys/.daemon-runner/runner.command` ejecuta `queue/*.sh` (tope 15 min).

## 6. Retomar en el Desktop (Windows)
- Lo que **sí** se trabaja aquí: el núcleo C++ portable (`src/daemon`, `adapters`, `tests/daemon` con CMake/MSVC o MSYS2),
  el Cubo de Neo (`build.ps1 -Target tests|service`, `run.ps1`), choisys (API/web) y la parte Windows de Cube Link.
- Lo que **no**: `apple/**` (SwiftUI/SceneKit) solo compila en macOS. Si hace falta, deja la tarea en el issue #10 para el Mac.
- Antes de tocar `src/daemon/policy.cpp` o `include/daemon/daemon_bridge.h`, parte de `main` actualizado: los usa la app de Mac.
```powershell
git clone https://github.com/NeoRetroo38/daemon-core; cd daemon-core
cmake -S . -B build\daemon; cmake --build build\daemon --config Release; ctest --test-dir build\daemon -C Release
.\build.ps1 -Target tests
```

## 7. Mapa del código (Apple)
- `apple/DaemonKit/Control/`: `CommandRunner` (argv sin shell, entorno mínimo, plazo, gate C++), `SystemProbe`, `PortProbe`,
  `TailnetProbe`, `NetworkProbe` (+ p50/p95/p99), `Topology` (`topology.json`), `Ecosystem` (observación + alertas + ruta del producto),
  `Toolchain`, `GitInsights`, `GitHubProbe`, `Discovery`, `RepositoryIndex` (huella SHA-256), `Evidence`.
- `apple/DaemonKit/Agent/`: `ToolRegistry` (catálogo con riesgo), `ToolExecutor`, `IntentRouter` (español, seguimiento),
  `DaemonVoice`, `AgentSession` (streaming, pasos), `ClaudeAgent` (tool use READ + SSE), `Clod` (memoria compartida), `Persona`.
- `apple/DaemonKit/UI/`: `Theme`, `Atmosphere` (SFX, arranque, transporte), `TopologyMap`, `MetricCube`, `AgentChatView`,
  `ClodChatView`, `TechnologyView`. App: `apple/DaemonMac/DaemonMacApp.swift`.
- Para añadir una capacidad: herramienta en `ToolCatalog` → implementación en `ToolExecutor` → si ejecuta un binario, regla en
  `policy.cpp` + caso en `tests/daemon/security_cases.cpp` → intención en `IntentRouter` → test en `ControlPlaneTests.swift`.

## 8. Cómo coordinarse
- Un comentario por unidad de trabajo en el **issue #10**: rama, qué cambió, cómo se probó, qué falta.
- Lo durable, en `clod/MEMORIA.md`; decisiones, una línea en `clod/bitacora.md`; encargos para Claude, en `clod/buzon/`.
- PR pequeña, cuerpo que empieza con `## Para el dueño`, asignada a `NeoRetroo38`, ready for review.
