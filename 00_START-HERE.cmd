@echo off
setlocal
if not exist "%~dp0config.json" (
  echo Welcome to uTempGuard. Run first-time setup.
  call "%~dp0Install-uTempGuard.cmd"
) else (
  "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Control.ps1"
)
