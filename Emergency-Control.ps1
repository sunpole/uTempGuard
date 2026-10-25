# User-controlled emergency shutdown setup. Never runs shutdown itself.
# Enabling is an explicit local decision, not a side effect of updating source code.
[CmdletBinding()]
param([ValidateSet('Status','Enable','Disable')][string]$Action = 'Status')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = $PSScriptRoot
$configPath = Join-Path $root 'config.json'
$receiptPath = Join-Path $root 'live-approval.json'
$managerPath = Join-Path $root 'Manage.ps1'
$dataPath = Join-Path $env:LOCALAPPDATA 'uTempGuard'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw 'Local config.json is missing. No settings changed.'
}
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
function Set-ConfigProperty {
    param([string]$Name, [object]$Value)
    if ($null -ne $config.PSObject.Properties[$Name]) {
        $config.$Name = $Value
    } else {
        $config | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}
function Save-LocalJson {
    param([string]$Path, [object]$Value)
    $temp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 16), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temp -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    }
}
function Restart-Monitor {
    $managerResult = & $managerPath -Action Status
    if ($null -ne $managerResult.Status -and $managerResult.Status.Running -and $managerResult.HeartbeatFresh) {
        $stopped = & $managerPath -Action Stop
        if (-not $stopped.StoppedConfirmed) { throw 'Stop not confirmed; inspect uTempGuard monitor.' }
    }
    $started = & $managerPath -Action Start
    if (-not ($started.Started -or $started.AlreadyRunning)) { throw 'Monitor restart not confirmed.' }
    Write-Output ('Monitor running. Local Mode: ' + $config.Mode)
}
if ($Action -eq 'Status') {
    $armed = $false
    try {
        if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
            $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $currentHash = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
            $armed = ($config.Mode -eq 'Live' -and $config.EnableForcedShutdown -is [bool] -and $config.EnableForcedShutdown -and
                $receipt.ApprovedByUser -is [bool] -and $receipt.ApprovedByUser -and
                $receipt.SensorValidatedForLive -is [bool] -and $receipt.SensorValidatedForLive -and
                $receipt.ForcedShutdownApproved -is [bool] -and $receipt.ForcedShutdownApproved -and
                $receipt.ConfigSha256 -eq $currentHash)
        }
    } catch { $armed = $false }
    $status = & $managerPath -Action Status
    [pscustomobject]@{
        ConfigurationMode=$config.Mode
        ForcedShutdownArmed=$armed
        MonitorRunning=($status.HeartbeatFresh -and $null -ne $status.Status -and $status.Status.Running)
        RunningMode=$(if($null -ne $status.Status){$status.Status.Mode}else{'Unknown'})
        ApprovedAppCount=@($config.AllowList | Where-Object { $_.Approved -eq $true }).Count
    }
    return
}
if ($Action -eq 'Disable') {
    if (Test-Path -LiteralPath $receiptPath) { Remove-Item -LiteralPath $receiptPath -Force }
    Set-ConfigProperty -Name 'Mode' -Value 'Observe'
    Set-ConfigProperty -Name 'EnableShutdown' -Value $false
    Set-ConfigProperty -Name 'EnableForcedShutdown' -Value $false
    Set-ConfigProperty -Name 'EnableAppClose' -Value $false
    Save-LocalJson -Path $configPath -Value $config
    Restart-Monitor
    return
}
# Enable never invents a new AIDA installation, changes privileges or uses real heat.
if ($config.Mode -ne 'Observe') { throw 'To arm, start from Observe mode. No settings changed.' }
if ([string]$config.SensorId -ne 'TCPUPKG' -or $config.WarningC -ne 70 -or $config.ShutdownC -ne 75) {
    throw 'Expected tested CPU Package and 70/75 thresholds. No settings changed.'
}
$state = & $managerPath -Action Status
if (-not $state.HeartbeatFresh -or $null -eq $state.Status -or -not $state.Status.Running -or
    $state.Status.State -ne 'Normal' -or -not [string]::IsNullOrWhiteSpace([string]$state.Status.SensorError)) {
    throw 'Active, fresh, healthy monitor is required. No settings changed.'
}
Import-Module (Join-Path $root 'src\Guard.Sensor.psm1') -Force
Import-Module (Join-Path $root 'src\Guard.CpuSummary.psm1') -Force
$context = @{}
$first = Read-AidaSensor -SensorId 'TCPUPKG' -AidaPath $config.AidaPath -MaxAgeSeconds $config.MaxAgeSeconds -Context $context
Start-Sleep -Milliseconds 2400
$second = Read-AidaSensor -SensorId 'TCPUPKG' -AidaPath $config.AidaPath -MaxAgeSeconds $config.MaxAgeSeconds -Context $context
if (-not $second.Healthy -or $second.Source -notlike 'Registry:*') {
    throw ('AIDA sensor not independently validated: ' + $second.Error)
}
$summary = Read-GuardCpuTemperatureSummary -VerifiedSample $second
if ($null -eq $summary -or $summary.AvailableCount -ne 15 -or $summary.MaxC -ge $config.WarningC) {
    throw 'All 15 fresh CPU channels must be available and below warning before arming. No settings changed.'
}
Write-Output ('Verified CPU Package and 14 cores; highest reported: {0:N0} C.' -f $summary.MaxC)
Write-Warning 'Enabling automatic forced shutdown at 75 C CAN DESTROY UNSAVED DOCUMENTS. Software cannot guarantee 100% operation.'
$approval = Read-Host 'Type EXACTLY ENABLE FORCE SHUTDOWN to approve this risk'
if ($approval -cne 'ENABLE FORCE SHUTDOWN') {
    Write-Output 'Cancelled. No settings changed.'
    return
}
$backupFolder = Join-Path $dataPath 'emergency-configuration-backups'
[IO.Directory]::CreateDirectory($backupFolder) | Out-Null
$backupPath=Join-Path $backupFolder ('config-' + [guid]::NewGuid().ToString('N') + '.json')
Copy-Item -LiteralPath $configPath -Destination $backupPath -ErrorAction Stop
# Revoke any old approval before changing config.
if (Test-Path -LiteralPath $receiptPath) { Remove-Item -LiteralPath $receiptPath -Force }
Set-ConfigProperty -Name 'Mode' -Value 'Live'
Set-ConfigProperty -Name 'EnableShutdown' -Value $true
Set-ConfigProperty -Name 'EnableForcedShutdown' -Value $true
Set-ConfigProperty -Name 'EnableAppClose' -Value $true
Set-ConfigProperty -Name 'AppCloseScope' -Value 'ApprovedInteractive'
Save-LocalJson -Path $configPath -Value $config
$hash = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
$receipt = [ordered]@{
    ApprovedByUser=$true
    SensorValidatedForLive=$true
    ForcedShutdownApproved=$true
    ConfigSha256=$hash
    ApprovedUtc=[datetime]::UtcNow.ToString('o')
}
Save-LocalJson -Path $receiptPath -Value $receipt
Write-Output 'Emergency permissions written locally; attempting monitor restart.'
Restart-Monitor
Write-Output 'Forced shutdown enabled only while the monitor and AIDA sensors are working. Approved app list may be empty.'
