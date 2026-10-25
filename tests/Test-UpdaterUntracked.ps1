# Regression test for Update-uTempGuard.ps1 using a completely synthetic git.exe.
# Does not touch actual origin, user checkout, sensors, config or shutdown actions.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path $PSScriptRoot -Parent
$folder=Join-Path $root ('artifacts\updater-untracked-test-'+[guid]::NewGuid().ToString('N'))
$bin=Join-Path $folder 'bin'
[IO.Directory]::CreateDirectory($bin)|Out-Null
$fake=Join-Path $bin 'git.exe'
$code=@'
using System;
using System.IO;
public class FakeGit {
 public static int Main(string[] args) {
  if(args.Length<3 || args[0]!="-C"){Console.Error.WriteLine("Unexpected git call");return 3;}
  string op=args[2];
  if(op=="rev-parse"){
   if(args.Length>3 && args[3]=="--show-toplevel"){Console.WriteLine(Environment.GetEnvironmentVariable("UTG_TEST_ROOT"));return 0;}
   Console.WriteLine(args[3]=="HEAD"?new string('a',40):Environment.GetEnvironmentVariable("UTG_TEST_UPSTREAM")== "changed"?new string('b',40):new string('a',40));
   return 0;
  }
  if(op=="branch"){Console.WriteLine("main");return 0;}
  if(op=="remote"){Console.WriteLine("https://github.com/sunpole/uTempGuard.git");return 0;}
  if(op=="status"){
   if(Environment.GetEnvironmentVariable("UTG_TEST_TRACKED")=="dirty"){Console.WriteLine(" M src/Guard.ModernMenu.ps1");}
   return 0;
  }
  if(op=="ls-files"){Console.WriteLine("docs/screenshots/Untracked.jpg");return 0;}
  if(op=="fetch"){Console.Error.WriteLine("From https://github.com/sunpole/uTempGuard");return 0;}
  if(op=="diff"){
   if(Environment.GetEnvironmentVariable("UTG_TEST_COLLISION")=="yes"){Console.WriteLine("docs/screenshots/Untracked.jpg");}
   return 0;
  }
  Console.Error.WriteLine("Unsupported mocked git operation: "+op);return 9;
 }
}
'@
Add-Type -TypeDefinition $code -OutputAssembly $fake -OutputType ConsoleApplication
$source=Join-Path $root 'Update-uTempGuard.ps1'
$copy=Join-Path $folder 'Update-uTempGuard.ps1'
Copy-Item -LiteralPath $source -Destination $copy
$beforePath=$env:PATH
$env:PATH=$bin+';'+$beforePath
$env:UTG_TEST_ROOT=$folder
$previousErrorActionPreference=$ErrorActionPreference
# PS5.1 treats expected stderr from intentionally failing child processes
# as NativeCommandError under Stop; capture it without aborting the test.
$ErrorActionPreference='Continue'
try{
  $env:UTG_TEST_TRACKED='clean'
  $env:UTG_TEST_UPSTREAM='same'
  $env:UTG_TEST_COLLISION='no'
  $output=@(& (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $copy -Action Preview 2>&1)
  if($LASTEXITCODE -ne 0 -or ($output -join [Environment]::NewLine) -notmatch 'Already up to date'){
    throw ('Untracked file blocked harmless update preview: '+($output -join ' | '))
  }
  $env:UTG_TEST_TRACKED='dirty'
  $output=@(& (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $copy -Action Preview 2>&1)
  if($LASTEXITCODE -eq 0 -or ($output -join [Environment]::NewLine) -notmatch 'Tracked modifications'){
    throw 'Tracked local modifications were not rejected'
  }
  $env:UTG_TEST_TRACKED='clean'
  $env:UTG_TEST_UPSTREAM='changed'
  $env:UTG_TEST_COLLISION='yes'
  $output=@(& (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $copy -Action Preview 2>&1)
  if($LASTEXITCODE -eq 0 -or ($output -join [Environment]::NewLine) -notmatch 'Untracked file conflict'){
    throw 'Incoming upstream filename collision was not rejected'
  }
  Write-Output 'PASS: untracked files preserved; modified tracked files and collisions safely block updater.'
}finally{
  $ErrorActionPreference=$previousErrorActionPreference
  $env:PATH=$beforePath
  foreach($key in @('UTG_TEST_ROOT','UTG_TEST_TRACKED','UTG_TEST_UPSTREAM','UTG_TEST_COLLISION')){
    Remove-Item ('Env:'+$key) -ErrorAction SilentlyContinue
  }
}
