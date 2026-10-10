#Requires -Version 7.0
param([Parameter(Mandatory)][string]$ConfigPath, [ValidateSet('api','web','cube')][string]$Service)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/deploy-common.ps1"
$c = Get-Content $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
$id = if ($Service -eq 'cube') { 'neos-cube' } else { 'choisys' }
$active = Get-Content (Join-Path $c.root "$id/active.json") -Raw | ConvertFrom-Json
$release = $active.release
$environment = @{PATH="$(Split-Path $c.node);$env:PATH"}
try {
    if ($Service -eq 'cube') {
        $secrets = Read-DeploySecrets $c.secretFile
        $environment.CHOISYS_LOCAL_API_TOKEN = $secrets.CHOISYS_LOCAL_API_TOKEN
        $environment.CHOISYS_LOCAL_LOG_DIR = Join-Path $c.root 'engine-logs'
        Invoke-DeployCommand "$release/build/neo-cube-service.exe" @() $release $environment 0 | Out-Null
    } elseif ($Service -eq 'api') {
        $secrets = Read-DeploySecrets $c.secretFile
        $environment.DATABASE_URL = $secrets.DATABASE_URL
        $environment.CHOISYS_LOCAL_API_TOKEN = $secrets.CHOISYS_LOCAL_API_TOKEN
        $environment.API_HOST = '127.0.0.1'; $environment.PORT = '3000'
        $environment.API_ALLOWED_ORIGINS = $c.allowedOrigins -join ','
        $environment.CHOISYS_ROLE_REQUESTS = if ($c.roleRequests) { '1' } else { '0' }
        Invoke-DeployCommand $c.node @('dist/index.js') "$release/apps/api" $environment 0 | Out-Null
    } else {
        # The web process receives no database connection or engine token.
        $environment.EXPO_PUBLIC_API_URL = $c.apiOrigin
        $environment.EXPO_NO_TELEMETRY = '1'; $environment.CI = '1'; $environment.BROWSER = 'none'
        Invoke-DeployCommand $c.node @('--dns-result-order=ipv4first',"$release/node_modules/expo/bin/cli",'start','--web','--localhost','--port','8081') "$release/apps/mobile" $environment 0 | Out-Null
    }
} catch { Write-DeployLog $c.root $id '' "service-$Service-exited"; exit 1 }
