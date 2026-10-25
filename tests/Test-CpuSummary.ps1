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
