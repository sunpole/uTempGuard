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

function Read-GuardCpuTemperatureSummary {
    [CmdletBinding()]
    param([AllowNull()][object]$VerifiedSample)
    # AIDA process, clock freshness and exact sensor source are already validated
    # by the current primary package reader. Never substitute an unvalidated source.
    if ($null -eq $VerifiedSample -or -not $VerifiedSample.Healthy -or
        [string]$VerifiedSample.Source -notlike 'Registry:*' -or
        [string]$VerifiedSample.SensorId -ne 'TCPUPKG') { return $null }
    $key=$null
    try {
        $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\FinalWire\AIDA64\SensorValues', $false)
        if ($null -eq $key) { return $null }
        $names = @($key.GetValueNames())
        $clock = [string]$key.GetValue('Value.STIME', $null)
        if ([string]::IsNullOrWhiteSpace($clock)) { return $null }
        $parsedClock=[datetime]::MinValue
        $clockFormats=@('H:mm:ss','HH:mm:ss','h:mm:ss tt','hh:mm:ss tt')
        if (-not [datetime]::TryParseExact($clock,$clockFormats,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::NoCurrentDateDefault,[ref]$parsedClock)) { return $null }
        $verifiedHeartbeat=[datetime]::MinValue
        if (-not [datetime]::TryParseExact([string]$VerifiedSample.Heartbeat,'yyyy-MM-ddTHH:mm:ss',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$verifiedHeartbeat)) { return $null }
        if ($parsedClock.TimeOfDay -ne $verifiedHeartbeat.TimeOfDay) { return $null }
        $rawDate=$key.GetValue('Value.SDATE',$null)
        if ($null -ne $rawDate) {
            $dateFormats=@('M/d/yyyy','MM/dd/yyyy','yyyy-MM-dd','d.M.yyyy','dd.MM.yyyy','d/M/yyyy','dd/MM/yyyy')
            $parsedDate=[datetime]::MinValue
            if (-not [datetime]::TryParseExact([string]$rawDate,$dateFormats,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$parsedDate) -or $parsedDate.Date -ne $verifiedHeartbeat.Date) { return $null }
        }
        $sensorList=New-Object 'System.Collections.Generic.List[object]'
        foreach ($name in $names) {
            if ($name -match '^Value\.(TCPUPKG|TCC-1-(?:[1-9]|1[0-4]))$') {
                $sensorList.Add([pscustomobject]@{Id=$Matches[1];Value=$key.GetValue($name,$null)})
            }
        }
        $summary=Get-GuardCpuTemperatureSummary -Sensors $sensorList.ToArray()
        if ($null -eq $summary) { return $null }
        $package=@($summary.Sensors | Where-Object { $_.Id -eq 'TCPUPKG' })
        if ($package.Count -ne 1 -or $package[0].State -ne 'Valid' -or
            $package[0].TemperatureC -ne [double]$VerifiedSample.TemperatureC) { return $null }
        # Do not claim data is current when AIDA advanced during the read.
        if ([string]$key.GetValue('Value.STIME',$null) -ne $clock) { return $null }
        return $summary
    } catch { return $null }
    finally { if ($null -ne $key) { $key.Dispose() } }
}
Export-ModuleMember -Function Get-GuardCpuTemperatureSummary,Read-GuardCpuTemperatureSummary
