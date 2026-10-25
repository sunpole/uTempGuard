# Read-only dynamic AIDA64 temperature catalog and independent source policies.
# Other than explicitly approved shutdown-source mode, does not affect Live grants.
Set-StrictMode -Version 2.0
$script:allowedTemperatureModes=@('LegacyCpu','All','Cores','CoresCpu','CoresCpuPackage','Custom','Disabled')
function Get-GuardTemperaturePolicy {
    [CmdletBinding()]
    param([string]$Path)
    $p=[pscustomobject]@{DisplayMode='LegacyCpu';DisplayIds=@();ShutdownMode='LegacyCpu';ShutdownIds=@()}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {return $p}
    try {
        $raw=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $raw -or $raw.DisplayMode -notin $script:allowedTemperatureModes -or
            $raw.ShutdownMode -notin $script:allowedTemperatureModes) {throw 'Invalid mode'}
        $p.DisplayMode=[string]$raw.DisplayMode
        $p.ShutdownMode=[string]$raw.ShutdownMode
        foreach($role in @('Display','Shutdown')){
            $ids=@($raw.($role+'Ids'))
            if($ids.Count -gt 128){throw 'Too many selections'}
            $safe=@()
            foreach($id in $ids){
                if($id -isnot [string] -or $id -cnotmatch '^T[A-Z0-9-]{1,31}$'){throw 'Invalid sensor ID'}
                if($id -cnotin $safe){$safe+=$id}
            }
            $p.($role+'Ids')=@($safe)
        }
    } catch {
        # Corrupt policy MUST fail closed for shutdown, not revert to Legacy.
        $p.ShutdownMode='Disabled'
        $p.ShutdownIds=@()
        $p.DisplayMode='LegacyCpu'
        $p.DisplayIds=@()
    }
    return $p
}
function Save-GuardTemperaturePolicy {
    [CmdletBinding()]
    param([string]$Path,[object]$Policy,[string]$ReceiptPath)
    if($Policy.DisplayMode -notin $script:allowedTemperatureModes -or
        $Policy.ShutdownMode -notin $script:allowedTemperatureModes){throw 'Invalid temperature mode'}
    foreach($role in @('Display','Shutdown')){
        foreach($id in @($Policy.($role+'Ids'))){
            if($id -isnot [string] -or $id -cnotmatch '^T[A-Z0-9-]{1,31}$'){throw 'Invalid sensor ID'}
        }
    }
    $folder=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
    [IO.Directory]::CreateDirectory($folder)|Out-Null
    # Revoke approval *before* changing shutdown selection, never after.
    if(-not [string]::IsNullOrWhiteSpace($ReceiptPath) -and (Test-Path -LiteralPath $ReceiptPath)){
        Remove-Item -LiteralPath $ReceiptPath -Force
    }
    $record=[ordered]@{
        DisplayMode=[string]$Policy.DisplayMode
        DisplayIds=@($Policy.DisplayIds | Sort-Object -Unique)
        ShutdownMode=[string]$Policy.ShutdownMode
        ShutdownIds=@($Policy.ShutdownIds | Sort-Object -Unique)
    }
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [IO.File]::WriteAllText($temp,($record|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temp -Destination $Path -Force
    } finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}
function Get-GuardActionSourceSignature {
    [CmdletBinding()]
    param([object]$Policy,[string]$ConfigPath)
    $ids=(@($Policy.ShutdownIds | Sort-Object -Unique) -join ',')
    $configHash=(Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash
    $payload='uTempGuard/action-source/v1|'+$Policy.ShutdownMode+'|'+$ids+'|'+$configHash
    $sha=[Security.Cryptography.SHA256]::Create()
    try {return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($payload))).Replace('-',''))}
    finally{$sha.Dispose()}
}
function Test-GuardActionSourceApproval {
    [CmdletBinding()]
    param([object]$Policy,[string]$ReceiptPath,[string]$ConfigPath)
    if($Policy.ShutdownMode -eq 'LegacyCpu'){return $true}
    if($Policy.ShutdownMode -eq 'Disabled' -or -not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)){return $false}
    try{
        $receipt=Get-Content -LiteralPath $ReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return ($receipt.Approved -is [bool] -and $receipt.Approved -and
          $receipt.Signature -ceq (Get-GuardActionSourceSignature -Policy $Policy -ConfigPath $ConfigPath))
    }catch{return $false}
}
function Save-GuardActionSourceApproval {
    [CmdletBinding()]
    param([object]$Policy,[string]$ReceiptPath,[string]$ConfigPath)
    if($Policy.ShutdownMode -in @('Disabled','LegacyCpu')){throw 'Only explicitly selected non-legacy modes can be approved'}
    $folder=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ReceiptPath))
    [IO.Directory]::CreateDirectory($folder)|Out-Null
    $record=[ordered]@{
        Approved=$true
        Signature=(Get-GuardActionSourceSignature -Policy $Policy -ConfigPath $ConfigPath)
        ApprovedUtc=[DateTime]::UtcNow.ToString('o')
    }
    $temp=$ReceiptPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [IO.File]::WriteAllText($temp,($record|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temp -Destination $ReceiptPath -Force
    }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}

function Test-GuardTemperatureValue {
    param([AllowNull()][object]$Value)
    $number=0.0
    if($null -eq $Value -or $Value -is [bool] -or $Value -is [array]){return $null}
    if(-not [double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,[ref]$number)){return $null}
    if([double]::IsNaN($number) -or [double]::IsInfinity($number) -or
       $number -le 0 -or $number -gt 110){return $null}
    return $number
}
function Get-GuardTemperatureCatalogFromValues {
    [CmdletBinding()]
    param([object]$VerifiedSample,[System.Collections.IDictionary]$Values)
    $fail={param([string]$why) [pscustomobject]@{Healthy=$false;Reason=$why;Sensors=@()}}
    if($null -eq $VerifiedSample -or -not $VerifiedSample.Healthy -or
       [string]$VerifiedSample.Source -notlike 'Registry:*' -or
       [string]$VerifiedSample.SensorId -ne 'TCPUPKG'){return (& $fail 'PrimaryNotVerified')}
    $v=Test-GuardCpuRegistrySnapshot -VerifiedSample $VerifiedSample -Values $Values
    if(-not $v.Healthy){return (& $fail $v.Reason)}
    $records=New-Object 'System.Collections.Generic.List[object]'
    foreach($key in $Values.Keys){
        if([string]$key -cnotmatch '^Value\.(T[A-Z0-9-]{1,31})$'){continue}
        $id=$Matches[1]
        $n=Test-GuardTemperatureValue -Value $Values[$key]
        $label=[string]$Values['Label.'+$id]
        if([string]::IsNullOrWhiteSpace($label)){$label=$id}
        $category=if($id -match '^TCC-\d+-\d+$'){'Core'}
                  elseif($id -eq 'TCPU'){'Cpu'}
                  elseif($id -eq 'TCPUPKG'){'Package'}
                  else{'Other'}
        $records.Add([pscustomobject]@{
            Id=$id
            Label=$label
            TemperatureC=$n
            State=$(if($null -ne $n){'Valid'}else{'Invalid'})
            Category=$category
            Source='AIDA64 Registry'
        })
    }
    return [pscustomobject]@{Healthy=$true;Reason='Valid';Sensors=@($records.ToArray())}
}
function Read-GuardTemperatureCatalog {
    [CmdletBinding()]
    param([object]$VerifiedSample)
    $fail={param($reason) [pscustomobject]@{Healthy=$false;Reason=$reason;Sensors=@()}}
    if($null -eq $VerifiedSample -or -not $VerifiedSample.Healthy -or
        [string]$VerifiedSample.Source -notlike 'Registry:*'){return (& $fail 'PrimaryNotVerified')}
    for($attempt=1;$attempt -le 3;$attempt++){
        $key=$null
        try{
            $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\FinalWire\AIDA64\SensorValues',$false)
            if($null -eq $key){return (& $fail 'RegistryUnavailable')}
            $clockBefore=[string]$key.GetValue('Value.STIME',$null)
            $dateBefore=[string]$key.GetValue('Value.SDATE',$null)
            $values=@{}
            foreach($name in $key.GetValueNames()){
                if($name -match '^(?:Value\.T[A-Z0-9-]{1,31}|Label\.T[A-Z0-9-]{1,31}|Value\.(?:STIME|SDATE))$'){
                    $values[$name]=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                }
            }
            $clockAfter=[string]$key.GetValue('Value.STIME',$null)
            $dateAfter=[string]$key.GetValue('Value.SDATE',$null)
            if($clockBefore -ne $clockAfter -or $dateBefore -ne $dateAfter){
                $result=& $fail 'RegistryChangedDuringRead'
            } else {
                $result=Get-GuardTemperatureCatalogFromValues -VerifiedSample $VerifiedSample -Values $values
            }
        }catch{
            return (& $fail ('RegistryReadException:'+$_.Exception.GetType().Name))
        }finally{if($null -ne $key){$key.Dispose()}}
        if($result.Healthy){return $result}
        if($result.Reason -notin @('RegistryChangedDuringRead','HeartbeatMismatch','CpuPackageChangedBetweenReads')){return $result}
        if($attempt -lt 3){Start-Sleep -Milliseconds 70}
    }
    return $result
}
function Get-GuardTemperatureSelection {
    [CmdletBinding()]
    param([object]$Catalog,[string]$Mode,[string[]]$SelectedIds=@(),[object]$CpuSummary)
    $disabled=[pscustomobject]@{
        Healthy=$false;Complete=$false;MaxC=$null;HottestId='';HottestLabel='';
        RequiredIds=@();MissingIds=@();Reason='Unavailable'
    }
    if($Mode -eq 'Disabled'){return $disabled}
    if($Mode -eq 'LegacyCpu'){
        if($null -eq $CpuSummary -or $CpuSummary.AvailableCount -lt 1 -or $null -eq $CpuSummary.MaxC){return $disabled}
        return [pscustomobject]@{Healthy=$true;Complete=$true;MaxC=[double]$CpuSummary.MaxC;
            HottestId=[string]$CpuSummary.HottestId;HottestLabel=[string]$CpuSummary.HottestId;
            RequiredIds=@();MissingIds=@();Reason='LegacyCpu'}
    }
    if($null -eq $Catalog -or -not $Catalog.Healthy){return $disabled}
    $cores=@(1..14 | ForEach-Object {'TCC-1-'+$_})
    switch($Mode){
        'All' { $ids=@($Catalog.Sensors | ForEach-Object {$_.Id}) }
        'Cores' {$ids=$cores}
        'CoresCpu' {$ids=@($cores)+@('TCPU')}
        'CoresCpuPackage' {$ids=@($cores)+@('TCPU','TCPUPKG')}
        'Custom' {$ids=@($SelectedIds)}
        default {return $disabled}
    }
    $ids=@($ids | Sort-Object -Unique)
    if($Mode -eq 'All'){
        # The complete CPU baseline must remain available even in machine-wide mode.
        foreach($cpuId in (@('TCPUPKG')+ $cores)){if($cpuId -cnotin $ids){$ids+= $cpuId}}
    }
    if($ids.Count -eq 0){return $disabled}
    $values=@{}
    foreach($sensor in $Catalog.Sensors){$values[$sensor.Id]=$sensor}
    $missing=@();$maximum=$null;$hottestId='';$hottestLabel=''
    foreach($id in $ids){
        if(-not $values.ContainsKey($id) -or $values[$id].State -ne 'Valid'){
            $missing+=$id;continue
        }
        $temp=[double]$values[$id].TemperatureC
        if($null -eq $maximum -or $temp -gt $maximum){
            $maximum=$temp;$hottestId=$id;$hottestLabel=[string]$values[$id].Label
        }
    }
    $complete=$missing.Count -eq 0 -and $null -ne $maximum
    return [pscustomobject]@{
        Healthy=$complete;Complete=$complete;MaxC=$maximum;HottestId=$hottestId;HottestLabel=$hottestLabel;
        RequiredIds=$ids;MissingIds=$missing;
        Reason=$(if($complete){'Valid'}else{'MissingOrInvalidSensors'})
    }
}
Export-ModuleMember -Function Get-GuardTemperaturePolicy,Save-GuardTemperaturePolicy,Test-GuardActionSourceApproval,Save-GuardActionSourceApproval,Get-GuardActionSourceSignature,Test-GuardTemperatureValue,Get-GuardTemperatureCatalogFromValues,Read-GuardTemperatureCatalog,Get-GuardTemperatureSelection
