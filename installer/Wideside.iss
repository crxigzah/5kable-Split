; Inno Setup script for Wideside. build.ps1 runs this; it can also be
; opened directly in the Inno Setup Compiler once dist\Wideside.exe exists.

#ifndef AppVersion
  #define AppVersion "1.1.0"
#endif
#define AppName "Wideside"
#define AppExe "Wideside.exe"

[Setup]
AppId={{C2A7E5D1-8B3F-4E62-A9D4-7F1B6E0C3A92}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Wideside
AppPublisherURL=https://crxigzah.github.io/wideside/
AppSupportURL=https://crxigzah.github.io/wideside/
AppCopyright=Copyright 2026 Wideside
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Installs per-user without an admin prompt; the dialog lets you pick all users instead
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=Wideside-Setup-{#AppVersion}
SetupIconFile=..\src\app.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
WizardImageFile=..\assets\wizard.bmp,..\assets\wizard-2x.bmp
WizardSmallImageFile=..\assets\wizard-small.bmp,..\assets\wizard-small-2x.bmp
Compression=lzma2/max
SolidCompression=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
WelcomeLabel2=This will install [name/ver] on your computer.%n%nWideside splits a big monitor into zones, so windows snap side by side like a multi-monitor setup.%n%nClose other applications before continuing.

[Tasks]
Name: "startup"; Description: "Start Wideside when Windows starts"; GroupDescription: "Startup:"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\dist\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\docs\guide.html"; DestDir: "{app}"; DestName: "Wideside Guide.html"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{#AppName} Guide"; Filename: "{app}\Wideside Guide.html"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon
; Same name the app uses for its own "Start with Windows" toggle, so the two stay in sync
Name: "{userstartup}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: startup

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/f /im {#AppExe}"; Flags: runhidden; RunOnceId: "StopApp"

[UninstallDelete]
Type: files; Name: "{userstartup}\{#AppName}.lnk"

[Code]
// Close a running copy so upgrades can replace the exe
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/f /im {#AppExe}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := '';
end;
