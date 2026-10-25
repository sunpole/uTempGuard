# Verifies preview behavior. Does not request a reboot.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$scriptPath=Join-Path $PSScriptRoot 'Invoke-OneShotRestartTest.ps1'
$result=& $scriptPath -Action Preview -TestId 'ci-preview'
if($result.Input -ne 'SIMULATED 75 C' -or $result.State -ne 'Critical' -or
   $result.Intent -ne 'Shutdown' -or $result.Executed -ne $false -or
   $result.ProductionConfigChanged -ne $false) {
    throw ('Preview result incorrect: ' + ($result | ConvertTo-Json -Compress))
}
Write-Output 'PASS: Preview reports 75 C Critical/Shutdown; cannot execute a reboot.'
