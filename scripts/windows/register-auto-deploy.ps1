#Requires -Version 7.0
# Run only after the owner approves adopting the existing manual services.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ConfigPath, [switch]$RegisterServices, [switch]$EnableWatcher)
$ErrorActionPreference = 'Stop'
$c = Get-Content $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
if (-not $c.servicesAdopted) { throw 'Owner-approved service adoption must be recorded in the local config' }
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$serviceSettings = New-ScheduledTaskSettingsSet -Hidden -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
if ($RegisterServices) {
    foreach ($name in @('api','web','cube')) {
        $task = $c.services[$name].task
        if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) { throw "Task already exists: $task; inspect instead of overwriting" }
        $action = New-ScheduledTaskAction -Execute $c.powershell -Argument "-NoProfile -WindowStyle Hidden -File `"$PSScriptRoot\run-deploy-service.ps1`" -ConfigPath `"$ConfigPath`" -Service $name" -WorkingDirectory $c.root
        Register-ScheduledTask -TaskName $task -Action $action -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $user) -Principal $principal -Settings $serviceSettings -Description "Scenarys $name from verified deployment release" | Out-Null
    }
}
if ($EnableWatcher) {
    foreach ($id in @('choisys','neos-cube')) {
        $state = Get-Content (Join-Path $c.root "$id/state.json") -Raw | ConvertFrom-Json
        if ($state.deployed -notmatch '^[a-f0-9]{40}$' -or -not (Test-Path $state.release)) { throw 'Verified deployment baseline missing' }
    }
    if (Get-ScheduledTask -TaskName 'Scenarys-PC-AutoDeploy' -ErrorAction SilentlyContinue) { throw 'Deployment task already exists; inspect instead of overwriting' }
    $action = New-ScheduledTaskAction -Execute $c.powershell -Argument "-NoProfile -WindowStyle Hidden -File `"$PSScriptRoot\auto-deploy.ps1`" -ConfigPath `"$ConfigPath`"" -WorkingDirectory $c.root
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 2)
    # Individual stages enforce timeouts; do not kill an entire rollout during activation.
    $settings = New-ScheduledTaskSettingsSet -Hidden -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName 'Scenarys-PC-AutoDeploy' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Fetch main every two minutes; verified releases only' | Out-Null
}
