# Installing uTempGuard on Windows

[English README](../README_EN.md) · [Русский](INSTALL_RU.md) · [User guide](USER_GUIDE_EN.md)

## Requirements

Windows 10/11, Windows PowerShell 5.1 and WinForms. **AIDA64 must be installed and licensed separately**; it is not distributed with this project. Enable AIDA64 external sensor export to the registry (SensorValues) and check that package/core readings and STIME/SDATE are refreshed. You may need to configure AIDA64's own startup separately.

## Fresh installation from the release ZIP

1. Download the **attached** `uTempGuard-vX.Y.Z-win.zip` from [GitHub Releases](https://github.com/sunpole/uTempGuard/releases/latest). Do not confuse it with GitHub's automatically generated “Source code (zip)”.
2. Extract to a **permanent directory**, for example `C:\Tools\uTempGuard`. Never run directly from inside a ZIP.
3. Double-click `00_START-HERE.cmd` or `Install-uTempGuard.cmd`. The first-run script is `Setup-uTempGuard.ps1`.
4. Enter the absolute path to a **digitally signed FinalWire aida64.exe**. Setup verifies its location and publisher signature.
5. The wizard creates `config.json` **only in Observe mode**. This means no shutdown and no application closing.
6. Type **INSTALL** only if you approve a current-user Startup shortcut and starting the monitor immediately. Declining leaves the prepared Observe-only config, but performs no Startup changes.
7. Wait for valid AIDA64 sensor export, then right-click uTempGuard's system-tray icon.

No Python, Node.js or WebView2 installation is required.

## Existing installation

Never overwrite your working `config.json`, `live-approval.json` or `%LOCALAPPDATA%\uTempGuard`. The first-run wizard refuses to overwrite an existing config.

For a **real Git clone** with the trusted origin URL, use:

```powershell
.\Update-uTempGuard.ps1 -Action Preview
.\Update-uTempGuard.ps1 -Action Apply
.\Emergency-Control.ps1 -Action Status
```

You must type **UPDATE** to apply. Untracked files are preserved unless they would collide with an incoming tracked path; modified tracked files require manual review.

## Upgrading while keeping local settings

**ZIP (without Git):** stop the monitor, download the new ZIP, extract it into a **separate folder** (do not overwrite/delete the original one), and carefully copy your `config.json` only after review. Do not assume a saved emergency approval remains valid: it is tied to the exact config hash. The current-user Startup shortcut still points to the original folder until deliberately updated; avoid running two copies concurrently. Logs/preferences in `%LOCALAPPDATA%\uTempGuard` are kept separately.

**Git clone:** keep the project in place and use the built-in updater, which performs a safe fast-forward after confirmation. Do not move its root directory.

## Status and troubleshooting

```powershell
.\Manage.ps1 -Action Status
.\Emergency-Control.ps1 -Action Status
.\Manage.ps1 -Action Diagnose
```

Observe means monitor-only. Live does **not** alone mean emergency shutdown is approved: check `ForcedShutdownArmed` and `ShutdownSourceApproved` individually. If sensors are missing, check the AIDA64 process path, sensor-export settings and timestamps. At Windows sign-in, AIDA64 may become ready later than uTempGuard.

The package does **not** automatically enable emergency shutdown or alter BIOS/cooling. Do not heat hardware to test limits.

To stop or disable startup:

```powershell
.\Manage.ps1 -Action Stop
.\Manage.ps1 -Action DisableStartup
```

`Uninstall.ps1` does not delete source, configuration, logs or AIDA64. More details: [User guide](USER_GUIDE_EN.md).
