[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Get-Content -LiteralPath (Join-Path $root 'config.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($config.Mode -ne 'Observe' -or $config.EnableAppClose -or $config.EnableShutdown -or (Test-Path -LiteralPath (Join-Path $root 'live-approval.json'))){throw 'Lifecycle testing requires unapproved Observe mode with actions disabled.'}
$dataDirectory=Join-Path $env:LOCALAPPDATA 'uTempGuard'
$reportPath=Join-Path $root 'artifacts\lifecycle-tests.json'
$shortcut=Join-Path ([Environment]::GetFolderPath('Startup')) 'uTempGuard.lnk'
$report=[ordered]@{CheckedUtc=[datetime]::UtcNow.ToString('o');Passed=$false;UninstallVerified=$false;DataAndSourcePreserved=$false;ReinstallVerified=$false;StartupShortcutLaunched=$false;DuplicateBlocked=$false;FinalSensorHealthy=$false;RealDangerousActions=0;NewLogonTested=$false}
try {
    & (Join-Path $root 'Uninstall.ps1') | Out-Null
    if(Test-Path -LiteralPath $shortcut){throw 'Uninstall did not remove owned startup shortcut'}
    $status=Get-Content -LiteralPath (Join-Path $dataDirectory 'status.json') -Raw|ConvertFrom-Json
    if($status.Running){throw 'Uninstall did not stop monitor'}
    $report.UninstallVerified=$true
    if(-not (Test-Path -LiteralPath (Join-Path $root 'config.json')) -or -not (Test-Path -LiteralPath (Join-Path $dataDirectory 'events.jsonl'))){throw 'Uninstall failed preservation contract'}
    $report.DataAndSourcePreserved=$true
    & (Join-Path $root 'Install.ps1') -NoStart | Out-Null
    if(-not (Test-Path -LiteralPath $shortcut)){throw 'Reinstall did not restore startup shortcut'}
    $report.ReinstallVerified=$true
    $requested=[datetime]::UtcNow
    Start-Process -FilePath $shortcut -WindowStyle Hidden | Out-Null
    $deadline=[datetime]::UtcNow.AddSeconds(20)
    do {
        Start-Sleep -Milliseconds 500
        try {$status=Get-Content -LiteralPath (Join-Path $dataDirectory 'status.json') -Raw|ConvertFrom-Json}catch{continue}
        if($status.Running -and [datetime]::Parse($status.UpdatedUtc).ToUniversalTime() -ge $requested -and $status.State -eq 'Normal'){break}
    }while([datetime]::UtcNow -lt $deadline)
    if(-not $status.Running -or $status.State -ne 'Normal' -or [datetime]::Parse($status.UpdatedUtc).ToUniversalTime() -lt $requested){throw 'Startup shortcut failed to start healthy monitor'}
    $report.StartupShortcutLaunched=$true
    $originalPid=$status.Pid
    $beforeStarts=@(Get-Content -LiteralPath (Join-Path $dataDirectory 'events.jsonl')|ForEach-Object{$_|ConvertFrom-Json}|Where-Object Event -eq 'Started').Count
    $powershellPath=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $variantPath=$dataDirectory.ToUpperInvariant()
    $arguments='-NoProfile -STA -ExecutionPolicy Bypass -File "'+(Join-Path $root 'uTempGuard.ps1')+'" -Headless -MaxSamples 1 -DataDirectory "'+$variantPath+'"'
    $duplicate=Start-Process -FilePath $powershellPath -ArgumentList $arguments -WindowStyle Hidden -PassThru
    $null=$duplicate.Handle
    if(-not $duplicate.WaitForExit(15000)){throw 'Duplicate did not exit within bounded wait'}
    $duplicate.Refresh()
    if($duplicate.ExitCode -ne 0){throw 'Duplicate exited with error'}
    $status=Get-Content -LiteralPath (Join-Path $dataDirectory 'status.json') -Raw|ConvertFrom-Json
    $afterStarts=@(Get-Content -LiteralPath (Join-Path $dataDirectory 'events.jsonl')|ForEach-Object{$_|ConvertFrom-Json}|Where-Object Event -eq 'Started').Count
    if($status.Pid -ne $originalPid -or $afterStarts -ne $beforeStarts){throw 'Duplicate altered runtime identity or logged another start'}
    $report.DuplicateBlocked=$true
    $report.FinalSensorHealthy=($status.State -eq 'Normal' -and [string]::IsNullOrEmpty($status.SensorError))
    $report.FinalPid=$status.Pid;$report.FinalTemperatureC=$status.TemperatureC
    $report.Passed=$true
} finally {
    # A failed test must not deliberately leave the authorized monitor disabled.
    if(-not (Test-Path -LiteralPath $shortcut)){& (Join-Path $root 'Install.ps1') -NoStart | Out-Null}
    & (Join-Path $root 'Manage.ps1') -Action Start | Out-Null
    [IO.File]::WriteAllText($reportPath,($report|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
}
$report|ConvertTo-Json -Depth 4
