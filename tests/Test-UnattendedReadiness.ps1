# Read-only unattended-monitor readiness checks. Windows PowerShell 5.1.
# Does not enable Live, alter configuration, start apps, or shut down Windows.
[CmdletBinding()]
param(
    [string]$ProjectPath = (Split-Path $PSScriptRoot -Parent),
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'uTempGuard')
)
$ErrorActionPreference = 'Stop'
$checks = New-Object 'System.Collections.Generic.List[object]'
function Add-Check {
    param([string]$Name,[bool]$Passed,[string]$Detail)
    $checks.Add([pscustomobject]@{Check=$Name;Passed=$Passed;Detail=$Detail})
}
try {
    $configPath=Join-Path $ProjectPath 'config.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        Add-Check 'ConfigPresent' $false 'Missing local config.json (never publish it)'
    } else {
        $config=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $configOk=($null -ne $config -and $config.SensorId -eq 'TCPUPKG' -and $config.Mode -in @('Observe','Live'))
        Add-Check 'ConfigPrimarySensor' $configOk ('Sensor='+[string]$config.SensorId+', Mode='+[string]$config.Mode)
        $poll=[double]$config.PollSeconds
        Add-Check 'PollInterval' ($poll -ge 1 -and $poll -le 5) ('Seconds='+$poll)
    }
    $statusPath=Join-Path $DataDirectory 'status.json'
    if (-not (Test-Path -LiteralPath $statusPath -PathType Leaf)) {
        Add-Check 'MonitorActive' $false 'status.json missing'
    } else {
        try {
            $status=Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $utc=[DateTimeOffset]::Parse([string]$status.UpdatedUtc,[Globalization.CultureInfo]::InvariantCulture).UtcDateTime
            $age=([datetime]::UtcNow-$utc).TotalSeconds
            $fresh=[bool]$status.Running -and $age -ge -2 -and $age -le 15 -and $status.State -ne 'SensorFault' -and
                $null -ne $status.TemperatureC -and [string]::IsNullOrWhiteSpace([string]$status.SensorError)
            Add-Check 'MonitorActive' $fresh ('Fresh='+$fresh+', State='+[string]$status.State+', AgeSeconds='+[math]::Round($age,1))
        } catch { Add-Check 'MonitorActive' $false 'Invalid monitor status or timestamp' }
    }
    $startup=Join-Path ([Environment]::GetFolderPath('Startup')) 'uTempGuard.lnk'
    Add-Check 'CurrentUserStartup' (Test-Path -LiteralPath $startup -PathType Leaf) 'Current-user Startup shortcut presence only; reboot test still needed'
    try {
        $aida=@(Get-Process -Name 'aida64' -ErrorAction SilentlyContinue)
        Add-Check 'AIDAProcessRunning' ($aida.Count -gt 0) ('Instances='+$aida.Count)
        foreach($process in $aida){$process.Dispose()}
    } catch { Add-Check 'AIDAProcessRunning' $false 'Unable to verify producer process' }
    try {
        $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\FinalWire\AIDA64\SensorValues',$false)
        if ($null -eq $key) {
            Add-Check 'AIDARegistryExport' $false 'AIDA registry export missing'
        } else {
            try {
                $names=@($key.GetValueNames())
                $hasPackage=('Value.TCPUPKG' -in $names)
                $hasClock=('Value.STIME' -in $names)
                $cores=@($names|Where-Object {$_ -match '^Value\.TCC-1-(?:[1-9]|1[0-4])$'}).Count
                Add-Check 'AIDARegistryExport' ($hasPackage -and $hasClock) ('Package='+$hasPackage+', Clock='+$hasClock+', CoreChannels='+$cores+'/14')
            } finally {$key.Dispose()}
        }
    } catch { Add-Check 'AIDARegistryExport' $false 'Unable to inspect AIDA registry export' }
    try {
        $task=Get-ScheduledTask -TaskName 'uTempGuard-AIDA64-user' -ErrorAction Stop
        $isEnabled=($task.State -ne 'Disabled')
        Add-Check 'AIDAStartupTask' $isEnabled ('State='+[string]$task.State+'; fresh-login startup still unverified')
    } catch { Add-Check 'AIDAStartupTask' $false 'Scheduled task missing or inaccessible' }
    Add-Check 'UnattendedRebootVerified' $false 'Cannot verify unattended reboot/autostart without a supervised restart'
} catch {
    Add-Check 'PreflightExecution' $false $_.Exception.GetType().Name
}
$checks | Format-Table -AutoSize -Wrap
$failed=@($checks | Where-Object { -not $_.Passed })
Write-Output ('READINESS: {0}/{1} checks passed. No shutdown or system modifications performed.' -f ($checks.Count-$failed.Count),$checks.Count)
if($failed.Count -gt 0){exit 2}
