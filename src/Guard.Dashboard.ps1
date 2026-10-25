# uTempGuard desktop dashboard. Visual presentation only: no direct hardware or power actions.
# Uses the monitor's already-verified in-memory snapshot; never invents temperatures.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$script:dashboardForm=$null
$script:dashboardLabels=@{}
$script:dashboardStatusColor=[Drawing.ColorTranslator]::FromHtml('#95a6b9')
$script:dashboardBackground=[Drawing.ColorTranslator]::FromHtml('#0C1423')
$script:dashboardPanel=[Drawing.ColorTranslator]::FromHtml('#15243A')
$script:dashboardPanelAlt=[Drawing.ColorTranslator]::FromHtml('#1C3150')
$script:dashboardWhite=[Drawing.ColorTranslator]::FromHtml('#F4F8FE')
$script:dashboardMuted=[Drawing.ColorTranslator]::FromHtml('#AFC0D5')
$script:dashboardBlue=[Drawing.ColorTranslator]::FromHtml('#63C7FF')
$script:dashboardGreen=[Drawing.ColorTranslator]::FromHtml('#63D399')
$script:dashboardAmber=[Drawing.ColorTranslator]::FromHtml('#FBC46A')
$script:dashboardRed=[Drawing.ColorTranslator]::FromHtml('#FF7777')

function New-GuardDashboardLabel {
    param([string]$Text,[single]$Size=11,[switch]$Bold,[Drawing.Color]$Color=$script:dashboardWhite)
    $l=[Windows.Forms.Label]::new()
    $l.Dock=[Windows.Forms.DockStyle]::Fill
    $l.Font=[Drawing.Font]::new('Segoe UI',$Size,$(if($Bold){[Drawing.FontStyle]::Bold}else{[Drawing.FontStyle]::Regular}))
    $l.ForeColor=$Color
    $l.Text=$Text
    $l.TextAlign=[Drawing.ContentAlignment]::MiddleLeft
    $l.AutoEllipsis=$true
    $l.Margin=[Windows.Forms.Padding]::new(13,0,13,0)
    $l.AccessibleName=$Text
    return $l
}
function New-GuardDashboardSurface {
    param([Drawing.Color]$Background=$script:dashboardPanel)
    $p=[Windows.Forms.Panel]::new()
    $p.Dock=[Windows.Forms.DockStyle]::Fill
    $p.Margin=[Windows.Forms.Padding]::new(7)
    $p.BackColor=$Background
    return $p
}
function Add-GuardDashboardTile {
    param([Windows.Forms.TableLayoutPanel]$Parent,[int]$Row,
        [string]$Title,[string]$Value,[string]$Slot,[Drawing.Color]$Highlight=$script:dashboardBlue)
    $panel=New-GuardDashboardSurface
    $box=[Windows.Forms.TableLayoutPanel]::new()
    $box.Dock=[Windows.Forms.DockStyle]::Fill
    $box.RowCount=2;$box.ColumnCount=1
    [void]$box.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,[single]36))
    [void]$box.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,[single]64))
    $titleLabel=New-GuardDashboardLabel -Text $Title -Size 9 -Color $script:dashboardMuted
    $valueLabel=New-GuardDashboardLabel -Text $Value -Size 15 -Bold -Color $Highlight
    $box.Controls.Add($titleLabel,0,0)
    $box.Controls.Add($valueLabel,0,1)
    [void]$panel.Controls.Add($box)
    $Parent.Controls.Add($panel,0,$Row)
    $script:dashboardLabels[$Slot]=$valueLabel
}
function New-GuardDashboardButton {
    param([string]$Key,[string]$Page='')
    $b=[Windows.Forms.Button]::new()
    $b.Text=(Get-GuardText -Key $Key)
    $b.Tag=@{Key=$Key;Page=$Page}
    $b.Dock=[Windows.Forms.DockStyle]::Fill
    $b.Margin=[Windows.Forms.Padding]::new(8,5,8,5)
    $b.FlatStyle=[Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize=1
    $b.FlatAppearance.BorderColor=[Drawing.ColorTranslator]::FromHtml('#2D4869')
    $b.FlatAppearance.MouseOverBackColor=[Drawing.ColorTranslator]::FromHtml('#274767')
    $b.BackColor=$script:dashboardPanel
    $b.ForeColor=$script:dashboardWhite
    $b.Font=[Drawing.Font]::new('Segoe UI',[single]11)
    $b.TextAlign=[Drawing.ContentAlignment]::MiddleLeft
    $b.Padding=[Windows.Forms.Padding]::new(14,0,4,0)
    $b.Cursor=[Windows.Forms.Cursors]::Hand
    $b.AutoEllipsis=$true
    $b.AccessibleName=$b.Text
    if($Page -eq '_gallery'){
        $b.add_Click({Invoke-GuardModernAction -Action 'OpenGallery'})
    }elseif($Page -eq '_refresh'){
        $b.add_Click({Update-GuardDashboard -Force})
    }else{
        $b.add_Click({
            param($sender,$e)
            $page=[string]$sender.Tag.Page
            if($null -eq $script:modernMenu){return}
            if(-not $script:modernMenu.Visible){Show-GuardModernMenu}
            Render-GuardModernPage -Page $page
        })
    }
    return $b
}
function Initialize-GuardDashboard {
    if($null -ne $script:dashboardForm -and -not $script:dashboardForm.IsDisposed){return}
    $form=[Windows.Forms.Form]::new()
    $form.Text='uTempGuard · Dashboard'
    $form.StartPosition=[Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle=[Windows.Forms.FormBorderStyle]::Sizable
    $form.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Dpi
    $form.ClientSize=[Drawing.Size]::new(925,600)
    $form.MinimumSize=[Drawing.Size]::new(760,540)
    $form.BackColor=$script:dashboardBackground
    $form.ForeColor=$script:dashboardWhite
    $form.ShowInTaskbar=$true
    $form.KeyPreview=$true
    $form.add_FormClosing({param($sender,$e)
        if($e.CloseReason -eq [Windows.Forms.CloseReason]::UserClosing){
            # Closing the window must not stop the background safety monitor.
            $e.Cancel=$true
            $sender.Hide()
        }
    })
    $form.add_KeyDown({param($sender,$e)
        if($e.KeyCode -eq [Windows.Forms.Keys]::Escape){$sender.Hide();$e.Handled=$true}
    })
    try{
        $logo=Get-GuardOfficialLogo
        if($null -ne $logo){
            $handle=$logo.GetHicon()
            try{
                $h=[Drawing.Icon]::FromHandle($handle)
                $form.Icon=[Drawing.Icon]$h.Clone()
            }finally{
                if('GuardTrayNative' -as [type]){[void][GuardTrayNative]::DestroyIcon($handle)}
                else{Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class GuardDashNative { [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h); }';[void][GuardDashNative]::DestroyIcon($handle)}
            }
        }
    }catch{}
    $root=[Windows.Forms.TableLayoutPanel]::new()
    $root.Dock=[Windows.Forms.DockStyle]::Fill
    $root.Padding=[Windows.Forms.Padding]::new(15)
    $root.ColumnCount=1;$root.RowCount=3
    [void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,[single]94))
    [void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,[single]100))
    [void]$root.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Absolute,[single]38))
    [void]$form.Controls.Add($root)
    $head=New-GuardDashboardSurface -Background $script:dashboardPanel
    $head.Margin=[Windows.Forms.Padding]::new(6,1,6,5)
    $headGrid=[Windows.Forms.TableLayoutPanel]::new()
    $headGrid.Dock=[Windows.Forms.DockStyle]::Fill
    $headGrid.ColumnCount=2;$headGrid.RowCount=1
    [void]$headGrid.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Absolute,[single]83))
    [void]$headGrid.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,[single]100))
    $picture=[Windows.Forms.PictureBox]::new()
    $picture.SizeMode=[Windows.Forms.PictureBoxSizeMode]::Zoom
    $picture.Dock=[Windows.Forms.DockStyle]::Fill
    $picture.Margin=[Windows.Forms.Padding]::new(10,10,4,10)
    $picture.Image=Get-GuardOfficialLogo
    $headGrid.Controls.Add($picture,0,0)
    $headText=[Windows.Forms.TableLayoutPanel]::new()
    $headText.Dock=[Windows.Forms.DockStyle]::Fill
    $headText.RowCount=2
    [void]$headText.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,[single]62))
    [void]$headText.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,[single]38))
    $heading=New-GuardDashboardLabel -Text 'uTempGuard' -Size 21 -Bold
    $sub=New-GuardDashboardLabel -Text (Get-GuardText -Key 'dashboard.subtitle') -Size 10 -Color $script:dashboardMuted
    $headText.Controls.Add($heading,0,0)
    $headText.Controls.Add($sub,0,1)
    $headGrid.Controls.Add($headText,1,0)
    [void]$head.Controls.Add($headGrid)
    $root.Controls.Add($head,0,0)
    $middle=[Windows.Forms.TableLayoutPanel]::new()
    $middle.Dock=[Windows.Forms.DockStyle]::Fill
    $middle.RowCount=1;$middle.ColumnCount=2
    [void]$middle.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,[single]56))
    [void]$middle.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,[single]44))
    $left=[Windows.Forms.TableLayoutPanel]::new()
    $left.Dock=[Windows.Forms.DockStyle]::Fill
    $left.RowCount=4;$left.ColumnCount=1
    foreach($weight in @(34,20,22,24)){[void]$left.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,[single]$weight))}
    Add-GuardDashboardTile -Parent $left -Row 0 -Title (Get-GuardText -Key 'dashboard.temperature') -Value '— °C' -Slot 'Temperature'
    Add-GuardDashboardTile -Parent $left -Row 1 -Title (Get-GuardText -Key 'dashboard.sensors') -Value '—' -Slot 'Sensors'
    Add-GuardDashboardTile -Parent $left -Row 2 -Title (Get-GuardText -Key 'dashboard.monitor') -Value (Get-GuardText -Key 'state.SensorFault') -Slot 'Monitor'
    Add-GuardDashboardTile -Parent $left -Row 3 -Title (Get-GuardText -Key 'dashboard.safety') -Value (Get-GuardText -Key 'approval.notApproved') -Slot 'Safety' -Highlight $script:dashboardAmber
    $middle.Controls.Add($left,0,0)
    $right=[Windows.Forms.TableLayoutPanel]::new()
    $right.Dock=[Windows.Forms.DockStyle]::Fill
    $right.RowCount=7;$right.ColumnCount=1
    foreach($i in 0..6){[void]$right.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,[single](100/7)))}
    $entries=@(
      @('dashboard.display','Display'),
      @('dashboard.shutdown','Shutdown'),
      @('dashboard.appearance','Appearance'),
      @('dashboard.language','Language'),
      @('dashboard.gallery','_gallery'),
      @('dashboard.updates','Updates'),
      @('dashboard.refresh','_refresh')
    )
    for($i=0;$i -lt $entries.Count;$i++){$right.Controls.Add((New-GuardDashboardButton -Key $entries[$i][0] -Page $entries[$i][1]),0,$i)}
    $middle.Controls.Add($right,1,0)
    $root.Controls.Add($middle,0,1)
    $footer=New-GuardDashboardLabel -Text (Get-GuardText -Key 'dashboard.footer') -Size 9 -Color $script:dashboardMuted
    $footer.TextAlign=[Drawing.ContentAlignment]::MiddleCenter
    $root.Controls.Add($footer,0,2)
    $script:dashboardLabels['Subtitle']=$sub
    $script:dashboardLabels['Footer']=$footer
    $script:dashboardForm=$form
    Update-GuardDashboard -Force
}
function Update-GuardDashboard {
    [CmdletBinding()]
    param([switch]$Force)
    if($null -eq $script:dashboardForm -or $script:dashboardForm.IsDisposed){return}
    if(-not $script:dashboardForm.Visible -and -not $Force){return}
    $healthy=$null -ne $script:lastSample -and [bool]$script:lastSample.Healthy -and
      $null -ne $script:lastDisplayTemperature -and [bool]$script:lastDisplayTemperature.Healthy
    if($healthy -and $null -ne $script:lastDisplayTemperature.MaxC){
        $temp=[double]$script:lastDisplayTemperature.MaxC
        $script:dashboardLabels.Temperature.Text=('{0:0.#} °C' -f $temp)
        $script:dashboardLabels.Temperature.ForeColor=if($temp -ge 75){$script:dashboardRed}elseif($temp -ge 70){$script:dashboardAmber}else{$script:dashboardGreen}
    }else{
        $script:dashboardLabels.Temperature.Text=Get-GuardText -Key 'dashboard.noReading'
        $script:dashboardLabels.Temperature.ForeColor=$script:dashboardMuted
    }
    if($null -ne $script:lastCpuSummary){
        $script:dashboardLabels.Sensors.Text=('{0}/{1}' -f $script:lastCpuSummary.AvailableCount,$script:lastCpuSummary.ExpectedCount)
    }else{$script:dashboardLabels.Sensors.Text=Get-GuardText -Key 'dashboard.noReading'}
    $state=if(-not $healthy){'SensorFault'}else{[string]$script:state}
    if($state -notin @('Normal','Warning','Critical','SensorFault')){$state='SensorFault'}
    $script:dashboardLabels.Monitor.Text=Get-GuardText -Key ('state.'+$state)
    $script:dashboardLabels.Monitor.ForeColor=switch($state){
        'Normal'{$script:dashboardGreen}
        'Warning'{$script:dashboardAmber}
        'Critical'{$script:dashboardRed}
        default{$script:dashboardMuted}
    }
    $permitted=$false
    try{
        if($null -ne $script:config -and $script:config.Mode -eq 'Live' -and (Test-LiveApproval)){
            $permitted=[bool](Test-GuardActionSourceApproval -Policy $script:temperaturePolicy -ReceiptPath $script:sourceApprovalPath -ConfigPath $ConfigPath)
        }
    }catch{$permitted=$false}
    # Approval never implies that a stale or missing shutdown sensor can act.
    $shutdownHealthy=($null -ne $script:lastSample -and $script:lastSample.Healthy -and
        $null -ne $script:lastShutdownTemperature -and $script:lastShutdownTemperature.Healthy)
    if($permitted -and -not $shutdownHealthy){
        $script:dashboardLabels.Safety.Text=Get-GuardText -Key 'dashboard.sensorBlocked'
        $script:dashboardLabels.Safety.ForeColor=$script:dashboardAmber
    }else{
        $script:dashboardLabels.Safety.Text=Get-GuardText -Key $(if($permitted){'dashboard.approved'}else{'dashboard.notApproved'})
        $script:dashboardLabels.Safety.ForeColor=if($permitted){$script:dashboardGreen}else{$script:dashboardAmber}
    }
    $script:dashboardLabels.Subtitle.Text=Get-GuardText -Key 'dashboard.subtitle'
    $script:dashboardLabels.Footer.Text=Get-GuardText -Key 'dashboard.footer'
}
function Show-GuardDashboard {
    if($null -eq $script:dashboardForm -or $script:dashboardForm.IsDisposed){Initialize-GuardDashboard}
    if($null -eq $script:dashboardForm){return}
    Update-GuardDashboard -Force
    if($script:dashboardForm.WindowState -eq [Windows.Forms.FormWindowState]::Minimized){
        $script:dashboardForm.WindowState=[Windows.Forms.FormWindowState]::Normal
    }
    if(-not $script:dashboardForm.Visible){$script:dashboardForm.Show()}
    $script:dashboardForm.BringToFront()
    $script:dashboardForm.Activate()
}
function Close-GuardDashboard {
    if($null -eq $script:dashboardForm){return}
    try{
        $script:dashboardForm.Hide()
        # Programmatic disposal is not user closing; background monitor is stopping.
        $script:dashboardForm.Dispose()
    }finally{
        $script:dashboardForm=$null
        $script:dashboardLabels=@{}
    }
}
