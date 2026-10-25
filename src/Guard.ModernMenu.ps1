# uTempGuard Fluent-inspired Windows Forms menu.
# UI only: delegates power approval/sensor validation to the existing guard.
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
$script:modernMenu = $null
$script:modernBody = $null
$script:modernHeaderTemperature = $null
$script:modernLogo = $null
$script:modernIcon = $null
$script:modernImage = $null
$script:modernModal = $false
$script:modernPage = 'Home'
$script:modernDark = [Drawing.ColorTranslator]::FromHtml('#101827')
$script:modernSurface = [Drawing.ColorTranslator]::FromHtml('#182438')
$script:modernHover = [Drawing.ColorTranslator]::FromHtml('#283B57')
$script:modernText = [Drawing.ColorTranslator]::FromHtml('#F1F5F9')
$script:modernMuted = [Drawing.ColorTranslator]::FromHtml('#A8BDD3')
$script:modernAccent = [Drawing.ColorTranslator]::FromHtml('#22D3EE')
$script:modernWarning = [Drawing.ColorTranslator]::FromHtml('#F59E0B')

function Get-GuardOfficialLogo {
    if($null -ne $script:modernImage){return $script:modernImage}
    $source = Join-Path $PSScriptRoot '..\assets\u_logo_64.png.base64'
    if(-not (Test-Path -LiteralPath $source -PathType Leaf)){return $null}
    try{
        $raw=Get-Content -LiteralPath $source -Raw -Encoding ASCII
        $bytes=[Convert]::FromBase64String($raw.Trim())
        $memory=[IO.MemoryStream]::new($bytes,$false)
        try{
            $image=[Drawing.Image]::FromStream($memory)
            try{$script:modernImage=[Drawing.Bitmap]::new($image)}
            finally{$image.Dispose()}
        } finally{$memory.Dispose()}
        return $script:modernImage
    }catch{return $null}
}
function Get-GuardModernSummaryText {
    if($null -eq $script:lastSample -or -not $script:lastSample.Healthy){return 'Ожидаем данные AIDA64'}
    $chosen=$script:lastDisplayTemperature
    $c=if($null -ne $chosen -and $chosen.Healthy){$chosen.MaxC}else{$script:lastSample.TemperatureC}
    if($null -eq $c){return 'Датчик не подтверждён'}
    return ('Сейчас {0:N0}°C · {1}' -f [double]$c,$script:state)
}
function New-GuardModernRow {
    param([string]$Text,[string]$Action='', [string]$Value='', [string]$Role='', [string]$Id='', [switch]$Accent,[switch]$Danger, [int]$Height=45)
    $button=[Windows.Forms.Button]::new()
    $button.Width=381
    $button.Height=$Height
    $button.FlatStyle=[Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize=0
    $button.FlatAppearance.MouseOverBackColor=$script:modernHover
    $button.BackColor=if($Accent){[Drawing.ColorTranslator]::FromHtml('#123C68')}else{$script:modernSurface}
    $button.ForeColor=if($Danger){[Drawing.ColorTranslator]::FromHtml('#FF7171')}elseif($Accent){$script:modernAccent}else{$script:modernText}
    $button.Font=[Drawing.Font]::new('Segoe UI',[single]10,[Drawing.FontStyle]::Regular)
    $button.TextAlign=[Drawing.ContentAlignment]::MiddleLeft
    $button.Padding=[Windows.Forms.Padding]::new(10,0,7,0)
    $button.Text=$Text
    $button.Margin=[Windows.Forms.Padding]::new(0,0,0,5)
    $button.Cursor=[Windows.Forms.Cursors]::Hand
    $button.Tag=@{Action=$Action;Value=$Value;Role=$Role;Id=$Id}
    if($Action){
        $button.add_Click({
            param($sender,$e)
            try{
                $args=$sender.Tag
                Invoke-GuardModernAction -Action ([string]$args.Action) -Value ([string]$args.Value) -Role ([string]$args.Role) -Id ([string]$args.Id)
            }catch{
                Write-GuardEvent 'ModernMenuActionError' @{Message=$_.Exception.Message}
                [Windows.Forms.MessageBox]::Show('Операция не выполнена: '+$_.Exception.Message,'uTempGuard')|Out-Null
            }
        })
    }else{$button.Enabled=$false}
    return $button
}
function Add-GuardModernRow {
    param([string]$Text,[string]$Action='', [string]$Value='', [string]$Role='', [string]$Id='', [switch]$Accent,[switch]$Danger,[int]$Height=45)
    $row=New-GuardModernRow -Text $Text -Action $Action -Value $Value -Role $Role -Id $Id -Accent:$Accent -Danger:$Danger -Height $Height
    [void]$script:modernBody.Controls.Add($row)
}
function Add-GuardModernSeparator {
    $line=[Windows.Forms.Panel]::new()
    $line.Width=381;$line.Height=1
    $line.BackColor=[Drawing.ColorTranslator]::FromHtml('#34445C')
    $line.Margin=[Windows.Forms.Padding]::new(0,6,0,10)
    [void]$script:modernBody.Controls.Add($line)
}
function Get-GuardModernModeDescription {
    param([string]$Role)
    $mode=[string]$script:temperaturePolicy.($Role+'Mode')
    $title=Get-GuardSourceTitle -Mode $mode
    if($Role -eq 'Display'){return $title}
    $approved=Test-GuardActionSourceApproval -Policy $script:temperaturePolicy -ReceiptPath $script:sourceApprovalPath -ConfigPath $ConfigPath
    if(-not $approved -or -not (Test-LiveApproval)){return 'НЕТ ДОПУСКА · '+$title}
    return 'Активно · '+$title
}
function Render-GuardModernPage {
    param([string]$Page='Home',[string]$Role='Display')
    if($null -eq $script:modernMenu -or $null -eq $script:modernBody){return}
    $script:modernPage=$Page
    $script:modernBody.SuspendLayout()
    try{
        $prior=@($script:modernBody.Controls)
        $script:modernBody.Controls.Clear()
        foreach($ctl in $prior){$ctl.Dispose()}
        if($Page -ne 'Home'){
            Add-GuardModernRow -Text '‹  НАЗАД' -Action 'Page' -Value 'Home' -Accent
            Add-GuardModernSeparator
        }
        switch($Page){
            'Home' {
                Add-GuardModernRow -Text ('◉  '+(Get-GuardModernSummaryText)) -Action 'Page' -Value 'Sensors' -Accent
                $sensorCount=if($null -ne $script:lastCpuSummary){'{0}/{1}' -f $script:lastCpuSummary.AvailableCount,$script:lastCpuSummary.ExpectedCount}else{'нет данных'}
                Add-GuardModernRow -Text ('▥  Датчики процессора  ·  '+$sensorCount+'    ›') -Action 'Page' -Value 'Sensors'
                Add-GuardModernSeparator
                Add-GuardModernRow -Text ('◉  ПОКАЗЫВАТЬ ЧТО  ›'+[Environment]::NewLine+'      '+(Get-GuardModernModeDescription -Role Display)) -Action 'Page' -Value 'Display' -Height 62
                Add-GuardModernRow -Text ('⏻  ВЫКЛЮЧАТЬ ПК ПО ТЕМПЕРАТУРЕ  ›'+[Environment]::NewLine+'      '+(Get-GuardModernModeDescription -Role Shutdown)) -Action 'Page' -Value 'Shutdown' -Height 68
                Add-GuardModernSeparator
                $style=if($script:overlaySettings.Style -eq 'Compact'){'Компактный'}else{'Полный'}
                Add-GuardModernRow -Text ('▣  Вид индикатора  ·  '+$style+'    ›') -Action 'Page' -Value 'Style'
                Add-GuardModernRow -Text ('◉  Показывать фон  ·  '+$(if($script:overlaySettings.ShowBackground){'ВКЛ'}else{'ВЫКЛ'})) -Action 'ToggleBackground'
                Add-GuardModernRow -Text ('◉  Показывать индикатор  ·  '+$(if($script:overlaySettings.Visible){'ВКЛ'}else{'ВЫКЛ'})) -Action 'ToggleVisible'
                Add-GuardModernRow -Text '◈  Прозрачность и положение  ›' -Action 'Page' -Value 'Appearance'
                Add-GuardModernRow -Text 'A+  Увеличить шрифт' -Action 'Font' -Value 'Increase'
                Add-GuardModernRow -Text 'A−  Уменьшить шрифт' -Action 'Font' -Value 'Decrease'
                Add-GuardModernSeparator
                Add-GuardModernRow -Text '⌂  О проекте · GitHub ↗' -Action 'OpenUrl' -Value 'https://github.com/sunpole/uTempGuard'
                Add-GuardModernRow -Text '↓  Последний релиз ↗' -Action 'OpenUrl' -Value 'https://github.com/sunpole/uTempGuard/releases/latest'
                Add-GuardModernRow -Text '↻  Проверить обновления (только проверка)' -Action 'CheckUpdates'
                Add-GuardModernRow -Text 'ⓘ  Сведения о программе  ›' -Action 'Page' -Value 'About'
                Add-GuardModernSeparator
                Add-GuardModernRow -Text '⏻  Остановить uTempGuard' -Action 'Stop' -Danger
            }
            'Sensors' {
                Add-GuardModernRow -Text 'ДАТЧИКИ ПРОЦЕССОРА'
                if($null -eq $script:lastCpuSummary){
                    Add-GuardModernRow -Text 'Ожидание достоверных показаний AIDA64'
                }else{
                    foreach($sensor in $script:lastCpuSummary.Sensors){
                        $t=if($sensor.State -eq 'Valid'){('{0:N0}°C' -f $sensor.TemperatureC)}else{$sensor.State}
                        Add-GuardModernRow -Text ('    '+$sensor.Label+'  ·  '+$t)
                    }
                }
            }
            {$_ -in @('Display','Shutdown')} {
                $role=$Page
                Add-GuardModernRow -Text $(if($role -eq 'Display'){'ПОКАЗЫВАТЬ ЧТО:'}else{'ВЫКЛЮЧАТЬ ПК ПО ТЕМПЕРАТУРЕ:'})
                $mode=[string]$script:temperaturePolicy.($role+'Mode')
                foreach($o in @(
                    @{K='All';T='1. Всё, что экспортирует AIDA64'},
                    @{K='Cores';T='2. Максимум всех ядер'},
                    @{K='CoresCpu';T='3. Ядра + ЦП'},
                    @{K='CoresCpuPackage';T='4. Ядра + ЦП + CPU Package'},
                    @{K='LegacyCpu';T='↺  Как раньше: Package + ядра'}
                )){
                    $tick=if($mode -eq $o.K){'●'}else{'○'}
                    Add-GuardModernRow -Text ($tick+'  '+$o.T) -Action 'ChooseMode' -Value $o.K -Role $role -Accent:($mode -eq $o.K)
                }
                $tick=if($mode -eq 'Custom'){'●'}else{'○'}
                Add-GuardModernRow -Text ($tick+'  5. Свой набор датчиков (галочки)  ›') -Action 'Page' -Value ($role+'Custom') -Accent:($mode -eq 'Custom')
                if($role -eq 'Shutdown'){
                    Add-GuardModernSeparator
                    $ready=Test-GuardActionSourceApproval -Policy $script:temperaturePolicy -ReceiptPath $script:sourceApprovalPath -ConfigPath $ConfigPath
                    $info=if($ready -and (Test-LiveApproval)){'✓ Источник выключения подтверждён'}else{'⚠ Нужен отдельный допуск'}
                    Add-GuardModernRow -Text $info
                    if($mode -notin @('LegacyCpu','Disabled')){
                        Add-GuardModernRow -Text '✓  Подтвердить выбранные датчики' -Action 'ConfirmSource' -Accent
                    }
                    Add-GuardModernRow -Text 'Выключение при 75°C требует живых датчиков.'
                }
            }
            {$_ -in @('DisplayCustom','ShutdownCustom')} {
                $role=if($Page -eq 'DisplayCustom'){'Display'}else{'Shutdown'}
                Add-GuardModernRow -Text ('ВЫБРАТЬ ДАТЧИКИ · '+$role)
                if($null -eq $script:lastTemperatureCatalog -or -not $script:lastTemperatureCatalog.Healthy){
                    Add-GuardModernRow -Text 'Ожидание достоверного экспорта AIDA64'
                }else{
                    foreach($sensor in @($script:lastTemperatureCatalog.Sensors | Sort-Object Category,Id)){
                        $checked=($script:temperaturePolicy.($role+'Mode') -eq 'Custom' -and $sensor.Id -cin @($script:temperaturePolicy.($role+'Ids')))
                        $sign=if($checked){'☑'}else{'☐'}
                        $temp=if($sensor.State -eq 'Valid'){('{0:N0}°C' -f $sensor.TemperatureC)}else{'недоступен'}
                        Add-GuardModernRow -Text ($sign+'  '+$sensor.Label+' · '+$temp) -Action 'ToggleSensor' -Role $role -Id $sensor.Id -Accent:$checked
                    }
                }
            }
            'Style' {
                Add-GuardModernRow -Text 'ВИД ИНДИКАТОРА'
                Add-GuardModernRow -Text '▣  Компактный' -Action 'Style' -Value 'Compact' -Accent:($script:overlaySettings.Style -eq 'Compact')
                Add-GuardModernRow -Text '▤  Полный' -Action 'Style' -Value 'Full' -Accent:($script:overlaySettings.Style -eq 'Full')
            }
            'Appearance' {
                Add-GuardModernRow -Text 'НЕПРОЗРАЧНОСТЬ'
                foreach($opacity in @(60,80,90,100)){
                    Add-GuardModernRow -Text ('▤  '+$opacity+'%') -Action 'Opacity' -Value ([string]$opacity) -Accent:($script:overlaySettings.Opacity -eq $opacity)
                }
                Add-GuardModernSeparator
                Add-GuardModernRow -Text 'ПОЛОЖЕНИЕ ИНДИКАТОРА'
                foreach($p in @(
                   @{K='TopRight';T='Справа сверху'},
                   @{K='TopLeft';T='Слева сверху'},
                   @{K='BottomRight';T='Справа снизу'},
                   @{K='BottomLeft';T='Слева снизу'}
                )){
                   Add-GuardModernRow -Text ('◈  '+$p.T) -Action 'Position' -Value $p.K -Accent:($script:overlaySettings.Position -eq $p.K)
                }
            }
            'About' {
                Add-GuardModernRow -Text 'uTempGuard v0.3.0 · современное меню'
                Add-GuardModernRow -Text 'Официальный логотип из SVG пользователя.'
                Add-GuardModernRow -Text 'Раздельные источники: показ и выключение.'
                Add-GuardModernRow -Text 'Проверенные датчики AIDA64 · PowerShell 5.1'
                Add-GuardModernSeparator
                Add-GuardModernRow -Text 'GitHub · исходники и история ↗' -Action 'OpenUrl' -Value 'https://github.com/sunpole/uTempGuard'
                Add-GuardModernRow -Text 'Последний выпуск ↗' -Action 'OpenUrl' -Value 'https://github.com/sunpole/uTempGuard/releases/latest'
                Add-GuardModernRow -Text 'Документация ↗' -Action 'OpenUrl' -Value 'https://github.com/sunpole/uTempGuard#readme'
            }
        }
    } finally{
        $script:modernBody.ResumeLayout()
    }
}
function Invoke-GuardModernAction {
    param([string]$Action,[string]$Value='',[string]$Role='',[string]$Id='')
    switch($Action){
        'Page' {Render-GuardModernPage -Page $Value; return}
        'ToggleBackground' {Set-GuardOverlayPreference -Name ShowBackground -Value (-not $script:overlaySettings.ShowBackground)}
        'ToggleVisible' {Set-GuardOverlayPreference -Name Visible -Value (-not $script:overlaySettings.Visible)}
        'Font' {
            $delta=if($Value -eq 'Increase'){1}else{-1}
            Set-GuardOverlayPreference -Name FontSize -Value ([int]$script:overlaySettings.FontSize+$delta)
        }
        'Style' {Set-GuardOverlayPreference -Name Style -Value $Value}
        'Opacity' {Set-GuardOverlayPreference -Name Opacity -Value ([int]::Parse($Value))}
        'Position' {Set-GuardOverlayPreference -Name Position -Value $Value}
        'ChooseMode' {
            $script:modernModal=$true
            try{Set-GuardSourceChoice -Role $Role -Mode $Value}
            finally{$script:modernModal=$false}
        }
        'ToggleSensor' {
            $script:modernModal=$true
            try{Set-GuardSourceChoice -Role $Role -Mode 'Custom' -Id $Id}
            finally{$script:modernModal=$false}
        }
        'ConfirmSource' {
            $script:modernModal=$true
            try{Confirm-GuardActionSource}
            finally{$script:modernModal=$false}
        }
        'CheckUpdates' {
            $updater=Join-Path $PSScriptRoot '..\Update-uTempGuard.ps1'
            if(-not (Test-Path -LiteralPath $updater -PathType Leaf)){throw 'Updater не найден'}
            $ps=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $arguments='-NoExit -NoProfile -ExecutionPolicy Bypass -File "'+[IO.Path]::GetFullPath($updater)+'" -Action Preview'
            Start-Process -FilePath $ps -ArgumentList $arguments
            if($null -ne $script:modernMenu){$script:modernMenu.Hide()}
            return
        }
        'OpenUrl' {
            if($Value -notin @(
                'https://github.com/sunpole/uTempGuard',
                'https://github.com/sunpole/uTempGuard/releases/latest',
                'https://github.com/sunpole/uTempGuard#readme')){return}
            Start-Process -FilePath $Value
            if($null -ne $script:modernMenu){$script:modernMenu.Hide()}
            return
        }
        'Stop' {
            [IO.File]::WriteAllText($stopPath,'stop')
            if($null -ne $script:modernMenu){$script:modernMenu.Hide()}
            return
        }
        default {return}
    }
    if($null -ne $script:modernMenu){Render-GuardModernPage -Page $script:modernPage}
}
function Show-GuardModernMenu {
    if($null -eq $script:modernMenu){return}
    if($script:modernMenu.Visible){
        $script:modernMenu.Hide()
        return
    }
    Render-GuardModernPage -Page 'Home'
    $cursor=[Windows.Forms.Cursor]::Position
    $area=[Windows.Forms.Screen]::FromPoint($cursor).WorkingArea
    $x=[math]::Max($area.Left,[math]::Min($cursor.X-400,$area.Right-$script:modernMenu.Width))
    $y=[math]::Max($area.Top,[math]::Min($cursor.Y-$script:modernMenu.Height+15,$area.Bottom-$script:modernMenu.Height))
    $script:modernMenu.Location=[Drawing.Point]::new([int]$x,[int]$y)
    $script:modernMenu.Show()
    $script:modernMenu.Activate()
}
function Set-GuardModernRoundedRegion {
    param([Windows.Forms.Form]$Form)
    $radius=16
    $edge=$radius*2
    $width=$Form.ClientSize.Width
    $height=$Form.ClientSize.Height
    $path=[Drawing.Drawing2D.GraphicsPath]::new()
    try{
        $path.AddArc(0,0,$edge,$edge,180,90)
        $path.AddArc($width-$edge-1,0,$edge,$edge,270,90)
        $path.AddArc($width-$edge-1,$height-$edge-1,$edge,$edge,0,90)
        $path.AddArc(0,$height-$edge-1,$edge,$edge,90,90)
        $path.CloseFigure()
        $region=[Drawing.Region]::new($path)
        $old=$Form.Region
        $Form.Region=$region
        if($null -ne $old){$old.Dispose()}
    }finally{$path.Dispose()}
}
function Initialize-GuardModernMenu {
    # Keep the old standard context menu as a fallback if this UI initialization fails.
    $form=[Windows.Forms.Form]::new()
    $form.FormBorderStyle=[Windows.Forms.FormBorderStyle]::None
    $form.StartPosition=[Windows.Forms.FormStartPosition]::Manual
    $form.ShowInTaskbar=$false
    $form.TopMost=$true
    $form.BackColor=$script:modernDark
    $form.ForeColor=$script:modernText
    $form.ClientSize=[Drawing.Size]::new(415,625)
    Set-GuardModernRoundedRegion -Form $form
    $form.KeyPreview=$true
    $form.add_KeyDown({param($sender,$e) if($e.KeyCode -eq [Windows.Forms.Keys]::Escape){$sender.Hide()}})
    $form.add_Deactivate({if(-not $script:modernModal){$script:modernMenu.Hide()}})
    $header=[Windows.Forms.Panel]::new()
    $header.Dock='Top'
    $header.Height=87
    $header.BackColor=[Drawing.ColorTranslator]::FromHtml('#17263D')
    [void]$form.Controls.Add($header)
    $logo=Get-GuardOfficialLogo
    if($null -ne $logo){
        $picture=[Windows.Forms.PictureBox]::new()
        $picture.Image=$logo
        $picture.SizeMode=[Windows.Forms.PictureBoxSizeMode]::Zoom
        $picture.Bounds=[Drawing.Rectangle]::new(16,12,58,58)
        [void]$header.Controls.Add($picture)
    }
    $title=[Windows.Forms.Label]::new()
    $title.Text='uTempGuard'
    $title.ForeColor=$script:modernText
    $title.Font=[Drawing.Font]::new('Segoe UI',[single]17,[Drawing.FontStyle]::Bold)
    $title.Bounds=[Drawing.Rectangle]::new(86,10,315,36)
    [void]$header.Controls.Add($title)
    $subtitle=[Windows.Forms.Label]::new()
    $subtitle.ForeColor=$script:modernMuted
    $subtitle.Text='Контроль температур · Защита системы'
    $subtitle.Font=[Drawing.Font]::new('Segoe UI',[single]9)
    $subtitle.Bounds=[Drawing.Rectangle]::new(88,48,300,24)
    [void]$header.Controls.Add($subtitle)
    $footer=[Windows.Forms.Panel]::new()
    $footer.Dock='Bottom'
    $footer.Height=30
    $footer.BackColor=$script:modernDark
    $copyright=[Windows.Forms.Label]::new()
    $copyright.ForeColor=$script:modernMuted
    $copyright.Text='uTempGuard  ·  GitHub  ·  Esc — закрыть'
    $copyright.TextAlign=[Drawing.ContentAlignment]::MiddleCenter
    $copyright.Dock='Fill'
    [void]$footer.Controls.Add($copyright)
    [void]$form.Controls.Add($footer)
    $body=[Windows.Forms.FlowLayoutPanel]::new()
    $body.Dock='Fill'
    $body.FlowDirection=[Windows.Forms.FlowDirection]::TopDown
    $body.WrapContents=$false
    $body.AutoScroll=$true
    $body.BackColor=$script:modernDark
    $body.Padding=[Windows.Forms.Padding]::new(10,11,0,8)
    [void]$form.Controls.Add($body)
    # Explicit z-order controls: docked header+footer must not be covered by body.
    $header.BringToFront()
    $footer.BringToFront()
    $script:modernMenu=$form
    $script:modernBody=$body
    # The official asset is rasterized from the committed SVG at build time.
    if($null -ne $logo){
        try{
            $handle=$logo.GetHicon()
            $icon=[Drawing.Icon]::FromHandle($handle)
            $script:modernIcon=[Drawing.Icon]$icon.Clone()
            $script:tray.Icon=$script:modernIcon
        }catch{Write-GuardEvent 'BrandIconFallback' @{Reason='IconConversionFailed'}}
    }
    $script:form.ContextMenuStrip=$null
    $script:tray.ContextMenuStrip=$null
    $script:tray.add_MouseUp({param($sender,$e)
        if($e.Button -eq [Windows.Forms.MouseButtons]::Right){Show-GuardModernMenu}
    })
    $script:form.add_MouseUp({param($sender,$e)
        if($e.Button -eq [Windows.Forms.MouseButtons]::Right){Show-GuardModernMenu}
    })
    $script:label.add_MouseUp({param($sender,$e)
        if($e.Button -eq [Windows.Forms.MouseButtons]::Right){Show-GuardModernMenu}
    })
}
function Close-GuardModernMenu {
    if($null -ne $script:modernMenu){$script:modernMenu.Hide();$script:modernMenu.Dispose();$script:modernMenu=$null}
    if($null -ne $script:modernIcon){$script:modernIcon.Dispose();$script:modernIcon=$null}
    if($null -ne $script:modernImage){$script:modernImage.Dispose();$script:modernImage=$null}
}
