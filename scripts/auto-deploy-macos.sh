#!/bin/bash
# Despliegue al fusionar: si origin/main cambió, prueba, compila e instala Daemon.app.
# Compila en un clon propio fuera de ~/Desktop: launchd no tiene permiso (TCC) para leer el Escritorio,
# y así nunca toca la copia de trabajo ni las ramas en curso.
# Si algo falla no instala nada y avisa. Lo lanza launchd cada 2 min (com.scenarys.daemon-deploy).
set -uo pipefail

remote="${DAEMON_REMOTE:-https://github.com/NeoRetroo38/daemon-core.git}"
state="$HOME/Library/Application Support/Daemon/deploy"
src="$state/src"
log="$HOME/.choisys-logs/deploy.log"
mkdir -p "$state" "$(dirname "$log")"

say() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$1" >> "$log"; }
notify() { osascript -e "display notification \"$1\" with title \"Daemon\"" >/dev/null 2>&1 || true; }

# Una sola ejecución a la vez.
mkdir "$state/lock" 2>/dev/null || exit 0
trap 'rmdir "$state/lock"' EXIT

# Un worktree antiguo apunta al repo del Escritorio, que launchd no puede leer: se sustituye por un clon.
[ -f "$src/.git" ] && rm -rf "$src"
[ -d "$src/.git" ] || git clone -q "$remote" "$src" 2>>"$log" || { say "clone falló"; exit 0; }
git -C "$src" fetch -q origin main 2>>"$log" || { say "fetch falló"; exit 0; }
target="$(git -C "$src" rev-parse origin/main)"
deployed="$(cat "$state/deployed" 2>/dev/null || true)"
[ "$target" = "$deployed" ] && exit 0
# Un commit que ya falló no se reintenta en bucle; se reintenta cuando llegue otro.
[ "$target" = "$(cat "$state/failed" 2>/dev/null || true)" ] && exit 0

short="${target:0:7}"
say "main $short: desplegando"
git -C "$src" checkout -q --force --detach "$target"

run() { (cd "$src" && "$@") >> "$log" 2>&1; }
if run swift test && run bash scripts/apple-build-macos.sh && run bash scripts/install-daemon-macos.sh; then
    echo "$target" > "$state/deployed"
    rm -f "$state/failed"
    # launchd ejecuta esta copia: se actualiza con cada despliegue, sin depender de la rama abierta en el repo.
    cp "$src/scripts/auto-deploy-macos.sh" "$state/auto-deploy.sh"
    say "main $short: instalado"
    if pgrep -xq Daemon; then
        osascript -e 'quit app "Daemon"' >/dev/null 2>&1; sleep 2; open -a /Applications/Daemon.app
    fi
    notify "Actualizado a $short"
else
    echo "$target" > "$state/failed"
    say "main $short: FALLÓ, se mantiene la versión instalada"
    notify "No se pudo instalar $short. Detalle en ~/.choisys-logs/deploy.log"
fi
