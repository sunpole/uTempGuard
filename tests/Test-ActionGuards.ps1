param([string]$ReportPath)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $ReportPath){$ReportPath=Join-Path $root 'artifacts\action-guard-tests.json'}
Import-Module (Join-Path $root 'src\Guard.Core.psm1') -Force
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'uTempGuard.ps1'),[ref]$tokens,[ref]$parseErrors)
if($parseErrors){throw 'Runtime parser errors'}
foreach($name in @('Test-LiveApproval','Invoke-GuardIntent')) {
    $definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    if(-not $definition){throw "Missing runtime function $name"}
    # AST extraction has no file-bound PSScriptRoot; bind that path seam to the actual runtime folder.
    . ([scriptblock]::Create($definition.Extent.Text.Replace('$PSScriptRoot','$root')))
}
$config=[pscustomobject]@{Mode='Observe';EnableAppClose=$true;EnableShutdown=$true;SensorId='TCPUPKG';AidaPath='C:\fixture\aida64.exe';MaxAgeSeconds=10;WarningC=70;ResumeBelowC=69;ShutdownC=75;AllowList=@()}
$ConfigPath=Join-Path $root 'config.json'
$SimulationPath=$null
$script:context=@{}
$script:clock=[Diagnostics.Stopwatch]::StartNew()
$script:lastActions=@{}
$script:events=@()
$script:boundaryCalls=0
function Write-GuardEvent { param($Event,$Details) $script:events+=@{Event=$Event;Details=$Details} }
function Invoke-CimMethod { $script:boundaryCalls++; throw 'Forbidden real action boundary reached in test' }
function Get-Process { $script:boundaryCalls++; throw 'Forbidden process action boundary reached in test' }
$checks=0
if(Test-LiveApproval){throw 'Observe admitted execution'};$checks++
$config.Mode='Live'
if(Test-Path -LiteralPath (Join-Path $root 'live-approval.json')){throw 'Tests require the unapproved project: remove no file automatically; stop and inspect approval.'}
if(Test-LiveApproval){throw 'Missing approval admitted execution'};$checks++
$SimulationPath='synthetic-scenario'
if(Test-LiveApproval){throw 'Simulation admitted execution'};$checks++
Invoke-GuardIntent -Decision ([pscustomobject]@{Intent='Shutdown';State='Critical';Temperature=80}) -Candidates @()
if($script:boundaryCalls -ne 0){throw 'Simulation crossed action boundary'};$checks++
if($script:events[-1].Details.ExecutionAllowed){throw 'Simulation logged execution permission'};$checks++
# Test the independent fresh-sensor gate with an in-memory approval stub.
# No approval file is created, and all action boundaries above remain throwing doubles.
function Test-LiveApproval { return $true }
$SimulationPath=$null
function Read-AidaSensor { [pscustomobject]@{Healthy=$false;TemperatureC=$null;Error='stale fixture'} }
Invoke-GuardIntent -Decision ([pscustomobject]@{Intent='Shutdown';State='Critical';Temperature=80}) -Candidates @()
if($script:boundaryCalls -ne 0){throw 'Stale sensor allowed shutdown'};$checks++
Invoke-GuardIntent -Decision ([pscustomobject]@{Intent='ReduceLoad';State='Warning';Temperature=71}) -Candidates @()
if($script:boundaryCalls -ne 0){throw 'Stale sensor allowed application close'};$checks++
function Read-AidaSensor { [pscustomobject]@{Healthy=$true;TemperatureC=68;Error=''} }
Invoke-GuardIntent -Decision ([pscustomobject]@{Intent='Shutdown';State='Critical';Temperature=80}) -Candidates @()
if($script:boundaryCalls -ne 0){throw 'Cooled sensor allowed shutdown'};$checks++
$report=[ordered]@{Passed=$true;Assertions=$checks;RealActionBoundaryCalls=$script:boundaryCalls;ApprovalFileCreated=$false;CheckedUtc=[datetime]::UtcNow.ToString('o')}
[IO.File]::WriteAllText($ReportPath,($report|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
$report|ConvertTo-Json
