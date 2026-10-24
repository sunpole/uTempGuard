Option Explicit
Dim fso, shell, projectPath, dataPath, runtimePath, configPath, powershellPath, command
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
projectPath = fso.GetParentFolderName(WScript.ScriptFullName)
runtimePath = fso.BuildPath(projectPath, "uTempGuard.ps1")
configPath = fso.BuildPath(projectPath, "config.json")
dataPath = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\uTempGuard"
If WScript.Arguments.Count > 0 Then dataPath = WScript.Arguments(0)
If Not fso.FileExists(runtimePath) Then WScript.Quit 2
If Not fso.FileExists(configPath) Then WScript.Quit 3
powershellPath = shell.ExpandEnvironmentStrings("%WINDIR%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
command = Q(powershellPath) & " -NoProfile -STA -ExecutionPolicy Bypass -File " & Q(runtimePath) & " -ConfigPath " & Q(configPath) & " -DataDirectory " & Q(dataPath)
shell.CurrentDirectory = projectPath
shell.Run command, 0, False
Function Q(value)
    Q = Chr(34) & value & Chr(34)
End Function
