# Independent tray UI source selections. Explicit approval required for shutdown source changes.
function Get-GuardSourceTitle {
    param([string]$Mode)
    switch($Mode){
        'LegacyCpu' {return 'CPU Package + ядра (ранее)'}
        'All' {return 'Максимум всех датчиков AIDA64'}
        'Cores' {return 'Только ядра CPU'}
        'CoresCpu' {return 'Ядра + ЦП'}
        'CoresCpuPackage' {return 'Ядра + ЦП + CPU Package'}
        'Custom' {return 'Свои датчики'}
        default {return 'Недоступно'}
    }
}
function Update-GuardSourceMenus {
    if($null -eq $script:sourceMenus){return}
    foreach($role in @('Display','Shutdown')){
        $node=$script:sourceMenus[$role]
        $mode=[string]$script:temperaturePolicy.($role+'Mode')
        foreach($item in $node.DropDownItems){
            if($item.Tag -is [System.Collections.IDictionary] -and $item.Tag.Contains('Mode')){
                $item.Checked=([string]$item.Tag.Mode -eq $mode)
            }
        }
        if($role -eq 'Display'){
            $node.Text='ПОКАЗЫВАТЬ ЧТО: '+(Get-GuardSourceTitle $mode)
        } else {
            $approved=Test-GuardActionSourceApproval -Policy $script:temperaturePolicy -ReceiptPath $script:sourceApprovalPath -ConfigPath $ConfigPath
            $active=($approved -and (Test-LiveApproval))
            $node.Text=if($active){'ВЫКЛЮЧАТЬ ПК ПО ТЕМПЕРАТУРЕ: активно'}else{'ВЫКЛЮЧАТЬ ПК ПО ТЕМПЕРАТУРЕ: НЕТ ДОПУСКА'}
            $script:sourceApproveItem.Enabled=($mode -notin @('LegacyCpu','Disabled') -and -not [bool]$SimulationPath)
            $script:sourceApproveItem.Text=if($active){'✓ Выбор подтверждён'}else{'Подтвердить выбранные датчики для выключения…'}
        }
    }
}
function Update-GuardSourceDisplay {
    if($null -eq $script:lastSample -or $null -eq $script:lastDecision){return}
    $script:lastDisplayTemperature=Get-GuardTemperatureSelection -Catalog $script:lastTemperatureCatalog -Mode $script:temperaturePolicy.DisplayMode -SelectedIds @($script:temperaturePolicy.DisplayIds) -CpuSummary $script:lastCpuSummary
    Update-GuardDisplay -Sample $script:lastSample -Decision $script:lastDecision -CpuSummary $script:lastCpuSummary -TemperatureSelection $script:lastDisplayTemperature
}
function Set-GuardSourceChoice {
    param([string]$Role,[string]$Mode,[string]$Id='')
    if($Role -notin @('Display','Shutdown')){return}
    if($Mode -eq 'Custom'){
        if($Id -cnotmatch '^T[A-Z0-9-]{1,31}$'){return}
        if($null -eq $script:lastTemperatureCatalog -or -not $script:lastTemperatureCatalog.Healthy){return}
        if(@($script:lastTemperatureCatalog.Sensors|Where-Object {$_.Id -ceq $Id}).Count -ne 1){return}
    } elseif($Mode -notin @('LegacyCpu','All','Cores','CoresCpu','CoresCpuPackage')){return}
    if($Role -eq 'Shutdown'){
        $msg='Выбор нового датчика отключит предыдущий допуск к выключению. Для новых датчиков потребуется отдельное подтверждение. Продолжить?'
        $ans=[Windows.Forms.MessageBox]::Show($msg,'uTempGuard: датчики выключения',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning)
        if($ans -ne [Windows.Forms.DialogResult]::Yes){return}
    }
    if($Mode -eq 'Custom'){
        $ids=@($script:temperaturePolicy.($Role+'Ids'))
        if($Id -cin $ids){$ids=@($ids|Where-Object {$_ -cne $Id})}
        else{$ids+=$Id}
        $script:temperaturePolicy.($Role+'Ids')=@($ids|Sort-Object -Unique)
    }
    $script:temperaturePolicy.($Role+'Mode')=$Mode
    Save-GuardTemperaturePolicy -Path $script:sourcePolicyPath -Policy $script:temperaturePolicy -ReceiptPath $script:sourceApprovalPath
    Write-GuardEvent 'TemperatureSourceChanged' @{Role=$Role;Mode=$Mode;RequiresApproval=($Role -eq 'Shutdown')}
    Update-GuardSourceMenus
    Update-GuardSourceDisplay
}
function Show-GuardSourceChecks {
    param([object]$MenuItem)
    if($null -eq $MenuItem -or $null -eq $MenuItem.Tag){return}
    $role=[string]$MenuItem.Tag.Role
    $MenuItem.DropDownItems.Clear()
    if($null -eq $script:lastTemperatureCatalog -or -not $script:lastTemperatureCatalog.Healthy){
        $item=$MenuItem.DropDownItems.Add('Ожидание подтверждённых датчиков AIDA64')
        $item.Enabled=$false
        return
    }
    foreach($sensor in @($script:lastTemperatureCatalog.Sensors|Sort-Object Category,Id)){
        $text=('{0} [{1}]' -f $sensor.Label,$sensor.Id)
        if($sensor.State -eq 'Valid'){$text+=(' {0:N0}°C' -f $sensor.TemperatureC)}
        else{$text+=' — нет показаний'}
        $item=[Windows.Forms.ToolStripMenuItem]::new($text)
        $item.Checked=($script:temperaturePolicy.($role+'Mode') -eq 'Custom' -and $sensor.Id -cin @($script:temperaturePolicy.($role+'Ids')))
        $item.Enabled=($sensor.State -eq 'Valid' -or $item.Checked)
        $item.Tag=@{Role=$role;Mode='Custom';Id=[string]$sensor.Id}
        $item.add_Click({param($sender,$e) Set-GuardSourceChoice -Role ([string]$sender.Tag.Role) -Mode 'Custom' -Id ([string]$sender.Tag.Id)})
        [void]$MenuItem.DropDownItems.Add($item)
    }
}
function Confirm-GuardActionSource {
    if([bool]$SimulationPath -or -not (Test-LiveApproval)){
        [Windows.Forms.MessageBox]::Show('Нужен активный Live и действующий допуск.','uTempGuard')|Out-Null
        return
    }
    $policy=$script:temperaturePolicy
    if($policy.ShutdownMode -in @('LegacyCpu','Disabled')){return}
    $fresh=$null;$selected=$null
    for($i=0;$i -lt 3;$i++){
        $fresh=Read-AidaSensor -SensorId 'TCPUPKG' -AidaPath $config.AidaPath -MaxAgeSeconds $config.MaxAgeSeconds -Context $script:context
        $catalog=if($fresh.Healthy){Read-GuardTemperatureCatalog -VerifiedSample $fresh}else{$null}
        $selected=Get-GuardTemperatureSelection -Catalog $catalog -Mode $policy.ShutdownMode -SelectedIds @($policy.ShutdownIds)
        if($fresh.Healthy -and $selected.Healthy){break}
        Start-Sleep -Milliseconds 350
    }
    if(-not $fresh.Healthy -or -not $selected.Healthy -or $selected.MaxC -ge $config.WarningC){
        [Windows.Forms.MessageBox]::Show('Нельзя подтвердить: датчики неполны, неактуальны или максимум уже достиг 70°C.','uTempGuard')|Out-Null
        return
    }
    $nl=[Environment]::NewLine
    $prompt='РЕАЛЬНОЕ ПРИНУДИТЕЛЬНОЕ ВЫКЛЮЧЕНИЕ WINDOWS ПРИ 75°C!'+$nl+
      'Режим: '+(Get-GuardSourceTitle $policy.ShutdownMode)+$nl+
      'Текущий максимум: '+([int][math]::Round($selected.MaxC))+'°C, '+$selected.HottestLabel+$nl+
      'При 75°C выбранных датчиков будет shutdown /s /f /t 0.'+$nl+
      'Несохранённые данные будут потеряны. Подтвердить?'
    $ans=[Windows.Forms.MessageBox]::Show($prompt,'uTempGuard: подтвердить источник',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning)
    if($ans -ne [Windows.Forms.DialogResult]::Yes){return}
    $fresh=Read-AidaSensor -SensorId 'TCPUPKG' -AidaPath $config.AidaPath -MaxAgeSeconds $config.MaxAgeSeconds -Context $script:context
    $catalog=if($fresh.Healthy){Read-GuardTemperatureCatalog -VerifiedSample $fresh}else{$null}
    $selected=Get-GuardTemperatureSelection -Catalog $catalog -Mode $policy.ShutdownMode -SelectedIds @($policy.ShutdownIds)
    if(-not $fresh.Healthy -or -not $selected.Healthy -or $selected.MaxC -ge $config.WarningC){
        [Windows.Forms.MessageBox]::Show('Датчики изменились. Допуск НЕ выдан.','uTempGuard')|Out-Null
        return
    }
    Save-GuardActionSourceApproval -Policy $policy -ReceiptPath $script:sourceApprovalPath -ConfigPath $ConfigPath
    Write-GuardEvent 'ActionSourceApproved' @{Mode=$policy.ShutdownMode;Count=@($selected.RequiredIds).Count}
    Update-GuardSourceMenus
}
function Initialize-GuardSourceMenus {
    param([object]$Menu)
    $script:sourceMenus=@{}
    foreach($role in @('Display','Shutdown')){
        $node=[Windows.Forms.ToolStripMenuItem]::new($(if($role -eq 'Display'){'ПОКАЗЫВАТЬ ЧТО'}else{'ВЫКЛЮЧАТЬ ПК ПО ТЕМПЕРАТУРЕ'}))
        $script:sourceMenus[$role]=$node
        [void]$Menu.Items.Add($node)
        foreach($entry in @(
            @{Mode='All';Text='1. Всё: AIDA64 (CPU, GPU, диски и др.)'}
            @{Mode='Cores';Text='2. Максимум ядер'}
            @{Mode='CoresCpu';Text='3. Ядра + ЦП'}
            @{Mode='CoresCpuPackage';Text='4. Ядра + ЦП + CPU Package'}
        )){
            $item=[Windows.Forms.ToolStripMenuItem]::new($entry.Text)
            $item.Tag=@{Role=$role;Mode=$entry.Mode}
            $item.add_Click({param($sender,$e) Set-GuardSourceChoice -Role ([string]$sender.Tag.Role) -Mode ([string]$sender.Tag.Mode)})
            [void]$node.DropDownItems.Add($item)
        }
        $custom=[Windows.Forms.ToolStripMenuItem]::new('5. Свой набор: выбрать галочками →')
        $custom.Tag=@{Role=$role;Mode='Custom'}
        $custom.add_DropDownOpening({param($sender,$e) Show-GuardSourceChecks -MenuItem $sender})
        [void]$node.DropDownItems.Add($custom)
        [void]$node.DropDownItems.Add('-')
        $legacy=[Windows.Forms.ToolStripMenuItem]::new('↩ Вернуть прежний вариант: CPU Package + ядра')
        $legacy.Tag=@{Role=$role;Mode='LegacyCpu'}
        $legacy.add_Click({param($sender,$e) Set-GuardSourceChoice -Role ([string]$sender.Tag.Role) -Mode 'LegacyCpu'})
        [void]$node.DropDownItems.Add($legacy)
        if($role -eq 'Shutdown'){
            [void]$node.DropDownItems.Add('-')
            $script:sourceApproveItem=[Windows.Forms.ToolStripMenuItem]::new('Подтвердить выбранные датчики…')
            $script:sourceApproveItem.add_Click({Confirm-GuardActionSource})
            [void]$node.DropDownItems.Add($script:sourceApproveItem)
        }
    }
    Update-GuardSourceMenus
}
