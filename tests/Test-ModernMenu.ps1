# UI smoke tests (never starts monitor, sensor, shutdown or shell).
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'src\Guard.Localization.psm1') -Force
$null=Initialize-GuardLocalization -DataDirectory (Join-Path $root 'artifacts\modern-ui-translation')
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
# Instantiate (but never show) the full tray panel and all main/settings pages.
# Windows runner has no interactive session; this validates actual controls only.
$script:form=[Windows.Forms.Form]::new()
$script:label=[Windows.Forms.Label]::new()
[void]$script:form.Controls.Add($script:label)
$script:tray=[Windows.Forms.NotifyIcon]::new()
$script:temperaturePolicy=[pscustomobject]@{
    DisplayMode='All';DisplayIds=@();ShutdownMode='LegacyCpu';ShutdownIds=@()
}
$script:overlaySettings=[pscustomobject]@{
    Style='Compact';FontSize=11;ShowBackground=$false;Visible=$true
    Opacity=90;Position='TopRight'
}
$ConfigPath=Join-Path $root 'README.md'
$script:sourceApprovalPath=Join-Path $root 'artifacts\ci-no-live-approval.json'
$script:lastSample=[pscustomobject]@{Healthy=$true;TemperatureC=41}
$script:lastDisplayTemperature=[pscustomobject]@{Healthy=$true;MaxC=41}
$script:lastCpuSummary=[pscustomobject]@{
    AvailableCount=2;ExpectedCount=15;Sensors=@(
        [pscustomobject]@{Id='TCPUPKG';Label='CPU Package';State='Valid';TemperatureC=41},
        [pscustomobject]@{Id='TCC-1-1';Label='Core 1';State='Valid';TemperatureC=38}
    )
}
$script:lastTemperatureCatalog=[pscustomobject]@{Healthy=$true;Sensors=@(
    [pscustomobject]@{Id='TCPUPKG';Label='CPU Package';TemperatureC=41;State='Valid';Category='Package'},
    [pscustomobject]@{Id='TGPU1';Label='GPU';TemperatureC=38;State='Valid';Category='Other'}
)}
$script:state='Normal'
$SimulationPath='mock-only'
function Test-LiveApproval{return $false}
function Test-GuardActionSourceApproval{return $true}
function Get-GuardSourceTitle{param([string]$Mode) return $Mode}
function Write-GuardEvent{param($Event,$Details)}
try{
    Initialize-GuardModernMenu
    Render-GuardModernPage -Page 'Home'
    # Dock layout: header/content/footer are separate table rows, never overlapping.
    $layout=@($script:modernMenu.Controls|Where-Object {$_ -is [Windows.Forms.TableLayoutPanel]})
    if($layout.Count -ne 1){throw 'Expected one non-overlapping TableLayoutPanel'}
    if($layout[0].GetRow($script:modernBody) -ne 1){
       throw 'Body must occupy the middle, separate table row'
    }
    if($null -eq $script:modernBackButton -or
       $script:modernBackButton.Parent -ne $layout[0].GetControlFromPosition(0,0)){
       throw 'Back button must remain in the independent fixed header'
    }
    if($null -eq $script:modernMenu -or $script:modernBody.Controls.Count -lt 12){
        throw 'Main dark context panel not created with expected actions'
    }
    $allText=@($script:modernBody.Controls | ForEach-Object {$_.Text}) -join ';'
    foreach($needle in @('Показывать','Выключение','GitHub','Обновления','Остановить')){
        if($allText -notmatch [regex]::Escape($needle)){throw ('Main UI missing: '+$needle)}
    }
    $metrics=Get-GuardModernPageMetrics -WorkingHeight 720
    if($metrics.Height -gt 545 -or $metrics.Overflow -or $script:modernBody.AutoScroll){
        throw ('Home menu is not compact or is clipped: '+($metrics|ConvertTo-Json -Compress))
    }
    foreach($control in $script:modernBody.Controls){
        if($control -is [Windows.Forms.Button] -and
          ($control.Height -gt 29 -or -not $control.AutoEllipsis -or
          $control.Text.Contains([Environment]::NewLine))){
            throw ('Menu row wrapped or too tall: '+$control.Text)
        }
    }
    Render-GuardModernPage -Page 'Language'
    if(@($script:modernBody.Controls|Where-Object {$_.Text -eq 'English'}).Count -ne 1){
        throw 'English language selection is missing'
    }
    $null=Set-GuardLanguage -Locale 'en-US'
    Render-GuardModernPage -Page 'Home'
    $enText=@($script:modernBody.Controls|ForEach-Object {$_.Text}) -join ';'
    if($enText -notmatch 'Shut down' -or $enText -notmatch 'Updates'){
        throw 'English UI labels failed to render'
    }
    $enMetrics=Get-GuardModernPageMetrics -WorkingHeight 720
    if($enMetrics.Overflow -or $enMetrics.Height -gt 545){throw 'English menu is clipped'}
    $null=Set-GuardLanguage -Locale 'ru-RU'
    Render-GuardModernPage -Page 'Home'
    Render-GuardModernPage -Page 'Display'
    if($script:modernBody.Controls.Count -lt 7){throw 'Display source selection options missing'}
    Render-GuardModernPage -Page 'Shutdown'
    if($script:modernBody.Controls.Count -lt 7){throw 'Shutdown source selection options missing'}
    Render-GuardModernPage -Page 'Language'
    Render-GuardModernPage -Page 'DisplayCustom'
    $custom=@($script:modernBody.Controls | Where-Object {$_.Text -match 'GPU'})
    if($custom.Count -ne 1){throw 'Custom sensor checkbox not rendered'}
    Render-GuardModernPage -Page 'Sensors'
    if(@($script:modernBody.Controls | Where-Object {$_.Text -match 'CPU Package'}).Count -ne 1){
        throw 'Read-only CPU sensor page was not rendered'
    }
    Render-GuardModernPage -Page 'Appearance'
    Render-GuardModernPage -Page 'Opacity'
    if(@($script:modernBody.Controls | Where-Object {$_.Text -match '100%'}).Count -ne 1){
        throw 'Opacity controls missing'
    }
    Render-GuardModernPage -Page 'Positions'
    if(@($script:modernBody.Controls | Where-Object {$_.Text -match 'Справа'}).Count -lt 2){throw 'Position controls missing'}
    Render-GuardModernPage -Page 'About'
    $logoLink=@($script:modernBody.Controls|Where-Object {$_ -is [Windows.Forms.Button] -and $_.Tag.Action -eq 'OpenUrl' -and $_.Tag.Value -match 'u_logo_tempg2.svg'})
    if($logoLink.Count -ne 1){throw 'Official SVG link is not clickable'}
    $gallery=@($script:modernBody.Controls|Where-Object {$_ -is [Windows.Forms.Button] -and $_.Tag.Action -eq 'OpenGallery'})
    if($gallery.Count -ne 1){throw 'Gallery is not reachable from About menu'}
    $description=@($script:modernBody.Controls|Where-Object {$_.Text -match 'Независимые датчики'})
    if($description.Count -ne 1 -or $description[0] -is [Windows.Forms.Button]){
        throw 'Static description must be a Label, not a dead button'
    }
    Invoke-GuardModernBack
    if($script:modernPage -ne 'Home'){throw 'Back navigation from submenu failed'}
    Render-GuardModernPage -Page 'DisplayCustom'
    Invoke-GuardModernBack
    if($script:modernPage -ne 'Display'){throw 'Custom mode back navigation failed'}
    Render-GuardModernPage -Page 'About'
    if(@($script:modernBody.Controls | Where-Object {$_.Text -match 'GitHub'}).Count -lt 1){
        throw 'About/repository action missing'
    }
}finally{
    Close-GuardModernMenu
    $script:tray.Dispose()
    $script:form.Dispose()
}
$logo.Dispose()
Write-Output 'PASS: official uploaded SVG, tray raster, dark WinForms controls, GitHub links; no real actions.'
