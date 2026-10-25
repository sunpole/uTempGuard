# UI smoke tests (never starts monitor, sensor, shutdown or shell).
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path $PSScriptRoot -Parent
$module=Join-Path $root 'src\Guard.ModernMenu.ps1'
$tokens=$null;$errors=$null
[void][Management.Automation.Language.Parser]::ParseFile($module,[ref]$tokens,[ref]$errors)
if($errors){throw ('ModernMenu parse errors: '+($errors -join '; '))}
. $module
$logo=Get-GuardOfficialLogo
if($null -eq $logo -or $logo.Width -ne 64 -or $logo.Height -ne 64){
    throw 'The official user SVG raster is missing or not a valid 64px icon'
}
if([string]$script:modernMenu -ne ''){throw 'Modern form started without explicit initialization'}
$row=New-GuardModernRow -Text 'Тест' -Action 'Page' -Value 'Sensors'
try{
    if($row.Width -lt 300 -or $row.Tag.Action -ne 'Page' -or $row.Tag.Value -ne 'Sensors'){
        throw 'Accessible menu row or action wiring invalid'
    }
    if($row.BackColor -eq [Drawing.Color]::White -or $row.ForeColor -eq [Drawing.Color]::Black){
        throw 'Unexpected legacy light menu palette'
    }
}finally{$row.Dispose()}
$svg=Get-Content -LiteralPath (Join-Path $root 'assets\u_logo_tempg2.svg') -Raw -Encoding UTF8
if($svg -notmatch '<svg' -or $svg -notmatch '#990000' -or $svg -notmatch '#FFCC00'){
    throw 'Original uploaded SVG is missing or recolored'
}
$allowed=@('https://github.com/sunpole/uTempGuard',
    'https://github.com/sunpole/uTempGuard/releases/latest')
foreach($link in $allowed){
    if((Get-Content $module -Raw -Encoding UTF8).IndexOf($link,[StringComparison]::Ordinal) -lt 0){
        throw ('Expected repository link missing: '+$link)
    }
}
$logo.Dispose()
Write-Output 'PASS: official uploaded SVG, tray raster, dark WinForms controls, GitHub links; no real actions.'
