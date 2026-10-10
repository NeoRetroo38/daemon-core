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
try {
    foreach ($id in @('neos-cube', 'choisys')) {
        $repo = $config.repositories[$id]
        $statePath = Join-Path $root "$id/state.json"
        $state = if (Test-Path $statePath) { Get-Content $statePath -Raw | ConvertFrom-Json -AsHashtable } else { @{deployed=''; release=''; failed=@(); attempting=''} }
        $sha = ''; $phase = 'fetch'; $activating = $false
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
            $phase = 'activate'; $activating = $true
            Invoke-DeployStep $config $ConfigPath $id 'activate' $release $previous
            $phase = 'verify'
            Invoke-DeployStep $config $ConfigPath $id 'verify' $release $previous
            $state.deployed = $sha; $state.release = $release; $state.attempting = ''
            Save-DeployJson $statePath $state
            Write-DeployLog $root $id $sha 'deployed'
        } catch {
            # Do not serialize exception messages or child output: they may contain credentials.
            Write-DeployLog $root $id $sha "failed-$phase"
            if ($sha -and $state.attempting -eq $sha) {
                $state.failed = @($state.failed) + @($sha) | Select-Object -Unique
                $state.attempting = ''
                Save-DeployJson $statePath $state
            }
            if ($activating) {
                try {
                    Invoke-DeployStep $config $ConfigPath $id 'rollback' $release $previous
                    Write-DeployLog $root $id $sha 'rollback-ok'
                } catch { Write-DeployLog $root $id $sha 'ROLLBACK-FAILED-NEEDS-OPERATOR' }
            }
        }
    }
} finally { $lock.Dispose() }
