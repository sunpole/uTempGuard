[CmdletBinding()]
param(
    [switch]$NoStart,
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'uTempGuard')
)
$ErrorActionPreference = 'Stop'
$projectPath = [IO.Path]::GetFullPath($PSScriptRoot)
$DataDirectory = [IO.Path]::GetFullPath($DataDirectory)
$launcherPath = Join-Path $projectPath 'Launch.vbs'
$runtimePath = Join-Path $projectPath 'uTempGuard.ps1'
$configPath = Join-Path $projectPath 'config.json'
foreach ($requiredPath in @($launcherPath, $runtimePath, $configPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Required file not found: $requiredPath" }
}
$startupDirectory = [Environment]::GetFolderPath('Startup')
if ([string]::IsNullOrWhiteSpace($startupDirectory)) { throw 'Current-user Startup folder is unavailable.' }
[IO.Directory]::CreateDirectory($startupDirectory) | Out-Null
[IO.Directory]::CreateDirectory($DataDirectory) | Out-Null
$shortcutPath = Join-Path $startupDirectory 'uTempGuard.lnk'
$targetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
$arguments = '"' + $launcherPath + '" "' + $DataDirectory + '"'
$shell = New-Object -ComObject WScript.Shell
try {
    if (Test-Path -LiteralPath $shortcutPath) {
        $existing = $shell.CreateShortcut($shortcutPath)
        if ($existing.TargetPath -ine $targetPath -or $existing.Arguments -cne $arguments -or $existing.Description -cne 'uTempGuard current-user startup') {
            throw "Refusing to overwrite an unrelated shortcut: $shortcutPath"
        }
    }
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $targetPath
    $shortcut.Arguments = $arguments
    $shortcut.WorkingDirectory = $projectPath
    $shortcut.Description = 'uTempGuard current-user startup'
    $shortcut.WindowStyle = 7
    $shortcut.Save()
} finally {
    [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null
}
$manifest = [ordered]@{
    Product = 'uTempGuard'; Version = '0.1.0'; ProjectPath = $projectPath
    DataDirectory = $DataDirectory; ShortcutPath = $shortcutPath
    TargetPath = $targetPath; Arguments = $arguments
    InstalledUtc = [DateTime]::UtcNow.ToString('o'); Scope = 'CurrentUser'
}
$manifestJson = $manifest | ConvertTo-Json
[IO.File]::WriteAllText((Join-Path $DataDirectory 'install.json'), $manifestJson, (New-Object Text.UTF8Encoding($false)))
if (-not $NoStart) { & (Join-Path $projectPath 'Manage.ps1') -Action Start -DataDirectory $DataDirectory }
[pscustomobject]@{ Installed = $true; AutoStart = $true; ShortcutPath = $shortcutPath; DataDirectory = $DataDirectory; Started = (-not $NoStart) }
