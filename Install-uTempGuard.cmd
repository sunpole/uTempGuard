@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-uTempGuard.ps1"
if errorlevel 1 (echo Setup failed. Check the message above.)
pause
