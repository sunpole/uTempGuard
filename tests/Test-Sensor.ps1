[CmdletBinding()]
param([string]$ReportPath = '')
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\sensor-tests.json' }
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Guard.Sensor.psm1') -Force
$script:results = New-Object 'System.Collections.Generic.List[object]'
function Assert-Equal {
    param([string]$Name, [AllowNull()][object]$Actual, [AllowNull()][object]$Expected)
    $passed = ($Actual -eq $Expected)
    if ($null -eq $Actual -and $null -eq $Expected) { $passed = $true }
    $script:results.Add([pscustomobject]@{ Name = $Name; Passed = [bool]$passed; Actual = $Actual; Expected = $Expected })
}
function New-Snapshot {
    param([string]$Time = '12:00:00', [object]$Temperature = '42', [string]$Date = '10/25/2026')
    $items = @([pscustomobject]@{ Id = 'TCPUPKG'; Label = 'CPU Package'; Value = $Temperature }, [pscustomobject]@{ Id = 'STIME'; Label = 'Time'; Value = $Time })
    if ($Date) { $items += [pscustomobject]@{ Id = 'SDATE'; Label = 'Date'; Value = $Date } }
    return $items
}
function Test-Pair {
    param([object[]]$Second = (New-Snapshot -Time '12:00:01'), [datetime]$Now = [datetime]'2026-10-25T12:00:01', [double]$Monotonic = 101, [bool]$Producer = $true)
    $context = @{}
    $null = Test-AidaSnapshot -Sensors (New-Snapshot) -ProducerRunning $true -Now ([datetime]'2026-10-25T12:00:00') -MonotonicSeconds 100 -Context $context
    return Test-AidaSnapshot -Sensors $Second -ProducerRunning $Producer -Now $Now -MonotonicSeconds $Monotonic -Context $context
}
$xml = '<temp><id>TCPUPKG</id><label>CPU Package</label><value>42</value></temp><sys><id>STIME</id><label>Time</label><value>12:00:00</value></sys>'
$parsed = @(ConvertFrom-AidaSensorXml $xml)
Assert-Equal 'fragment parser count' $parsed.Count 2
Assert-Equal 'fragment id preserved' $parsed[0].Id 'TCPUPKG'
Assert-Equal 'fragment value preserved' $parsed[0].Value '42'
Assert-Equal 'root wrapped accepted' @(ConvertFrom-AidaSensorXml ('<AIDA64>' + $xml + '</AIDA64>')).Count 2
foreach ($badXml in @('', '<temp>', '<temp><id>TCPUPKG</id><value>42</value></temp>', ($xml + $xml), '<!DOCTYPE doc [<!ENTITY x SYSTEM "file:///C:/Windows/win.ini">]><temp><id>TCPUPKG</id><label>x</label><value>&x;</value></temp>', '<temp><id>TCPUPKG</id><label>x</label><value><nested>42</nested></value></temp>')) {
    $rejected = $false
    try { $null = ConvertFrom-AidaSensorXml $badXml } catch { $rejected = $true }
    Assert-Equal 'malformed/duplicate/DTD XML rejected' $rejected $true
}
$context = @{}
$first = Test-AidaSnapshot -Sensors (New-Snapshot) -ProducerRunning $true -Now ([datetime]'2026-10-25T12:00:00') -MonotonicSeconds 100 -Context $context
Assert-Equal 'first snapshot waits' $first.Healthy $false
Assert-Equal 'first snapshot no actionable temperature' $first.TemperatureC $null
Assert-Equal 'first snapshot wait reason' $first.Error 'AwaitingHeartbeatChange'
$unchangedFirst = Test-AidaSnapshot -Sensors (New-Snapshot) -ProducerRunning $true -Now ([datetime]'2026-10-25T12:00:00') -MonotonicSeconds 100.5 -Context $context
Assert-Equal 'second unchanged snapshot still waits' $unchangedFirst.Healthy $false
Assert-Equal 'second unchanged snapshot no temperature' $unchangedFirst.TemperatureC $null
Assert-Equal 'second unchanged wait reason' $unchangedFirst.Error 'AwaitingHeartbeatChange'
$second = Test-AidaSnapshot -Sensors (New-Snapshot -Time '12:00:01') -ProducerRunning $true -Now ([datetime]'2026-10-25T12:00:01') -MonotonicSeconds 101 -Context $context
Assert-Equal 'heartbeat advances healthy' $second.Healthy $true
Assert-Equal 'temperature value' $second.TemperatureC 42
$sameTemperature = Test-AidaSnapshot -Sensors (New-Snapshot -Time '12:00:02') -ProducerRunning $true -Now ([datetime]'2026-10-25T12:00:02') -MonotonicSeconds 102 -Context $context
Assert-Equal 'same temperature with moving time is healthy' $sameTemperature.Healthy $true
Assert-Equal 'missing producer' (Test-Pair -Producer $false).Healthy $false
Assert-Equal 'missing producer no temperature' (Test-Pair -Producer $false).TemperatureC $null
Assert-Equal 'no sensors' (Test-Pair -Second @()).Healthy $false
$wrongId = New-Snapshot -Time '12:00:01'; $wrongId[0].Id = 'TCPU'
Assert-Equal 'wrong sensor no automatic fallback' (Test-Pair -Second $wrongId).Error 'ConfiguredSensorMissing'
$noTime = @((New-Snapshot -Time '12:00:01') | Where-Object { $_.Id -ne 'STIME' })
Assert-Equal 'time heartbeat mandatory' (Test-Pair -Second $noTime).Error 'HeartbeatTimeMissing'
$duplicate = @(New-Snapshot -Time '12:00:01') + @([pscustomobject]@{ Id = 'TCPUPKG'; Label = 'CPU Package'; Value = '99' })
Assert-Equal 'duplicate ID invalid' (Test-Pair -Second $duplicate).Error 'MissingOrDuplicateSensorId'
foreach ($value in @($null, 'TRIAL', 'NaN', 'Infinity', '-1', '0', '110.1', $true, '42 C')) {
    $bad = Test-Pair -Second (New-Snapshot -Time '12:00:01' -Temperature $value)
    Assert-Equal "invalid temperature [$value]" $bad.Healthy $false
    Assert-Equal "invalid temperature has no value [$value]" $bad.TemperatureC $null
}
Assert-Equal 'stale wallclock' (Test-Pair -Now ([datetime]'2026-10-25T12:00:12') -Monotonic 112).Error 'HeartbeatClockStale'
Assert-Equal 'future wallclock' (Test-Pair -Second (New-Snapshot -Time '12:00:04')).Error 'HeartbeatClockInFuture'
Assert-Equal 'future tolerance two seconds' (Test-Pair -Second (New-Snapshot -Time '12:00:03')).Healthy $true
Assert-Equal 'wrong date stale' (Test-Pair -Second (New-Snapshot -Time '12:00:01' -Date '10/24/2026')).Error 'HeartbeatClockStale'
Assert-Equal 'date malformed' (Test-Pair -Second (New-Snapshot -Time '12:00:01' -Date 'n/a')).Error 'HeartbeatDateInvalid'
Assert-Equal 'time without seconds invalid' (Test-Pair -Second (New-Snapshot -Time '12:00')).Error 'HeartbeatTimeInvalid'
Assert-Equal 'monotonic reversal invalid' (Test-Pair -Monotonic 99).Error 'MonotonicClockReversed'
Assert-Equal 'frozen heartbeat despite wallclock rollback' (Test-Pair -Second (New-Snapshot) -Now ([datetime]'2026-10-25T12:00:00') -Monotonic 111).Error 'HeartbeatNotAdvancing'
Assert-Equal 'en-US 12-hour time supported' (Test-Pair -Second (New-Snapshot -Time '12:00:01 PM')).Healthy $true
Assert-Equal '24-hour 0 to 23 time supported' (Test-Pair -Second (New-Snapshot -Time '23:00:01') -Now ([datetime]'2026-10-25T23:00:01')).Healthy $true
$midnightContext = @{}
$null = Test-AidaSnapshot -Sensors (New-Snapshot -Time '23:59:59' -Date '') -ProducerRunning $true -Now ([datetime]'2026-10-25T23:59:59') -MonotonicSeconds 100 -Context $midnightContext
$midnight = Test-AidaSnapshot -Sensors (New-Snapshot -Time '00:00:00' -Date '') -ProducerRunning $true -Now ([datetime]'2026-10-26T00:00:00') -MonotonicSeconds 101 -Context $midnightContext
Assert-Equal 'no date midnight rollover' $midnight.Healthy $true
$resetContext = @{}
$null = Test-AidaSnapshot -Sensors (New-Snapshot) -ProducerRunning $true -Now ([datetime]'2026-10-25T12:00:00') -MonotonicSeconds 100 -Context $resetContext -Source 'First'
$changedSource = Test-AidaSnapshot -Sensors (New-Snapshot -Time '12:00:01') -ProducerRunning $true -Now ([datetime]'2026-10-25T12:00:01') -MonotonicSeconds 101 -Context $resetContext -Source 'Second'
Assert-Equal 'new source reestablishes heartbeat' $changedSource.Error 'AwaitingHeartbeatChange'
$failed = @($script:results | Where-Object { -not $_.Passed })
$report = [pscustomobject]@{ TimestampUtc = [datetime]::UtcNow.ToString('o'); PowerShellVersion = $PSVersionTable.PSVersion.ToString(); Total = $script:results.Count; Passed = $script:results.Count - $failed.Count; Failed = $failed.Count; Tests = @($script:results.ToArray()) }
$directory = Split-Path -Parent $ReportPath
if ($directory -and -not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
if ($failed.Count -gt 0) { $failed | Format-Table -AutoSize | Out-String | Write-Output; Write-Output "FAILED: $($failed.Count)/$($script:results.Count)"; exit 1 }
Write-Output "PASS: $($script:results.Count) sensor assertions; report: $ReportPath"
exit 0
