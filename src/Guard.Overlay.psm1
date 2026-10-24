# Visual preferences are separate from config.json and never affect Live approvals.
function Get-GuardOverlaySettings {
    [CmdletBinding()]
    param([string]$Path)
    $settings = [ordered]@{
        Style = 'Compact'
        FontSize = 11
        Opacity = 90
        ShowBackground = $true
        Position = 'TopRight'
        Visible = $true
    }
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]$settings
    }
    try {
        $stored = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $stored -or $stored -isnot [pscustomobject]) { return [pscustomobject]$settings }
        $values = @{}
        foreach ($property in $stored.PSObject.Properties) { $values[$property.Name] = $property.Value }
        if ($values.ContainsKey('Style') -and $values.Style -in @('Compact','Full')) { $settings.Style = $values.Style }
        if ($values.ContainsKey('Position') -and $values.Position -in @('TopRight','TopLeft','BottomRight','BottomLeft')) { $settings.Position = $values.Position }
        $number = 0
        if ($values.ContainsKey('FontSize') -and [int]::TryParse([string]$values.FontSize, [ref]$number) -and $number -ge 9 -and $number -le 22) { $settings.FontSize = $number }
        if ($values.ContainsKey('Opacity') -and [int]::TryParse([string]$values.Opacity, [ref]$number) -and $number -ge 45 -and $number -le 100) { $settings.Opacity = $number }
        if ($values.ContainsKey('ShowBackground') -and $values.ShowBackground -is [bool]) { $settings.ShowBackground = $values.ShowBackground }
        if ($values.ContainsKey('Visible') -and $values.Visible -is [bool]) { $settings.Visible = $values.Visible }
    } catch {
        # An invalid visual-preferences file must not stop temperature monitoring.
    }
    return [pscustomobject]$settings
}

function Save-GuardOverlaySettings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Settings)
    # Serialize only the explicitly allowed visual fields.
    $record = [ordered]@{
        Style = [string]$Settings.Style
        FontSize = [int]$Settings.FontSize
        Opacity = [int]$Settings.Opacity
        ShowBackground = [bool]$Settings.ShowBackground
        Position = [string]$Settings.Position
        Visible = [bool]$Settings.Visible
    }
    if ($record.Style -notin @('Compact','Full') -or $record.Position -notin @('TopRight','TopLeft','BottomRight','BottomLeft') -or
        $record.FontSize -lt 9 -or $record.FontSize -gt 22 -or $record.Opacity -lt 45 -or $record.Opacity -gt 100) {
        throw 'Invalid overlay preferences.'
    }
    $folder = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
    [IO.Directory]::CreateDirectory($folder) | Out-Null
    $tempPath = Join-Path $folder ('.overlay-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($tempPath, ($record | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tempPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
    }
}

Export-ModuleMember -Function Get-GuardOverlaySettings,Save-GuardOverlaySettings
