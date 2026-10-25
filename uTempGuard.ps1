[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'uTempGuard'),
    [switch]$Headless,
    [int]$MaxSamples = 0,
    [string]$SimulationPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath=Join-Path $PSScriptRoot 'config.json' }
Import-Module (Join-Path $PSScriptRoot 'src\Guard.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'src\Guard.Sensor.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'src\Guard.CpuSummary.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'src\Guard.Overlay.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'src\Guard.Notices.psm1') -Force
$DataDirectory = [IO.Path]::GetFullPath($DataDirectory).TrimEnd('\')
[IO.Directory]::CreateDirectory($DataDirectory) | Out-Null
$statusPath = Join-Path $DataDirectory 'status.json'
$stopPath = Join-Path $DataDirectory 'stop.request'
$logPath = Join-Path $DataDirectory 'events.jsonl'
$started = [datetime]::UtcNow.ToString('o')
$script:form = $null
$script:overlayPreview = $false
$script:tray = $null
$script:lastNotice = [datetime]::MinValue
$script:firstValidSensorSeen = $false
$script:startupPendingLogged = $false
$script:previousProcesses = @{}
$script:clock = [Diagnostics.Stopwatch]::StartNew()
$script:context = @{}
$script:state = 'Normal'
$script:lastSample = $null
$script:lastCpuSummary = $null
$script:lastDecision = $null
$script:overlaySettingsPath = Join-Path $DataDirectory 'overlay.json'
$script:overlaySettings = $null
$script:count = 0
$mutex = $null
$ownsMutex = $false
$instanceLock = $null
$script:lastActions = @{}
$running = $false

function Write-GuardEvent {
    param([string]$Event, [object]$Details)
    if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 5MB) {
        for ($n=2; $n -ge 1; $n--) {
            $old = "$logPath.$n"
            if (Test-Path -LiteralPath $old) { Move-Item -LiteralPath $old -Destination "$logPath.$($n+1)" -Force }
        }
        Move-Item -LiteralPath $logPath -Destination "$logPath.1" -Force
    }
    $record = [ordered]@{Utc=[datetime]::UtcNow.ToString('o');Event=$Event;Details=$Details}
    [IO.File]::AppendAllText($logPath, (($record | ConvertTo-Json -Depth 8 -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}
function Write-GuardStatus {
    param([bool]$IsRunning, [string]$State, [object]$Sample)
    $temperature = $null; $sensorError = $null
    if ($null -ne $Sample) { $temperature = $Sample.TemperatureC; $sensorError = $Sample.Error }
    $value = [ordered]@{Pid=$PID;StartedUtc=$started;UpdatedUtc=[datetime]::UtcNow.ToString('o');Running=$IsRunning;State=$State;TemperatureC=$temperature;SensorError=$sensorError;Mode=$config.Mode;Simulation=[bool]$SimulationPath;SensorId=$config.SensorId;SampleCount=$script:count;LogicalProcessors=$logicalCount}
    $tmp = "$statusPath.$PID.tmp"
    [IO.File]::WriteAllText($tmp, ($value | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $statusPath -Force
}
function Show-GuardNotice {
    param([string]$Text)
    if ($null -ne $script:tray -and ([datetime]::UtcNow-$script:lastNotice).TotalSeconds -ge 60) {
        $script:tray.ShowBalloonTip(10000, 'uTempGuard', $Text, [Windows.Forms.ToolTipIcon]::Warning)
        $script:lastNotice = [datetime]::UtcNow
    }
}
function Get-GuardCandidates {
    $nowSeconds = $script:clock.Elapsed.TotalSeconds
    $next = @{}; $hot = @()
    $scope = $config.PSObject.Properties['AppCloseScope']
    $scanApproved = ($null -ne $scope -and $scope.Value -eq 'ApprovedInteractive')
    $approvedNames = @()
    if ($scanApproved) {
        foreach ($entry in @($config.AllowList)) {
            if ($null -ne $entry -and $entry.Approved -is [bool] -and $entry.Approved -and
                -not [string]::IsNullOrWhiteSpace([string]$entry.Path)) {
                $approvedNames += [IO.Path]::GetFileNameWithoutExtension([string]$entry.Path)
            }
        }
    }
    foreach ($proc in [Diagnostics.Process]::GetProcesses()) {
        try {
            $startUtc = $proc.StartTime.ToUniversalTime().ToString('o')
            $key = '{0}|{1}' -f $proc.Id,$startUtc
            $cpu = $proc.TotalProcessorTime.TotalSeconds
            $next[$key] = @{Cpu=$cpu;Time=$nowSeconds}
            if (-not $script:previousProcesses.ContainsKey($key)) { continue }
            $prev = $script:previousProcesses[$key]
            $percent = Get-NormalizedCpuPercent -CpuSecondsDelta ($cpu-$prev.Cpu) -ElapsedSeconds ($nowSeconds-$prev.Time) -LogicalProcessors $logicalCount
            if ($null -eq $percent) { continue }
            if ($scanApproved) {
                if ($proc.ProcessName -notin $approvedNames) { continue }
            } elseif ($percent -le $config.CpuThresholdPercent) { continue }
            $owner = $null; $isService = $true
            $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)" -ErrorAction Stop
            $ownerResult = Invoke-CimMethod -InputObject $cim -MethodName GetOwnerSid -ErrorAction Stop
            if ($ownerResult.ReturnValue -eq 0) { $owner = $ownerResult.Sid }
            $services = @(Get-CimInstance Win32_Service -Filter "ProcessId=$($proc.Id)" -ErrorAction Stop)
            $isService = $services.Count -gt 0
            $candidate = [pscustomobject]@{Pid=$proc.Id;Name=($proc.ProcessName+'.exe');Path=$proc.Path;OwnerSid=$owner;SessionId=$proc.SessionId;IsService=$isService;StartTimeUtc=$startUtc;HasWindow=($proc.MainWindowHandle -ne [IntPtr]::Zero);CpuPercent=[math]::Round($percent,2)}
            $eligibility = Test-AllowedApplication -Candidate $candidate -AllowList @($config.AllowList) -CurrentUserSid $userSid -CurrentSessionId $sessionId
            $hot += [pscustomobject]@{Candidate=$candidate;Eligibility=$eligibility}
        } catch { # Unreadable processes are never candidates for an action.
        } finally { $proc.Dispose() }
    }
    $script:previousProcesses = $next
    return $hot
}
function Test-LiveApproval {
    if ($SimulationPath -or $config.Mode -ne 'Live') { return $false }
    $receiptPath = Join-Path $PSScriptRoot 'live-approval.json'
    if (-not (Test-Path -LiteralPath $receiptPath)) { return $false }
    try {
        $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        return ($receipt.ApprovedByUser -is [bool] -and $receipt.ApprovedByUser -and $receipt.SensorValidatedForLive -is [bool] -and $receipt.SensorValidatedForLive -and $receipt.ConfigSha256 -eq (Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash)
    } catch { return $false }
}
function Test-ForcedShutdownApproval {
    if (-not (Test-LiveApproval)) { return $false }
    $setting = $config.PSObject.Properties['EnableForcedShutdown']
    if ($null -eq $setting -or $setting.Value -isnot [bool] -or -not $setting.Value) { return $false }
    $receiptPath = Join-Path $PSScriptRoot 'live-approval.json'
    try {
        $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $permission = $receipt.PSObject.Properties['ForcedShutdownApproved']
        return ($null -ne $permission -and $permission.Value -is [bool] -and $permission.Value)
    } catch { return $false }
}
function Get-VerifiedCpuMaximum {
    param([object]$Primary, [AllowNull()][object]$CpuSummary)
    if ($null -eq $Primary -or -not $Primary.Healthy) { return $null }
    $temperature=[double]$Primary.TemperatureC
    if ($null -ne $CpuSummary -and $CpuSummary.AvailableCount -ge 1 -and $null -ne $CpuSummary.MaxC) {
        $max=[double]$CpuSummary.MaxC
        if ($max -ge $temperature -and $max -gt 0 -and $max -le 110) { $temperature=$max }
    }
    return $temperature
}
function Invoke-GuardIntent {
    param([object]$Decision, [object[]]$Candidates)
    if ($Decision.Intent -eq 'None') { return }
    $live = Test-LiveApproval
    Write-GuardEvent 'Intent' @{Intent=$Decision.Intent;State=$Decision.State;TemperatureC=$Decision.Temperature;ExecutionAllowed=$live;Candidates=@($Candidates | ForEach-Object { @{Pid=$_.Candidate.Pid;Name=$_.Candidate.Name;CpuPercent=$_.Candidate.CpuPercent;Allowed=$_.Eligibility.Allowed;Reason=$_.Eligibility.Reason} })}
    if (-not $live) { return }
    # Re-read the producer immediately before every side effect. Invalid input cancels it.
    $fresh = Read-AidaSensor -SensorId $config.SensorId -AidaPath $config.AidaPath -MaxAgeSeconds $config.MaxAgeSeconds -Context $script:context
    $freshSummary = if ($fresh.Healthy) { Read-GuardCpuTemperatureSummary -VerifiedSample $fresh } else { $null }
    $verifiedMaximum = Get-VerifiedCpuMaximum -Primary $fresh -CpuSummary $freshSummary
    $again = Get-GuardDecision -Temperature $verifiedMaximum -SensorHealthy $fresh.Healthy -PreviousState $Decision.State -WarningC $config.WarningC -ResumeBelowC $config.ResumeBelowC -ShutdownC $config.ShutdownC
    if ($Decision.Intent -eq 'Shutdown' -and $again.Intent -eq 'Shutdown' -and $config.EnableShutdown -is [bool] -and $config.EnableShutdown) {
        if ($script:lastActions.ContainsKey('shutdown') -and ($script:clock.Elapsed.TotalSeconds-$script:lastActions['shutdown']) -lt 60) { return }
        $script:lastActions['shutdown']=$script:clock.Elapsed.TotalSeconds
        $forceRequested = $null -ne $config.PSObject.Properties['EnableForcedShutdown'] -and
            $config.EnableForcedShutdown -is [bool] -and $config.EnableForcedShutdown
        if ($forceRequested) {
            if (-not (Test-ForcedShutdownApproval)) {
                Write-GuardEvent 'ForcedShutdownBlocked' @{Reason='SeparateExplicitApprovalMissing'}
                return
            }
            Write-GuardEvent 'ForcedShutdownRequested' @{TemperatureC=$verifiedMaximum;Mode='ApprovedEmergency'}
            # Explicitly user-approved emergency mode. Unsaved application data can be lost.
            $shutdownPath = Join-Path $env:WINDIR 'System32\shutdown.exe'
            & $shutdownPath /s /f /t 0
            Write-GuardEvent 'ForcedShutdownCommandReturned' @{ExitCode=$LASTEXITCODE}
        } else {
            Write-GuardEvent 'OrderlyShutdownRequested' @{TemperatureC=$verifiedMaximum}
            $os = Get-CimInstance Win32_OperatingSystem
            $result = Invoke-CimMethod -InputObject $os -MethodName Win32Shutdown -Arguments @{Flags=1;Reserved=0}
            Write-GuardEvent 'OrderlyShutdownResult' @{ReturnValue=$result.ReturnValue}
        }
        return
    }
    if ($again.Intent -ne 'ReduceLoad' -or $config.EnableAppClose -isnot [bool] -or -not $config.EnableAppClose) { return }
    foreach ($item in $Candidates) {
        if (-not $item.Eligibility.Allowed) { continue }
        try {
            $fresh = Read-AidaSensor -SensorId $config.SensorId -AidaPath $config.AidaPath -MaxAgeSeconds $config.MaxAgeSeconds -Context $script:context
            $freshSummary = if ($fresh.Healthy) { Read-GuardCpuTemperatureSummary -VerifiedSample $fresh } else { $null }
            $freshMax = Get-VerifiedCpuMaximum -Primary $fresh -CpuSummary $freshSummary
            if ($null -eq $freshMax -or $freshMax -lt $config.ResumeBelowC) { break }
            $candidate = $item.Candidate
            $actionKey='{0}|{1}' -f $candidate.Pid,$candidate.StartTimeUtc
            if ($script:lastActions.ContainsKey($actionKey) -and ($script:clock.Elapsed.TotalSeconds-$script:lastActions[$actionKey]) -lt 60) { continue }
            $proc = Get-Process -Id $candidate.Pid -ErrorAction Stop
            try {
                if ($proc.StartTime.ToUniversalTime().ToString('o') -ne $candidate.StartTimeUtc -or $proc.Path -ne $candidate.Path -or $proc.SessionId -ne $sessionId -or $proc.MainWindowHandle -eq [IntPtr]::Zero) { continue }
                $owner = Invoke-CimMethod -InputObject (Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)") -MethodName GetOwnerSid
                if ($owner.ReturnValue -ne 0 -or $owner.Sid -ne $userSid) { continue }
                if (@(Get-CimInstance Win32_Service -Filter "ProcessId=$($proc.Id)").Count -gt 0) { continue }
                if ((Get-FileHash -LiteralPath $candidate.Path -Algorithm SHA256).Hash -ne $item.Eligibility.Entry.Sha256) { continue }
                $script:lastActions[$actionKey]=$script:clock.Elapsed.TotalSeconds
                $accepted = $proc.CloseMainWindow()
                Write-GuardEvent 'GracefulCloseRequested' @{Pid=$proc.Id;Accepted=$accepted;Path=$candidate.Path}
                # An application may ask to save or refuse. Never kill or escalate.
            } finally { $proc.Dispose() }
        } catch { Write-GuardEvent 'ActionError' @{Message=$_.Exception.Message} }
    }
}
. (Join-Path $PSScriptRoot 'src\Guard.OverlayUI.ps1')

try {
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($config.Mode -notin @('Observe','Live') -or $config.PollSeconds -lt 1 -or $config.PollSeconds -gt 30 -or $config.MaxAgeSeconds -lt 3 -or $config.MaxAgeSeconds -gt 30 -or $config.CpuThresholdPercent -ne 30) { throw 'Invalid configuration: Mode, poll, freshness, CPU threshold.' }
    $thresholdCheck = Get-GuardDecision -Temperature 40 -SensorHealthy $true -WarningC $config.WarningC -ResumeBelowC $config.ResumeBelowC -ShutdownC $config.ShutdownC
    if ($thresholdCheck.State -eq 'SensorFault') { throw 'Invalid temperature thresholds.' }
    $logicalCount = [Environment]::ProcessorCount
    $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $mutexKey = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($DataDirectory.ToUpperInvariant())).Replace('/','_').Replace('+','-')
    $mutex = [Threading.Mutex]::new($false, ('Local\uTempGuard-'+$mutexKey))
    try { $ownsMutex=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex=$true }
    if (-not $ownsMutex) { exit 0 }
    # File identity also covers aliases/junctions referring to the same data folder.
    try { $instanceLock=[IO.File]::Open((Join-Path $DataDirectory 'instance.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
    catch [IO.IOException] { exit 0 }
    if (Test-Path -LiteralPath $stopPath) { Remove-Item -LiteralPath $stopPath }
    $simulation = @()
    if ($SimulationPath) { $simulation = Get-Content -LiteralPath $SimulationPath -Raw | ConvertFrom-Json; if ($simulation.Count -eq 0) { throw 'Empty simulation.' } }
    $script:overlaySettings = Get-GuardOverlaySettings -Path $script:overlaySettingsPath
    if (-not $Headless) { Initialize-GuardOverlay }
    $running=$true
    Write-GuardEvent 'Started' @{Version=$config.Version;Mode=$config.Mode;Simulation=[bool]$SimulationPath;LogicalProcessors=$logicalCount;ConfigPath=$ConfigPath;LiveApproved=(Test-LiveApproval)}
    $nextTick=0.0
    while (-not (Test-Path -LiteralPath $stopPath)) {
        if ($null -ne $script:form) { [Windows.Forms.Application]::DoEvents() }
        if ($script:clock.Elapsed.TotalSeconds -lt $nextTick) { Start-Sleep -Milliseconds 100; continue }
        $nextTick=$script:clock.Elapsed.TotalSeconds+$config.PollSeconds
        $previousState=$script:state
        if ($SimulationPath) {
            if ($script:count -ge $simulation.Count) { break }
            $sim=$simulation[$script:count]
            $script:lastSample=[pscustomobject]@{Healthy=[bool]$sim.Healthy;TemperatureC=$sim.TemperatureC;Error=$sim.Error;SensorId=$config.SensorId;Source='Simulation';Heartbeat='simulation'}
            $candidates=@()
            $script:lastCpuSummary=$null
        } else {
            $script:lastSample=Read-AidaSensor -SensorId $config.SensorId -AidaPath $config.AidaPath -MaxAgeSeconds $config.MaxAgeSeconds -Context $script:context
            $script:lastCpuSummary=Read-GuardCpuTemperatureSummary -VerifiedSample $script:lastSample
            $candidates=@()
        }
        if (-not $SimulationPath -and $script:lastSample.Healthy -and -not $script:firstValidSensorSeen) {
            $script:firstValidSensorSeen = $true
            Write-GuardEvent 'StartupTelemetryReady' @{ElapsedSeconds=[math]::Round($script:clock.Elapsed.TotalSeconds,2)}
        }
        $decisionTemperature=Get-VerifiedCpuMaximum -Primary $script:lastSample -CpuSummary $script:lastCpuSummary
        $decision=Get-GuardDecision -Temperature $decisionTemperature -SensorHealthy $script:lastSample.Healthy -PreviousState $script:state -WarningC $config.WarningC -ResumeBelowC $config.ResumeBelowC -ShutdownC $config.ShutdownC
        if (-not $SimulationPath -and $decision.Intent -eq 'ReduceLoad' -and $config.EnableAppClose -and @($config.AllowList).Count -gt 0 -and (Test-LiveApproval)) {
            $candidates=@(Get-GuardCandidates)
        }
        $script:state=$decision.State; $script:lastDecision=$decision; $script:count++
        if ($previousState -ne $script:state -or $script:count -eq 1) { Write-GuardEvent 'StateChanged' @{From=$previousState;To=$script:state;TemperatureC=$script:lastSample.TemperatureC;Error=$script:lastSample.Error} }
        # Suppress the initial *popup only* while AIDA is starting. The fault
        # state, CPU --C display, status and live-action veto remain unchanged.
        $notice = Get-GuardNoticePolicy -State $script:state -VerifiedOnce ($script:firstValidSensorSeen -or [bool]$SimulationPath) -UptimeSeconds $script:clock.Elapsed.TotalSeconds
        if ($notice.StartupPending -and -not $script:startupPendingLogged) {
            $script:startupPendingLogged = $true
            Write-GuardEvent 'StartupAwaitingAida' @{Reason=[string]$script:lastSample.Error}
        }
        if ($notice.Notify) { Show-GuardNotice $(if ($script:state -eq 'SensorFault') {'Нет достоверных данных CPU. Защитные действия заблокированы.'} else {"Температура CPU $($script:lastSample.TemperatureC) °C. Режим: $($config.Mode)."}) }
        Invoke-GuardIntent -Decision $decision -Candidates $candidates
        Update-GuardDisplay -Sample $script:lastSample -Decision $decision -CpuSummary $script:lastCpuSummary
        Write-GuardStatus -IsRunning $true -State $script:state -Sample $script:lastSample
        if ($script:count % 30 -eq 0) { Write-GuardEvent 'Sample' $script:lastSample }
        if ($MaxSamples -gt 0 -and $script:count -ge $MaxSamples) { break }
    }
    Write-GuardEvent 'Stopped' @{Samples=$script:count}
} catch {
    [IO.File]::AppendAllText((Join-Path $DataDirectory 'fatal.log'), ([datetime]::UtcNow.ToString('o')+' '+$_.ToString()+[Environment]::NewLine+$_.ScriptStackTrace+[Environment]::NewLine))
    try { Write-GuardEvent 'FatalError' @{Message=$_.Exception.Message;Stack=$_.ScriptStackTrace} } catch {}
    if ($null -ne $script:tray) { $script:tray.ShowBalloonTip(10000,'uTempGuard: остановлен',$_.Exception.Message,[Windows.Forms.ToolTipIcon]::Error) }
    throw
} finally {
    if ($ownsMutex) {
        if ($running) { try { Write-GuardStatus -IsRunning $false -State 'Stopped' -Sample $script:lastSample } catch {} }
        if ($null -ne $script:tray) { $script:tray.Visible=$false; $script:tray.Dispose() }
        if ($null -ne $script:form) { $script:form.Dispose() }
        $mutex.ReleaseMutex()
    }
    if ($null -ne $instanceLock) { $instanceLock.Dispose() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
