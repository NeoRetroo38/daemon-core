#Requires -Version 7.0
param([Parameter(Mandatory)][string]$ConfigPath,
    [ValidateSet('choisys','neos-cube')][string]$Repo,
    [ValidateSet('build','test','database','activate','verify','rollback')][string]$Phase,
    [Parameter(Mandatory)][string]$Release, [string]$Previous,
    [ValidateSet('api','web','cube')][string]$Service)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/deploy-common.ps1"
$c = Get-Content $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
$services = if ($Service) { @($Service) } elseif ($Repo -eq 'choisys') { @('api','web') } else { @('cube') }
$npm = @($c.npmCli)
$buildEnv = @{PATH="$(Split-Path $c.node);$env:PATH";CI='1';EXPO_NO_TELEMETRY='1';GIT_CONFIG_COUNT='2';
    GIT_CONFIG_KEY_0='url.https://github.com/.insteadOf';GIT_CONFIG_VALUE_0='ssh://git@github.com/';
    GIT_CONFIG_KEY_1='url.https://github.com/.insteadOf';GIT_CONFIG_VALUE_1='git@github.com:'}
switch ($Phase) {
    'build' {
        if ($Repo -eq 'choisys') {
            Invoke-DeployCommand $c.node ($npm + @('ci')) $Release $buildEnv | Out-Null
            Invoke-DeployCommand $c.node ($npm + @('run','build')) $Release $buildEnv | Out-Null
        } else { Invoke-DeployCommand $c.powershell @('-NoProfile','-File',"$Release/build.ps1",'-Target','service','-Compiler',$c.compiler) $Release | Out-Null }
    }
    'test' {
        if ($Repo -eq 'choisys') {
            Invoke-DeployCommand $c.node ($npm + @('run','check')) $Release $buildEnv | Out-Null
            Invoke-DeployCommand $c.node ($npm + @('test')) $Release $buildEnv | Out-Null
            # Compile the web before switching the Metro task; Pages publishing is not part of deployment.
            $buildEnv.EXPO_PUBLIC_API_URL = $c.apiOrigin
            Invoke-DeployCommand $c.node @("$Release/node_modules/expo/bin/cli",'export','--platform','web','--output-dir','dist-deploy-check') "$Release/apps/mobile" $buildEnv | Out-Null
        } else { Invoke-DeployCommand $c.powershell @('-NoProfile','-File',"$Release/build.ps1",'-Target','tests','-Compiler',$c.compiler) $Release | Out-Null }
    }
    'database' {
        if ($Repo -eq 'choisys') {
            $secrets = Read-DeploySecrets $c.secretFile
            $dbEnv = @{DATABASE_URL=$secrets.DATABASE_URL;PATH=$buildEnv.PATH}
            Invoke-DeployCommand $c.node @("$PSScriptRoot/deploy-database.mjs",$Release,'preflight') $Release $dbEnv | Out-Null
            Invoke-DeployCommand $c.node ($npm + @('run','db:migrate','--workspace','apps/api')) $Release $dbEnv | Out-Null
            Invoke-DeployCommand $c.node ($npm + @('run','db:seed','--workspace','apps/api')) $Release $dbEnv | Out-Null
            Invoke-DeployCommand $c.node @("$PSScriptRoot/deploy-database.mjs",$Release,'verify') $Release $dbEnv | Out-Null
        }
    }
    { $_ -in @('activate','rollback') } {
        $target = if ($Phase -eq 'rollback') { $Previous } else { $Release }
        if (-not (Test-Path $target)) { throw 'Release unavailable' }
        # Refuse an unmanaged listener rather than killing somebody else's process.
        foreach ($name in $services) {
            $task = Get-ScheduledTask -TaskName $c.services[$name].task
            # Exit 3 = nothing was touched; the caller skips this service instead of rolling back.
            if ($task.State -ne 'Running' -and (Get-NetTCPConnection -State Listen -LocalPort $c.services[$name].port -ErrorAction SilentlyContinue)) { exit 3 }
        }
        foreach ($name in $services) {
            $wasRunning = (Get-ScheduledTask -TaskName $c.services[$name].task).State -eq 'Running'
            Stop-ScheduledTask -TaskName $c.services[$name].task
            # Stopping the task ends only its PowerShell wrapper; the node child keeps the port.
            if ($wasRunning) {
                Get-NetTCPConnection -State Listen -LocalPort $c.services[$name].port -ErrorAction SilentlyContinue |
                    ForEach-Object { taskkill /T /F /PID $_.OwningProcess | Out-Null }
            }
        }
        foreach ($name in $services) {
            $deadline = [DateTime]::UtcNow.AddSeconds(20)
            while (Get-NetTCPConnection -State Listen -LocalPort $c.services[$name].port -ErrorAction SilentlyContinue) {
                if ([DateTime]::UtcNow -ge $deadline) { throw 'Task did not release its port' }; Start-Sleep -Milliseconds 250
            }
        }
        # One active release per service, so API and web can sit on different commits.
        foreach ($name in $services) { Save-DeployJson (Join-Path $c.root "$Repo/active-$name.json") @{release=$target} }
        foreach ($name in $services) { Start-ScheduledTask -TaskName $c.services[$name].task }
        if ($Phase -eq 'rollback') {
            $verifyArgs = @{ConfigPath=$ConfigPath; Repo=$Repo; Phase='verify'; Release=$target}
            if ($Service) { $verifyArgs.Service = $Service }
            & $PSCommandPath @verifyArgs
        }
    }
    'verify' {
        foreach ($name in $services) {
            $s = $c.services[$name]
            Test-DeployHealth $s.health $s.status
            $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $s.port)
            if ($listeners.Count -ne 1 -or $listeners[0].LocalAddress -ne '127.0.0.1') { throw 'Unsafe listener' }
        }
        if ($Repo -eq 'choisys') {
            if ('api' -in $services) { Test-DeployHealth "$($c.apiOrigin)/health" 200 }
            if ('web' -in $services) { Test-DeployHealth $c.webOrigin 200 }
        } else {
            # The upstream Windows smoke intentionally uses the real loopback port and local secret file.
            Invoke-DeployCommand $c.powershell @('-NoProfile','-File',"$Release/tests/smoke.ps1") $Release | Out-Null
        }
    }
}
