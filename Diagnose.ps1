[CmdletBinding()]
param([string]$DataDirectory=(Join-Path $env:LOCALAPPDATA 'uTempGuard'),[string]$ConfigPath,[string]$ReportPath)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($ConfigPath)){$ConfigPath=Join-Path $PSScriptRoot 'config.json'}
Import-Module (Join-Path $PSScriptRoot 'src\Guard.Sensor.psm1') -Force
$config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$context=@{}; $samples=@()
for($i=0;$i -lt 6;$i++) {
    $samples+=Read-AidaSensor -SensorId $config.SensorId -AidaPath $config.AidaPath -MaxAgeSeconds $config.MaxAgeSeconds -Context $context
    if($i -lt 5){Start-Sleep -Seconds 2}
}
$status=$null
$statusPath=Join-Path $DataDirectory 'status.json'
if(Test-Path -LiteralPath $statusPath){$status=Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json}
$report=[ordered]@{CheckedUtc=[datetime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();LogicalProcessors=[Environment]::ProcessorCount;Mode=$config.Mode;EnableAppClose=$config.EnableAppClose;EnableShutdown=$config.EnableShutdown;AllowListCount=@($config.AllowList).Count;LiveApprovalPresent=(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'live-approval.json'));AidaPath=$config.AidaPath;AidaExists=(Test-Path -LiteralPath $config.AidaPath);SensorId=$config.SensorId;HealthySamples=@($samples|Where-Object Healthy).Count;Samples=$samples;Status=$status;StartupShortcut=(Test-Path -LiteralPath (Join-Path ([Environment]::GetFolderPath('Startup')) 'uTempGuard.lnk'))}
$json=$report|ConvertTo-Json -Depth 8
if($ReportPath){[IO.File]::WriteAllText($ReportPath,$json,[Text.UTF8Encoding]::new($false))}
$json
