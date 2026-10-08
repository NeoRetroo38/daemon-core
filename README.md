# daemon-core

Repositorio **privado** con todas las herramientas C++ del Cubo de Neo (scenarys S.L.), hechas por neo, Codex y Claude. Solo el dueño tiene acceso.

> Es una instantánea de trabajo del 8 de octubre de 2026. El motor público sigue viviendo en [`neos-cube`](https://github.com/NeoRetroo38/neos-cube) y el producto en [`choisys`](https://github.com/NeoRetroo38/choisys); aquí se junta todo en un sitio. No hay inferencia: espera una especificación matemática aprobada (`docs/INFERENCE_ARCHITECTURE.md`).

## Qué es cada cosa

| Carpeta / fichero | Qué es | Para qué sirve | Estado |
| --- | --- | --- | --- |
| `src/core/cube.hpp` | **Motor del Cubo**: `Run` (3 fases) y `Session` | Registra selecciones 3×3 por fase, intentos, entradas vacías/inválidas/fuera y salidas. Es la única fuente de la lógica | Probado |
| `src/api/server.cpp` | **Servicio HTTP local** | Expone el motor en `127.0.0.1:8765` con token Bearer, plazos y límites; lo consume la API de choisys. Windows, macOS y Linux | Probado en Windows; Mac/Linux por verificar |
| `src/library/neo_cube_c_api.cpp` + `include/scenarys/neo_cube.h` | **Librería con interfaz C (ABI 1)** | Permite usar el motor desde cualquier lenguaje sin ver el código C++ (DLL, `.so`, `.dylib`, `.a`) | Probado; **de Codex, sin commitear en su origen** |
| `package/manifest.json` | Manifiesto del paquete privado | Versión, ABI y artefactos por plataforma | Borrador |
| `examples/simulate_runs.cpp` | **Simulador de recorridos** | Genera recorridos sintéticos con la librería real (semilla fija) para demos e informes | Probado |
| `experimental/console.cpp` | Consola de pruebas | Probar el motor a mano desde el terminal | Experimental |
| `experimental/gui.cpp` | Interfaz de escritorio (Win32) | Banco de pruebas visual en Windows | Experimental |
| `tests/core-tests.cpp` | Pruebas del núcleo | Comprueban `Run` y `Session` | Pasa |
| `tests/library-tests.cpp` | Pruebas de la librería C | Comprueban el contrato de la interfaz C | Pasa |
| `tests/smoke.ps1`, `tests/smoke-posix.sh` | Prueba de humo del servicio | Arranca el servicio y lo prueba de extremo a extremo | Windows ok; POSIX sin ejecutar en Mac |
| `prototypes/original/` | **Prototipos originales** de Codex | Origen del motor (consola de 3 fases, GUI, tests). Solo referencia histórica | Archivo |
| `Makefile`, `build.ps1`, `run.sh`, `run.ps1` | Compilar y ejecutar | `make tests service library` (macOS/Linux) · `build.ps1 -Target ...` (Windows) | Ver nota |
| `docs/` | Documentación | Contrato de la librería, amenazas, inferencia, traspaso entre agentes | Al día |

## Compilar y probar (resumen)

```sh
# C++17, sin dependencias. macOS/Linux:
make tests library-test

# Windows (MSYS2 g++): compilar a mano
g++ -std=c++17 -Wall -Wextra -Wpedantic tests/core-tests.cpp -o build/core-tests.exe
g++ -std=c++17 -Wall -Wextra -Wpedantic -DSCENARYS_NEO_CUBE_BUILD -Iinclude tests/library-tests.cpp src/library/neo_cube_c_api.cpp -o build/lib-tests.exe
```

Comprobado el 8 oct 2026 en Windows con g++ 16.2: `ALL NEO CUBE TESTS PASSED`, pruebas de la librería correctas, ejemplo y servicio compilan sin avisos. `make` no estaba instalado en ese equipo, así que **los objetivos del Makefile no se ejecutaron**.

## Reglas heredadas

- Sin inferencia inventada; dominio no negativo; resultado determinista.
- Lo que sale del servicio es un DTO público aprobado (`measurements`, `phaseTransitions`).
- Credenciales fuera del repositorio; el servicio solo escucha en loopback. Más en `AGENTS.md`.
- No se instalan ni versionan binarios ni secretos (`.gitignore`).

## Procedencia

- Motor, servicio, tests, ejemplo y docs: `neos-cube` rama `main` (8 oct 2026).
- Librería C, manifiesto, contrato, Makefile y `build.ps1` ampliados: copiados del trabajo de Codex en `codex/home-network` (aún sin commitear allí).
- Prototipos originales: `Documents/Codex/2026-10-04/h/outputs/neo-cube`.
