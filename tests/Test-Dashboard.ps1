# Dashboard WinForms smoke-test, synthetic telemetry, never opens a real window or modifies OS.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'src\Guard.Localization.psm1') -Force
$null=Initialize-GuardLocalization -DataDirectory (Join-Path $root 'artifacts\dashboard-smoke-ui')
. (Join-Path $root 'src\Guard.ModernMenu.ps1')
. (Join-Path $root 'src\Guard.Dashboard.ps1')
$script:lastSample=$null
$script:lastDisplayTemperature=$null
$script:lastCpuSummary=$null
$script:temperaturePolicy=[pscustomobject]@{DisplayMode='All';ShutdownMode='All'}
$script:sourceApprovalPath=Join-Path $root 'artifacts\ci-never-approved.json'
$ConfigPath=Join-Path $root 'config.example.json'
$script:config=[pscustomobject]@{Mode='Observe'}
$script:state='Normal'
function Test-LiveApproval{return $false}
function Test-GuardActionSourceApproval{return $false}
$icon=Get-GuardOfficialLogo
try{
    Initialize-GuardDashboard
    if($null -eq $script:dashboardForm -or $script:dashboardForm.Visible -or
       $script:dashboardForm.ClientSize.Width -lt 800 -or
       -not $script:dashboardForm.ShowInTaskbar){
        throw 'Dashboard must initialize as a hidden, full-sized taskbar window.'
    }
    $table=@($script:dashboardForm.Controls|Where-Object {$_ -is [Windows.Forms.TableLayoutPanel]})
    if($table.Count -ne 1 -or $table[0].RowCount -ne 3){
        throw 'Dashboard header/content/footer responsive layout missing.'
    }
    if($script:dashboardLabels.Temperature.Text -notmatch 'Нет достоверных'){
        throw 'Unverified temperature displayed as real reading.'
    }
    if($script:dashboardLabels.Safety.Text -notmatch 'Не разрешено'){
        throw 'Dashboard incorrectly armed emergency shutdown.'
    }
    $script:lastSample=[pscustomobject]@{Healthy=$true;TemperatureC=41}
    $script:lastDisplayTemperature=[pscustomobject]@{Healthy=$true;MaxC=41.5}
    $script:lastCpuSummary=[pscustomobject]@{ExpectedCount=15;AvailableCount=15}
    $script:state='Normal'
    Update-GuardDashboard -Force
    if($script:dashboardLabels.Temperature.Text -notmatch '41' -or
       $script:dashboardLabels.Sensors.Text -ne '15/15'){
        throw 'Synthetic verified readings not shown.'
    }
    $script:lastSample.Healthy=$false
    Update-GuardDashboard -Force
    if($script:dashboardLabels.Temperature.Text -notmatch 'Нет достоверных'){
        throw 'Stale sample not removed from dashboard.'
    }
    $null=Set-GuardLanguage -Locale 'en-US'
    Update-GuardDashboard -Force
    if($script:dashboardLabels.Safety.Text -notmatch 'Not approved'){
        throw 'English dashboard texts missing.'
    }
    $null=Set-GuardLanguage -Locale 'ru-RU'
    # Check source text too so missing buttons are caught even on non-interactive CI.
    $source=Get-Content -LiteralPath (Join-Path $root 'src\Guard.Dashboard.ps1') -Raw -Encoding UTF8
    foreach($name in @('dashboard.display','dashboard.shutdown','dashboard.gallery','dashboard.updates','dashboard.language')){
        if(-not $source.Contains($name)){throw ('Dashboard action missing: '+$name)}
    }
}finally{
    Close-GuardDashboard
    if($null -ne $icon){$icon.Dispose()}
}
if($null -ne $script:dashboardForm){throw 'Dashboard was not disposed'}
Write-Output 'PASS: desktop dashboard form, verified temperature, sensor fault, RU/EN, independent unapproved safety and navigation.'
