# Safe synthetic test of independent displayed/shutdown telemetry choices.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'src\Guard.CpuSummary.psm1') -Force
Import-Module (Join-Path $root 'src\Guard.TemperatureSources.psm1') -Force
$sample=[pscustomobject]@{
    Healthy=$true
    Source='Registry:HKCU\Software\FinalWire\AIDA64\SensorValues'
    SensorId='TCPUPKG';TemperatureC=41
    Heartbeat='2026-10-25T14:33:00'
}
$values=@{'Value.STIME'='14:33:00';'Value.SDATE'='2026-10-25'
    'Value.TCPUPKG'='41';'Label.TCPUPKG'='CPU Package'
    'Value.TCPU'='43';'Label.TCPU'='CPU'
    'Value.TGPU1'='68';'Label.TGPU1'='GPU'
    'Value.THDD1'='65';'Label.THDD1'='Disk'
    'Value.TMB'='52';'Label.TMB'='Mainboard'
}
for($n=1;$n -le 14;$n++){
    $values['Value.TCC-1-'+$n]=[string](35+$n)
    $values['Label.TCC-1-'+$n]='CPU Core '+$n
}
$catalog=Get-GuardTemperatureCatalogFromValues -VerifiedSample $sample -Values $values
if(-not $catalog.Healthy -or @($catalog.Sensors).Count -ne 19){throw ('Catalog rejected: '+$catalog.Reason)}
function Check([string]$Mode,[string[]]$Ids,[int]$Expected,[string]$Hottest){
    $result=Get-GuardTemperatureSelection -Catalog $catalog -Mode $Mode -SelectedIds $Ids
    if(-not $result.Healthy -or $result.MaxC -ne $Expected -or $result.HottestId -ne $Hottest){
        throw ('Selection incorrect: '+$Mode+'/'+$result.Reason+'/'+$result.MaxC+'/'+$result.HottestId)
    }
}
Check -Mode 'All' -Ids @() -Expected 68 -Hottest 'TGPU1'
Check -Mode 'Cores' -Ids @() -Expected 49 -Hottest 'TCC-1-14'
Check -Mode 'CoresCpu' -Ids @() -Expected 49 -Hottest 'TCC-1-14'
Check -Mode 'CoresCpuPackage' -Ids @() -Expected 49 -Hottest 'TCC-1-14'
Check -Mode 'Custom' -Ids @('THDD1','TMB') -Expected 65 -Hottest 'THDD1'
$incomplete=Get-GuardTemperatureSelection -Catalog $catalog -Mode Custom -SelectedIds @('THDD1','TGPU2')
if($incomplete.Healthy -or $incomplete.MissingIds -cnotcontains 'TGPU2'){throw 'Missing user-selected sensor was ignored'}
$values['Value.TGPU1']='not-a-temperature'
$invalid=Get-GuardTemperatureCatalogFromValues -VerifiedSample $sample -Values $values
if((Get-GuardTemperatureSelection -Catalog $invalid -Mode All).Healthy){throw 'Invalid machine temperature admitted'}
if(-not (Get-GuardTemperatureSelection -Catalog $invalid -Mode Cores).Healthy){throw 'Unrelated invalid GPU blocked core-only choice'}
$values['Value.STIME']='14:33:01'
if((Get-GuardTemperatureCatalogFromValues -VerifiedSample $sample -Values $values).Healthy){throw 'Mixed AIDA timestamp admitted'}
$values['Value.STIME']='14:33:00'
$values['Value.TCPUPKG']='75'
if((Get-GuardTemperatureCatalogFromValues -VerifiedSample $sample -Values $values).Healthy){throw 'Mixed CPU package admitted'}

$folder=Join-Path $root ('artifacts\selection-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($folder)|Out-Null
$file=Join-Path $folder 'temperature-sources.json'
$receipt=Join-Path $folder 'approval.json'
$config=Join-Path $root 'README.md'
$p=Get-GuardTemperaturePolicy -Path $file
if($p.ShutdownMode -ne 'LegacyCpu' -or $p.DisplayMode -ne 'LegacyCpu'){throw 'Default mode changed legacy emergency behavior'}
$p.ShutdownMode='All'
Save-GuardTemperaturePolicy -Path $file -Policy $p -ReceiptPath $receipt
if(Test-GuardActionSourceApproval -Policy $p -ReceiptPath $receipt -ConfigPath $config){throw 'Unapproved new shutdown selector is active'}
Save-GuardActionSourceApproval -Policy $p -ReceiptPath $receipt -ConfigPath $config
if(-not (Test-GuardActionSourceApproval -Policy $p -ReceiptPath $receipt -ConfigPath $config)){throw 'Explicit source approval not recognized'}
$p.DisplayMode='Cores'
Save-GuardTemperaturePolicy -Path $file -Policy $p -ReceiptPath $receipt
if(-not (Test-GuardActionSourceApproval -Policy $p -ReceiptPath $receipt -ConfigPath $config)){throw 'Display-only choice revoked separate shutdown permission'}
$p.ShutdownMode='Custom'
$p.ShutdownIds=@('TGPU1')
Save-GuardTemperaturePolicy -Path $file -Policy $p -ReceiptPath $receipt
if(Test-GuardActionSourceApproval -Policy $p -ReceiptPath $receipt -ConfigPath $config){throw 'Changing shutdown sensor retained old approval'}
[IO.File]::WriteAllText($file,'{broken',[Text.UTF8Encoding]::new($false))
if((Get-GuardTemperaturePolicy -Path $file).ShutdownMode -ne 'Disabled'){throw 'Corrupt policy re-enabled legacy emergency shutdown'}
Write-Output 'PASS: all five selections, invalid/stale checks, independent settings, explicit shutdown approval, fail-closed policy.'
