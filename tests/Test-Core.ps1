[CmdletBinding()]
param([string]$ReportPath = '')
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts\core-tests.json' }
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Guard.Core.psm1') -Force
$script:results = New-Object 'System.Collections.Generic.List[object]'
function Assert-Equal {
    param([string]$Name, [AllowNull()][object]$Actual, [AllowNull()][object]$Expected)
    $passed = ($Actual -eq $Expected)
    if ($null -eq $Actual -and $null -eq $Expected) { $passed = $true }
    $script:results.Add([pscustomobject]@{ Name = $Name; Passed = [bool]$passed; Actual = $Actual; Expected = $Expected })
}
function Check-Decision {
    param([string]$Name, [AllowNull()][object]$Temperature, [string]$Previous, [string]$State, [string]$Intent, [bool]$Healthy = $true)
    $decision = Get-GuardDecision -Temperature $Temperature -SensorHealthy $Healthy -PreviousState $Previous
    Assert-Equal "$Name state" $decision.State $State
    Assert-Equal "$Name intent" $decision.Intent $Intent
}
Check-Decision '68.9 normal' 68.9 Normal Normal None
Check-Decision '69 initially normal' 69 Normal Normal None
Check-Decision '69.9 initially normal' 69.9 Normal Normal None
Check-Decision '70 warning' 70 Normal Warning ReduceLoad
Check-Decision '74.9 warning' 74.9 Normal Warning ReduceLoad
Check-Decision '75 critical immediately' 75 Normal Critical Shutdown
Check-Decision '110 valid upper boundary' 110 Normal Critical Shutdown
Check-Decision '69 hysteresis' 69 Warning Warning ReduceLoad
Check-Decision '69.999 hysteresis' 69.999 Warning Warning ReduceLoad
Check-Decision '68.999 resumes' 68.999 Warning Normal None
Check-Decision 'critical cools to warning' 72 Critical Warning ReduceLoad
Check-Decision 'critical cools to normal' 68 Critical Normal None
Check-Decision 'sensor fault clears protective intent' 100 Warning SensorFault None $false
Check-Decision 'fault recovery at 69 is normal' 69 SensorFault Normal None
foreach ($invalid in @($null, [double]::NaN, [double]::PositiveInfinity, [double]::NegativeInfinity, -1, 0, 110.1, 'TRIAL', '', $true)) {
    Check-Decision "invalid [$invalid]" $invalid Critical SensorFault None
}
Assert-Equal 'invalid threshold order' (Get-GuardDecision -Temperature 80 -SensorHealthy $true -ResumeBelowC 71).Intent None
Assert-Equal 'invalid threshold NaN' (Get-GuardDecision -Temperature 80 -SensorHealthy $true -ShutdownC ([double]::NaN)).State SensorFault
Assert-Equal '28 logical processors one busy thread' ([math]::Round((Get-NormalizedCpuPercent 1 1 28), 6)) 3.571429
Assert-Equal '28 logical processors all busy' (Get-NormalizedCpuPercent 28 1 28) 100
Assert-Equal '30 percent threshold exact' (Get-NormalizedCpuPercent 8.4 1 28) 30
Assert-Equal '30 percent not eligible for strict greater-than comparison' ((Get-NormalizedCpuPercent 8.4 1 28) -gt 30) $false
Assert-Equal '31 percent eligible for strict greater-than comparison' ((Get-NormalizedCpuPercent 8.68 1 28) -gt 30) $true
Assert-Equal '31 percent above threshold' ([math]::Round((Get-NormalizedCpuPercent 8.68 1 28), 6)) 31
Assert-Equal 'five seconds wall clock' (Get-NormalizedCpuPercent 42 5 28) 30
Assert-Equal 'zero CPU legitimate' (Get-NormalizedCpuPercent 0 2 28) 0
foreach ($argsCase in @(@(-1, 1, 28), @(1, 0, 28), @(1, -1, 28), @(1, 1, 0), @(1, 1, 1.5), @([double]::NaN, 1, 28), @([double]::PositiveInfinity, 1, 28), @(29, 1, 28), @($null, 1, 28))) {
    Assert-Equal "invalid CPU sample [$argsCase]" (Get-NormalizedCpuPercent $argsCase[0] $argsCase[1] $argsCase[2]) $null
}
$candidate = [pscustomobject]@{ Name = 'game'; Path = 'D:\Games\game.exe'; OwnerSid = 'S-1-5-21-test'; SessionId = 1; IsService = $false; StartTimeUtc = '2026-10-25T12:00:00Z'; HasWindow = $true }
$approved = [pscustomobject]@{ Path = 'D:\Games\game.exe'; Sha256 = ('a' * 64); Approved = $true }
function Check-Candidate {
    param([string]$Name, [object]$Object, [object[]]$Entries, [bool]$Expected)
    Assert-Equal $Name (Test-AllowedApplication -Candidate $Object -AllowList $Entries -CurrentUserSid 'S-1-5-21-test' -CurrentSessionId 1).Allowed $Expected
}
Check-Candidate 'approved application' $candidate @($approved) $true
Check-Candidate 'empty allowlist' $candidate @() $false
Check-Candidate 'unknown application' $null @($approved) $false
foreach ($field in @('Name', 'Path', 'OwnerSid', 'SessionId', 'IsService', 'StartTimeUtc', 'HasWindow')) {
    $copy = $candidate.PSObject.Copy(); $copy.$field = $null
    Check-Candidate "missing candidate $field" $copy @($approved) $false
}
foreach ($case in @(
    @{ Field = 'IsService'; Value = $true }, @{ Field = 'IsService'; Value = 'False' },
    @{ Field = 'HasWindow'; Value = $false }, @{ Field = 'HasWindow'; Value = 'True' },
    @{ Field = 'OwnerSid'; Value = 'S-1-5-18' }, @{ Field = 'SessionId'; Value = 0 },
    @{ Field = 'Path'; Value = 'D:\Games\other.exe' }, @{ Field = 'StartTimeUtc'; Value = 'unknown' },
    @{ Field = 'Path'; Value = '.\game.exe' }, @{ Field = 'Path'; Value = '\\server\game.exe' },
    @{ Field = 'Path'; Value = 'D:\Games\..\game.exe' }, @{ Field = 'Path'; Value = 'D:\Games\game.exe:stream.exe' }
)) {
    $copy = $candidate.PSObject.Copy(); $copy.($case.Field) = $case.Value
    Check-Candidate "deny $($case.Field) $($case.Value)" $copy @($approved) $false
}
foreach ($name in @('explorer', 'svchost', 'MsMpEng', 'lsass', 'SecurityHealthService', 'avp', 'crowdstrike-agent', 'powershell', 'aida64')) {
    $copy = $candidate.PSObject.Copy(); $copy.Name = $name; $copy.Path = "D:\Games\$name.exe"
    $entry = [pscustomobject]@{ Path = $copy.Path; Sha256 = ('a' * 64); Approved = $true }
    Check-Candidate "protected name $name even if allowlisted" $copy @($entry) $false
}
$copy = $candidate.PSObject.Copy(); $copy.Path = 'C:\Windows\System32\game.exe'
$entry = [pscustomobject]@{ Path = $copy.Path; Sha256 = ('a' * 64); Approved = $true }
Check-Candidate 'protected directory even if allowlisted' $copy @($entry) $false
foreach ($case in @(@{ Approved = 'True'; Sha256 = ('a' * 64) }, @{ Approved = $false; Sha256 = ('a' * 64) }, @{ Approved = $true; Sha256 = '' }, @{ Approved = $true; Sha256 = 'hash' })) {
    $entry = [pscustomobject]@{ Path = $candidate.Path; Sha256 = $case.Sha256; Approved = $case.Approved }
    Check-Candidate 'approval must be boolean and hash complete' $candidate @($entry) $false
}
$failed = @($script:results | Where-Object { -not $_.Passed })
$report = [pscustomobject]@{ TimestampUtc = [datetime]::UtcNow.ToString('o'); PowerShellVersion = $PSVersionTable.PSVersion.ToString(); Total = $script:results.Count; Passed = $script:results.Count - $failed.Count; Failed = $failed.Count; Tests = @($script:results.ToArray()) }
$directory = Split-Path -Parent $ReportPath
if ($directory -and -not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
if ($failed.Count -gt 0) { $failed | Format-Table -AutoSize | Out-String | Write-Output; Write-Output "FAILED: $($failed.Count)/$($script:results.Count)"; exit 1 }
Write-Output "PASS: $($script:results.Count) core assertions; report: $ReportPath"
exit 0
