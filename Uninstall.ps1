[CmdletBinding()]
param([string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'uTempGuard'))
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Manage.ps1') -Action DisableStartup -DataDirectory $DataDirectory
& (Join-Path $PSScriptRoot 'Manage.ps1') -Action Stop -DataDirectory $DataDirectory
[pscustomobject]@{
    Uninstalled = $true; DataPreserved = $true; SourcePreserved = $true
    DataDirectory = [IO.Path]::GetFullPath($DataDirectory)
    Message = 'Current-user startup removed. Source, configuration, logs, and AIDA64 are preserved.'
}
