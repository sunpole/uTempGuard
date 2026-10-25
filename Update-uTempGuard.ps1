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
    # Windows PowerShell 5.1 treats Git's harmless stderr progress ("From ...")
    # as a NativeCommandError when the caller uses ErrorActionPreference=Stop.
    # The process exit code, not stderr, determines command success.
    $previousPreference=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        $lines=@(& $script:git -C $script:root @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $exitCode=$LASTEXITCODE
    } finally {
        $ErrorActionPreference=$previousPreference
    }
    if ($exitCode -ne 0) { throw ('Git failed (exit ' + $exitCode + '): ' + ($Arguments -join ' ') + [Environment]::NewLine + ($lines -join [Environment]::NewLine)) }
    return $lines
}
$checkout=[string](Invoke-LocalGit -Arguments @('rev-parse','--show-toplevel') | Select-Object -First 1)
if ([IO.Path]::GetFullPath($checkout).TrimEnd('\') -ine $root.TrimEnd('\')) { throw 'Updater must be inside its own project checkout.' }
$branch=[string](Invoke-LocalGit -Arguments @('branch','--show-current') | Select-Object -First 1)
if ($branch -cne 'main') { throw 'Updater only applies to main. Switch branches manually after reviewing changes.' }
$remote=[string](Invoke-LocalGit -Arguments @('remote','get-url','origin') | Select-Object -First 1)
if ($remote -notin @('https://github.com/sunpole/uTempGuard.git','https://github.com/sunpole/uTempGuard','git@github.com:sunpole/uTempGuard.git')) { throw 'Unexpected origin. Refusing to fetch or apply.' }
# Tracked edits (including staged changes) are blocked; never overwrite user work.
# Untracked user files are preserved. Git fast-forward itself also rejects any
# path that would overwrite an untracked file; detect that collision explicitly.
$trackedChanges=@(Invoke-LocalGit -Arguments @('status','--porcelain','--untracked-files=no') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($trackedChanges.Count -gt 0) {
    Write-Output 'Tracked local modifications block an automatic update:'
    $trackedChanges | ForEach-Object { Write-Output $_ }
    throw 'Tracked modifications detected. Preserve/commit them before updating; no files changed.'
}
$untracked=@(Invoke-LocalGit -Arguments @('ls-files','--others','--exclude-standard') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if($untracked.Count -gt 0) {
    Write-Output ('Keeping {0} untracked local file(s) without modifying them:' -f $untracked.Count)
    $untracked | Select-Object -First 15 | ForEach-Object { Write-Output ('  '+$_) }
}

Write-Output 'Checking approved GitHub main (no project files modified yet)...'
Invoke-LocalGit -Arguments @('fetch','--no-tags','origin','+refs/heads/main:refs/remotes/origin/main') | Out-Null
$old=[string](Invoke-LocalGit -Arguments @('rev-parse','HEAD') | Select-Object -First 1)
$new=[string](Invoke-LocalGit -Arguments @('rev-parse','refs/remotes/origin/main') | Select-Object -First 1)
# Prevent a local untracked file from colliding with new tracked files upstream.
# Do this before stopping the monitor or asking for UPDATE.
$incoming=@(Invoke-LocalGit -Arguments @('diff','--name-only','--diff-filter=A','HEAD','origin/main'))
$untrackedLookup=@{}
foreach($p in $untracked){$untrackedLookup[$p.Replace('\','/')]=$true}
$collision=@($incoming | Where-Object { $untrackedLookup.ContainsKey($_.Replace('\','/')) })
if($collision.Count -gt 0){
    Write-Output 'New upstream files collide with these untracked local files:'
    $collision | ForEach-Object {Write-Output ('  '+$_)}
    throw 'Untracked file conflict: no update applied. Preserve or move these files manually.'
}
if ($old -ceq $new) {
    Write-Output ('Already up to date: '+$old.Substring(0,12))
    return
}
# Here exit 1 is an expected "not an ancestor" outcome, not a PS error.
$oldPreference=$ErrorActionPreference
try {
    $ErrorActionPreference='Continue'
    $null=@(& $script:git -C $root merge-base --is-ancestor HEAD origin/main 2>&1)
    $ancestorExitCode=$LASTEXITCODE
} finally {
    $ErrorActionPreference=$oldPreference
}
if ($ancestorExitCode -ne 0) { throw 'Local main has diverged or Git could not verify ancestry; no update applied. Manual review required.' }
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
