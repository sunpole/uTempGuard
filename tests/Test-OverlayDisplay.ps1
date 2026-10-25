# Pure display tests using stub objects; no WinForms window or live sensor.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Drawing
$root=Split-Path $PSScriptRoot -Parent
$script:form=[pscustomobject]@{BackColor=$null;TransparencyKey=$null}
$script:label=[pscustomobject]@{Text='';ForeColor=$null}
$script:tray=[pscustomobject]@{Text=''}
$script:menuCpuSensors=$null
$script:overlaySettings=[pscustomobject]@{Style='Compact';ShowBackground=$true}
$SimulationPath='safe'
$config=[pscustomobject]@{Mode='Observe';WarningC=70;ShutdownC=75}
function Test-LiveApproval { return $false }
. (Join-Path $root 'src\Guard.OverlayUI.ps1')
$good=[pscustomobject]@{Healthy=$true;TemperatureC=41}
$fault=[pscustomobject]@{Healthy=$true;TemperatureC=999}
$missing=[pscustomobject]@{Healthy=$false;TemperatureC=75}
$normal=[pscustomobject]@{State='Normal'}
$bad=[pscustomobject]@{State='SensorFault'}
Update-GuardDisplay -Sample $good -Decision $normal
if ($script:label.Text -ne 'CPU 41°C') { throw "Valid normal display failed: $($script:label.Text)" }
$max=[pscustomobject]@{
    MaxC=72
    HottestId='TCC-1-14'
    AvailableCount=2
    ExpectedCount=15
    Sensors=@()
}
Update-GuardDisplay -Sample $good -Decision $normal -CpuSummary $max
if ($script:label.Text -ne 'CPU MAX 72°C') { throw 'Valid hottest core was not displayed' }

Update-GuardDisplay -Sample $fault -Decision $bad
if ($script:label.Text -ne 'CPU --°C' -or $script:tray.Text -match '999') { throw 'Invalid temperature was shown as a number' }
Update-GuardDisplay -Sample $missing -Decision $bad
if ($script:label.Text -ne 'CPU --°C' -or $script:tray.Text -match '75°C') { throw 'Unhealthy sensor was shown as measured temperature' }
$script:overlaySettings.Style='Full'
Update-GuardDisplay -Sample $fault -Decision $bad
if ($script:label.Text -match '999') { throw 'Full mode leaked invalid sensor temperature' }
Write-Output 'PASS: overlay displays valid CPU number and masks sensor fault/invalid values.'
