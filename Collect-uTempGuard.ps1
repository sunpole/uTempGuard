# uTempGuard - Source Collector, Windows PowerShell 5.1+
# Collects text source files only. Never installs or modifies uTempGuard.
# Review the resulting ZIP before uploading it to a chat.
[CmdletBinding()]
param([string]$ProjectPath = '')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Get-ProjectCandidates {
    $roots = @(
        'C:\!CODE_CLUB\new 2026',
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:USERPROFILE 'Documents'),
        (Join-Path $env:USERPROFILE 'Downloads')
    ) | Select-Object -Unique
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        if ((Split-Path $root -Leaf) -match '(?i)uTempGuard') { $result.Add($root) }
        # Scan just project-name directories. Ignore access-denied items.
        Get-ChildItem -LiteralPath $root -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)uTempGuard' } |
            ForEach-Object { $result.Add($_.FullName) }
    }
    return @($result | Select-Object -Unique)
}

try {
    Write-Host 'uTempGuard | source collector' -ForegroundColor Cyan
    Write-Host 'This tool only copies source files into a ZIP. No administrator rights needed.'
    if (-not $ProjectPath) {
        $options = @(Get-ProjectCandidates)
        if ($options.Count -eq 1) {
            $ProjectPath = $options[0]
            Write-Host "Found project: $ProjectPath" -ForegroundColor Green
        } elseif ($options.Count -gt 1) {
            Write-Host 'Project directories found:'
            for ($i = 0; $i -lt $options.Count; $i++) { Write-Host ('  [{0}] {1}' -f ($i+1), $options[$i]) }
            $answer = Read-Host 'Enter the number (or 0 to choose a folder manually)'
            $pick = 0
            if ([int]::TryParse($answer, [ref]$pick) -and $pick -gt 0 -and $pick -le $options.Count) {
                $ProjectPath = $options[$pick-1]
            }
        }
    }
    if (-not $ProjectPath) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Select the uTempGuard SOURCE project folder'
        $dialog.ShowNewFolderButton = $false
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            Write-Host 'Cancelled. No files changed.' -ForegroundColor Yellow
            exit 0
        }
        $ProjectPath = $dialog.SelectedPath
    }

    $folder = (Get-Item -LiteralPath $ProjectPath -ErrorAction Stop)
    if (-not $folder.PSIsContainer) { throw 'Selected path is not a directory.' }
    if ($folder.FullName.TrimEnd('\').Length -lt 8) { throw 'Select the project folder, not an entire drive.' }
    $extensions = @('.ps1','.psm1','.psd1','.py','.cs','.csproj','.sln','.xaml',
        '.json','.xml','.config','.md','.txt','.yml','.yaml','.html','.css',
        '.js','.ts','.jsx','.tsx','.cmd','.bat','.ini','.toml','.props',
        '.targets','.resx','.wxs','.wxi','.vb','.vbs','.ahk')
    $excludeParts = '(?i)(^|[\\/])(\.git|node_modules|\.venv|venv|__pycache__|\.idea|\.vs|dist|build|bin|obj|backups?|logs?|temp|tmp|\.next|\.cache)([\\/]|$)'
    $excludeNames = '(?i)(^\.env($|\.)|secret|credential|password|api[_-]?key|token|private[_-]?key|\.pem$|\.key$|\.pfx$|\.log$)'
    $files = @(Get-ChildItem -LiteralPath $folder.FullName -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName.Substring($folder.FullName.Length) -notmatch $excludeParts -and
            $_.Name -notmatch $excludeNames -and
            $extensions -contains $_.Extension.ToLowerInvariant() -and
            $_.Length -le 3MB
        })
    if ($files.Count -eq 0) { throw 'No matching source files found. Choose the directory containing .ps1, .py, .cs or other source code.' }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not (Test-Path -LiteralPath $desktop)) { $desktop = $env:USERPROFILE }
    $zipPath = Join-Path $desktop ("uTempGuard_sources_{0}.zip" -f $stamp)
    $stage = Join-Path $env:TEMP ("uTempGuard_export_{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    try {
        foreach ($file in $files) {
            $rel = $file.FullName.Substring($folder.FullName.Length).TrimStart('\')
            $dest = Join-Path $stage $rel
            $parent = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $file.FullName -Destination $dest -ErrorAction Stop
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($stage,$zipPath)
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host ''
    Write-Host ('ZIP CREATED: {0}' -f $zipPath) -ForegroundColor Green
    Write-Host ('Source files included: {0}' -f $files.Count)
    Write-Host 'Review the ZIP before uploading; configuration files can still contain personal data.' -ForegroundColor Yellow
    Write-Host 'Next step: attach this ZIP in your ChatGPT conversation.' -ForegroundColor Cyan
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
