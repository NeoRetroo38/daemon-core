#!/bin/bash
# Instala build/apple/Daemon.app en /Applications conservando la versión anterior.
# No usa sudo. Copia de seguridad: ~/Library/Application Support/Daemon/backups (se guardan 3).
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
source_app="$repo_root/build/apple/Daemon.app"
target="/Applications/Daemon.app"
backups="$HOME/Library/Application Support/Daemon/backups"

[ -d "$source_app" ] || { printf '%s\n' "No existe $source_app. Ejecuta antes scripts/apple-build-macos.sh." >&2; exit 1; }
plutil -lint "$source_app/Contents/Info.plist" >/dev/null
codesign --force --deep --sign - "$source_app"
codesign --verify --deep "$source_app"

mkdir -p "$backups"
if [ -d "$target" ]; then
    stamp="$(date +%Y%m%d-%H%M%S)"
    ditto "$target" "$backups/Daemon-$stamp.app"
    printf 'Copia de la versión anterior: %s\n' "$backups/Daemon-$stamp.app"
fi
ditto "$source_app" "$target.incoming"
if [ -d "$target" ]; then mv "$target" "$target.previous"; fi
mv "$target.incoming" "$target"
# La versión anterior ya está copiada en backups; se retira la del sitio.
if [ -d "$target.previous" ]; then rm -rf "$target.previous"; fi
# Solo se conservan las 3 copias más recientes.
ls -1dt "$backups"/Daemon-*.app 2>/dev/null | tail -n +4 | while read -r old; do rm -rf "$old"; done
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target" >/dev/null 2>&1 || true
printf 'Instalado: %s (%s)\n' "$target" "$(defaults read "$target/Contents/Info.plist" CFBundleShortVersionString)"
