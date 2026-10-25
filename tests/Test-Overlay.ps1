# Pure preference tests: no GUI, sensors, startup, or Live actions.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\src\Guard.Overlay.psm1') -Force
$folder = Join-Path $PSScriptRoot ('..\artifacts\overlay-test-' + [guid]::NewGuid().ToString('N'))
$path = Join-Path $folder 'overlay.json'
$defaults = Get-GuardOverlaySettings -Path $path
if ($defaults.Style -ne 'Compact' -or $defaults.FontSize -ne 11 -or $defaults.Opacity -ne 90 -or $defaults.ShowBackground) { throw 'Bad overlay defaults' }
$defaults.Style = 'Full'
$defaults.FontSize = 16
$defaults.Opacity = 80
$defaults.ShowBackground = $false
$defaults.Position = 'BottomLeft'
Save-GuardOverlaySettings -Path $path -Settings $defaults
$loaded = Get-GuardOverlaySettings -Path $path
if ($loaded.Style -ne 'Full' -or $loaded.FontSize -ne 16 -or $loaded.Opacity -ne 80 -or $loaded.ShowBackground -or $loaded.Position -ne 'BottomLeft') { throw 'Overlay settings did not persist' }
[IO.File]::WriteAllText($path,'{"Style":"Unknown","FontSize":99,"Opacity":2,"Visible":false}',(New-Object Text.UTF8Encoding($false)))
$invalid = Get-GuardOverlaySettings -Path $path
if ($invalid.Style -ne 'Compact' -or $invalid.FontSize -ne 11 -or $invalid.Opacity -ne 90 -or $invalid.Visible) { throw 'Invalid preferences were not safely normalized' }
[IO.File]::WriteAllText($path,'{broken',(New-Object Text.UTF8Encoding($false)))
$broken = Get-GuardOverlaySettings -Path $path
if ($broken.Style -ne 'Compact' -or $broken.Visible -ne $true) { throw 'Corrupt preferences prevented safe defaults' }
Write-Output 'PASS: overlay preferences defaults, persistence, invalid values, corrupted JSON.'
