param([string]$ReportPath)
if([string]::IsNullOrWhiteSpace($ReportPath)){$ReportPath=Join-Path $PSScriptRoot '..\artifacts\runtime-tests.json'}
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sandbox=Join-Path $root ('artifacts\simulation-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($sandbox)|Out-Null
& (Join-Path $root 'uTempGuard.ps1') -Headless -DataDirectory $sandbox -SimulationPath (Join-Path $PSScriptRoot 'scenario.json')
$events=@(Get-Content -LiteralPath (Join-Path $sandbox 'events.jsonl')|ForEach-Object{$_|ConvertFrom-Json})
$states=@($events|Where-Object Event -eq 'StateChanged'|ForEach-Object{$_.Details.To})
$expected=@('Normal','Warning','Normal','Critical','SensorFault','Normal')
if(($states -join ',') -ne ($expected -join ',')){throw "Wrong transitions: $($states -join ',')"}
$intents=@($events|Where-Object Event -eq 'Intent')
if(@($intents|Where-Object {$_.Details.ExecutionAllowed -ne $false}).Count -gt 0){throw 'Simulation admitted execution'}
if(@($events|Where-Object Event -in @('GracefulCloseRequested','OrderlyShutdownRequested')).Count -gt 0){throw 'Simulation attempted side effect'}
if(@($intents|Where-Object {$_.Details.Intent -eq 'Shutdown'}).Count -ne 1){throw '75C must produce one dry-run shutdown intent'}
if(@($intents|Where-Object {$_.Details.Intent -eq 'ReduceLoad'}).Count -ne 2){throw '70C and 69C hysteresis expected two dry-run load intents'}
$status=Get-Content -LiteralPath (Join-Path $sandbox 'status.json') -Raw|ConvertFrom-Json
if($status.Running -or $status.SampleCount -ne 10 -or -not $status.Simulation){throw 'Wrong final status'}
$report=[ordered]@{Passed=$true;CheckedUtc=[datetime]::UtcNow.ToString('o');States=$states;DryRunIntents=$intents.Count;RealActions=0;Samples=$status.SampleCount;Sandbox=$sandbox}
[IO.File]::WriteAllText($ReportPath,($report|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
$report|ConvertTo-Json -Depth 5
