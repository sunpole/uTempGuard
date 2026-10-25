# Reproduces the PS5.1 updater failure: native Git writes benign progress on stderr.
# Uses a synthetic locally compiled executable; never touches network, main, or real Git.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path $PSScriptRoot -Parent
$folder=Join-Path $root ('artifacts\updater-stderr-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($folder)|Out-Null
$exe=Join-Path $folder 'git-stderr-fixture.exe'
$code=@'
using System;
public class GitStderrFixture {
    public static int Main(string[] args) {
        if (args.Length < 3 || args[0] != "-C") {
            Console.Error.WriteLine("fatal: unexpected arguments");
            return 2;
        }
        switch(args[2]) {
            case "fetch":
                Console.Error.WriteLine("From https://github.com/sunpole/uTempGuard");
                Console.WriteLine("FetchComplete");
                return 0;
            case "fail":
                Console.Error.WriteLine("fatal: simulated network failure");
                return 128;
            default:
                Console.WriteLine("OK");
                return 0;
        }
    }
}
'@
Add-Type -TypeDefinition $code -OutputAssembly $exe -OutputType ConsoleApplication
$tokens=$null;$errorsFound=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Update-uTempGuard.ps1'),[ref]$tokens,[ref]$errorsFound)
if($errorsFound){throw 'Updater parse failed'}
$functionAst=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-LocalGit'},$true)
if($null -eq $functionAst){throw 'Updater Git adapter not found'}
. ([scriptblock]::Create($functionAst.Extent.Text))
$script:git=$exe
$script:root=$folder
$success=@(Invoke-LocalGit -Arguments @('fetch'))
if($success -notcontains 'FetchComplete'){throw 'Successful Git command did not return stdout'}
if($success -notmatch 'From https://github.com/sunpole/uTempGuard'){throw 'Stderr did not reach diagnostic output'}
if($ErrorActionPreference -ne 'Stop'){throw 'Global error policy changed by Git wrapper'}
$failed=$false
try {
    $null=@(Invoke-LocalGit -Arguments @('fail'))
} catch {
    $failed=$true
    if($_.Exception.Message -notmatch 'exit 128' -or $_.Exception.Message -notmatch 'simulated network failure'){
        throw 'Git failure details were lost'
    }
}
if(-not $failed){throw 'Nonzero Git exit code was treated as success'}
if($ErrorActionPreference -ne 'Stop'){throw 'Global error policy was not restored'}
Write-Output 'PASS: benign native Git stderr ignored for success; real exit errors preserved; no network or local repo changes.'
