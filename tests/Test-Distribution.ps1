# Verify distributable ZIP without touching local app or AIDA64.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path $PSScriptRoot -Parent
$work=Join-Path $root ('artifacts\release-verification-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work)|Out-Null
$out=Join-Path $work 'zips'
$result=& (Join-Path $root 'tools\Build-Distribution.ps1') -Version '0.5.1' -OutputDirectory $out
if($null -eq $result -or -not (Test-Path -LiteralPath $result.ZipPath)){throw 'Release ZIP not built'}
if(-not (Test-Path -LiteralPath $result.ChecksumPath)){throw 'Release checksum missing'}
$sha=(Get-FileHash -LiteralPath $result.ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
if($sha -cne $result.SHA256){throw 'Release checksum mismatch'}
$extract=Join-Path $work 'extracted'
Expand-Archive -LiteralPath $result.ZipPath -DestinationPath $extract
$application=Join-Path $extract 'uTempGuard'
foreach($relative in @('00_START-HERE.cmd','Install-uTempGuard.cmd','Open-uTempGuard.cmd','Open-uTempGuard.ps1','Open-uTempGuard.vbs',
 'Setup-uTempGuard.ps1','Install.ps1','Launch.vbs','Manage.ps1','uTempGuard.ps1',
 'config.example.json','README.md','README_EN.md','src\Guard.Sensor.psm1',
 'src\Guard.ModernMenu.ps1','i18n\ru-RU.json','i18n\en-US.json',
 'assets\logo\utg_b_020.svg','assets\logo\utg_w_020.svg',
 'assets\tray-icons\utg_b_020.png.base64','assets\tray-icons\utg_w_020.png.base64',
 'docs\INSTALL_RU.md','docs\INSTALL_EN.md','docs\icon-gallery.html',
 'docs\ICON_CATALOG.md','docs\ICON_CATALOG_EN.md','src\Guard.Dashboard.ps1')){
  if(-not (Test-Path -LiteralPath (Join-Path $application $relative) -PathType Leaf)){
    throw ('Package is not runnable; missing '+$relative)
  }
}
foreach($excluded in @('.git','.github','tests','tools','.release','artifacts','config.json',
 'live-approval.json','docs\screenshots')){
 if(Test-Path -LiteralPath (Join-Path $application $excluded)){
    throw ('Forbidden developer/private content: '+$excluded)
 }
}
$all=@(Get-ChildItem -LiteralPath $application -File -Recurse)
if(@($all | Where-Object { $_.Extension -in @('.cdr','.pem','.pfx','.bak','.log') }).Count -gt 0){
 throw 'Private working file leaked into public ZIP'
}
$template=Get-Content -LiteralPath (Join-Path $application 'config.example.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($template.Mode -cne 'Observe' -or $template.EnableShutdown -or $template.EnableForcedShutdown -or
   $template.EnableAppClose -or -not [string]::IsNullOrWhiteSpace($template.AidaPath)){
    throw 'Download template is not a safe blank Observe setup'
}
# Setup wizard must never overwrite a local existing config.
$setup=Get-Content -LiteralPath (Join-Path $application 'Setup-uTempGuard.ps1') -Raw -Encoding UTF8
if($setup -notmatch 'CreateNew' -or $setup -notmatch 'FinalWire' -or $setup -notmatch 'INSTALL'){
    throw 'Setup wizard lacks safe overwrite and signature checks'
}
Write-Output ('PASS: Windows ZIP, {0} files, 28 original SVGs, safe first-run template and SHA256.' -f $all.Count)
