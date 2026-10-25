# Selection-only tests: no AIDA, registry, hardware, power, or Windows icon changes.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'src\Guard.TrayIconSelector.psm1') -Force
function Expect([object]$InputC,[string]$Theme,[double]$Second,[string]$Expected) {
    $result=Get-GuardTrayIconChoice -TemperatureC $InputC -TaskbarTheme $Theme -ElapsedSeconds $Second
    if($result.Key -cne $Expected){throw ("Unexpected {0} at {1} C: {2}, expected {3}" -f $Theme,$InputC,$result.Key,$Expected)}
}
Expect 0 Dark 0 'utg_w_000'
Expect 9.99 Light 0 'utg_b_000'
Expect 10 Dark 0 'utg_w_010'
Expect 19.9 Dark 0 'utg_w_010'
Expect 20 Light 0 'utg_b_020'
Expect 39.99 Dark 0 'utg_w_030'
Expect 70 Dark 0 'utg_w_070'
Expect 79.99 Light 0.6 'utg_b_070'
Expect 80 Dark 0 'utg_w_080'
Expect 80 Dark 0.399 'utg_w_080'
Expect 80 Dark 0.4 'utg_w_080_active'
Expect 80 Dark 0.799 'utg_w_080_active'
Expect 80 Dark 0.8 'utg_w_080'
Expect 90 Light 0.4 'utg_b_090_active'
Expect 100 Dark 0.4 'utg_w_100_active'
Expect 109 Dark 0.4 'utg_w_100_active'
foreach($bad in @(-1,111,$null,[double]::NaN,[double]::PositiveInfinity,'invalid')){
    $result=Get-GuardTrayIconChoice -TemperatureC $bad
    if($result.Ready){throw ('Unverified temperature produced active icon: '+$bad)}
}
if((Get-GuardTrayIconChoice -TemperatureC 50 -SensorHealthy $false).Ready){throw 'Unhealthy sensor selected icon'}
$dir=Join-Path $root ('artifacts\tray-icon-selector-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($dir)|Out-Null
$frame=Join-Path $dir 'utg_b_010.png.base64'
[IO.File]::WriteAllText($frame,'safe mock only',[Text.UTF8Encoding]::new($false))
$result=Get-GuardTrayIconChoice -TemperatureC 25 -TaskbarTheme Light -AssetDirectory $dir
if(-not $result.Ready -or $result.Key -cne 'utg_b_010' -or $result.Reason -ne 'MissingFrameFallback'){
    throw 'Missing user b_020 did not select nearest lower icon'
}
[IO.File]::WriteAllText((Join-Path $dir 'utg_b_080.png.base64'),'safe mock only',[Text.UTF8Encoding]::new($false))
$result=Get-GuardTrayIconChoice -TemperatureC 80 -TaskbarTheme Light -ElapsedSeconds 0.4 -AssetDirectory $dir
if($result.Key -cne 'utg_b_080'){throw 'Missing active icon did not fall back to normal'}
$result=Get-GuardTrayIconChoice -TemperatureC $null -AssetDirectory $dir
if($result.Ready){throw 'Lost sensor showed a stale temperature icon'}
Write-Output 'PASS: all 0-100 temperature buckets, dark/light themes, 0.4s alert toggle and safe missing-file fallback.'
