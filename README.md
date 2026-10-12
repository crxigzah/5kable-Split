<p align="center"><img src="assets/logo-512.png" width="112" alt="Wideside"></p>

<h1 align="center">Wideside</h1>
<p align="center">One big monitor, perfectly split. Snap windows into side-by-side zones on ultrawide and large monitors, like Dell Easy Arrange.</p>
<p align="center"><a href="https://crxigzah.github.io/wideside/"><b>Website and download</b></a></p>

Wideside was made for the MSI MAG C42CQR E2, but it works on any monitor. It reads the resolution, scaling and taskbar position from Windows.

## Using it

| Action | What it does |
|---|---|
| Hold **Shift** while dragging a window | Shows the zones. The one under the mouse lights up orange; let go to snap. |
| **Win+Alt+Left / Right** | Moves the active window to the previous / next zone |
| **Win+Alt+1 to 9** | Moves the active window to that zone number |
| **Win+Alt+Up** | Maximises across the whole monitor |
| **Win+Alt+L** | Next layout |
| **Win+Alt+Z** | Shows the zone numbers |

Click the tray icon to open **Settings**. In there you can pick a layout (with a live preview), choose the gap size, turn the Shift requirement on or off, and set it to start with Windows.

Built-in layouts: 50/50, 60/40, 40/60, three columns, 25/50/25, left half + right stacked, and four quarters. For your own layouts, go to Settings, click **Edit custom layouts**, then choose **Reload** from the tray menu.

## Releases

Every push to `main` that touches the app builds it in GitHub Actions (`.github/workflows/build.yml`) on a Windows runner. The build checks the script for errors, compiles `Wideside.exe`, creates the installer and a portable zip, and publishes them as a GitHub release tagged with the app version. The website's download button always points at the latest release.

To ship a new version:

1. Change `AppVersion` and the `;@Ahk2Exe-SetVersion` line at the top of `src\Wideside.ahk`.
2. Commit and push to `main`.

## Building locally

On a Windows PC, double-click **`build.cmd`**. The first build:

1. downloads AutoHotkey v2 and the Ahk2Exe compiler into `tools\` (portable, nothing gets installed)
2. checks the script for errors, then compiles `dist\Wideside.exe`
3. creates `dist\Wideside-<version>-portable.zip`
4. installs Inno Setup with winget if you don't have it (you may get one UAC prompt), then builds `dist\Wideside-Setup-<version>.exe`

## What the installer does

- Installs per-user to `%LocalAppData%\Programs\Wideside`, with no admin prompt. The first screen has an option to install for all users instead.
- Adds a Start menu shortcut, plus optional tick boxes for "Start with Windows" and a desktop icon.
- Shows up in Apps & features and uninstalls cleanly.
- Running a newer setup over the top upgrades it in place. It closes the running copy first.

Settings are stored in `%AppData%\Wideside\settings.ini`, so they survive upgrades.

## Project layout

```
src\Wideside.ahk          the app
src\app.ico, logo.png     icon and logo (built into the exe)
assets\                   logo source (SVG) and installer artwork
installer\Wideside.iss    Inno Setup script
docs\                     the website (GitHub Pages)
build.cmd / build.ps1     one-click build
```

## Limitations

- Windows still sees **one** monitor, same as Easy Arrange. Maximise, full-screen games and full-screen video use the whole panel.
- Apps running as admin (Task Manager, some installers) can't be moved unless Wideside also runs as admin.
- Some apps have a minimum width and won't shrink fully into a narrow zone.
- The exe isn't code-signed, so SmartScreen shows "Windows protected your PC" the first time someone runs the installer. Click **More info > Run anyway**.
