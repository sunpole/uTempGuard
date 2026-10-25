# Checks all user-uploaded vector icons have a single offline gallery.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path $PSScriptRoot -Parent
$file=Join-Path $root 'docs\icon-gallery.html'
$html=Get-Content -LiteralPath $file -Raw -Encoding UTF8
$orig=Join-Path $root 'assets\logo'
$icons=@(Get-ChildItem -LiteralPath $orig -Filter 'utg_*.svg' -File)
if($icons.Count -ne 28){throw ('Expected 28 official uploaded icons, found '+$icons.Count)}
if($html -notmatch '<html' -or $html -notmatch 'assets/logo/' -or
   $html -notmatch '400' -or $html -notmatch 'setInterval' -or
   $html -notmatch '32 px' -or $html -notmatch '080' -or $html -notmatch '100'){
    throw 'Offline gallery lost temperature/theme/animation controls'
}
foreach($prefix in @('w','b')){
    foreach($bucket in @(0,10,20,30,40,50,60,70,80,90,100)){
        $name=('utg_{0}_{1:D3}.svg' -f $prefix,$bucket)
        if(-not (Test-Path -LiteralPath (Join-Path $orig $name))){throw ('Missing vector frame: '+$name)}
    }
    foreach($bucket in @(80,90,100)){
        $name=('utg_{0}_{1:D3}_active.svg' -f $prefix,$bucket)
        if(-not (Test-Path -LiteralPath (Join-Path $orig $name))){throw ('Missing blinking frame: '+$name)}
    }
}
if($html -match 'fetch\(' -or $html -match 'https?://'){throw 'Gallery must work offline and never fetch remote scripts'}
Write-Output 'PASS: complete 28-SVG gallery, 32px preview, 2 themes, 400ms demo; offline only.'
