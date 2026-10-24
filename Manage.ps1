[CmdletBinding()]
param(
    [ValidateSet('Status','Start','Stop','EnableStartup','DisableStartup','Diagnose','OpenConfig','OpenLogs')]
    [string]$Action = 'Status',
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'uTempGuard')
)
$ErrorActionPreference = 'Stop'
$projectPath = [IO.Path]::GetFullPath($PSScriptRoot)
$DataDirectory = [IO.Path]::GetFullPath($DataDirectory)
$statusPath = Join-Path $DataDirectory 'status.json'
$stopPath = Join-Path $DataDirectory 'stop.request'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'uTempGuard.lnk'
$launcherPath = Join-Path $projectPath 'Launch.vbs'
$targetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
$arguments = '"' + $launcherPath + '" "' + $DataDirectory + '"'
$pollSeconds = 2.0
try {
    $managerConfig = Get-Content -LiteralPath (Join-Path $projectPath 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $configuredPoll = [double]$managerConfig.PollSeconds
    if ($configuredPoll -ge 1 -and $configuredPoll -le 30) { $pollSeconds = $configuredPoll }
} catch { }
$freshnessSeconds = [Math]::Max(15.0, 2.0 * $pollSeconds + 5.0)
$startWaitSeconds = [Math]::Max(12.0, $pollSeconds + 5.0)

function Read-GuardStatus {
    if (-not (Test-Path -LiteralPath $statusPath -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return $null }
}
function Test-OwnedStartup {
    if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) { return $false }
    $shell = New-Object -ComObject WScript.Shell
    try {
        $link = $shell.CreateShortcut($shortcutPath)
        return ($link.TargetPath -ieq $targetPath -and $link.Arguments -ceq $arguments -and $link.Description -ceq 'uTempGuard current-user startup')
    } finally { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null }
}
function ConvertTo-GuardUtc {
    param([AllowNull()][object]$Value)
    if ($Value -is [DateTimeOffset]) { return $Value.UtcDateTime }
    if ($Value -is [DateTime]) { return $Value.ToUniversalTime() }
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { throw 'Missing status timestamp.' }
    return [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal).UtcDateTime
}
function Get-StatusAgeSeconds($Status) {
    if ($null -eq $Status) { return $null }
    try { return [Math]::Round(([DateTime]::UtcNow - (ConvertTo-GuardUtc $Status.UpdatedUtc)).TotalSeconds, 1) }
    catch { return $null }
}

switch ($Action) {
    'Status' {
        $status = Read-GuardStatus
        $age = Get-StatusAgeSeconds $status
        [pscustomobject]@{
            AutoStart = (Test-OwnedStartup); DataDirectory = $DataDirectory
            StatusAgeSeconds = $age; HeartbeatFresh = ($null -ne $age -and $age -ge -2 -and $age -le $freshnessSeconds)
            FreshnessLimitSeconds = $freshnessSeconds
            Status = $status
        }
    }
    'Start' {
        $before = Read-GuardStatus
        $age = Get-StatusAgeSeconds $before
        if ($null -ne $before -and $before.Running -eq $true -and $null -ne $age -and $age -ge -2 -and $age -le $freshnessSeconds) {
            [pscustomobject]@{ Started = $false; AlreadyRunning = $true; Status = $before }
            return
        }
        if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) { throw "Launcher not found: $launcherPath" }
        $requestedUtc = [DateTime]::UtcNow
        Start-Process -FilePath $targetPath -ArgumentList $arguments -WindowStyle Hidden | Out-Null
        $deadline = [DateTime]::UtcNow.AddSeconds($startWaitSeconds)
        do {
            Start-Sleep -Milliseconds 400
            $status = Read-GuardStatus
            if ($null -ne $status -and $status.Running -eq $true) {
                try {
                    if ((ConvertTo-GuardUtc $status.UpdatedUtc) -ge $requestedUtc) {
                        [pscustomobject]@{ Started = $true; AlreadyRunning = $false; Status = $status }
                        return
                    }
                } catch { }
            }
        } while ([DateTime]::UtcNow -lt $deadline)
        throw "Start was requested, but no fresh running status appeared within $startWaitSeconds seconds. Inspect $DataDirectory."
    }
    'Stop' {
        [IO.Directory]::CreateDirectory($DataDirectory) | Out-Null
        $before = Read-GuardStatus
        $requestedUtc = [DateTime]::UtcNow
        [IO.File]::WriteAllText($stopPath, $requestedUtc.ToString('o'), (New-Object Text.UTF8Encoding($false)))
        if ($null -eq $before -or $before.Running -ne $true) {
            [pscustomobject]@{ StopRequested = $true; StoppedConfirmed = ($null -ne $before -and $before.Running -eq $false); Message = 'No running status; stop request retained for any active instance.' }
            return
        }
        $deadline = [DateTime]::UtcNow.AddSeconds(12)
        do {
            Start-Sleep -Milliseconds 400
            $status = Read-GuardStatus
            if ($null -ne $status -and $status.Running -eq $false -and $status.State -eq 'Stopped') {
                try {
                    if ((ConvertTo-GuardUtc $status.UpdatedUtc) -ge $requestedUtc) {
                        [pscustomobject]@{ StopRequested = $true; StoppedConfirmed = $true; Status = $status }
                        return
                    }
                } catch { }
            }
        } while ([DateTime]::UtcNow -lt $deadline)
        throw "Stop was requested, but a fresh stopped status was not confirmed within 12 seconds. No process was killed. Inspect $statusPath."
    }
    'EnableStartup' { & (Join-Path $projectPath 'Install.ps1') -NoStart -DataDirectory $DataDirectory }
    'DisableStartup' {
        if (Test-Path -LiteralPath $shortcutPath) {
            if (-not (Test-OwnedStartup)) { throw "Refusing to remove an unrelated shortcut: $shortcutPath" }
            Remove-Item -LiteralPath $shortcutPath -Force
        }
        [pscustomobject]@{ AutoStart = $false; ShortcutPath = $shortcutPath }
    }
    'Diagnose' { & (Join-Path $projectPath 'Diagnose.ps1') -DataDirectory $DataDirectory }
    'OpenConfig' { Start-Process -FilePath (Join-Path $env:WINDIR 'System32\notepad.exe') -ArgumentList ('"' + (Join-Path $projectPath 'config.json') + '"') | Out-Null }
    'OpenLogs' {
        [IO.Directory]::CreateDirectory($DataDirectory) | Out-Null
        Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList ('"' + $DataDirectory + '"') | Out-Null
    }
}
