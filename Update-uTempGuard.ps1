# Update only this trusted Git checkout. No privilege elevation, arbitrary commands, or Live changes.
[CmdletBinding()]
param([ValidateSet('Preview','Apply')][string]$Action='Preview')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($PSScriptRoot)
$gitCommand=Get-Command git.exe -ErrorAction Stop
$script:git=$gitCommand.Source
$script:root=$root
function Invoke-LocalGit {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $lines=@(& $script:git -C $script:root @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ('Git failed: ' + ($Arguments -join ' ') + [Environment]::NewLine + ($lines -join [Environment]::NewLine)) }
    return $lines
}
$checkout=[string](Invoke-LocalGit -Arguments @('rev-parse','--show-toplevel') | Select-Object -First 1)
if ([IO.Path]::GetFullPath($checkout).TrimEnd('\') -ine $root.TrimEnd('\')) { throw 'Updater must be inside its own project checkout.' }
$branch=[string](Invoke-LocalGit -Arguments @('branch','--show-current') | Select-Object -First 1)
if ($branch -cne 'main') { throw 'Updater only applies to main. Switch branches manually after reviewing changes.' }
$remote=[string](Invoke-LocalGit -Arguments @('remote','get-url','origin') | Select-Object -First 1)
if ($remote -notin @('https://github.com/sunpole/uTempGuard.git','https://github.com/sunpole/uTempGuard','git@github.com:sunpole/uTempGuard.git')) { throw 'Unexpected origin. Refusing to fetch or apply.' }
$dirty=@(Invoke-LocalGit -Arguments @('status','--porcelain','--untracked-files=all'))
if ($dirty.Count -gt 0) { throw 'Uncommitted files detected. No update was applied. Review git status.' }

Write-Output 'Checking approved GitHub main (no project files modified yet)...'
Invoke-LocalGit -Arguments @('fetch','--no-tags','origin','+refs/heads/main:refs/remotes/origin/main') | Out-Null
$old=[string](Invoke-LocalGit -Arguments @('rev-parse','HEAD') | Select-Object -First 1)
$new=[string](Invoke-LocalGit -Arguments @('rev-parse','refs/remotes/origin/main') | Select-Object -First 1)
if ($old -ceq $new) {
    Write-Output ('Already up to date: '+$old.Substring(0,12))
    return
}
$null=@(& $script:git -C $root merge-base --is-ancestor HEAD origin/main 2>&1)
if ($LASTEXITCODE -ne 0) { throw 'Local main has diverged; no update applied. Manual review required.' }
Write-Output ('Local:  '+$old.Substring(0,12))
Write-Output ('Remote: '+$new.Substring(0,12))
Invoke-LocalGit -Arguments @('diff','--stat','HEAD','origin/main') | ForEach-Object { Write-Output $_ }
if ($Action -eq 'Preview') {
    Write-Output 'PREVIEW ONLY. For application run: .\Update-uTempGuard.ps1 -Action Apply'
    return
}
$answer=Read-Host 'Type UPDATE to stop the monitor, fast-forward main and restart it'
if ($answer -cne 'UPDATE') { Write-Output 'Cancelled; no source files changed.'; return }
$manager=Join-Path $root 'Manage.ps1'
$before=& $manager -Action Status
$wasRunning=($before.HeartbeatFresh -and $null -ne $before.Status -and $before.Status.Running)
$stopped=$false
try {
    if ($wasRunning) {
        $result=& $manager -Action Stop
        if (-not $result.StoppedConfirmed) { throw 'Monitor stop not confirmed; update cancelled.' }
        $stopped=$true
    }
    Invoke-LocalGit -Arguments @('merge','--ff-only','origin/main') | ForEach-Object { Write-Output $_ }
    Write-Output 'Git fast-forward applied. Local config.json preserved.'
} finally {
    if ($stopped) {
        Write-Output 'Restarting the monitor...'
        & $manager -Action Start | Out-Null
    }
}
