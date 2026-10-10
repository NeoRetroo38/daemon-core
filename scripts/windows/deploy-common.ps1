# Shared helpers. Never write command output, environment values or exceptions to deploy.log.
function Save-DeployJson([string]$Path, $Value) {
    [IO.Directory]::CreateDirectory((Split-Path $Path)) | Out-Null
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temporary, $Path, $true)
}
function Write-DeployLog([string]$Root, [string]$Repo, [string]$Commit, [string]$Event) {
    $row = @{at=[DateTime]::UtcNow.ToString('o'); repository=$Repo; commit=$Commit; event=$Event}
    [IO.File]::AppendAllText((Join-Path $Root 'deploy.log'), ($row | ConvertTo-Json -Compress) + "`n")
}
function Read-DeploySecrets([string]$Path) {
    $values = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^(DATABASE_URL|CHOISYS_LOCAL_API_TOKEN)=(.*)$') {
            if ($values.ContainsKey($Matches[1])) { throw 'Duplicate secret setting' }
            $values[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
        }
    }
    if (-not $values.DATABASE_URL -or $values.CHOISYS_LOCAL_API_TOKEN -notmatch '^[A-Za-z0-9_-]{32,256}$') { throw 'Missing local credentials' }
    return $values
}
function Invoke-DeployCommand([string]$Exe, [string[]]$Arguments, [string]$Directory,
    [hashtable]$Environment = @{}, [int]$TimeoutSeconds = 900) {
    $info = [Diagnostics.ProcessStartInfo]::new($Exe)
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.WorkingDirectory = $Directory
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    foreach ($arg in $Arguments) { $info.ArgumentList.Add($arg) }
    foreach ($key in @('DATABASE_URL','CHOISYS_LOCAL_API_TOKEN','PGPASSWORD')) { $info.Environment.Remove($key) | Out-Null }
    foreach ($key in $Environment.Keys) { $info.Environment[$key] = [string]$Environment[$key] }
    $process = [Diagnostics.Process]::Start($info)
    try {
        if ($TimeoutSeconds -eq 0) {
            $stdoutDrain = $process.StandardOutput.BaseStream.CopyToAsync([IO.Stream]::Null)
            $stderrDrain = $process.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
            $process.WaitForExit()
            $stdoutDrain.GetAwaiter().GetResult(); $stderrDrain.GetAwaiter().GetResult()
            if ($process.ExitCode -ne 0) { throw "Service exit $($process.ExitCode)" }
            return ''
        }
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true); $process.WaitForExit(); throw 'Command timed out'
        }
        $output = $stdout.GetAwaiter().GetResult(); $null = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "Command exit $($process.ExitCode)" }
        return $output
    } finally { $process.Dispose() }
}
function Invoke-DeployStep($Config, [string]$ConfigPath, [string]$Repo, [string]$Phase, [string]$Release, [string]$Previous, [string]$Service = '') {
    $args = @('-NoProfile','-File',$Config.stepScript,'-ConfigPath',$ConfigPath,'-Repo',$Repo,
        '-Phase',$Phase,'-Release',$Release,'-Previous',$Previous)
    if ($Service) { $args += @('-Service',$Service) }
    Invoke-DeployCommand $Config.powershell $args $Config.root @{} 1800 | Out-Null
}
function Test-DeployHealth([string]$Url, [int]$Expected, [int]$Seconds = 45) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        try { if ((Invoke-WebRequest $Url -SkipHttpErrorCheck -TimeoutSec 3).StatusCode -eq $Expected) { return } } catch { }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Health deadline exceeded'
}
