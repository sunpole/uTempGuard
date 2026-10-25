# UI only. No changes to sensor validation, temperature thresholds, or action permissions.
function Update-GuardOverlayMenu {
    if ($null -eq $script:form) { return }
    $script:menuCompact.Checked = ($script:overlaySettings.Style -eq 'Compact')
    $script:menuFull.Checked = ($script:overlaySettings.Style -eq 'Full')
    $script:menuBackground.Checked = [bool]$script:overlaySettings.ShowBackground
    $script:menuVisible.Checked = [bool]$script:overlaySettings.Visible
}
function Set-GuardOverlayLayout {
    if ($null -eq $script:form) { return }
    $settings = $script:overlaySettings
    $script:label.Font = [Drawing.Font]::new('Segoe UI', [single]$settings.FontSize, [Drawing.FontStyle]::Bold)
    if ($settings.Style -eq 'Compact') {
        $width = [math]::Max(94, [int](27 + 7.4 * $settings.FontSize))
        $height = [math]::Max(25, [int](9 + 1.8 * $settings.FontSize))
    } else {
        $width = [math]::Max(350, [int](260 + 9 * $settings.FontSize))
        $height = [math]::Max(76, [int](22 + 4.5 * $settings.FontSize))
    }
    $script:form.Size = [Drawing.Size]::new($width, $height)
    $script:form.Opacity = [double]$settings.Opacity / 100.0
    $area = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $marginX = [int]$config.Overlay.MarginX
    $marginY = [int]$config.Overlay.MarginY
    if ($settings.Position -in @('TopLeft','BottomLeft')) { $x = $area.Left + $marginX }
    else { $x = $area.Right - $width - $marginX }
    if ($settings.Position -in @('BottomLeft','BottomRight')) { $y = $area.Bottom - $height - $marginY }
    else { $y = $area.Top + $marginY }
    $script:form.Location = [Drawing.Point]::new([int]$x,[int]$y)
    if ([bool]$config.Overlay.Enabled -and [bool]$settings.Visible) {
        if (-not $script:form.Visible) { $script:form.Show() }
    } elseif ($script:form.Visible) { $script:form.Hide() }
    Update-GuardOverlayMenu
}
function Set-GuardOverlayPreference {
    param([string]$Name, [object]$Value)
    switch ($Name) {
        'Style' { if ($Value -in @('Compact','Full')) { $script:overlaySettings.Style = [string]$Value } }
        'Position' { if ($Value -in @('TopRight','TopLeft','BottomRight','BottomLeft')) { $script:overlaySettings.Position = [string]$Value } }
        'FontSize' { $script:overlaySettings.FontSize = [int][math]::Max(9,[math]::Min(22,[int]$Value)) }
        'Opacity' { $script:overlaySettings.Opacity = [int][math]::Max(45,[math]::Min(100,[int]$Value)) }
        'ShowBackground' { $script:overlaySettings.ShowBackground = [bool]$Value }
        'Visible' { $script:overlaySettings.Visible = [bool]$Value }
        default { return }
    }
    try { Save-GuardOverlaySettings -Path $script:overlaySettingsPath -Settings $script:overlaySettings }
    catch { Write-GuardEvent 'OverlaySettingsError' @{Message=$_.Exception.Message} }
    Set-GuardOverlayLayout
    if ($null -ne $script:lastSample -and $null -ne $script:lastDecision) {
        Update-GuardDisplay -Sample $script:lastSample -Decision $script:lastDecision -CpuSummary $script:lastCpuSummary
    }
}
function Update-GuardDisplay {
    param([object]$Sample, [object]$Decision, [AllowNull()][object]$CpuSummary = $null)
    if ($null -eq $script:form) { return }
    $suffix = if ($SimulationPath) {'ИМИТАЦИЯ'} elseif ($config.Mode -eq 'Observe') {'НАБЛЮДЕНИЕ'} elseif (Test-LiveApproval) {'БОЕВОЙ РЕЖИМ'} else {'ДЕЙСТВИЯ ЗАБЛОКИРОВАНЫ'}
    $foreground = [Drawing.Color]::FromArgb(158,248,180)
    $background = [Drawing.Color]::FromArgb(20,30,24)
    if (-not $Sample.Healthy -or $Decision.State -eq 'SensorFault') {
        $shortText = 'CPU --°C'
        $fullText = 'CPU: нет достоверных данных' + [Environment]::NewLine + "$suffix | ДАТЧИК НЕДОСТУПЕН"
        $foreground = [Drawing.Color]::White
        $background = [Drawing.Color]::FromArgb(120,60,0)
    } else {
        $readout = [double]$Sample.TemperatureC
        $sourceName = 'CPU Package'
        $readoutTitle = 'CPU'
        if ($null -ne $CpuSummary -and $null -ne $CpuSummary.MaxC -and $CpuSummary.AvailableCount -ge 1) {
            $readout = [double]$CpuSummary.MaxC
            $readoutTitle = 'CPU MAX'
            $sourceName = if ($CpuSummary.HottestId -eq 'TCPUPKG') { 'CPU Package' } else { 'CPU ' + $CpuSummary.HottestId }
        }
        $shortText = ('{0} {1:N0}°C' -f $readoutTitle,$readout)
        $fullText = ('{0}: {1:N0} °C' -f $sourceName,$readout) + [Environment]::NewLine + "$suffix | $($Decision.State)"
        if ($readout -ge $config.WarningC -and $Decision.State -eq 'Normal') {
            $foreground = [Drawing.Color]::White
            $background = [Drawing.Color]::DarkOrange
            if ($readout -ge $config.ShutdownC) { $background = [Drawing.Color]::DarkRed }
        }
        if ($Decision.State -eq 'Critical') {
            $foreground = [Drawing.Color]::White
            $background = [Drawing.Color]::DarkRed
        } elseif ($Decision.State -eq 'Warning') {
            $foreground = [Drawing.Color]::White
            $background = [Drawing.Color]::DarkOrange
        }
    }
    if ($script:overlaySettings.Style -eq 'Compact') { $script:label.Text = $shortText }
    else { $script:label.Text = $fullText }
    $script:label.ForeColor = $foreground
    if ($script:overlaySettings.ShowBackground) {
        $script:form.TransparencyKey = [Drawing.Color]::Empty
        $script:form.BackColor = $background
    } else {
        # Transparent only for the background, not the CPU text.
        $script:form.BackColor = [Drawing.Color]::Magenta
        $script:form.TransparencyKey = [Drawing.Color]::Magenta
    }
    if ($null -ne $script:menuCpuSensors) {
        $script:menuCpuSensors.DropDownItems.Clear()
        if ($null -eq $CpuSummary) {
            $script:menuCpuSensors.Text = 'Датчики CPU: нет новых данных'
            $item=$script:menuCpuSensors.DropDownItems.Add('Нет подтверждённых данных ядер')
            $item.Enabled=$false
        } else {
            $script:menuCpuSensors.Text=('Датчики CPU: {0}/{1}' -f $CpuSummary.AvailableCount,$CpuSummary.ExpectedCount)
            foreach ($sensor in $CpuSummary.Sensors) {
                $text = if ($sensor.State -eq 'Valid') { ('{0}: {1:N0}°C' -f $sensor.Label,$sensor.TemperatureC) }
                    elseif ($sensor.State -eq 'Invalid') { "$($sensor.Label): недостоверно" }
                    else { "$($sensor.Label): не экспортируется" }
                if ($sensor.Id -eq $CpuSummary.HottestId) { $text = '★ ' + $text }
                $item=$script:menuCpuSensors.DropDownItems.Add($text)
                $item.Enabled=$false
            }
        }
    }
    $tooltip = $shortText + ' | ' + $suffix + ' | ' + $Decision.State
    $script:tray.Text = $tooltip.Substring(0,[math]::Min(63,$tooltip.Length))
}
function Initialize-GuardOverlay {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()
    $script:form=[Windows.Forms.Form]::new()
    $script:form.Text='uTempGuard'
    $script:form.FormBorderStyle='None'
    $script:form.TopMost=$true
    $script:form.ShowInTaskbar=$false
    $script:form.StartPosition='Manual'
    $script:label=[Windows.Forms.Label]::new()
    $script:label.Dock='Fill'
    $script:label.BackColor=[Drawing.Color]::Transparent
    $script:label.TextAlign='MiddleCenter'
    $script:form.Controls.Add($script:label)

    $menu=[Windows.Forms.ContextMenuStrip]::new()
    $script:menuCompact=$menu.Items.Add('Компактный: CPU 41°C')
    $script:menuCompact.add_Click({ Set-GuardOverlayPreference -Name 'Style' -Value 'Compact' })
    $script:menuFull=$menu.Items.Add('Полный индикатор')
    $script:menuFull.add_Click({ Set-GuardOverlayPreference -Name 'Style' -Value 'Full' })
    $script:menuCpuSensors=[Windows.Forms.ToolStripMenuItem]::new('Датчики CPU')
    $menu.Items.Add($script:menuCpuSensors) | Out-Null
    $menu.Items.Add('-') | Out-Null
    $fontIncrease=$menu.Items.Add('Шрифт крупнее')
    $fontIncrease.add_Click({ Set-GuardOverlayPreference -Name 'FontSize' -Value ([int]$script:overlaySettings.FontSize + 1) })
    $fontDecrease=$menu.Items.Add('Шрифт мельче')
    $fontDecrease.add_Click({ Set-GuardOverlayPreference -Name 'FontSize' -Value ([int]$script:overlaySettings.FontSize - 1) })
    $script:menuBackground=$menu.Items.Add('Показывать фон')
    $script:menuBackground.add_Click({ Set-GuardOverlayPreference -Name 'ShowBackground' -Value (-not $script:overlaySettings.ShowBackground) })
    $opacityMenu=[Windows.Forms.ToolStripMenuItem]::new('Непрозрачность')
    $opacity100=$opacityMenu.DropDownItems.Add('100%')
    $opacity100.add_Click({ Set-GuardOverlayPreference -Name 'Opacity' -Value 100 })
    $opacity80=$opacityMenu.DropDownItems.Add('80%')
    $opacity80.add_Click({ Set-GuardOverlayPreference -Name 'Opacity' -Value 80 })
    $opacity60=$opacityMenu.DropDownItems.Add('60%')
    $opacity60.add_Click({ Set-GuardOverlayPreference -Name 'Opacity' -Value 60 })
    $menu.Items.Add($opacityMenu) | Out-Null
    $positionMenu=[Windows.Forms.ToolStripMenuItem]::new('Положение')
    $topRight=$positionMenu.DropDownItems.Add('Справа сверху')
    $topRight.add_Click({ Set-GuardOverlayPreference -Name 'Position' -Value 'TopRight' })
    $topLeft=$positionMenu.DropDownItems.Add('Слева сверху')
    $topLeft.add_Click({ Set-GuardOverlayPreference -Name 'Position' -Value 'TopLeft' })
    $bottomRight=$positionMenu.DropDownItems.Add('Справа снизу')
    $bottomRight.add_Click({ Set-GuardOverlayPreference -Name 'Position' -Value 'BottomRight' })
    $bottomLeft=$positionMenu.DropDownItems.Add('Слева снизу')
    $bottomLeft.add_Click({ Set-GuardOverlayPreference -Name 'Position' -Value 'BottomLeft' })
    $menu.Items.Add($positionMenu) | Out-Null
    $script:menuVisible=$menu.Items.Add('Показать индикатор')
    $script:menuVisible.add_Click({ Set-GuardOverlayPreference -Name 'Visible' -Value (-not $script:overlaySettings.Visible) })
    $menu.Items.Add('-') | Out-Null
    $stopLabel = if ($script:overlayPreview) { 'Закрыть предпросмотр' } else { 'Остановить uTempGuard' }
    $stopItem=$menu.Items.Add($stopLabel)
    $stopItem.add_Click({ [IO.File]::WriteAllText($stopPath,'stop') })

    $script:form.ContextMenuStrip=$menu
    $script:tray=[Windows.Forms.NotifyIcon]::new()
    $script:tray.Icon=[Drawing.SystemIcons]::Information
    $script:tray.ContextMenuStrip=$menu
    $script:tray.Visible=$true
    $script:tray.Text='uTempGuard'
    Set-GuardOverlayLayout
}
