# Avances del motor (8 oct 2026)

Resumen para el equipo. La presentación completa del backend está en `choisys/docs/avances/` (HTML, PDF y PowerPoint/Keynote).

## Hecho

- **Núcleo `Run`/`Session`** (`src/core/cube.hpp`): tres fases, cuadrícula 3×3 por fase, intentos y entradas vacías, inválidas o fuera, salidas anticipadas.
- **Servicio local** (`src/api/server.cpp`): solo `127.0.0.1:8765`, token Bearer, peticiones y plazos acotados, logs sin datos. Portable: Winsock en Windows, sockets POSIX en macOS/Linux.
- **Pruebas:** `tests/core-tests.cpp` (núcleo) y humo extremo a extremo (`smoke.ps1`, `smoke-posix.sh`).
- **Ejemplo:** `examples/simulate_runs.cpp` genera recorridos **sintéticos** con la librería real (semilla fija, salida idéntica). Alimenta el informe ejecutivo de choisys.
- **Amenazas:** `docs/THREAT_MODEL.md`.

## Cómo lo usa el producto

La API de choisys envía las decisiones de cada fase y recibe la confirmación; al completar la fase 3 recibe `measurements` (fase, fila, columna) y los guarda en el historial de la persona. TypeScript no calcula nada del Cubo.

## Pendiente

- Primera compilación y ejecución reales en macOS (`make test smoke`).
- Inferencia: no existe y no se escribe sin una especificación matemática aprobada (`docs/INFERENCE_ARCHITECTURE.md`).
# 9 de octubre de 2026 — workspace por repositorio

- Selección directa de repositorios desde la barra lateral.
- Métricas locales de archivos, líneas, tamaño, lenguajes y capacidades.
- Diagnósticos de solo lectura para API, backend, frontend y Cubo.
- Visualización 3D interactiva con SceneKit.
- Cubo 3×3×3 para cruzar densidad de código, estado Git y capacidad operativa.
- Proyección de usuarios limitada al nombre visible en repos con login y DB.
- Detección de Blender y Ableton Live Lite como estudio creativo local.
- Chat con personalidad inmutable y contexto del repositorio seleccionado (agente renombrado a Daemon).
- Daemon continúa sin escribir código, ejecutar shell ni controlar servicios.

# 9 de octubre de 2026 — control plane, Clod y dirección de arte (rama claude/control-plane)

- Núcleo C++: gate de políticas para herramientas de observación y túneles solo loopback; C ABI 0.2.0.
- Capa Control: puertos, procesos, Tailscale, sondas HTTP/TCP con p50/p95/p99, topología declarada, índice local con huella.
- Agente Daemon con 26 herramientas declaradas, router en español sin tokens y adaptador Claude opcional (solo lectura).
- Clod: Claude dentro de Daemon con memoria compartida, bitácora y buzón para sesiones de Claude.
- Mapa vivo, cubo 3D en el idioma del Cubo de Neo, vistas Sistema, Red y Tecnología (versión y licencia verificables).
- Cube Link: Cubo del Desktop disponible en 127.0.0.1:8765 del Mac por túnel SSH sobre Tailscale.
- Dirección de arte desde kill-aesthetics; arranque renderizado con Blender; SFX generados y sustituibles desde Ableton.
