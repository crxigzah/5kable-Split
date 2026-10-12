# Builds dist\5kableSplit.exe, a portable zip and the installer.
# Downloads AutoHotkey v2 and Ahk2Exe into .\tools the first time, and installs
# Inno Setup with winget (or Chocolatey) if it isn't already installed.
# Works in Windows PowerShell 5.1 and PowerShell 7.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root  = $PSScriptRoot
$Tools = Join-Path $Root 'tools'
$Dist  = Join-Path $Root 'dist'
$Src   = Join-Path $Root 'src\5kableSplit.ahk'
New-Item -ItemType Directory -Force -Path $Tools, $Dist | Out-Null

$Version = [regex]::Match((Get-Content $Src -Raw), 'AppVersion := "([^"]+)"').Groups[1].Value
if (-not $Version) { throw 'Could not read AppVersion from src\5kableSplit.ahk' }
Write-Host "Building 5kable Split $Version" -ForegroundColor Cyan

# GitHub API headers; a token (set automatically in GitHub Actions) avoids rate limits
$GhHeaders = @{ 'User-Agent' = '5kable-Split-build' }
if ($env:GITHUB_TOKEN) { $GhHeaders['Authorization'] = "Bearer $env:GITHUB_TOKEN" }

function Get-Zip($Url, $Dest) {
    $zip = Join-Path $Tools 'download.zip'
    Invoke-WebRequest $Url -OutFile $zip -UseBasicParsing
    Expand-Archive $zip $Dest -Force
    Remove-Item $zip
}

function Find-File($Dir, $Name) {
    if (-not (Test-Path $Dir)) { return $null }
    Get-ChildItem $Dir -Recurse -Filter $Name -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
}

# 1. AutoHotkey v2 runtime (used as the base of the compiled exe)
$AhkDir = Join-Path $Tools 'ahk'
$AhkBase = Find-File $AhkDir 'AutoHotkey64.exe'
if (-not $AhkBase) {
    # From GitHub rather than autohotkey.com, which puts a Cloudflare bot
    # check in front of downloads from CI machines
    Write-Host 'Downloading AutoHotkey v2...'
    $rels = Invoke-RestMethod 'https://api.github.com/repos/AutoHotkey/AutoHotkey/releases?per_page=30' -Headers $GhHeaders
    $asset = $rels | Where-Object { -not $_.prerelease } | ForEach-Object { $_.assets } |
        Where-Object { $_.name -match '^AutoHotkey.*v?2\.\d.*\.zip$' } | Select-Object -First 1
    if (-not $asset) { throw 'No AutoHotkey v2 zip found on GitHub releases' }
    Get-Zip $asset.browser_download_url $AhkDir
    $AhkBase = Find-File $AhkDir 'AutoHotkey64.exe'
    if (-not $AhkBase) { throw 'AutoHotkey64.exe not found in the AutoHotkey download' }
}

# 2. Ahk2Exe compiler
$A2EDir = Join-Path $Tools 'Ahk2Exe'
$Ahk2Exe = Find-File $A2EDir 'Ahk2Exe.exe'
if (-not $Ahk2Exe) {
    Write-Host 'Downloading Ahk2Exe...'
    $rel = Invoke-RestMethod 'https://api.github.com/repos/AutoHotkey/Ahk2Exe/releases/latest' -Headers $GhHeaders
    $asset = $rel.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
    if (-not $asset) { throw 'No Ahk2Exe zip found on the latest GitHub release' }
    Get-Zip $asset.browser_download_url $A2EDir
    $Ahk2Exe = Find-File $A2EDir 'Ahk2Exe.exe'
    if (-not $Ahk2Exe) { throw 'Ahk2Exe.exe not found in the download' }
}

# 3. Check the script for syntax / load-time errors (Ahk2Exe doesn't)
Write-Host 'Validating script...'
$errLog = Join-Path $Tools 'validate.log'
$v = Start-Process $AhkBase -Wait -PassThru -NoNewWindow -RedirectStandardError $errLog `
    -ArgumentList @('/ErrorStdOut', '/Validate', "`"$Src`"")
Write-Host "  exit code $($v.ExitCode)"
if ($v.ExitCode -ne 0) { throw "Script has errors:`n$(Get-Content $errLog -Raw)" }

# 4. Compile the exe (icon and version info come from the ;@Ahk2Exe lines in the script)
$Exe = Join-Path $Dist '5kableSplit.exe'
Remove-Item $Exe -ErrorAction SilentlyContinue
Write-Host 'Compiling 5kableSplit.exe...'
$p = Start-Process $Ahk2Exe -Wait -PassThru -ArgumentList @(
    '/in', "`"$Src`"", '/out', "`"$Exe`"", '/base', "`"$AhkBase`"", '/silent', 'verbose')
if ($p.ExitCode -ne 0 -or -not (Test-Path $Exe)) { throw "Ahk2Exe failed (exit code $($p.ExitCode))" }

# 5. Portable zip
$Portable = Join-Path $Dist "5kableSplit-$Version-portable.zip"
Remove-Item $Portable -ErrorAction SilentlyContinue
Compress-Archive -Path $Exe -DestinationPath $Portable

# 6. Installer
function Find-Iscc {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    $cmd = Get-Command iscc -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$Iscc = Find-Iscc
if (-not $Iscc) {
    Write-Host 'Inno Setup not found, installing it...'
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id JRSoftware.InnoSetup -e --silent --accept-source-agreements --accept-package-agreements | Out-Host
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        choco install innosetup -y --no-progress | Out-Host
    }
    $Iscc = Find-Iscc
}
if (-not $Iscc) {
    Write-Warning 'Inno Setup could not be installed, so only the exe and portable zip were built. Install it from https://jrsoftware.org/isdl.php and run this again.'
    exit 0
}

Write-Host 'Building installer...'
& $Iscc "/DAppVersion=$Version" /Qp (Join-Path $Root 'installer\5kableSplit.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed (exit code $LASTEXITCODE)" }

Write-Host ''
Write-Host 'Done:' -ForegroundColor Green
Get-ChildItem $Dist | ForEach-Object { Write-Host "  dist\$($_.Name)" }
