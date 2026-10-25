# Safe, UI-only preview. Static synthetic temperature, no access to AIDA or live monitor.
[CmdletBinding()]
param(
    [ValidateRange(1,110)][int]$TemperatureC=41,
    [switch]$SensorFault
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'src\Guard.Overlay.psm1') -Force
Import-Module (Join-Path $root 'src\Guard.TemperatureSources.psm1') -Force
$ConfigPath=Join-Path $root 'config.json' # Path used for mock UI signature only, not read in simulation.
$DataDirectory=Join-Path $root 'artifacts\visual-preview-ui'
[IO.Directory]::CreateDirectory($DataDirectory) | Out-Null
$stopPath=Join-Path $DataDirectory 'stop.request'
if (Test-Path -LiteralPath $stopPath) { Remove-Item -LiteralPath $stopPath }
$script:overlaySettingsPath=Join-Path $DataDirectory 'overlay.json'
$script:overlaySettings=Get-GuardOverlaySettings -Path $script:overlaySettingsPath
$script:sourcePolicyPath=Join-Path $DataDirectory 'temperature-sources.json'
$script:sourceApprovalPath=Join-Path $DataDirectory 'temperature-power-approval.json'
$script:temperaturePolicy=Get-GuardTemperaturePolicy -Path $script:sourcePolicyPath
$script:sourceMenus=$null
$script:lastTemperatureCatalog=$null
$script:lastDisplayTemperature=$null
$script:form=$null
$script:tray=$null
$script:overlayPreview=$true
$SimulationPath='UI-only preview'
$config=[pscustomobject]@{
    Mode='Observe'
    Overlay=[pscustomobject]@{Enabled=$true; MarginX=20; MarginY=20}
    WarningC=70
    ShutdownC=75
}
$script:lastCpuSummary=$null
$script:lastSample=[pscustomobject]@{
    Healthy= (-not $SensorFault)
    TemperatureC= $(if ($SensorFault) { $null } else { $TemperatureC })
    Error= $(if ($SensorFault) { 'Preview sensor unavailable' } else { $null })
}
$script:lastDecision=[pscustomobject]@{
    State= $(if ($SensorFault) { 'SensorFault' } else { 'Normal' })
}
function Test-LiveApproval { return $false }
function Write-GuardEvent { param([string]$Event,[object]$Details) }
. (Join-Path $root 'src\Guard.OverlayUI.ps1')
. (Join-Path $root 'src\Guard.SourceMenu.ps1')
try {
    Initialize-GuardOverlay
    Update-GuardDisplay -Sample $script:lastSample -Decision $script:lastDecision
    Write-Output 'UI preview only: no sensor polling, application closing, shutdown, startup or administrator operations.'
    Write-Output 'Use the uTempGuard icon near the Windows clock -> right-click -> Закрыть предпросмотр.'
    while (-not (Test-Path -LiteralPath $stopPath)) {
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 75
    }
} finally {
    if ($null -ne $script:tray) { $script:tray.Visible=$false; $script:tray.Dispose() }
    if ($null -ne $script:form) { $script:form.Dispose() }
    if (Test-Path -LiteralPath $stopPath) { Remove-Item -LiteralPath $stopPath }
}
