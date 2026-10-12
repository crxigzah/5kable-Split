# Third-party notices

Wideside's own code is released under the MIT License (see `LICENSE`).
The release binaries are built from this repository by GitHub Actions and
include or are produced with the following third-party software.

| Component | Used for | License | Source |
|---|---|---|---|
| [AutoHotkey v2](https://www.autohotkey.com) | Runtime embedded in `Wideside.exe` | GPL-2.0 | https://github.com/AutoHotkey/AutoHotkey |
| [Ahk2Exe](https://github.com/AutoHotkey/Ahk2Exe) | Compiles the script into `Wideside.exe` (build tool, not shipped) | WTFPL | https://github.com/AutoHotkey/Ahk2Exe |
| [Inno Setup](https://jrsoftware.org/isinfo.php) | Builds `Wideside-Setup-<version>.exe` | Inno Setup License | https://github.com/jrsoftware/issrc |

The installer, exe and portable zip are downloaded and built fresh by
`build.ps1` on every release; no third-party binaries are committed to this
repository.
