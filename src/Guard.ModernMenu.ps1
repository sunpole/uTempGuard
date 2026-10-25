# Compact responsive Windows 10 WinForms UI. Presentation-only; no changed power actions.
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
$script:modernMenu=$null
$script:modernBody=$null
$script:modernSubtitle=$null
$script:modernBackButton=$null
$script:modernIcon=$null
$script:modernImage=$null
$script:modernModal=$false
$script:modernPage='Home'
$script:modernSensorPage=0
$script:modernPageSize=12
$script:modernRowHeight=26
$script:modernWidth=370
$script:modernHeaderHeight=55
$script:modernFooterHeight=21
$script:modernDark=[Drawing.ColorTranslator]::FromHtml('#101827')
$script:modernSurface=[Drawing.ColorTranslator]::FromHtml('#182438')
$script:modernHover=[Drawing.ColorTranslator]::FromHtml('#283B57')
$script:modernText=[Drawing.ColorTranslator]::FromHtml('#F1F5F9')
$script:modernMuted=[Drawing.ColorTranslator]::FromHtml('#A8BDD3')
$script:modernAccent=[Drawing.ColorTranslator]::FromHtml('#22D3EE')
$script:modernWarning=[Drawing.ColorTranslator]::FromHtml('#F59E0B')
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

function Get-GuardUiText {
    param([string]$Key,[object[]]$Values=@())
    Get-GuardText -Key $Key -Values $Values
}
function Get-GuardModernSummaryText {
    if($null -eq $script:lastSample -or -not $script:lastSample.Healthy){
        return (Get-GuardUiText 'home.waiting')
    }
    $selected=$script:lastDisplayTemperature
    $c=if($null -ne $selected -and $selected.Healthy){$selected.MaxC}else{$script:lastSample.TemperatureC}
    if($null -eq $c){return (Get-GuardUiText 'home.waiting')}
    $number=([int][math]::Round([double]$c)).ToString([Globalization.CultureInfo]::InvariantCulture)
    return (Get-GuardUiText 'home.temperature' @($number))
}
function Get-GuardModernMode {
    param([string]$Role)
    $mode=[string]$script:temperaturePolicy.($Role+'Mode')
    if($Role -eq 'Shutdown'){
        $approved=Test-GuardActionSourceApproval -Policy $script:temperaturePolicy -ReceiptPath $script:sourceApprovalPath -ConfigPath $ConfigPath
        if(-not $approved -or -not (Test-LiveApproval)){
            return (Get-GuardUiText 'approval.notApproved')
        }
    }
    return (Get-GuardUiText ('mode.'+$mode))
}
function New-GuardModernRow {
    param([string]$Text,[string]$Action='',[string]$Value='',[string]$Role='',[string]$Id='',[switch]$Accent,[switch]$Danger,[switch]$Warning)
    $btn=[Windows.Forms.Button]::new()
    $btn.Width=342
    $btn.Height=$script:modernRowHeight
    $btn.Font=[Drawing.Font]::new('Segoe UI',[single]9,[Drawing.FontStyle]::Regular)
    $btn.FlatStyle=[Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize=0
    $btn.FlatAppearance.MouseOverBackColor=$script:modernHover
    $btn.BackColor=if($Accent){[Drawing.ColorTranslator]::FromHtml('#163959')}else{$script:modernSurface}
    $btn.ForeColor=if($Danger){[Drawing.ColorTranslator]::FromHtml('#FF7777')}elseif($Warning){$script:modernWarning}elseif($Accent){$script:modernAccent}else{$script:modernText}
    $btn.UseMnemonic=$false
    $btn.AutoEllipsis=$true
    $btn.TextAlign=[Drawing.ContentAlignment]::MiddleLeft
    $btn.Padding=[Windows.Forms.Padding]::new(7,0,4,0)
    $btn.Margin=[Windows.Forms.Padding]::new(0,0,0,1)
    $btn.Cursor=if($Action){[Windows.Forms.Cursors]::Hand}else{[Windows.Forms.Cursors]::Default}
    $btn.Text=$Text
    $btn.AccessibleName=$Text
    $btn.Tag=@{Action=$Action;Value=$Value;Role=$Role;Id=$Id}
    if($Action){
        $btn.add_Click({
            param($sender,$e)
            try{
                $a=$sender.Tag
                Invoke-GuardModernAction -Action ([string]$a.Action) -Value ([string]$a.Value) -Role ([string]$a.Role) -Id ([string]$a.Id)
            }catch{
                Write-GuardEvent 'ModernMenuActionError' @{Message=$_.Exception.Message}
                $errorMessage=Get-GuardUiText 'error.action' @($_.Exception.Message)
                [Windows.Forms.MessageBox]::Show($errorMessage,'uTempGuard')|Out-Null
            }
        })
    }
    return $btn
}
function Add-GuardModernRow {
    param([string]$Text,[string]$Action='',[string]$Value='',[string]$Role='',[string]$Id='',[switch]$Accent,[switch]$Danger,[switch]$Warning)
    if([string]::IsNullOrWhiteSpace($Action)){
        # Static information is a Label, never a disabled button pretending to be clickable.
        $info=[Windows.Forms.Label]::new()
        $info.Width=342
        $info.Height=$script:modernRowHeight
        $info.BackColor=$script:modernDark
        $info.ForeColor=if($Warning){$script:modernWarning}else{$script:modernMuted}
        $info.Font=[Drawing.Font]::new('Segoe UI',[single]9)
        $info.AutoEllipsis=$true
        $info.TextAlign=[Drawing.ContentAlignment]::MiddleLeft
        $info.Padding=[Windows.Forms.Padding]::new(8,0,4,0)
        $info.Margin=[Windows.Forms.Padding]::new(0,0,0,1)
        $info.Text=$Text
        $info.AccessibleName=$Text
        [void]$script:modernBody.Controls.Add($info)
        return
    }
    $btn=New-GuardModernRow -Text $Text -Action $Action -Value $Value -Role $Role -Id $Id -Accent:$Accent -Danger:$Danger -Warning:$Warning
    [void]$script:modernBody.Controls.Add($btn)
}
function Add-GuardModernSeparator {
    $line=[Windows.Forms.Panel]::new()
    $line.Width=342
    $line.Height=1
    $line.Margin=[Windows.Forms.Padding]::new(0,3,0,4)
    $line.BackColor=[Drawing.ColorTranslator]::FromHtml('#34445C')
    [void]$script:modernBody.Controls.Add($line)
}
function Set-GuardModernRoundedRegion {
    param([Windows.Forms.Form]$Form)
    $width=$Form.ClientSize.Width;$height=$Form.ClientSize.Height
    $diameter=26
    $path=[Drawing.Drawing2D.GraphicsPath]::new()
    try{
        $path.AddArc(0,0,$diameter,$diameter,180,90)
        $path.AddArc($width-$diameter-1,0,$diameter,$diameter,270,90)
        $path.AddArc($width-$diameter-1,$height-$diameter-1,$diameter,$diameter,0,90)
        $path.AddArc(0,$height-$diameter-1,$diameter,$diameter,90,90)
        $path.CloseFigure()
        $region=[Drawing.Region]::new($path)
        $old=$Form.Region
        $Form.Region=$region
        if($null -ne $old){$old.Dispose()}
    }finally{$path.Dispose()}
}
function Get-GuardModernPageMetrics {
    param([int]$WorkingHeight=720)
    $content=16
    if($null -ne $script:modernBody){
        foreach($ctl in $script:modernBody.Controls){
            $content+=[int]$ctl.Height+[int]$ctl.Margin.Top+[int]$ctl.Margin.Bottom
        }
    }
    $maximum=[math]::Max(140,$WorkingHeight-16)
    $desired=$content+$script:modernHeaderHeight+$script:modernFooterHeight
    $height=[int][math]::Min($maximum,[math]::Max(142,$desired))
    [pscustomobject]@{Height=$height;ContentHeight=$content;AvailableContentHeight=$height-$script:modernHeaderHeight-$script:modernFooterHeight;Overflow=($desired -gt $maximum);Controls=$(if($null -eq $script:modernBody){0}else{$script:modernBody.Controls.Count})}
}
function Update-GuardModernLayout {
    if($null -eq $script:modernMenu){return}
    $area=[Windows.Forms.Screen]::FromPoint([Windows.Forms.Cursor]::Position).WorkingArea
    $metrics=Get-GuardModernPageMetrics -WorkingHeight $area.Height
    $script:modernMenu.ClientSize=[Drawing.Size]::new($script:modernWidth,$metrics.Height)
    # AutoScroll is a fallback on exceptionally small screens only.
    $script:modernBody.AutoScroll=$metrics.Overflow
    Set-GuardModernRoundedRegion -Form $script:modernMenu
    if($script:modernMenu.Visible){
        $pt=$script:modernMenu.Location
        $x=[math]::Max($area.Left,[math]::Min($pt.X,$area.Right-$script:modernMenu.Width))
        $y=[math]::Max($area.Top,[math]::Min($pt.Y,$area.Bottom-$script:modernMenu.Height))
        $script:modernMenu.Location=[Drawing.Point]::new([int]$x,[int]$y)
    }
}
function Get-GuardModernParentPage {
    param([string]$Page)
    if($Page -in @('DisplayCustom','ShutdownCustom')){return $(if($Page -eq 'DisplayCustom'){'Display'}else{'Shutdown'})}
    if($Page -in @('Opacity','Positions')){return 'Appearance'}
    return 'Home'
}
function Invoke-GuardModernBack {
    if($script:modernPage -eq 'Home'){return}
    Render-GuardModernPage -Page (Get-GuardModernParentPage -Page $script:modernPage)
}
function Render-GuardModernPage {
    param([string]$Page='Home')
    if($null -eq $script:modernMenu -or $null -eq $script:modernBody){return}
    $script:modernPage=$Page
    $script:modernBody.SuspendLayout()
    try{
        $previous=@($script:modernBody.Controls)
        $script:modernBody.Controls.Clear()
        foreach($item in $previous){$item.Dispose()}
        # Back navigation lives in the fixed header, outside scrolling content.
        if($null -ne $script:modernBackButton){
            $script:modernBackButton.Visible=($Page -ne 'Home')
            $script:modernBackButton.AccessibleName=Get-GuardUiText 'nav.back'
        }
        switch($Page){
            'Home' {
                Add-GuardModernRow -Text (Get-GuardModernSummaryText) -Action 'Page' -Value 'Sensors' -Accent
                $count=if($null -ne $script:lastCpuSummary){
                    Get-GuardUiText 'home.sensors' @($script:lastCpuSummary.AvailableCount,$script:lastCpuSummary.ExpectedCount)
                }else{Get-GuardUiText 'home.sensorsMissing'}
                Add-GuardModernRow -Text $count -Action 'Page' -Value 'Sensors'
                Add-GuardModernSeparator
                Add-GuardModernRow -Text (Get-GuardUiText 'home.display' @((Get-GuardModernMode Display))) -Action 'Page' -Value 'Display'
                $powerStatus=Get-GuardModernMode Shutdown
                Add-GuardModernRow -Text (Get-GuardUiText 'home.shutdown' @($powerStatus)) -Action 'Page' -Value 'Shutdown' -Warning:($powerStatus -eq (Get-GuardUiText 'approval.notApproved'))
                Add-GuardModernSeparator
                $style=Get-GuardUiText ('appearance.style'+$(if($script:overlaySettings.Style -eq 'Compact'){'Compact'}else{'Full'}))
                Add-GuardModernRow -Text (Get-GuardUiText 'home.appearance' @($style)) -Action 'Page' -Value 'Appearance'
                $lang=Get-GuardCurrentLanguage
                Add-GuardModernRow -Text (Get-GuardUiText 'home.language' @((Get-GuardUiText ('language.'+$lang)))) -Action 'Page' -Value 'Language'
                Add-GuardModernSeparator
                Add-GuardModernRow -Text (Get-GuardUiText 'home.project') -Action 'OpenUrl' -Value 'https://github.com/sunpole/uTempGuard'
                Add-GuardModernRow -Text (Get-GuardUiText 'home.updates') -Action 'Page' -Value 'Updates'
                Add-GuardModernRow -Text (Get-GuardUiText 'home.about') -Action 'Page' -Value 'About'
                Add-GuardModernSeparator
                Add-GuardModernRow -Text (Get-GuardUiText 'home.stop') -Action 'Stop' -Danger
            }
            'Display' {Show-GuardModernModes -Role Display}
            'Shutdown' {Show-GuardModernModes -Role Shutdown}
            'DisplayCustom' {Show-GuardModernCustomSensors -Role Display}
            'ShutdownCustom' {Show-GuardModernCustomSensors -Role Shutdown}
            'Sensors' {
                Add-GuardModernRow -Text (Get-GuardUiText 'page.sensors')
                if($null -eq $script:lastCpuSummary){
                    Add-GuardModernRow -Text (Get-GuardUiText 'option.noSensors')
                }else{
                    foreach($sensor in $script:lastCpuSummary.Sensors){
                        $reading=if($sensor.State -eq 'Valid'){('{0:N0}°C' -f $sensor.TemperatureC)}
                            else{Get-GuardUiText 'option.invalid'}
                        Add-GuardModernRow -Text ('  '+$sensor.Label+' · '+$reading)
                    }
                }
            }
            'Appearance' {
                Add-GuardModernRow -Text (Get-GuardUiText 'page.appearance')
                foreach($style in @('Compact','Full')){
                    $text=Get-GuardUiText ('appearance.style'+$style)
                    Add-GuardModernRow -Text ('  '+$text) -Action 'Style' -Value $style -Accent:($script:overlaySettings.Style -eq $style)
                }
                Add-GuardModernSeparator
                $back=Get-GuardUiText 'appearance.showBackground'
                $shown=Get-GuardUiText $(if($script:overlaySettings.ShowBackground){'nav.on'}else{'nav.off'})
                Add-GuardModernRow -Text ($back+' · '+$shown) -Action 'ToggleBackground'
                $label=Get-GuardUiText 'appearance.showIndicator'
                $shown=Get-GuardUiText $(if($script:overlaySettings.Visible){'nav.on'}else{'nav.off'})
                Add-GuardModernRow -Text ($label+' · '+$shown) -Action 'ToggleVisible'
                Add-GuardModernRow -Text (Get-GuardUiText 'appearance.opacity') -Action 'Page' -Value 'Opacity'
                Add-GuardModernRow -Text (Get-GuardUiText 'appearance.position') -Action 'Page' -Value 'Positions'
                Add-GuardModernRow -Text (Get-GuardUiText 'gallery.open') -Action 'OpenGallery'
                Add-GuardModernSeparator
                Add-GuardModernRow -Text (Get-GuardUiText 'appearance.fontUp') -Action 'Font' -Value 'Increase'
                Add-GuardModernRow -Text (Get-GuardUiText 'appearance.fontDown') -Action 'Font' -Value 'Decrease'
            }
            'Opacity' {
                Add-GuardModernRow -Text (Get-GuardUiText 'page.opacity')
                foreach($percentage in @(60,80,90,100)){
                    Add-GuardModernRow -Text ($percentage.ToString()+'%') -Action 'Opacity' -Value ([string]$percentage) -Accent:($script:overlaySettings.Opacity -eq $percentage)
                }
            }
            'Positions' {
                Add-GuardModernRow -Text (Get-GuardUiText 'page.positions')
                foreach($mode in @('TopRight','TopLeft','BottomRight','BottomLeft')){
                    Add-GuardModernRow -Text (Get-GuardUiText ('appearance.positions.'+$mode.Substring(0,1).ToLowerInvariant()+$mode.Substring(1))) -Action 'Position' -Value $mode -Accent:($script:overlaySettings.Position -eq $mode)
                }
            }
            'Language' {
                Add-GuardModernRow -Text (Get-GuardUiText 'page.language')
                foreach($locale in @(Get-GuardSupportedLanguages)){
                    Add-GuardModernRow -Text (Get-GuardUiText ('language.'+$locale)) -Action 'SetLanguage' -Value $locale -Accent:((Get-GuardCurrentLanguage) -ceq $locale)
                }
                Add-GuardModernRow -Text (Get-GuardUiText 'language.hint')
            }
            'Updates' {
                Add-GuardModernRow -Text (Get-GuardUiText 'page.updates')
                Add-GuardModernRow -Text (Get-GuardUiText 'updates.check') -Action 'CheckUpdates'
                if(-not [bool]$SimulationPath){
                    Add-GuardModernRow -Text (Get-GuardUiText 'updates.apply') -Action 'ApplyUpdate'
                }
                Add-GuardModernRow -Text (Get-GuardUiText 'updates.release') -Action 'OpenUrl' -Value 'https://github.com/sunpole/uTempGuard/releases/latest'
                Add-GuardModernRow -Text (Get-GuardUiText 'updates.docs') -Action 'OpenUrl' -Value 'https://github.com/sunpole/uTempGuard#readme'
                Add-GuardModernRow -Text (Get-GuardUiText 'updates.manual')
            }
            'About' {
                Add-GuardModernRow -Text (Get-GuardUiText 'page.about')
                foreach($key in @('about.version','about.details','about.sources')){
                    Add-GuardModernRow -Text (Get-GuardUiText $key)
                }
                Add-GuardModernRow -Text (Get-GuardUiText 'about.logoLink') -Action 'OpenUrl' -Value 'https://github.com/sunpole/uTempGuard/blob/main/assets/u_logo_tempg2.svg'
                Add-GuardModernRow -Text (Get-GuardUiText 'gallery.open') -Action 'OpenGallery'
                Add-GuardModernRow -Text (Get-GuardUiText 'about.github') -Action 'OpenUrl' -Value 'https://github.com/sunpole/uTempGuard'
                Add-GuardModernRow -Text (Get-GuardUiText 'about.release') -Action 'OpenUrl' -Value 'https://github.com/sunpole/uTempGuard/releases/latest'
                Add-GuardModernRow -Text (Get-GuardUiText 'about.docs') -Action 'OpenUrl' -Value 'https://github.com/sunpole/uTempGuard#readme'
            }
            default {Add-GuardModernRow -Text (Get-GuardUiText 'option.noData')}
        }
    }finally{
        $script:modernBody.ResumeLayout()
        Update-GuardModernLayout
    }
}
function Show-GuardModernModes {
    param([string]$Role)
    $mode=[string]$script:temperaturePolicy.($Role+'Mode')
    Add-GuardModernRow -Text (Get-GuardUiText $(if($Role -eq 'Display'){'page.display'}else{'page.shutdown'}))
    foreach($option in @('All','Cores','CoresCpu','CoresCpuPackage','Custom','LegacyCpu')){
        $label=Get-GuardUiText ('option.'+$(if($option -eq 'LegacyCpu'){'legacy'}else{$option.Substring(0,1).ToLowerInvariant()+$option.Substring(1)}))
        if($option -eq 'Custom'){
            Add-GuardModernRow -Text ('☑  '+$label) -Action 'Page' -Value ($Role+'Custom') -Accent:($mode -eq $option)
        }else{
            Add-GuardModernRow -Text ('◉  '+$label) -Action 'ChooseMode' -Value $option -Role $Role -Accent:($mode -eq $option)
        }
    }
    if($Role -eq 'Shutdown'){
        Add-GuardModernSeparator
        $approved=Test-GuardActionSourceApproval -Policy $script:temperaturePolicy -ReceiptPath $script:sourceApprovalPath -ConfigPath $ConfigPath
        $active=$approved -and (Test-LiveApproval)
        Add-GuardModernRow -Text (Get-GuardUiText $(if($active){'approval.active'}else{'approval.notApproved'})) -Warning:(-not $active)
        if($mode -notin @('LegacyCpu','Disabled')){
            Add-GuardModernRow -Text (Get-GuardUiText 'approval.confirm') -Action 'ConfirmSource' -Accent
        }
    }
}
function Show-GuardModernCustomSensors {
    param([string]$Role)
    Add-GuardModernRow -Text (Get-GuardUiText $(if($Role -eq 'Display'){'page.customDisplay'}else{'page.customShutdown'}))
    if($null -eq $script:lastTemperatureCatalog -or -not $script:lastTemperatureCatalog.Healthy){
        Add-GuardModernRow -Text (Get-GuardUiText 'option.noSensors')
        return
    }
    $all=@($script:lastTemperatureCatalog.Sensors | Sort-Object Category,Id)
    if($all.Count -eq 0){Add-GuardModernRow -Text (Get-GuardUiText 'option.noSensors');return}
    $totalPages=[int][math]::Ceiling($all.Count/[double]$script:modernPageSize)
    $script:modernSensorPage=[int][math]::Max(0,[math]::Min($script:modernSensorPage,$totalPages-1))
    $first=$script:modernSensorPage*$script:modernPageSize
    $last=[math]::Min($all.Count-1,$first+$script:modernPageSize-1)
    for($i=$first;$i -le $last;$i++){
        $sensor=$all[$i]
        $checked=$script:temperaturePolicy.($Role+'Mode') -eq 'Custom' -and
            $sensor.Id -cin @($script:temperaturePolicy.($Role+'Ids'))
        $tick=if($checked){'[x]'}else{'[ ]'}
        $reading=if($sensor.State -eq 'Valid'){('{0:N0}°C' -f $sensor.TemperatureC)}
          else{Get-GuardUiText 'option.invalid'}
        Add-GuardModernRow -Text ($tick+' '+$sensor.Label+' · '+$reading) -Action 'ToggleSensor' -Role $Role -Id ([string]$sensor.Id) -Accent:$checked
    }
    if($totalPages -gt 1){
        Add-GuardModernSeparator
        if($script:modernSensorPage -gt 0){
            Add-GuardModernRow -Text ('‹ '+($script:modernSensorPage).ToString()+'/'+$totalPages) -Action 'SensorPage' -Value '-1'
        }
        if($script:modernSensorPage -lt ($totalPages-1)){
            Add-GuardModernRow -Text ('› '+($script:modernSensorPage+2).ToString()+'/'+$totalPages) -Action 'SensorPage' -Value '1'
        }
    }
}
function Invoke-GuardModernAction {
    param([string]$Action,[string]$Value='',[string]$Role='',[string]$Id='')
    switch($Action){
        'Page' {
            if($Value -in @('DisplayCustom','ShutdownCustom')){$script:modernSensorPage=0}
            Render-GuardModernPage -Page $Value;return
        }
        'SensorPage' {
            $script:modernSensorPage+=[int]::Parse($Value)
            Render-GuardModernPage -Page $script:modernPage;return
        }
        'SetLanguage' {
            $null=Set-GuardLanguage -Locale $Value
            if($null -ne $script:modernSubtitle){$script:modernSubtitle.Text=Get-GuardUiText 'app.tagline'}
            Render-GuardModernPage -Page $script:modernPage;return
        }
        'ToggleBackground' {Set-GuardOverlayPreference -Name ShowBackground -Value (-not $script:overlaySettings.ShowBackground)}
        'ToggleVisible' {Set-GuardOverlayPreference -Name Visible -Value (-not $script:overlaySettings.Visible)}
        'Font' {
            $delta=if($Value -eq 'Increase'){1}else{-1}
            $size=[math]::Max(9,[math]::Min(22,[int]$script:overlaySettings.FontSize+$delta))
            Set-GuardOverlayPreference -Name FontSize -Value $size
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
            try{Set-GuardSourceChoice -Role $Role -Mode Custom -Id $Id}
            finally{$script:modernModal=$false}
        }
        'ConfirmSource' {
            $script:modernModal=$true
            try{Confirm-GuardActionSource}
            finally{$script:modernModal=$false}
        }
        'OpenGallery' {
            $file=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\docs\icon-gallery.html'))
            if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw 'Icon gallery is not installed'}
            Start-Process -FilePath $file
            if($null -ne $script:modernMenu){$script:modernMenu.Hide()}
            return
        }
        'CheckUpdates' {Start-GuardUpdater -Mode Preview;return}
        'ApplyUpdate' {if(-not [bool]$SimulationPath){Start-GuardUpdater -Mode Apply};return}
        'OpenUrl' {
            if($Value -notin @('https://github.com/sunpole/uTempGuard',
                'https://github.com/sunpole/uTempGuard/releases/latest',
                'https://github.com/sunpole/uTempGuard#readme',
                'https://github.com/sunpole/uTempGuard/blob/main/assets/u_logo_tempg2.svg')){return}
            Start-Process -FilePath $Value
            $script:modernMenu.Hide();return
        }
        'Stop' {[IO.File]::WriteAllText($stopPath,'stop');$script:modernMenu.Hide();return}
        default {return}
    }
    if($null -ne $script:modernMenu){Render-GuardModernPage -Page $script:modernPage}
}
function Start-GuardUpdater {
    param([ValidateSet('Preview','Apply')][string]$Mode)
    $updater=Join-Path $PSScriptRoot '..\Update-uTempGuard.ps1'
    if(-not (Test-Path -LiteralPath $updater -PathType Leaf)){throw (Get-GuardUiText 'error.updaterMissing')}
    $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args='-NoExit -NoProfile -ExecutionPolicy Bypass -File "'+[IO.Path]::GetFullPath($updater)+'" -Action '+$Mode
    Start-Process -FilePath $exe -ArgumentList $args
    if($null -ne $script:modernMenu){$script:modernMenu.Hide()}
}
function Show-GuardModernMenu {
    if($null -eq $script:modernMenu){return}
    if($script:modernMenu.Visible){$script:modernMenu.Hide();return}
    Render-GuardModernPage -Page Home
    $cursor=[Windows.Forms.Cursor]::Position
    $area=[Windows.Forms.Screen]::FromPoint($cursor).WorkingArea
    $x=[math]::Max($area.Left,[math]::Min($cursor.X-$script:modernMenu.Width+20,$area.Right-$script:modernMenu.Width))
    $y=[math]::Max($area.Top,[math]::Min($cursor.Y-$script:modernMenu.Height+12,$area.Bottom-$script:modernMenu.Height))
    $script:modernMenu.Location=[Drawing.Point]::new([int]$x,[int]$y)
    $script:modernMenu.Show()
    $script:modernMenu.Activate()
}
function Initialize-GuardModernMenu {
    $form=[Windows.Forms.Form]::new()
    $form.FormBorderStyle=[Windows.Forms.FormBorderStyle]::None
    $form.StartPosition=[Windows.Forms.FormStartPosition]::Manual
    $form.ShowInTaskbar=$false
    $form.TopMost=$true
    $form.AutoScaleMode=[Windows.Forms.AutoScaleMode]::None
    $form.BackColor=$script:modernDark
    $form.ForeColor=$script:modernText
    $form.ClientSize=[Drawing.Size]::new($script:modernWidth,400)
    $form.KeyPreview=$true
    $form.add_KeyDown({param($s,$e)
        if($e.KeyCode -eq [Windows.Forms.Keys]::Escape){
            if($script:modernPage -eq 'Home'){$s.Hide()}
            else{Invoke-GuardModernBack}
            $e.Handled=$true
        }
    })
    $form.add_Deactivate({if(-not $script:modernModal){$script:modernMenu.Hide()}})
    # Strict three-row layout prevents the header from covering the first menu row.
    $layout=[Windows.Forms.TableLayoutPanel]::new()
    $layout.Dock=[Windows.Forms.DockStyle]::Fill
    $layout.ColumnCount=1
    $layout.RowCount=3
    $layout.Margin=[Windows.Forms.Padding]::new(0)
    $layout.Padding=[Windows.Forms.Padding]::new(0)
    [void]$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,[single]100))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,[single]$script:modernHeaderHeight))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,[single]100))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,[single]$script:modernFooterHeight))
    [void]$form.Controls.Add($layout)
    $header=[Windows.Forms.Panel]::new()
    $header.Dock=[Windows.Forms.DockStyle]::Fill
    $header.Margin=[Windows.Forms.Padding]::new(0)
    $header.BackColor=[Drawing.ColorTranslator]::FromHtml('#17263D')
    $layout.Controls.Add($header,0,0)
    $logo=Get-GuardOfficialLogo
    if($null -ne $logo){
        $iconbox=[Windows.Forms.PictureBox]::new()
        $iconbox.Image=$logo
        $iconbox.SizeMode=[Windows.Forms.PictureBoxSizeMode]::Zoom
        $iconbox.Bounds=[Drawing.Rectangle]::new(9,5,45,45)
        [void]$header.Controls.Add($iconbox)
    }
    $title=[Windows.Forms.Label]::new()
    $title.Text='uTempGuard'
    $title.ForeColor=$script:modernText
    $title.Font=[Drawing.Font]::new('Segoe UI',[single]14,[Drawing.FontStyle]::Bold)
    $title.Bounds=[Drawing.Rectangle]::new(62,5,298,27)
    [void]$header.Controls.Add($title)
    $subtitle=[Windows.Forms.Label]::new()
    $subtitle.Text=Get-GuardUiText 'app.tagline'
    $subtitle.ForeColor=$script:modernMuted
    $subtitle.Font=[Drawing.Font]::new('Segoe UI',[single]8)
    $subtitle.Bounds=[Drawing.Rectangle]::new(64,29,296,18)
    [void]$header.Controls.Add($subtitle)
    $script:modernSubtitle=$subtitle
    $backButton=[Windows.Forms.Button]::new()
    $backButton.Text='‹'
    $backButton.Font=[Drawing.Font]::new('Segoe UI',[single]19,[Drawing.FontStyle]::Bold)
    $backButton.FlatStyle=[Windows.Forms.FlatStyle]::Flat
    $backButton.FlatAppearance.BorderSize=0
    $backButton.FlatAppearance.MouseOverBackColor=$script:modernHover
    $backButton.BackColor=[Drawing.ColorTranslator]::FromHtml('#17263D')
    $backButton.ForeColor=$script:modernAccent
    $backButton.Bounds=[Drawing.Rectangle]::new(327,7,34,36)
    $backButton.Cursor=[Windows.Forms.Cursors]::Hand
    $backButton.Visible=$false
    $backButton.add_Click({Invoke-GuardModernBack})
    [void]$header.Controls.Add($backButton)
    $backButton.BringToFront()
    $script:modernBackButton=$backButton
    $footer=[Windows.Forms.Panel]::new()
    $footer.Dock=[Windows.Forms.DockStyle]::Fill
    $footer.Margin=[Windows.Forms.Padding]::new(0)
    $footer.BackColor=$script:modernDark
    $tip=[Windows.Forms.Label]::new()
    $tip.Text='uTempGuard · github.com/sunpole/uTempGuard'
    $tip.ForeColor=$script:modernMuted
    $tip.TextAlign=[Drawing.ContentAlignment]::MiddleCenter
    $tip.Dock='Fill'
    $tip.Font=[Drawing.Font]::new('Segoe UI',[single]8)
    [void]$footer.Controls.Add($tip)
    $layout.Controls.Add($footer,0,2)
    $body=[Windows.Forms.FlowLayoutPanel]::new()
    $body.Dock=[Windows.Forms.DockStyle]::Fill
    $body.Margin=[Windows.Forms.Padding]::new(0)
    $body.FlowDirection=[Windows.Forms.FlowDirection]::TopDown
    $body.WrapContents=$false
    $body.AutoScroll=$false
    $body.Padding=[Windows.Forms.Padding]::new(7,8,0,8)
    $body.BackColor=$script:modernDark
    $layout.Controls.Add($body,0,1)
    $script:modernMenu=$form
    $script:modernBody=$body
    if($null -ne $logo){
        try{
            $hicon=$logo.GetHicon()
            $temp=[Drawing.Icon]::FromHandle($hicon)
            $script:modernIcon=[Drawing.Icon]$temp.Clone()
            $script:tray.Icon=$script:modernIcon
        }catch{Write-GuardEvent 'BrandIconFallback' @{Reason='IconConversionFailed'}}
    }
    $script:form.ContextMenuStrip=$null
    $script:tray.ContextMenuStrip=$null
    $script:tray.add_MouseUp({param($s,$e)
        if($e.Button -eq [Windows.Forms.MouseButtons]::Right){Show-GuardModernMenu}
    })
    $script:form.add_MouseUp({param($s,$e)
        if($e.Button -eq [Windows.Forms.MouseButtons]::Right){Show-GuardModernMenu}
    })
    $script:label.add_MouseUp({param($s,$e)
        if($e.Button -eq [Windows.Forms.MouseButtons]::Right){Show-GuardModernMenu}
    })
    Render-GuardModernPage -Page Home
}
function Close-GuardModernMenu {
    if($null -ne $script:modernMenu){$script:modernMenu.Hide();$script:modernMenu.Dispose();$script:modernMenu=$null}
    $script:modernSubtitle=$null
    $script:modernBackButton=$null
    if($null -ne $script:modernIcon){$script:modernIcon.Dispose();$script:modernIcon=$null}
    if($null -ne $script:modernImage){$script:modernImage.Dispose();$script:modernImage=$null}
}
