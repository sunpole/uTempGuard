# Pure image-selection policy. Does not read sensors, change approvals, or execute power actions.
Set-StrictMode -Version 2.0
function Get-GuardTrayBucket {
    [CmdletBinding()]
    param([AllowNull()][object]$TemperatureC,[bool]$SensorHealthy=$true)
    if(-not $SensorHealthy -or $null -eq $TemperatureC -or
       $TemperatureC -is [bool]){return $null}
    $temp=0.0
    if(-not [double]::TryParse([string]$TemperatureC,[Globalization.NumberStyles]::Float,
       [Globalization.CultureInfo]::InvariantCulture,[ref]$temp)){return $null}
    if([double]::IsNaN($temp) -or [double]::IsInfinity($temp) -or
       $temp -lt 0 -or $temp -gt 110){return $null}
    return [int][math]::Min(100,[math]::Floor($temp/10)*10)
}
function Get-GuardTrayIconChoice {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$TemperatureC,
        [bool]$SensorHealthy=$true,
        [ValidateSet('Dark','Light')][string]$TaskbarTheme='Dark',
        [double]$ElapsedSeconds=0.0,
        [string]$AssetDirectory=''
    )
    $bucket=Get-GuardTrayBucket -TemperatureC $TemperatureC -SensorHealthy $SensorHealthy
    $mode=if($TaskbarTheme -eq 'Dark'){'w'}else{'b'}
    $fallback=[pscustomobject]@{Ready=$false;Key='';Bucket=$bucket;Blink=$false;Theme=$mode;Reason='NoVerifiedTemperature'}
    if($null -eq $bucket){return $fallback}
    if([double]::IsNaN($ElapsedSeconds) -or [double]::IsInfinity($ElapsedSeconds) -or $ElapsedSeconds -lt 0){
        $ElapsedSeconds=0
    }
    $on=($bucket -ge 80 -and ([math]::Floor($ElapsedSeconds/0.4)%2 -eq 1))
    $code='{0:D3}' -f $bucket
    $key='utg_'+$mode+'_'+$code
    # Never invent an active frame for 000-070.
    if($on){$key+='_active'}
    if([string]::IsNullOrWhiteSpace($AssetDirectory)){return [pscustomobject]@{
        Ready=$true;Key=$key;Bucket=$bucket;Blink=$on;Theme=$mode;Reason='SelectionOnly'
    }}
    # Resolve missing frames safely: active -> static -> lower bucket in same theme -> other theme.
    $candidates=New-Object 'System.Collections.Generic.List[string]'
    $candidates.Add($key)
    $normal='utg_'+$mode+'_'+$code
    if($normal -cne $key){$candidates.Add($normal)}
    for($n=$bucket-10;$n -ge 0;$n-=10){$candidates.Add(('utg_{0}_{1:D3}' -f $mode,$n))}
    $alternate=if($mode -eq 'w'){'b'}else{'w'}
    $candidates.Add(('utg_{0}_{1:D3}' -f $alternate,$bucket))
    for($n=$bucket-10;$n -ge 0;$n-=10){$candidates.Add(('utg_{0}_{1:D3}' -f $alternate,$n))}
    foreach($candidate in $candidates){
        if($candidate -cnotmatch '^utg_[wb]_(?:0[0-9]0|100)(?:_active)?$'){continue}
        $file=Join-Path $AssetDirectory ($candidate+'.png.base64')
        if(Test-Path -LiteralPath $file -PathType Leaf){
            return [pscustomobject]@{
                Ready=$true;Key=$candidate;Bucket=$bucket
                Blink=$on;Theme=$mode;Reason=$(if($candidate -ceq $key){'Exact'}else{'MissingFrameFallback'})
            }
        }
    }
    return [pscustomobject]@{Ready=$false;Key='';Bucket=$bucket;Blink=$on;Theme=$mode;Reason='NoRenderedFrames'}
}
Export-ModuleMember -Function Get-GuardTrayBucket,Get-GuardTrayIconChoice
