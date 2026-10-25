Option Explicit
' Opens only the trusted local PowerShell dashboard launcher. No power actions.
Dim fso, sh, root, target, ps
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
root = fso.GetParentFolderName(WScript.ScriptFullName)
target = fso.BuildPath(root, "Open-uTempGuard.ps1")
If Not fso.FileExists(target) Then WScript.Quit 2
ps = sh.ExpandEnvironmentStrings("%WINDIR%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
sh.CurrentDirectory = root
sh.Run Chr(34) & ps & Chr(34) & " -NoProfile -ExecutionPolicy Bypass -File " & Chr(34) & target & Chr(34), 0, False
