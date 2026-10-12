<p align="center"><img src="assets/logo-256.png" width="128" alt="5kable"></p>

<h1 align="center">5kable Split</h1>
<p align="center">Window zones for big monitors. Split one screen into side-by-side areas, like Dell Easy Arrange.</p>
<p align="center"><a href="https://5kable.net/split"><b>Download from 5kable.net/split</b></a></p>

5kable Split was made for the MSI MAG C42CQR E2, but it works on any monitor. It reads the resolution, scaling and taskbar position from Windows.

## Building the installer

On a Windows PC, double-click **`build.cmd`**. The first build:

1. downloads AutoHotkey v2 and the Ahk2Exe compiler into `tools\` (portable, nothing gets installed)
2. compiles `dist\5kableSplit.exe` with the 5kable icon and version info
3. creates `dist\5kableSplit-<version>-portable.zip`
4. installs Inno Setup with winget if you don't have it (you may get one UAC prompt), then builds `dist\5kableSplit-Setup-<version>.exe`

When it's done, the `dist` folder opens. That setup exe is the file you hand out.

If you push this folder to a GitHub repo, `.github/workflows/build.yml` builds the same files in GitHub Actions. Push a tag like `v1.0.1` and it attaches them to a GitHub release. The download button on 5kable.net/split always points at the latest release.

## What the installer does

- Installs per-user to `%LocalAppData%\Programs\5kable Split`, with no admin prompt. The first screen has an option to install for all users instead.
- Adds a Start menu shortcut, plus optional tick boxes for "Start with Windows" and a desktop icon.
- Shows up in Apps & features with the 5kable icon and uninstalls cleanly.
- Running a newer setup over the top upgrades it in place. It closes the running copy first.

Settings are stored in `%AppData%\5kable Split\settings.ini`, so they survive upgrades.

## Using it

| Action | What it does |
|---|---|
| Hold **Shift** while dragging a window | Shows the zones. The one under the mouse lights up teal; let go to snap. |
| **Win+Alt+Left / Right** | Moves the active window to the previous / next zone |
| **Win+Alt+1 to 9** | Moves the active window to that zone number |
| **Win+Alt+Up** | Maximises across the whole monitor |
| **Win+Alt+L** | Next layout |
| **Win+Alt+Z** | Shows the zone numbers |

Click the tray icon to open **Settings**. In there you can pick a layout (with a live preview), choose the gap size, turn the Shift requirement on or off, and set it to start with Windows.

Built-in layouts: 50/50, 60/40, 40/60, three columns, 25/50/25, left half + right stacked, and four quarters. For your own layouts, go to Settings, click **Edit custom layouts**, then choose **Reload** from the tray menu.

## Releasing a new version

1. Change `AppVersion` and the `;@Ahk2Exe-SetVersion` line at the top of `src\5kableSplit.ahk`.
2. Commit, then tag and push: `git tag v1.0.1 && git push origin main v1.0.1`.
3. GitHub Actions builds the installer and publishes the release, and 5kable.net/split picks it up automatically.

## Project layout

```
src\5kableSplit.ahk        the app
src\app.ico, logo.png      icon and logo (built into the exe)
assets\                    installer artwork
installer\5kableSplit.iss  Inno Setup script
build.cmd / build.ps1      one-click build
```

## Limitations

- Windows still sees **one** monitor, same as Easy Arrange. Maximise, full-screen games and full-screen video use the whole panel.
- Apps running as admin (Task Manager, some installers) can't be moved unless 5kable Split also runs as admin.
- Some apps have a minimum width and won't shrink fully into a narrow zone.
- Unsigned exe: SmartScreen will show "Windows protected your PC" the first time someone runs the installer. Click **More info > Run anyway**. Getting rid of that warning needs a code-signing certificate.
