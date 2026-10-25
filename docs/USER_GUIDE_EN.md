# uTempGuard — User guide

[English README](../README_EN.md) · [Installation](INSTALL_EN.md) · [Русский](USER_GUIDE_RU.md)

## Everyday operation

- `00_START-HERE.cmd` opens the first-run setup or the management menu.
- `Start-uTempGuard.cmd` starts an already configured monitor.
- `Управление.cmd` opens a console menu for start/stop/status/diagnostics/autostart.
- Right-click the **system-tray icon** to open the dark menu. A fixed back arrow in the header or Esc navigates to the parent page.
- `Open-Icon-Gallery.cmd` previews all 28 SVG images without heating hardware.

## Temperature sources

The **Display** selector decides which verified AIDA64 temperatures are shown in the indicator/tray icon. Modes include all available sensors, CPU cores, cores+CPU, cores+CPU+Package, and a custom multi-selection.

The independent **Shutdown** selector decides which sensors may be evaluated against the user-configured emergency threshold. Selecting a different shutdown source requires an independent explicit approval. It does not inherit the display selector's preferences.

**Appearance** controls the compact/full style, font, background, opacity, position, visibility and icon gallery. **Language** lets you select Russian or English and stores only a local preference in `%LOCALAPPDATA%\uTempGuard\language.json`.

If AIDA64 readings are stale or unverifiable, emergency actions are blocked rather than using an old temperature.

## Tray icons and safe preview

Original user-supplied CorelDRAW SVGs live under `assets/logo`: `utg_w_*` targets dark Windows taskbars, `utg_b_*` targets light ones. Each 10°C bucket has an icon (000–100). At 80°C or above, a static and warning frame can alternate every **0.4 seconds** while the PC is running.

Open `docs/icon-gallery.html` (or `Open-Icon-Gallery.cmd`) to compare both color themes, scale to a real 32px tray size, select simulated temperature or demonstrate blinking. None of these controls changes measured CPU temperature.

CorelDRAW CDR work files are personal editing sources. Do not upload, move or delete them automatically. Edited SVGs retain their original filenames so GitHub Actions can regenerate Windows tray frames.

## Protection status and safety

A **fresh installation is Observe only**. The user-configured warning/shutdown thresholds in the existing project are 70°C / 75°C, which are not universally safe thresholds for a CPU, GPU or drive.

Check:
```powershell
.\Emergency-Control.ps1 -Action Status
```

Live alone does not prove that shutdown is armed: check `ForcedShutdownArmed` and `ShutdownSourceApproved`. When the approved source is All, GPU and drive temperatures may contribute. An unexpected forced shutdown can lose unsaved work. Software cannot guarantee operation if Windows or AIDA64 crashes.

The CPU load warning can request graceful close only for explicitly approved applications. If `ApprovedAppCount=0`, no applications are included.

Do not artificially heat the computer for testing. Display and icon animations do not change emergency permissions.

## Files and updates

The local `config.json` and `live-approval.json` must remain private. Logs, status, UI preferences and extra approvals are in `%LOCALAPPDATA%\uTempGuard`. The original SVGs and generated frames are in separate `assets` folders.

If installed from a **Git clone**, use `Update-uTempGuard.ps1 -Action Preview` and then `-Action Apply` (requires typing `UPDATE`). If installed from ZIP, follow the **manual** procedure in [Installation](INSTALL_EN.md#upgrading-while-keeping-local-settings).

Troubleshooting: `Manage.ps1 -Action Diagnose`. Verify AIDA64 is running from the configured path and its registry export is current. Report issues via [GitHub Issues](https://github.com/sunpole/uTempGuard/issues) without sharing local configuration, private approval files or credentials.
