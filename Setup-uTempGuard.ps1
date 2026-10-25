# First-run wizard for a downloaded ZIP or fresh Git checkout.
# Never modifies an existing config.json or enables Live/emergency actions.
[CmdletBinding()]
param(
    [string]$AidaPath='',
    [switch]$PrepareOnly,
    [string]$DataDirectory=(Join-Path $env:LOCALAPPDATA 'uTempGuard')
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=[IO.Path]::GetFullPath($PSScriptRoot)
$template=Join-Path $root 'config.example.json'
$configPath=Join-Path $root 'config.json'
if(-not (Test-Path -LiteralPath $template -PathType Leaf)){
    throw 'Template config.example.json is missing; please download the complete release.'
}
if(Test-Path -LiteralPath $configPath -PathType Leaf){
    Write-Output 'Existing config.json found; no configuration, approvals or setup were changed.'
    Write-Output 'Already installed? Use Manage.ps1 -Action Status, not this first-run wizard.'
    return
}
$sample=Get-Content -LiteralPath $template -Raw -Encoding UTF8 | ConvertFrom-Json
if($sample.Mode -cne 'Observe' -or $sample.EnableShutdown -ne $false -or
   $sample.EnableForcedShutdown -ne $false -or $sample.EnableAppClose -ne $false -or
   $sample.SensorId -cne 'TCPUPKG' -or @($sample.AllowList).Count -ne 0){
    throw 'Unsafe template; first-run installation aborted.'
}
$given=$AidaPath.Trim().Trim('"')
if(-not $given){
    Write-Output 'uTempGuard uses AIDA64 Extreme. Install/configure AIDA64 sensor export before starting.'
    Write-Output 'AIDA64: Settings -> Hardware monitoring -> External applications -> Registry (SensorValues).'
    $given=(Read-Host 'Enter full path to your installed aida64.exe').Trim().Trim('"')
}
if([string]::IsNullOrWhiteSpace($given)){Write-Output 'Cancelled. No files changed.';return}
if(-not [IO.Path]::IsPathRooted($given) -or
   -not (Test-Path -LiteralPath $given -PathType Leaf) -or
   [IO.Path]::GetFileName($given) -ine 'aida64.exe'){
    throw 'Invalid AIDA64 executable path. No config was written.'
}
$fullPath=[IO.Path]::GetFullPath($given)
$signature=Get-AuthenticodeSignature -LiteralPath $fullPath
if($signature.Status -ne 'Valid' -or
   $null -eq $signature.SignerCertificate -or
   $signature.SignerCertificate.Subject -notmatch 'FinalWire'){
    throw 'AIDA64 signature was not verified as FinalWire. Setup stopped without changes.'
}
$sample.AidaPath=$fullPath
$json=$sample | ConvertTo-Json -Depth 16
# CreateNew ensures that existing user configuration is never overwritten.
$handle=[IO.File]::Open($configPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes($json+[Environment]::NewLine)
    $handle.Write($bytes,0,$bytes.Length)
}finally{$handle.Dispose()}
Write-Output 'Observe-only config.json created. Shutdown and application closing remain DISABLED.'
Write-Output 'Do not publish config.json or approval files to GitHub.'
if($PrepareOnly){
    Write-Output 'PrepareOnly: no startup shortcut installed, monitor not launched.'
    return
}
Write-Output 'Next: optional current-user startup shortcut and monitor start (no admin required).'
$answer=Read-Host 'Type INSTALL to approve installing and starting OBSERVE ONLY'
if($answer -cne 'INSTALL'){
    Write-Output 'No startup changes. You can later run Install.ps1 yourself.'
    return
}
& (Join-Path $root 'Install.ps1') -DataDirectory $DataDirectory
Write-Output 'Installed. Confirm AIDA64 export in the system tray; the first sample may be unavailable.'
Write-Output 'Emergency shutdown is NOT approved. See the safety guide before enabling.'
