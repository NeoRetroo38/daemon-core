# Habilita OpenSSH Server en el Desktop SOLO para la tailnet (100.64.0.0/10), con clave y sin contraseña.
# Ejecutar en PowerShell como administrador:
#   .\enable-openssh-tailnet.ps1 -PublicKey "ssh-ed25519 AAAA... neo-mac-cubelink"
# Qué abre: sshd en el puerto 22, aceptando conexiones solo desde direcciones Tailscale.
# Para qué: Cube Link (túnel -L 127.0.0.1:8765 desde el Mac). El Cubo sigue escuchando solo en 127.0.0.1.
# Cómo deshacerlo: Stop-Service sshd; Set-Service sshd -StartupType Disabled; Remove-NetFirewallRule -Name Scenarys-SSH-Tailnet
param([Parameter(Mandatory = $true)][string]$PublicKey)
$ErrorActionPreference = "Stop"

if (-not (Get-WindowsCapability -Online -Name "OpenSSH.Server*" | Where-Object State -eq "Installed")) {
    Add-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" | Out-Null
}
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

# Solo la tailnet: se desactiva la regla genérica y se crea una restringida.
Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Disable-NetFirewallRule
if (-not (Get-NetFirewallRule -Name "Scenarys-SSH-Tailnet" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name "Scenarys-SSH-Tailnet" -DisplayName "SSH solo Tailscale (Scenarys)" -Direction Inbound `
        -Protocol TCP -LocalPort 22 -RemoteAddress "100.64.0.0/10" -Action Allow | Out-Null
}

# Sin contraseñas: solo clave.
$config = "$env:ProgramData\ssh\sshd_config"
$text = Get-Content $config -Raw
if ($text -notmatch "(?m)^PasswordAuthentication no") { Add-Content $config "`nPasswordAuthentication no" }
if ($text -notmatch "(?m)^GatewayPorts no") { Add-Content $config "GatewayPorts no" }

# Usuarios administradores leen administrators_authorized_keys.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$keys = if ($isAdmin) { "$env:ProgramData\ssh\administrators_authorized_keys" } else { "$env:USERPROFILE\.ssh\authorized_keys" }
New-Item -ItemType File -Force -Path $keys | Out-Null
if (-not (Select-String -Path $keys -SimpleMatch $PublicKey -Quiet)) { Add-Content -Path $keys -Value $PublicKey }
if ($isAdmin) { icacls $keys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null }

Restart-Service sshd
Write-Host "OpenSSH listo solo para la tailnet. El Cubo debe seguir en 127.0.0.1:8765."
