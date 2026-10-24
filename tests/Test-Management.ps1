[CmdletBinding()]
param([string]$ReportPath)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path $projectPath 'artifacts\management-tests.json' }
$managerPath = Join-Path $projectPath 'Manage.ps1'
$fixtureRoot = Join-Path $projectPath 'artifacts\management-fixtures'
[IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
$results = New-Object Collections.Generic.List[object]
$originalCulture = [Threading.Thread]::CurrentThread.CurrentCulture
function Assert-Result {
    param([string]$Name, [bool]$Passed)
    $results.Add([pscustomobject]@{Name=$Name;Passed=$Passed})
    if (-not $Passed) { throw "FAIL: $Name" }
}
function Write-Fixture {
    param([string]$Directory, [object]$Value)
    [IO.Directory]::CreateDirectory($Directory) | Out-Null
    [IO.File]::WriteAllText((Join-Path $Directory 'status.json'), ($Value | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
}
try {
    [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('ru-RU')
    $absent = Join-Path $fixtureRoot ('absent-' + [guid]::NewGuid().ToString('N'))
    $status = & $managerPath -Action Status -DataDirectory $absent
    Assert-Result 'Missing status is not fresh' (-not $status.HeartbeatFresh -and $null -eq $status.Status)

    $fresh = Join-Path $fixtureRoot 'fresh'
    $freshRecord = @{Pid=$PID;StartedUtc=[datetime]::UtcNow.AddMinutes(-1).ToString('o');UpdatedUtc=[datetime]::UtcNow.ToString('o');Running=$true;State='Normal';TemperatureC=40;SensorError=$null}
    Write-Fixture $fresh $freshRecord
    $status = & $managerPath -Action Status -DataDirectory $fresh
    Assert-Result 'Fresh valid heartbeat is fresh' ($status.HeartbeatFresh -and $status.Status.Running)
    $beforeStatus = [IO.File]::ReadAllText((Join-Path $fresh 'status.json'))
    $startResult = & $managerPath -Action Start -DataDirectory $fresh
    Assert-Result 'Fresh running status avoids launch' ($startResult.AlreadyRunning -and -not $startResult.Started -and $beforeStatus -ceq [IO.File]::ReadAllText((Join-Path $fresh 'status.json')))

    $stale = Join-Path $fixtureRoot 'stale'
    Write-Fixture $stale @{Running=$true;UpdatedUtc=[datetime]::UtcNow.AddMinutes(-10).ToString('o');State='Normal'}
    $status = & $managerPath -Action Status -DataDirectory $stale
    Assert-Result 'Old heartbeat is stale' (-not $status.HeartbeatFresh)

    $future = Join-Path $fixtureRoot 'future'
    Write-Fixture $future @{Running=$true;UpdatedUtc=[datetime]::UtcNow.AddMinutes(10).ToString('o');State='Normal'}
    $status = & $managerPath -Action Status -DataDirectory $future
    Assert-Result 'Future heartbeat is invalid' (-not $status.HeartbeatFresh)

    $offset = Join-Path $fixtureRoot 'offset'
    Write-Fixture $offset @{Running=$true;UpdatedUtc=[DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(3)).ToString('o');State='Normal'}
    $status = & $managerPath -Action Status -DataDirectory $offset
    Assert-Result 'Offset timestamp stays fresh under ru-RU culture' ($status.HeartbeatFresh -and $null -ne $status.StatusAgeSeconds)

    $invalidDate = Join-Path $fixtureRoot 'invalid-date'
    Write-Fixture $invalidDate @{Running=$true;UpdatedUtc='not-a-timestamp';State='Normal'}
    $status = & $managerPath -Action Status -DataDirectory $invalidDate
    Assert-Result 'Invalid timestamp is not trusted' (-not $status.HeartbeatFresh -and $null -eq $status.StatusAgeSeconds)

    $malformed = Join-Path $fixtureRoot 'malformed'
    [IO.Directory]::CreateDirectory($malformed) | Out-Null
    [IO.File]::WriteAllText((Join-Path $malformed 'status.json'), '{broken')
    $status = & $managerPath -Action Status -DataDirectory $malformed
    Assert-Result 'Broken status is not trusted' (-not $status.HeartbeatFresh -and $null -eq $status.Status)

    $emptyStop = Join-Path $fixtureRoot ('stop-' + [guid]::NewGuid().ToString('N'))
    $stopResult = & $managerPath -Action Stop -DataDirectory $emptyStop
    Assert-Result 'Stop without status records request without claiming stopped' ($stopResult.StopRequested -and -not $stopResult.StoppedConfirmed -and (Test-Path -LiteralPath (Join-Path $emptyStop 'stop.request')))

    $stopped = Join-Path $fixtureRoot 'stopped'
    Write-Fixture $stopped @{Running=$false;State='Stopped';UpdatedUtc=[datetime]::UtcNow.ToString('o')}
    $stopResult = & $managerPath -Action Stop -DataDirectory $stopped
    Assert-Result 'Previously stopped instance is reported' ($stopResult.StopRequested -and $stopResult.StoppedConfirmed)
} catch {
    $results.Add([pscustomobject]@{Name='Test execution';Passed=$false;Error=$_.Exception.Message})
} finally {
    [Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
    [IO.Directory]::CreateDirectory((Split-Path -Parent ([IO.Path]::GetFullPath($ReportPath)))) | Out-Null
    $report = [ordered]@{Utc=[datetime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();TestCulture='ru-RU';StartupModified=$false;RuntimeLaunched=$false;Results=$results.ToArray()}
    [IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
}
$failed = @($results | Where-Object {-not $_.Passed})
if ($failed.Count -gt 0) { Write-Output ($failed | ConvertTo-Json -Depth 5); exit 1 }
Write-Output ('PASS: {0} management checks; no startup changes or runtime launch.' -f $results.Count)
