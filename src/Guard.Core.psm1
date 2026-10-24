Set-StrictMode -Version 2.0

function Get-GuardDecision {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Temperature,
        [bool]$SensorHealthy = $false,
        [string]$PreviousState = 'Normal',
        [double]$WarningC = 70,
        [double]$ResumeBelowC = 69,
        [double]$ShutdownC = 75
    )
    $fault = { param($reason) [pscustomobject]@{ State = 'SensorFault'; Intent = 'None'; Temperature = $null; Reason = $reason } }
    if (-not $SensorHealthy) { return (& $fault 'SensorUnhealthy') }
    foreach ($threshold in @($WarningC, $ResumeBelowC, $ShutdownC)) {
        if ([double]::IsNaN($threshold) -or [double]::IsInfinity($threshold)) { return (& $fault 'InvalidThresholds') }
    }
    if ($ResumeBelowC -le 0 -or $ResumeBelowC -ge $WarningC -or $WarningC -ge $ShutdownC -or $ShutdownC -gt 110) {
        return (& $fault 'InvalidThresholds')
    }
    if ($null -eq $Temperature -or $Temperature -is [bool] -or $Temperature -is [array]) { return (& $fault 'InvalidTemperature') }
    $numeric = 0.0
    if (-not [double]::TryParse([string]$Temperature, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$numeric)) {
        return (& $fault 'InvalidTemperature')
    }
    if ([double]::IsNaN($numeric) -or [double]::IsInfinity($numeric) -or $numeric -le 0 -or $numeric -gt 110) {
        return (& $fault 'InvalidTemperature')
    }
    $state = 'Normal'
    $intent = 'None'
    $reason = 'BelowWarning'
    if ($numeric -ge $ShutdownC) { $state = 'Critical'; $intent = 'Shutdown'; $reason = 'ShutdownThreshold' }
    elseif ($numeric -ge $WarningC) { $state = 'Warning'; $intent = 'ReduceLoad'; $reason = 'WarningThreshold' }
    elseif ($numeric -ge $ResumeBelowC -and $PreviousState -in @('Warning', 'Critical')) {
        $state = 'Warning'; $intent = 'ReduceLoad'; $reason = 'Hysteresis'
    }
    return [pscustomobject]@{ State = $state; Intent = $intent; Temperature = $numeric; Reason = $reason }
}

function Get-NormalizedCpuPercent {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$CpuSecondsDelta,
        [AllowNull()][object]$ElapsedSeconds,
        [AllowNull()][object]$LogicalProcessors
    )
    $values = @()
    foreach ($inputValue in @($CpuSecondsDelta, $ElapsedSeconds, $LogicalProcessors)) {
        if ($null -eq $inputValue -or $inputValue -is [bool] -or $inputValue -is [array]) { return $null }
        $numeric = 0.0
        if (-not [double]::TryParse([string]$inputValue, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$numeric)) { return $null }
        if ([double]::IsNaN($numeric) -or [double]::IsInfinity($numeric)) { return $null }
        $values += $numeric
    }
    if ($values[0] -lt 0 -or $values[1] -le 0 -or $values[2] -lt 1 -or [math]::Truncate($values[2]) -ne $values[2]) { return $null }
    $result = 100.0 * $values[0] / $values[1] / $values[2]
    # A delta above wall time * processor count indicates invalid/reused sampling data.
    if ([double]::IsNaN($result) -or [double]::IsInfinity($result) -or $result -gt 100.01) { return $null }
    return [math]::Min(100.0, $result)
}

function Get-GuardProperty {
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

function Test-AllowedApplication {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Candidate,
        [AllowEmptyCollection()][object[]]$AllowList = @(),
        [string]$CurrentUserSid,
        [int]$CurrentSessionId
    )
    $deny = { param($reason) [pscustomobject]@{ Allowed = $false; Reason = $reason; Entry = $null } }
    if ($null -eq $Candidate -or [string]::IsNullOrWhiteSpace($CurrentUserSid) -or $CurrentSessionId -le 0) { return (& $deny 'UnknownIdentity') }
    $service = Get-GuardProperty $Candidate 'IsService'
    $window = Get-GuardProperty $Candidate 'HasWindow'
    if ($service -isnot [bool] -or $service) { return (& $deny 'ServiceOrUnknown') }
    if ($window -isnot [bool] -or -not $window) { return (& $deny 'NoWindow') }
    if ((Get-GuardProperty $Candidate 'OwnerSid') -ne $CurrentUserSid) { return (& $deny 'OtherOrUnknownUser') }
    $session = Get-GuardProperty $Candidate 'SessionId'
    if ($null -eq $session -or [string]$session -ne [string]$CurrentSessionId) { return (& $deny 'OtherOrUnknownSession') }
    $startTime = Get-GuardProperty $Candidate 'StartTimeUtc'
    $parsedStart = [datetime]::MinValue
    if ($null -eq $startTime -or -not [datetime]::TryParse([string]$startTime, [ref]$parsedStart) -or $parsedStart -eq [datetime]::MinValue) { return (& $deny 'UnknownStartTime') }

    $path = [string](Get-GuardProperty $Candidate 'Path')
    $name = [string](Get-GuardProperty $Candidate 'Name')
    if ([string]::IsNullOrWhiteSpace($path) -or [string]::IsNullOrWhiteSpace($name)) { return (& $deny 'UnknownProgram') }
    # Local executable paths only: no relative paths, UNC/device paths, ADS or traversal.
    if ($path -notmatch '^[A-Za-z]:\\' -or $path.Substring(2).Contains(':') -or $path -match '\\\.\.?\\' -or $path -notmatch '\.exe$') {
        return (& $deny 'InvalidExecutablePath')
    }
    try { $fullPath = [System.IO.Path]::GetFullPath($path) }
    catch { return (& $deny 'InvalidExecutablePath') }
    if (-not [string]::Equals($path, $fullPath, [System.StringComparison]::OrdinalIgnoreCase)) { return (& $deny 'NonCanonicalPath') }
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fullPath)
    if ($name -match '\.exe$') { $name = $name.Substring(0, $name.Length - 4) }
    if (-not [string]::Equals($baseName, $name, [System.StringComparison]::OrdinalIgnoreCase)) { return (& $deny 'NamePathMismatch') }
    $protectedNames = @(
        'system', 'idle', 'registry', 'secure system', 'smss', 'csrss', 'wininit', 'winlogon', 'services', 'svchost',
        'lsass', 'lsaiso', 'fontdrvhost', 'dwm', 'explorer', 'sihost', 'taskhostw', 'taskhost', 'conhost', 'dllhost',
        'runtimebroker', 'shellexperiencehost', 'startmenuexperiencehost', 'searchui', 'searchapp', 'searchhost', 'searchindexer',
        'applicationframehost', 'ctfmon', 'spoolsv', 'audiodg', 'wmiprvse', 'wudfhost', 'wlanext', 'userinit', 'logonui',
        'securityhealthservice', 'securityhealthsystray', 'msmpeng', 'mssense', 'nissrv', 'smartscreen', 'msseces', 'msascuil',
        'msascui', 'mpcmdrun', 'senseir', 'sensesc', 'sensece', 'sensesampleuploader', 'sensesecurityservice',
        'avp', 'avpui', 'avguard', 'avgnt', 'avgsvc', 'avastsvc', 'avastui', 'avgui', 'avgnt', 'ekrn', 'egui',
        'mbamservice', 'mbamtray', 'bdservicehost', 'bdagent', 'bdswitchagent', 'ccsvchst', 'nortonsecurity', 'mcshield',
        'mfemms', 'mfetp', 'windefend', 'aida64', 'rtss', 'fancontrol', 'hwinfo', 'hwinfo64', 'hwinfo32',
        'powershell', 'pwsh', 'shutdown'
    )
    if ($baseName -in $protectedNames -or $baseName -match '^(securityhealth|sense|msmp|mpdefender|avast|avg|sophos|sentinel|crowdstrike|csfalcon|elastic-endpoint|eset|kaspersky)') {
        return (& $deny 'ProtectedProcess')
    }
    $protectedRoots = @('C:\Windows', 'C:\ProgramData\Microsoft\Windows Defender', 'C:\Program Files\Windows Defender', 'C:\Program Files (x86)\Windows Defender')
    if (-not [string]::IsNullOrWhiteSpace($env:SystemRoot)) { $protectedRoots += $env:SystemRoot.TrimEnd('\') }
    foreach ($root in $protectedRoots) {
        if ($fullPath.StartsWith($root.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return (& $deny 'ProtectedDirectory') }
    }
    foreach ($entry in $AllowList) {
        $approved = Get-GuardProperty $entry 'Approved'
        $entryPath = [string](Get-GuardProperty $entry 'Path')
        $hash = [string](Get-GuardProperty $entry 'Sha256')
        if ($approved -is [bool] -and $approved -and $hash -match '^[0-9a-fA-F]{64}$' -and [string]::Equals($fullPath, $entryPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{ Allowed = $true; Reason = 'ApprovedExactPath'; Entry = $entry }
        }
    }
    return (& $deny 'NotApproved')
}

Export-ModuleMember -Function Get-GuardDecision, Get-NormalizedCpuPercent, Test-AllowedApplication
