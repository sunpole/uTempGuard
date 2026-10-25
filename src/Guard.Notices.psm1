# Notification policy only; never changes measurement, status, or actions.
Set-StrictMode -Version 2.0
function Get-GuardNoticePolicy {
    [CmdletBinding()]
    param(
        [ValidateSet('Normal','Warning','Critical','SensorFault')][string]$State,
        [bool]$VerifiedOnce = $false,
        [double]$UptimeSeconds = 0,
        [double]$StartupGraceSeconds = 45
    )
    if ([double]::IsNaN($UptimeSeconds) -or [double]::IsInfinity($UptimeSeconds) -or
        $UptimeSeconds -lt 0 -or [double]::IsNaN($StartupGraceSeconds) -or
        [double]::IsInfinity($StartupGraceSeconds) -or $StartupGraceSeconds -lt 0) {
        throw 'Invalid notice-policy timing'
    }
    # Suppress only the *initial* expected sensor-fault balloon while AIDA
    # starts and a heartbeat change is being verified. The fault itself remains
    # visible as CPU --C, and LIVE actions are still blocked.
    $defer = ($State -eq 'SensorFault' -and -not $VerifiedOnce -and
        $UptimeSeconds -lt $StartupGraceSeconds)
    [pscustomobject]@{
        Notify = ($State -ne 'Normal' -and -not $defer)
        StartupPending = $defer
        Reason = $(if ($defer) { 'InitialAidaGrace' } elseif ($State -eq 'Normal') { 'Healthy' } else { 'NoticeAllowed' })
    }
}
Export-ModuleMember -Function Get-GuardNoticePolicy
