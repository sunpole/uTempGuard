Set-StrictMode -Version 2.0
# Read-only CPU telemetry for display. Not an input to automatic power/process actions.
function Get-GuardCpuTemperatureSummary {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Sensors = @())
    $values = @{}
    $duplicate = $false
    foreach ($sensor in $Sensors) {
        if ($null -eq $sensor) { continue }
        $id = [string]$sensor.Id
        if (-not $id) { continue }
        if ($values.ContainsKey($id)) { $duplicate = $true; break }
        $values[$id] = $sensor.Value
    }
    if ($duplicate) { return $null }
    $ids = @('TCPUPKG') + @(1..14 | ForEach-Object { 'TCC-1-' + $_ })
    $records = New-Object 'System.Collections.Generic.List[object]'
    $max = $null
    $hottest = $null
    $count = 0
    foreach ($id in $ids) {
        $value = $null
        $state = 'NotExported'
        if ($values.ContainsKey($id)) {
            $raw = $values[$id]
            $numeric = 0.0
            if ($null -ne $raw -and $raw -isnot [bool] -and $raw -isnot [array] -and
                [double]::TryParse([string]$raw, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$numeric) -and
                -not [double]::IsNaN($numeric) -and -not [double]::IsInfinity($numeric) -and $numeric -gt 0 -and $numeric -le 110) {
                $state = 'Valid'
                $value = $numeric
                $count++
                if ($null -eq $max -or $numeric -gt $max) { $max = $numeric; $hottest = $id }
            } else { $state = 'Invalid' }
        }
        $label = if ($id -eq 'TCPUPKG') { 'CPU Package' } else { 'Ядро ' + $id.Substring(6) }
        $records.Add([pscustomobject]@{Id=$id;Label=$label;TemperatureC=$value;State=$state})
    }
    return [pscustomobject]@{
        MaxC=$max
        HottestId=$hottest
        AvailableCount=$count
        ExpectedCount=$ids.Count
        Sensors=$records.ToArray()
    }
}

function Test-GuardCpuRegistrySnapshot {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$VerifiedSample,
        [AllowNull()][object]$Values
    )
    $fail = { param([string]$reason) [pscustomobject]@{Healthy=$false;Reason=$reason;Summary=$null} }
    if ($null -eq $VerifiedSample -or -not $VerifiedSample.Healthy -or
        [string]$VerifiedSample.Source -notlike 'Registry:*' -or
        [string]$VerifiedSample.SensorId -ne 'TCPUPKG') { return (& $fail 'PrimarySensorNotVerified') }
    if ($null -eq $Values -or $Values -isnot [System.Collections.IDictionary]) { return (& $fail 'RegistrySnapshotMissing') }

    $clock = [string]$Values['Value.STIME']
    if ([string]::IsNullOrWhiteSpace($clock)) { return (& $fail 'HeartbeatTimeMissing') }
    $parsedClock = [datetime]::MinValue
    [string[]]$clockFormats=@('H:mm:ss','HH:mm:ss','h:mm:ss tt','hh:mm:ss tt')
    if (-not [datetime]::TryParseExact($clock,$clockFormats,[Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::NoCurrentDateDefault,[ref]$parsedClock)) { return (& $fail 'HeartbeatTimeInvalid') }
    $verifiedHeartbeat=[datetime]::MinValue
    if (-not [datetime]::TryParseExact([string]$VerifiedSample.Heartbeat,
        'yyyy-MM-ddTHH:mm:ss',[Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None,[ref]$verifiedHeartbeat)) { return (& $fail 'VerifiedHeartbeatInvalid') }
    if ($parsedClock.TimeOfDay -ne $verifiedHeartbeat.TimeOfDay) { return (& $fail 'HeartbeatMismatch') }

    if ($Values.Contains('Value.SDATE')) {
        [string[]]$dateFormats=@('M/d/yyyy','MM/dd/yyyy','yyyy-MM-dd','d.M.yyyy','dd.MM.yyyy','d/M/yyyy','dd/MM/yyyy')
        $parsedDate=[datetime]::MinValue
        if (-not [datetime]::TryParseExact([string]$Values['Value.SDATE'],$dateFormats,
            [Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,
            [ref]$parsedDate)) { return (& $fail 'HeartbeatDateInvalid') }
        if ($parsedDate.Date -ne $verifiedHeartbeat.Date) { return (& $fail 'HeartbeatDateMismatch') }
    }

    $sensors=New-Object 'System.Collections.Generic.List[object]'
    foreach ($name in $Values.Keys) {
        if ([string]$name -match '^Value\.(TCPUPKG|TCC-1-(?:[1-9]|1[0-4]))$') {
            $sensors.Add([pscustomobject]@{Id=$Matches[1];Value=$Values[$name]})
        }
    }
    if ($sensors.Count -lt 1) { return (& $fail 'NoCpuTemperatureEntries') }
    $summary=Get-GuardCpuTemperatureSummary -Sensors $sensors.ToArray()
    if ($null -eq $summary) { return (& $fail 'DuplicateSensorId') }
    $package=@($summary.Sensors | Where-Object { $_.Id -eq 'TCPUPKG' })
    if ($package.Count -ne 1 -or $package[0].State -ne 'Valid') { return (& $fail 'CpuPackageMissingOrInvalid') }
    if ($package[0].TemperatureC -ne [double]$VerifiedSample.TemperatureC) { return (& $fail 'CpuPackageChangedBetweenReads') }
    return [pscustomobject]@{Healthy=$true;Reason='Valid';Summary=$summary}
}

function Read-GuardCpuTemperatureSummary {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$VerifiedSample,
        [switch]$Diagnostic
    )
    $status=[pscustomobject]@{Healthy=$false;Reason='NotRead';Summary=$null}
    if ($null -eq $VerifiedSample -or -not $VerifiedSample.Healthy -or
        [string]$VerifiedSample.Source -notlike 'Registry:*' -or
        [string]$VerifiedSample.SensorId -ne 'TCPUPKG') {
        $status.Reason='PrimarySensorNotVerified'
        if ($Diagnostic) { return $status }
        return $null
    }
    # An AIDA update can occur between two independent registry reads. Retry
    # short-lived inconsistencies, but never relax primary identity/heartbeat.
    foreach ($attempt in 1..3) {
        $key=$null
        try {
            $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\FinalWire\AIDA64\SensorValues',$false)
            if ($null -eq $key) {
                $status.Reason='RegistryKeyUnavailable'
                break
            }
            $values=@{}
            $names=@($key.GetValueNames())
            $clockBefore=$key.GetValue('Value.STIME',$null)
            $dateBefore=$key.GetValue('Value.SDATE',$null)
            foreach ($name in $names) {
                if ($name -match '^Value\.(?:TCPUPKG|TCC-1-(?:[1-9]|1[0-4])|STIME|SDATE)$') {
                    $values[$name]=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                }
            }
            $clockAfter=$key.GetValue('Value.STIME',$null)
            $dateAfter=$key.GetValue('Value.SDATE',$null)
            if ([string]$clockBefore -ne [string]$clockAfter -or [string]$dateBefore -ne [string]$dateAfter) {
                $status.Reason='RegistryChangedDuringRead'
            } else {
                $status=Test-GuardCpuRegistrySnapshot -VerifiedSample $VerifiedSample -Values $values
            }
        } catch {
            $status=[pscustomobject]@{Healthy=$false;Reason=('RegistryReadException:'+$_.Exception.GetType().Name);Summary=$null}
            break
        } finally { if ($null -ne $key) { $key.Dispose() } }
        if ($status.Healthy) { break }
        if ($status.Reason -notin @('RegistryChangedDuringRead','HeartbeatMismatch','CpuPackageChangedBetweenReads')) { break }
        if ($attempt -lt 3) { Start-Sleep -Milliseconds 80 }
    }
    if ($Diagnostic) { return $status }
    if ($status.Healthy) { return $status.Summary }
    return $null
}
Export-ModuleMember -Function Get-GuardCpuTemperatureSummary,Read-GuardCpuTemperatureSummary,Test-GuardCpuRegistrySnapshot
