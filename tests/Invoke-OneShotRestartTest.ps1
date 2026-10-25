# One supervised, non-forced Windows restart to test an OS reboot request.
# A synthetic 75 C input selects the threshold. NEVER heats hardware or loops at startup.
# Does not modify the persistent emergency (shutdown) configuration.
[CmdletBinding()]
param(
    [ValidateSet('Preview','RestartOnce','Status')][string]$Action = 'Preview',
    [ValidatePattern('^[a-zA-Z0-9-]{1,24}$')][string]$TestId = 'trial-1'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'src\Guard.Core.psm1') -Force
$decision=Get-GuardDecision -Temperature 75 -SensorHealthy $true -WarningC 70 -ResumeBelowC 69 -ShutdownC 75
if($decision.State -ne 'Critical' -or $decision.Intent -ne 'Shutdown') {
    throw 'Synthetic 75 C threshold did not produce Critical/Shutdown. No restart.'
}
$dataDirectory=Join-Path $env:LOCALAPPDATA 'uTempGuard'
$testDirectory=Join-Path $dataDirectory 'supervised-restart-tests'
$latch=Join-Path $testDirectory ('restart-'+$TestId+'.json')
if($Action -eq 'Preview') {
    [pscustomobject]@{
        Input='SIMULATED 75 C';State=$decision.State;Intent=$decision.Intent
        ProposedAction='One supervised, ordinary Windows restart WITHOUT -Force'
        Executed=$false;ProductionConfigChanged=$false
        TestId=$TestId
    }
    return
}
if($Action -eq 'Status') {
    [pscustomobject]@{
        TestId=$TestId;PreviouslyRequested=(Test-Path -LiteralPath $latch -PathType Leaf)
        ProductionConfigChanged=$false
        Note='A stored request is NOT proof Windows completed the restart'
    }
    return
}
# Below here: opt-in real one-time restart only. No attempt to make CPU hot.
if(-not [Environment]::UserInteractive -or -not (Test-Path -LiteralPath (Join-Path $env:WINDIR 'System32\shutdown.exe'))) {
    throw 'Interactive Windows user session is required. No reboot requested.'
}
if(Test-Path -LiteralPath $latch) { throw 'This test ID was used already. No reboot requested.' }
$readiness=& (Join-Path $root 'Emergency-Control.ps1') -Action Status
if(-not $readiness.ForcedShutdownArmed -or -not $readiness.MonitorRunning -or
    $readiness.RunningMode -ne 'Live') {
    throw 'Live temperature monitor is not currently armed/healthy. No reboot requested.'
}
$config=Get-Content -LiteralPath (Join-Path $root 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Import-Module (Join-Path $root 'src\Guard.Sensor.psm1') -Force
Import-Module (Join-Path $root 'src\Guard.CpuSummary.psm1') -Force
$context=@{}
$null=Read-AidaSensor -SensorId 'TCPUPKG' -AidaPath $config.AidaPath -MaxAgeSeconds $config.MaxAgeSeconds -Context $context
Start-Sleep -Milliseconds 2500
$sample=Read-AidaSensor -SensorId 'TCPUPKG' -AidaPath $config.AidaPath -MaxAgeSeconds $config.MaxAgeSeconds -Context $context
if(-not $sample.Healthy) { throw ('AIDA64 did not pass freshness verification: '+$sample.Error) }
$summary=Read-GuardCpuTemperatureSummary -VerifiedSample $sample
if($null -eq $summary -or $summary.AvailableCount -ne 15 -or
    $summary.MaxC -ge $config.WarningC) {
    throw 'Fresh package + all 14 cores below warning are required. No reboot requested.'
}
Write-Host ('SIMULATED: 75 C -> {0} -> {1}' -f $decision.State,$decision.Intent)
Write-Host ('ACTUAL CURRENT MAX: {0:N0} C, 15/15 sensors' -f $summary.MaxC)
Write-Warning 'This is a real Windows restart. Save work. Application shutdown may be blocked by unsaved documents. No force flag or automatic restart loop.'
$answer=Read-Host 'To request ONE ordinary restart enter exactly RESTART ONCE'
if($answer -cne 'RESTART ONCE') {
    Write-Output 'Cancelled: no changes.'
    return
}
# Persistent one-time latch prevents repeated reboot after startup or accidental reruns.
[IO.Directory]::CreateDirectory($testDirectory) | Out-Null
$record=[ordered]@{TestId=$TestId;Utc=[datetime]::UtcNow.ToString('o');SimulatedC=75;Command='Restart-Computer (without -Force)';Requested=$true}
$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($record|ConvertTo-Json -Compress))
$file=[IO.File]::Open($latch,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try { $file.Write($bytes,0,$bytes.Length);$file.Flush($true) }
finally { $file.Dispose() }
Write-Output 'One-time marker saved. Requesting an ordinary Windows restart, no -Force.'
try {
    Restart-Computer -ErrorAction Stop
} catch {
    Write-Warning ('Windows restart was not confirmed: '+$_.Exception.Message)
    throw
}
