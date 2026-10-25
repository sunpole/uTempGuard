@echo off
setlocal
if not exist "%~dp0config.json" (
  echo Welcome to uTempGuard. Run first-time setup.
  call "%~dp0Install-uTempGuard.cmd"
) else (
  start "" "%SystemRoot%\System32\wscript.exe" "%~dp0Open-uTempGuard.vbs"
)
