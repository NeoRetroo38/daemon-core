# Daemon: superficies Apple nativas

La aplicación del Mac usa SwiftUI y el núcleo C++20 compartido. No usa WebView,
JavaScript, motores de choisys duplicados ni servidores nuevos. El puente Swift
consume únicamente la ABI C de `include/daemon/daemon_bridge.h`:

- `daemon_core_version()` devuelve una cadena estática; no se libera.
- `daemon_snapshot_json(repo_path)` devuelve JSON UTF-8 propiedad del llamador.
- `daemon_snapshot_json_many(repo_paths, count)` agrupa rutas explícitas en una
  sola instantánea; no descubre directorios ni redes por su cuenta.
- `daemon_free_string()` libera esa cadena exactamente una vez.

`DaemonKit` decodifica el esquema 1 y presenta estados verificado, no disponible
y no verificado. Un campo nulo nunca se presenta como limpio o conectado. Las
secciones vacías de servicios y agentes no prueban que funcionen. La lectura Git
es local, en segundo plano, al abrir la ventana o pulsar Actualizar; no hay sondeo
periódico ni comandos introducidos por el usuario.

## Mac

Requisitos: macOS 14 o posterior y herramientas Swift/Clang compatibles con
Swift 6. Basta Command Line Tools para compilar esta aplicación; el paquete
SwiftPM declara los mismos seis archivos C++ que el compilador directo.

```sh
swift test --scratch-path build/apple-spm
bash scripts/apple-build-direct.sh # checks with compilers, without SwiftPM/XCTest
bash scripts/apple-build-macos.sh
build/apple/Daemon.app/Contents/MacOS/Daemon --repo /ruta/al/repositorio
```

El resultado local es `build/apple/Daemon.app`, con ejecutable y `Info.plist`.
El bundle incorpora `Assets/Daemon.icns`, derivado del máster PNG versionado,
y puede instalarse localmente en `/Applications/Daemon.app` con firma ad-hoc.
La instalación local inicial puede precargar únicamente rutas seleccionadas;
backups y clones fallidos no deben entrar en el catálogo operativo.
Sin `--repo`, la aplicación usa un catálogo de rutas elegido por el usuario y
persistido en `UserDefaults`. Añadir acepta una ruta o el selector de carpetas;
quitar solo borra la entrada del catálogo y nunca elimina archivos. La
aplicación no presupone que un directorio sea un repositorio. El proceso no instala la aplicación, modifica Git,
configura Tailscale ni abre puertos. Este paquete no incorpora distribución
firmada ni notarización; tampoco cambia permisos de seguridad de macOS.

El empaquetador usa los compiladores directamente por defecto. Con SwiftPM
funcionando, `DAEMON_APPLE_BUILD_DRIVER=swiftpm bash scripts/apple-build-macos.sh`
elige ese constructor. `DAEMON_APPLE_SDK` permite seleccionar un SDK local sin
cambiar la configuración global de Xcode; si existe se prefiere macOS 26.5.

Verificación en este Mac (9 oct 2026): Swift 6.3.3, SDK macOS 26.5, compilación
del núcleo y app completada, checks del puente correctos e `Info.plist`
validado. SwiftPM/XCTest ejecutó 7 pruebas correctamente, incluidas instantáneas
multi-repositorio y catálogo vacío. Falta verificar con el SDK iOS real,
Xcode completo, simulador y dispositivo.

## iPhone/iPad

`DaemonIOS` es una biblioteca SwiftUI que utiliza el mismo `DaemonKit` y núcleo.
`apple/DaemonIOSApp/DaemonIOSApp.swift` aporta la entrada de aplicación. El proyecto
Xcode adyacente consume este paquete local. Requiere Xcode completo, un SDK iOS,
y las credenciales de firma del dueño para instalar en un dispositivo.

El iPhone importa una instantánea JSON seleccionada mediante Archivos. Muestra
su timestamp y avisa que es evidencia histórica, no el estado vivo del Mac.
El botón de control remoto queda deshabilitado: no hay API segura configurada.
El núcleo compilado para iOS excluye la ejecución de procesos y declara el modo
`remote-required`; importar un archivo tampoco puede habilitar controles.

```sh
xcodebuild -project apple/DaemonIOSApp/DaemonIOS.xcodeproj \
  -scheme DaemonIOSApp -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Los tests Swift verifican decodificación, esquema desconocido, conservación de
estados no verificados, controles deshabilitados y propiedad de memoria del
puente C. Una compilación Mac no confirma una compilación iOS, instalación,
firma, sincronización iCloud, conexión remota ni evaluación del motor.
