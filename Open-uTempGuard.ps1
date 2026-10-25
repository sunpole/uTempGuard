# Open the main dashboard in the running per-user monitor (or start that monitor).
# No approvals or power settings are changed; only a local UI request is written.
[CmdletBinding()]
param([string]$DataDirectory=(Join-Path $env:LOCALAPPDATA 'uTempGuard'))
$ErrorActionPreference='Stop'
$data=[IO.Path]::GetFullPath($DataDirectory)
$manager=Join-Path $PSScriptRoot 'Manage.ps1'
$current=& $manager -Action Status -DataDirectory $data
if(-not $current.HeartbeatFresh -or $null -eq $current.Status -or -not $current.Status.Running){
    $launch=& $manager -Action Start -DataDirectory $data
    if(-not ($launch.Started -or $launch.AlreadyRunning)){
        throw 'uTempGuard monitor did not start; dashboard request was not sent.'
    }
}
[IO.Directory]::CreateDirectory($data)|Out-Null
$request=Join-Path $data 'dashboard.request'
[IO.File]::WriteAllText($request,[datetime]::UtcNow.ToString('o'),[Text.UTF8Encoding]::new($false))
Write-Output 'Dashboard requested. The current user monitor will display it on the next UI tick.'
