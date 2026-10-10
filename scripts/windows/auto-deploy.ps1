#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ConfigPath, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/deploy-common.ps1"
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
$root = [IO.Path]::GetFullPath($config.root)
[IO.Directory]::CreateDirectory($root) | Out-Null
try { $lock = [IO.File]::Open((Join-Path $root 'deploy.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
catch [IO.IOException] { return } # The OS releases this lock even after a crash.
$servicesByRepo = @{ 'neos-cube' = @('cube'); 'choisys' = @('api', 'web') }
try {
    foreach ($id in @('neos-cube', 'choisys')) {
        $repo = $config.repositories[$id]
        $statePath = Join-Path $root "$id/state.json"
        $state = if (Test-Path $statePath) { Get-Content $statePath -Raw | ConvertFrom-Json -AsHashtable } else { @{deployed=''; release=''; failed=@(); attempting=''} }
        $sha = ''; $phase = 'fetch'
        try {
            Invoke-DeployCommand $config.git @('-C',$repo,'fetch','origin','refs/heads/main:refs/remotes/origin/main') $root | Out-Null
            $sha = (Invoke-DeployCommand $config.git @('-C',$repo,'rev-parse','origin/main') $root).Trim()
            if ($sha -notmatch '^[a-f0-9]{40}$') { throw 'Invalid main commit' }
            if ($sha -eq $state.deployed) { Write-DeployLog $root $id $sha 'main-up-to-date'; continue }
            if ($sha -in $state.failed -or $sha -eq $state.attempting) { Write-DeployLog $root $id $sha 'skipped-failed-or-interrupted'; continue }
            if ($CheckOnly) { Write-DeployLog $root $id $sha 'update-available'; continue }
            if (-not $config.servicesAdopted -or -not $state.deployed -or -not $state.release) { throw 'Services and verified baseline must be adopted before enabling deployment' }
            $previous = $state.release
            $release = Join-Path $root "$id/releases/$sha"
            if (Test-Path $release) { throw 'Candidate path already exists; retained for manual inspection' }
            $state.attempting = $sha
            Save-DeployJson $statePath $state
            $phase = 'checkout'
            Invoke-DeployCommand $config.git @('-C',$repo,'worktree','add','--detach',$release,$sha) $root | Out-Null
            foreach ($phase in @('build','test','database')) {
                Write-DeployLog $root $id $sha "$phase-start"
                Invoke-DeployStep $config $ConfigPath $id $phase $release $previous
                Write-DeployLog $root $id $sha "$phase-ok"
            }
            # Nothing before this point changes a running process or its active release.
            # Each service activates on its own: a failing web must not hold back the API.
            $phase = 'activate'
            if (-not $state.services) { $state.services = @{} }
            $partial = $false
            foreach ($svc in $servicesByRepo[$id]) {
                $svcPrevious = if ($state.services[$svc]) { $state.services[$svc] } else { $previous }
                $step = 'activate'
                try {
                    Invoke-DeployStep $config $ConfigPath $id 'activate' $release $svcPrevious $svc
                    $step = 'verify'
                    Invoke-DeployStep $config $ConfigPath $id 'verify' $release $svcPrevious $svc
                    $state.services[$svc] = $release
                    Write-DeployLog $root $id $sha "deployed-$svc"
                } catch {
                    $partial = $true
                    # Exit 3 from activate: unmanaged listener, nothing was stopped, so nothing to roll back.
                    if ($step -eq 'activate' -and $_.Exception.Message -eq 'Command exit 3') {
                        Write-DeployLog $root $id $sha "skipped-$svc-unmanaged"; continue
                    }
                    Write-DeployLog $root $id $sha "failed-$step-$svc"
                    try {
                        Invoke-DeployStep $config $ConfigPath $id 'rollback' $release $svcPrevious $svc
                        Write-DeployLog $root $id $sha "rollback-ok-$svc"
                    } catch { Write-DeployLog $root $id $sha "ROLLBACK-FAILED-NEEDS-OPERATOR-$svc" }
                }
            }
            # The commit is processed even if a service was left behind; it is not retried.
            $state.deployed = $sha; $state.release = $release; $state.attempting = ''
            Save-DeployJson $statePath $state
            Write-DeployLog $root $id $sha $(if ($partial) { 'deployed-partial' } else { 'deployed' })
        } catch {
            # Do not serialize exception messages or child output: they may contain credentials.
            Write-DeployLog $root $id $sha "failed-$phase"
            if ($sha -and $state.attempting -eq $sha) {
                $state.failed = @(@($state.failed) + @($sha) | Select-Object -Unique)
                $state.attempting = ''
                Save-DeployJson $statePath $state
            }
        }
    }
} finally { $lock.Dispose() }
