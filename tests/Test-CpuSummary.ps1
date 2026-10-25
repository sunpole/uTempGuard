# Data-only test. No Registry, sensors, elevated access or shutdown.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot '..\src\Guard.CpuSummary.psm1') -Force
function New-Sensor([string]$Id, [object]$Value) {
    [pscustomobject]@{Id=$Id;Value=$Value}
}
$only=Get-GuardCpuTemperatureSummary -Sensors @((New-Sensor 'TCPUPKG' '42'))
if ($only.MaxC -ne 42 -or $only.HottestId -ne 'TCPUPKG' -or $only.AvailableCount -ne 1 -or $only.ExpectedCount -ne 15) { throw 'Package-only snapshot incorrect' }
$all=@((New-Sensor 'TCPUPKG' '43'))
for ($n=1; $n -le 14; $n++) { $all+=New-Sensor ('TCC-1-' + $n) ([string](35 + $n)) }
$summary=Get-GuardCpuTemperatureSummary -Sensors $all
if ($summary.MaxC -ne 49 -or $summary.HottestId -ne 'TCC-1-14' -or $summary.AvailableCount -ne 15) { throw 'Highest core not selected' }
$invalid=@((New-Sensor 'TCPUPKG' 42),(New-Sensor 'TCC-1-1' '999'),(New-Sensor 'TCC-1-2' 'NaN'),(New-Sensor 'TCC-1-3' '70'))
$r=Get-GuardCpuTemperatureSummary -Sensors $invalid
if ($r.MaxC -ne 70 -or $r.AvailableCount -ne 2 -or @($r.Sensors|Where-Object { $_.State -eq 'Invalid' }).Count -ne 2) { throw 'Invalid reading promoted as valid' }
$duplicate=Get-GuardCpuTemperatureSummary -Sensors @((New-Sensor 'TCPUPKG' 45),(New-Sensor 'TCPUPKG' 100))
if ($null -ne $duplicate) { throw 'Duplicate sensor identity accepted' }
$extra=Get-GuardCpuTemperatureSummary -Sensors @((New-Sensor 'TCPUPKG' 42),(New-Sensor 'TCPU' 100),(New-Sensor 'TGPU1' 105))
if ($extra.MaxC -ne 42) { throw 'Motherboard/GPU temperature included in CPU core maximum' }
Write-Output 'PASS: CPU package + 14 cores, hottest selection, missing, invalid, duplicate and unrelated sensor rejection.'

# Cross-source data consistency checks (no access to the real registry).
$verified=[pscustomobject]@{
    Healthy=$true
    Source='Registry:HKCU\Software\FinalWire\AIDA64\SensorValues'
    SensorId='TCPUPKG'
    TemperatureC=43
    Heartbeat='2026-10-25T10:38:00'
}
$values=@{'Value.STIME'='10:38:00';'Value.SDATE'='2026-10-25';'Value.TCPUPKG'='43'}
for($n=1;$n -le 14;$n++){
    $values['Value.TCC-1-'+$n]=[string](35+$n)
}
$ok=Test-GuardCpuRegistrySnapshot -VerifiedSample $verified -Values $values
if(-not $ok.Healthy -or $ok.Reason -ne 'Valid' -or $ok.Summary.AvailableCount -ne 15 -or $ok.Summary.MaxC -ne 49){
    throw ('Valid complete snapshot rejected: ' + $ok.Reason)
}
$values['Value.STIME']='10:38:01'
$stale=Test-GuardCpuRegistrySnapshot -VerifiedSample $verified -Values $values
if($stale.Healthy -or $stale.Reason -ne 'HeartbeatMismatch'){throw 'Mixed snapshots admitted despite changed clock'}
$values['Value.STIME']='10:38:00'
$values['Value.TCPUPKG']='44'
$changed=Test-GuardCpuRegistrySnapshot -VerifiedSample $verified -Values $values
if($changed.Healthy -or $changed.Reason -ne 'CpuPackageChangedBetweenReads'){throw 'Changed package accepted'}
$values['Value.TCPUPKG']='43'
$values.Remove('Value.TCC-1-14')
$missing=Test-GuardCpuRegistrySnapshot -VerifiedSample $verified -Values $values
if(-not $missing.Healthy -or $missing.Summary.AvailableCount -ne 14){throw 'Missing channel must remain visible, not fabricated'}
$values['Value.TCC-1-14']='NaN'
$invalid=Test-GuardCpuRegistrySnapshot -VerifiedSample $verified -Values $values
if(-not $invalid.Healthy -or $invalid.Summary.AvailableCount -ne 14){throw 'Invalid channel counted as valid'}
Write-Output 'PASS: verified AIDA snapshots, clock/package mismatch, missing and invalid core channel handling.'
