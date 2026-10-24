[CmdletBinding()]
param([ValidateSet('Status','Install','Remove')][string]$Action='Status')
$ErrorActionPreference='Stop'
$config=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$taskName='uTempGuard-AIDA64-user'
$task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if($Action -eq 'Status') {
    if($null -eq $task){[pscustomobject]@{TaskName=$taskName;Installed=$false};return}
    [pscustomobject]@{TaskName=$taskName;Installed=$true;State=[string]$task.State;Executable=@($task.Actions)[0].Execute;User=$task.Principal.UserId;RunLevel=[string]$task.Principal.RunLevel}
    return
}
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){throw 'Administrator session required. Request user permission before elevation.'}
if($Action -eq 'Remove') {
    if($null -ne $task) {
        if($task.Description -ne 'uTempGuard: approved AIDA64 producer at current-user logon' -or @($task.Actions)[0].Execute -ine $config.AidaPath){throw 'Refusing to remove unrelated scheduled task.'}
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    return
}
if(-not (Test-Path -LiteralPath $config.AidaPath -PathType Leaf)){throw 'AIDA64 executable missing.'}
$signature=Get-AuthenticodeSignature -LiteralPath $config.AidaPath
if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'FinalWire'){throw 'AIDA64 signature could not be verified.'}
if($null -ne $task) {
    if($task.Description -ne 'uTempGuard: approved AIDA64 producer at current-user logon' -or @($task.Actions)[0].Execute -ine $config.AidaPath){throw 'Refusing to overwrite unrelated scheduled task.'}
}
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$actionObject=New-ScheduledTaskAction -Execute $config.AidaPath -WorkingDirectory (Split-Path $config.AidaPath -Parent)
$trigger=New-ScheduledTaskTrigger -AtLogOn -User $sid
$principal=New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Highest
$settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([timespan]::Zero) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$definition=New-ScheduledTask -Action $actionObject -Trigger $trigger -Principal $principal -Settings $settings -Description 'uTempGuard: approved AIDA64 producer at current-user logon'
Register-ScheduledTask -TaskName $taskName -InputObject $definition -Force | Out-Null
[pscustomobject]@{Installed=$true;TaskName=$taskName;Executable=$config.AidaPath;UserSid=$sid;RunLevel='Highest';Trigger='UserLogon'}
