# Notification-only tests, no sensors, windows, or shutdown involved.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot '..\src\Guard.Notices.psm1') -Force
$pending=Get-GuardNoticePolicy -State SensorFault -VerifiedOnce $false -UptimeSeconds 0
if($pending.Notify -or -not $pending.StartupPending -or $pending.Reason -ne 'InitialAidaGrace'){
    throw 'Initial AIDA startup notice must be deferred'
}
$stillPending=Get-GuardNoticePolicy -State SensorFault -VerifiedOnce $false -UptimeSeconds 44.9
if($stillPending.Notify -or -not $stillPending.StartupPending){throw 'Premature AIDA startup balloon'}
$late=Get-GuardNoticePolicy -State SensorFault -VerifiedOnce $false -UptimeSeconds 45
if(-not $late.Notify -or $late.StartupPending){throw 'Persistent fault must be announced at grace boundary'}
$lost=Get-GuardNoticePolicy -State SensorFault -VerifiedOnce $true -UptimeSeconds 4
if(-not $lost.Notify -or $lost.StartupPending){throw 'Real sensor loss after healthy reading was hidden'}
foreach($state in @('Warning','Critical')){
    $warning=Get-GuardNoticePolicy -State $state -VerifiedOnce $false -UptimeSeconds 1
    if(-not $warning.Notify -or $warning.StartupPending){throw ('Thermal alert was suppressed: '+$state)}
}
$normal=Get-GuardNoticePolicy -State Normal -VerifiedOnce $true -UptimeSeconds 90
if($normal.Notify){throw 'Healthy state must not issue a fault balloon'}
Write-Output 'PASS: defer only startup fault balloon; persistent fault, thermal warning and real sensor loss still notify.'
