#!/bin/bash
# Cube Link: publica el Cubo de Neo del Desktop en 127.0.0.1:8765 de ESTE Mac mediante un túnel SSH
# sobre Tailscale, como servicio permanente (LaunchAgent). Así cualquier programa local (choisys API,
# scripts, Daemon…) usa http://127.0.0.1:8765 sin exponer el Cubo en la LAN ni en la tailnet.
#
# Qué abre: ssh (este Mac) escucha SOLO en 127.0.0.1:8765 → Desktop 127.0.0.1:8765, cifrado, por la tailnet.
# Quién consume: programas de este Mac. Cómo cerrarlo: ./cube-link.command --off
# Requisitos: OpenSSH Server en el Desktop (daemon-core/scripts/windows/enable-openssh-tailnet.ps1) y tu clave autorizada.
set -euo pipefail

LABEL="com.scenarys.cubelink"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
TOPOLOGY="$HOME/Library/Application Support/Daemon/topology.json"
TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
fail() { printf '\n\033[31m%s\033[0m\n' "$1"; read -r -p 'Pulsa Enter para cerrar.'; exit 1; }

if [ "${1:-}" = "--off" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  say "Cube Link apagado. 127.0.0.1:8765 queda libre."; exit 0
fi

say "Cube Link · Cubo del Desktop en el loopback de este Mac"
DESKTOP="${SCENARYS_PC:-desktop-dgjsrgv}"
USER_PC=""
if [ -f "$TOPOLOGY" ]; then
  USER_PC="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("desktopSSHUser") or "")' "$TOPOLOGY" 2>/dev/null || true)"
fi
if [ -z "$USER_PC" ]; then
  read -r -p "Usuario de Windows en el Desktop (p. ej. Admin): " USER_PC
  [ -n "$USER_PC" ] || fail "Necesito el usuario del Desktop."
  if [ -f "$TOPOLOGY" ]; then
    /usr/bin/python3 - "$TOPOLOGY" "$USER_PC" <<'PY'
import json, sys
path, user = sys.argv[1], sys.argv[2]
data = json.load(open(path))
data["desktopSSHUser"] = user
json.dump(data, open(path, "w"), indent=2, sort_keys=True)
PY
    echo "  Guardado desktopSSHUser en topology.json"
  fi
fi

[ -x "$TS" ] || fail "No encuentro Tailscale.app."
PC_IP="$(TERM=dumb "$TS" status --json 2>/dev/null | /usr/bin/python3 -c '
import json,sys
want=sys.argv[1].lower()
d=json.load(sys.stdin)
for p in (d.get("Peer") or {}).values():
    if p.get("HostName","").lower()==want or p.get("DNSName","").lower().startswith(want+"."):
        print(next((ip for ip in p.get("TailscaleIPs",[]) if "." in ip),"")); break' "$DESKTOP")"
[ -n "$PC_IP" ] || fail "No veo $DESKTOP en la tailnet. ¿Está encendido y con Tailscale conectado?"
echo "  Desktop en la tailnet: $PC_IP"

KEY="$HOME/.ssh/id_ed25519_cubelink"
if [ ! -f "$KEY" ]; then KEY="$HOME/.ssh/id_ed25519"; fi
if [ ! -f "$KEY" ]; then
  say "Creando tu clave SSH (ed25519)…"
  ssh-keygen -t ed25519 -N "" -f "$KEY" -C "neo-mac-cubelink" >/dev/null
fi
echo "  Clave pública (pégala en el Desktop si aún no está autorizada):"
echo "  $(cat "$KEY.pub")"

say "Probando SSH sin contraseña…"
if ! ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new "$USER_PC@$PC_IP" exit 2>/dev/null; then
  fail "SSH no entra todavía. En el Desktop, como administrador: daemon-core/scripts/windows/enable-openssh-tailnet.ps1 -PublicKey '<la clave de arriba>'"
fi
if lsof -nP -iTCP:8765 -sTCP:LISTEN >/dev/null 2>&1; then
  fail "127.0.0.1:8765 ya está ocupado en este Mac (¿un Cubo local o un túnel abierto?). Ciérralo y vuelve a abrir este archivo."
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/ssh</string><string>-N</string>
    <string>-i</string><string>$KEY</string><string>-o</string><string>IdentitiesOnly=yes</string>
    <string>-L</string><string>127.0.0.1:8765:127.0.0.1:8765</string>
    <string>-o</string><string>ExitOnForwardFailure=yes</string>
    <string>-o</string><string>BatchMode=yes</string>
    <string>-o</string><string>ServerAliveInterval=20</string>
    <string>-o</string><string>ServerAliveCountMax=3</string>
    <string>-o</string><string>ConnectTimeout=8</string>
    <string>$USER_PC@$PC_IP</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/cubelink.log</string>
</dict></plist>
PL
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
sleep 3
CODE="$(curl -s -o /dev/null -m 4 -w '%{http_code}' http://127.0.0.1:8765/health || true)"
case "$CODE" in
  200|401) say "Listo: el Cubo del Desktop responde en http://127.0.0.1:8765 (HTTP $CODE; 401 = vivo y exige token)." ;;
  *) say "El túnel está levantado pero el Cubo no respondió (HTTP ${CODE:-sin respuesta}). ¿Está arrancado en el Desktop?" ;;
esac
echo "  Los programas locales usan http://127.0.0.1:8765 con el token del Cubo del Desktop (CHOISYS_LOCAL_API_TOKEN)."
echo "  Apagar: ./cube-link.command --off"
read -r -p 'Pulsa Enter para cerrar.'
