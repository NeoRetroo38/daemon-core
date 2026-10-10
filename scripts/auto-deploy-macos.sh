#!/bin/bash
# Despliegue al fusionar: si origin/main cambió, prueba, compila e instala Daemon.app.
# Compila en un worktree aparte: nunca toca la copia de trabajo ni las ramas en curso.
# Si algo falla no instala nada y avisa. Lo lanza launchd cada 2 min (com.scenarys.daemon-deploy).
set -uo pipefail

repo="${DAEMON_REPO:-$HOME/Desktop/scenarys/daemon-core}"
state="$HOME/Library/Application Support/Daemon/deploy"
src="$state/src"
log="$HOME/.choisys-logs/deploy.log"
mkdir -p "$state" "$(dirname "$log")"

say() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$1" >> "$log"; }
notify() { osascript -e "display notification \"$1\" with title \"Daemon\"" >/dev/null 2>&1 || true; }

# Una sola ejecución a la vez.
mkdir "$state/lock" 2>/dev/null || exit 0
trap 'rmdir "$state/lock"' EXIT

git -C "$repo" fetch -q origin main || { say "fetch falló"; exit 0; }
target="$(git -C "$repo" rev-parse origin/main)"
deployed="$(cat "$state/deployed" 2>/dev/null || true)"
[ "$target" = "$deployed" ] && exit 0
# Un commit que ya falló no se reintenta en bucle; se reintenta cuando llegue otro.
[ "$target" = "$(cat "$state/failed" 2>/dev/null || true)" ] && exit 0

short="${target:0:7}"
say "main $short: desplegando"
if [ -d "$src" ]; then
    git -C "$src" checkout -q --detach "$target"
else
    git -C "$repo" worktree add -q --detach "$src" "$target"
fi

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
