Set-StrictMode -Version 2.0

function Get-AidaProperty {
    param([AllowNull()][object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Reset-AidaHeartbeat {
    param([hashtable]$Context)
    foreach ($name in @('LastHeartbeat', 'LastChangeMonotonic', 'LastSeenMonotonic', 'HeartbeatConfirmed')) { $Context.Remove($name) }
}

function ConvertFrom-AidaSensorXml {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Xml)
    if ([string]::IsNullOrWhiteSpace($Xml) -or $Xml.Length -gt 1048576) { throw 'AIDA XML is empty or exceeds 1 MiB.' }
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.MaxCharactersInDocument = 1048576
    $document = New-Object System.Xml.XmlDocument
    $document.XmlResolver = $null
    $clean = $Xml.Trim().TrimStart([char]0xFEFF) -replace '^<\?xml[^?]*\?>', ''
    $textReader = New-Object System.IO.StringReader ('<aida_snapshot>' + $clean + '</aida_snapshot>')
    $reader = $null
    try {
        $reader = [System.Xml.XmlReader]::Create($textReader, $settings)
        $document.Load($reader)
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        $textReader.Dispose()
    }
    $container = $document.DocumentElement
    if ($container.ChildNodes.Count -eq 1 -and $container.FirstChild.Name -in @('AIDA64', 'aida64')) { $container = $container.FirstChild }
    $seen = @{}
    $result = New-Object 'System.Collections.Generic.List[object]'
    foreach ($node in $container.ChildNodes) {
        if ($node.NodeType -eq [System.Xml.XmlNodeType]::Comment -or $node.NodeType -eq [System.Xml.XmlNodeType]::Whitespace) { continue }
        if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) { throw 'Unexpected text in AIDA sensor XML.' }
        $ids = @($node.SelectNodes('id'))
        $labels = @($node.SelectNodes('label'))
        $values = @($node.SelectNodes('value'))
        if ($ids.Count -ne 1 -or $labels.Count -ne 1 -or $values.Count -ne 1) { throw 'Each AIDA sensor must contain one id, label and value.' }
        foreach ($field in @($ids[0], $labels[0], $values[0])) {
            foreach ($child in $field.ChildNodes) {
                if ($child.NodeType -eq [System.Xml.XmlNodeType]::Element) { throw 'Nested AIDA sensor fields are invalid.' }
            }
        }
        $sensorId = $ids[0].InnerText.Trim()
        if ($sensorId -notmatch '^[A-Za-z0-9_.:-]+$' -or $seen.ContainsKey($sensorId)) { throw 'Invalid or duplicate AIDA sensor id.' }
        $seen[$sensorId] = $true
        $result.Add([pscustomobject]@{ Id = $sensorId; Label = $labels[0].InnerText; Value = $values[0].InnerText.Trim() })
    }
    if ($result.Count -eq 0) { throw 'AIDA XML has no sensor entries.' }
    return $result.ToArray()
}

function Test-AidaSnapshot {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Sensors = @(),
        [string]$SensorId = 'TCPUPKG',
        [bool]$ProducerRunning = $false,
        [double]$MaxAgeSeconds = 10,
        [hashtable]$Context = @{},
        [datetime]$Now = [datetime]::Now,
        [double]$MonotonicSeconds = ([System.Diagnostics.Stopwatch]::GetTimestamp() / [double][System.Diagnostics.Stopwatch]::Frequency),
        [string]$Source = 'Snapshot'
    )
    if ($null -eq $Context) { $Context = @{} }
    $result = [ordered]@{
        Healthy = $false; TemperatureC = $null; SensorId = $SensorId; Label = ''; Heartbeat = $null;
        AgeSeconds = $null; Error = ''; Source = $Source; ObservedUtc = $Now.ToUniversalTime().ToString('o')
    }
    $fail = {
        param($reason)
        Reset-AidaHeartbeat -Context $Context
        $result.Error = $reason
        [pscustomobject]$result
    }
    if (-not $ProducerRunning) { return (& $fail 'ProducerNotRunningOrPathMismatch') }
    if ([double]::IsNaN($MaxAgeSeconds) -or [double]::IsInfinity($MaxAgeSeconds) -or $MaxAgeSeconds -le 0 -or
        [double]::IsNaN($MonotonicSeconds) -or [double]::IsInfinity($MonotonicSeconds) -or $MonotonicSeconds -lt 0) { return (& $fail 'InvalidFreshnessConfiguration') }
    if ([string]::IsNullOrWhiteSpace($SensorId)) { return (& $fail 'MissingConfiguredSensorId') }
    $byId = @{}
    foreach ($sensor in $Sensors) {
        $idValue = [string](Get-AidaProperty $sensor 'Id')
        if ([string]::IsNullOrWhiteSpace($idValue) -or $byId.ContainsKey($idValue)) { return (& $fail 'MissingOrDuplicateSensorId') }
        $byId[$idValue] = $sensor
    }
    if (-not $byId.ContainsKey($SensorId)) { return (& $fail 'ConfiguredSensorMissing') }
    $result.Label = [string](Get-AidaProperty $byId[$SensorId] 'Label')
    $rawTemperature = Get-AidaProperty $byId[$SensorId] 'Value'
    if ($null -eq $rawTemperature -or $rawTemperature -is [bool] -or $rawTemperature -is [array]) { return (& $fail 'InvalidTemperature') }
    $temperature = 0.0
    if (-not [double]::TryParse([string]$rawTemperature, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$temperature) -or
        [double]::IsNaN($temperature) -or [double]::IsInfinity($temperature) -or $temperature -le 0 -or $temperature -gt 110) { return (& $fail 'InvalidTemperature') }
    if (-not $byId.ContainsKey('STIME')) { return (& $fail 'HeartbeatTimeMissing') }
    $clock = [string](Get-AidaProperty $byId['STIME'] 'Value')
    $parsedClock = [datetime]::MinValue
    [string[]]$clockFormats = @('H:mm:ss', 'HH:mm:ss', 'h:mm:ss tt', 'hh:mm:ss tt')
    if (-not [datetime]::TryParseExact($clock, $clockFormats, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::NoCurrentDateDefault, [ref]$parsedClock)) {
        return (& $fail 'HeartbeatTimeInvalid')
    }
    $dates = @()
    $dateToken = ''
    if ($byId.ContainsKey('SDATE')) {
        $dateToken = [string](Get-AidaProperty $byId['SDATE'] 'Value')
        $parsedDate = [datetime]::MinValue
        [string[]]$dateFormats = @('M/d/yyyy', 'MM/dd/yyyy', 'yyyy-MM-dd', 'd.M.yyyy', 'dd.MM.yyyy', 'd/M/yyyy', 'dd/MM/yyyy')
        if (-not [datetime]::TryParseExact($dateToken, $dateFormats, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsedDate)) {
            return (& $fail 'HeartbeatDateInvalid')
        }
        $dates = @($parsedDate.Date)
    }
    else { $dates = @($Now.Date.AddDays(-1), $Now.Date, $Now.Date.AddDays(1)) }
    $heartbeat = $null
    $bestDifference = [double]::PositiveInfinity
    foreach ($date in $dates) {
        $candidateTime = $date.Add($parsedClock.TimeOfDay)
        $difference = [math]::Abs(($Now - $candidateTime).TotalSeconds)
        if ($difference -lt $bestDifference) { $bestDifference = $difference; $heartbeat = $candidateTime }
    }
    $wallAge = ($Now - $heartbeat).TotalSeconds
    $result.Heartbeat = $heartbeat.ToString('yyyy-MM-ddTHH:mm:ss')
    $result.AgeSeconds = [math]::Round([math]::Max(0, $wallAge), 3)
    if ($wallAge -gt $MaxAgeSeconds) { return (& $fail 'HeartbeatClockStale') }
    if ($wallAge -lt -2) { return (& $fail 'HeartbeatClockInFuture') }
    $token = $dateToken + '|' + $clock
    if ($Context.ContainsKey('Source') -and $Context.Source -ne $Source) { Reset-AidaHeartbeat -Context $Context }
    $Context.Source = $Source
    if (-not $Context.ContainsKey('LastHeartbeat')) {
        $Context.LastHeartbeat = $token
        $Context.LastChangeMonotonic = $MonotonicSeconds
        $Context.LastSeenMonotonic = $MonotonicSeconds
        $Context.HeartbeatConfirmed = $false
        $result.Error = 'AwaitingHeartbeatChange'
        return [pscustomobject]$result
    }
    if ($MonotonicSeconds -lt $Context.LastSeenMonotonic) { return (& $fail 'MonotonicClockReversed') }
    $Context.LastSeenMonotonic = $MonotonicSeconds
    if ($Context.LastHeartbeat -ne $token) {
        $Context.LastHeartbeat = $token
        $Context.LastChangeMonotonic = $MonotonicSeconds
        $Context.HeartbeatConfirmed = $true
    }
    $monotonicAge = $MonotonicSeconds - $Context.LastChangeMonotonic
    $result.AgeSeconds = [math]::Round([math]::Max($result.AgeSeconds, $monotonicAge), 3)
    if ($monotonicAge -gt $MaxAgeSeconds) { return (& $fail 'HeartbeatNotAdvancing') }
    if (-not $Context.HeartbeatConfirmed) {
        $result.Error = 'AwaitingHeartbeatChange'
        return [pscustomobject]$result
    }
    $result.Healthy = $true
    $result.TemperatureC = $temperature
    return [pscustomobject]$result
}

function Read-AidaRegistrySnapshot {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\FinalWire\AIDA64\SensorValues', $false)
    if ($null -eq $key) { throw 'AIDA registry sensor key is unavailable.' }
    try {
        $snapshot = @{}
        foreach ($name in $key.GetValueNames()) { $snapshot[$name] = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
        $sensors = @()
        foreach ($name in $snapshot.Keys) {
            if ($name.StartsWith('Value.', [System.StringComparison]::Ordinal)) {
                $idValue = $name.Substring(6)
                $sensors += [pscustomobject]@{ Id = $idValue; Label = [string]$snapshot['Label.' + $idValue]; Value = $snapshot[$name] }
            }
        }
        if ($sensors.Count -eq 0) { throw 'AIDA registry snapshot has no Value.* entries.' }
        return $sensors
    }
    finally { $key.Dispose() }
}

function Read-AidaMemorySnapshot {
    param([string]$Name)
    $mapping = $null
    $stream = $null
    try {
        $mapping = [System.IO.MemoryMappedFiles.MemoryMappedFile]::OpenExisting($Name, [System.IO.MemoryMappedFiles.MemoryMappedFileRights]::Read)
        $stream = $mapping.CreateViewStream(0, 0, [System.IO.MemoryMappedFiles.MemoryMappedFileAccess]::Read)
        if ($stream.Length -le 0 -or $stream.Length -gt 1048576) { throw [System.FormatException]::new('AIDA shared memory size exceeds the permitted bound.') }
        $buffer = New-Object byte[] ([int]$stream.Length)
        $count = 0
        while ($count -lt $buffer.Length) {
            $read = $stream.Read($buffer, $count, $buffer.Length - $count)
            if ($read -le 0) { break }
            $count += $read
        }
        $terminator = [array]::IndexOf($buffer, [byte]0)
        if ($terminator -le 0 -or $terminator -ge $count) { throw [System.FormatException]::new('AIDA shared memory lacks a valid null-terminated snapshot.') }
        $encoding = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage)
        $xml = $encoding.GetString($buffer, 0, $terminator)
        try { return ConvertFrom-AidaSensorXml -Xml $xml }
        catch { throw [System.FormatException]::new('AIDA shared memory XML is invalid: ' + $_.Exception.Message) }
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $mapping) { $mapping.Dispose() }
    }
}

function Get-AidaProcessPath {
    param([System.Diagnostics.Process]$Process)
    try {
        $path = $Process.Path
        if (-not [string]::IsNullOrWhiteSpace($path)) { return $path }
    }
    catch { }
    # A filtered user token can query an elevated process image with limited-query
    # access even when System.Diagnostics.Process.MainModule/Path is unavailable.
    if ($null -eq ('UTempGuard.Native.SensorProcessPath' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
namespace UTempGuard.Native {
    public static class SensorProcessPath {
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(uint access, bool inheritHandle, int processId);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool QueryFullProcessImageNameW(IntPtr process, uint flags, StringBuilder filename, ref uint size);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);
        public static string Read(int processId) {
            IntPtr process = OpenProcess(0x1000, false, processId);
            if (process == IntPtr.Zero) return null;
            try {
                uint size = 32768;
                StringBuilder path = new StringBuilder((int)size);
                return QueryFullProcessImageNameW(process, 0, path, ref size) ? path.ToString() : null;
            }
            finally { CloseHandle(process); }
        }
    }
}
'@ -ErrorAction Stop
    }
    return [UTempGuard.Native.SensorProcessPath]::Read($Process.Id)
}

function Read-AidaSensor {
    [CmdletBinding()]
    param(
        [string]$SensorId = 'TCPUPKG',
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$AidaPath,
        [double]$MaxAgeSeconds = 10,
        [hashtable]$Context = @{}
    )
    if ($null -eq $Context) { $Context = @{} }
    $identity = $null
    $producerPathMatched = $false
    if (-not [string]::IsNullOrWhiteSpace($AidaPath)) {
        foreach ($process in @(Get-Process -Name 'aida64' -ErrorAction SilentlyContinue)) {
            try {
                if ($null -eq $identity) {
                    $producerPath = Get-AidaProcessPath -Process $process
                    if ([string]::Equals($producerPath, $AidaPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $producerPathMatched = $true
                        $identity = [string]$process.Id + '|' + $process.StartTime.ToUniversalTime().ToString('o')
                    }
                }
            }
            catch { continue }
            finally { $process.Dispose() }
        }
    }
    if ($null -eq $identity) {
        $source = 'Unavailable'
        if ($producerPathMatched) { $source = 'UnverifiableProducer' }
        return Test-AidaSnapshot -SensorId $SensorId -ProducerRunning $false -Context $Context -MaxAgeSeconds $MaxAgeSeconds -Source $source
    }
    if ($Context.ContainsKey('ProducerIdentity') -and $Context.ProducerIdentity -ne $identity) { Reset-AidaHeartbeat -Context $Context }
    $Context.ProducerIdentity = $identity
    $errors = @()
    foreach ($mapName in @('AIDA64_SensorValues', 'Global\AIDA64_SensorValues', 'Local\AIDA64_SensorValues')) {
        try {
            $sensors = @(Read-AidaMemorySnapshot -Name $mapName)
            $ids = @($sensors | ForEach-Object { $_.Id })
            if ($SensorId -notin $ids -or 'STIME' -notin $ids) {
                $errors += $mapName + ': configured sensor or STIME is not exported.'
                continue
            }
            return Test-AidaSnapshot -Sensors $sensors -SensorId $SensorId -ProducerRunning $true -Context $Context -MaxAgeSeconds $MaxAgeSeconds -Source ('MemoryMappedFile:' + $mapName)
        }
        catch {
            $exception = $_.Exception
            $malformed = $false
            while ($null -ne $exception) {
                if ($exception -is [System.FormatException] -or $exception -is [System.Xml.XmlException]) { $malformed = $true; break }
                $exception = $exception.InnerException
            }
            if ($malformed) {
                $result = Test-AidaSnapshot -SensorId $SensorId -ProducerRunning $true -Context $Context -MaxAgeSeconds $MaxAgeSeconds -Source ('MemoryMappedFile:' + $mapName)
                $result.Error = 'SensorExportInvalid: ' + $_.Exception.Message
                return $result
            }
            $errors += $mapName + ': ' + $_.Exception.Message
        }
    }
    try {
        $sensors = @(Read-AidaRegistrySnapshot)
        return Test-AidaSnapshot -Sensors $sensors -SensorId $SensorId -ProducerRunning $true -Context $Context -MaxAgeSeconds $MaxAgeSeconds -Source 'Registry:HKCU\Software\FinalWire\AIDA64\SensorValues'
    }
    catch { $errors += 'Registry: ' + $_.Exception.Message }
    $result = Test-AidaSnapshot -SensorId $SensorId -ProducerRunning $true -Context $Context -MaxAgeSeconds $MaxAgeSeconds -Source 'Unavailable'
    $result.Error = 'SensorExportUnavailable: ' + ($errors -join '; ')
    return $result
}

Export-ModuleMember -Function Read-AidaSensor, ConvertFrom-AidaSensorXml, Test-AidaSnapshot
