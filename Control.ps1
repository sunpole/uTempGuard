$ErrorActionPreference='Stop'
do {
    Write-Host ''
    Write-Host 'uTempGuard — управление (режим и состояние: пункт 1)'
    Write-Host '1. Статус   2. Запуск   3. Остановка   4. Конфигурация'
    Write-Host '5. Журналы  6. Диагностика  7. Включить автозапуск  8. Отключить автозапуск'
    Write-Host '9. Удаление uTempGuard (данные сохраняются)   0. Выход'
    $choice=Read-Host 'Номер'
    try {
        $actions=@{'1'='Status';'2'='Start';'3'='Stop';'4'='OpenConfig';'5'='OpenLogs';'6'='Diagnose';'7'='EnableStartup';'8'='DisableStartup'}
        if($actions.ContainsKey($choice)){& (Join-Path $PSScriptRoot 'Manage.ps1') -Action $actions[$choice] | Format-List | Out-Host}
        elseif($choice -eq '9'){& (Join-Path $PSScriptRoot 'Uninstall.ps1') | Format-List | Out-Host}
    }catch{Write-Host $_.Exception.Message -ForegroundColor Red}
}while($choice -ne '0')
