; Inno Setup script for the native Windows build of Ghostty.
;
; Build the release artifacts first:
;   zig build -Dtarget=x86_64-windows -Dapp-runtime=win32 --release=fast
;
; Then compile the installer (paths are passed as defines so the script has no
; hard-coded machine layout):
;   ISCC /DBuildDir="<repo>\zig-out" /DAppVersion="1.3.2" dist\windows\ghostty.iss
;
; The installed layout is {app}\bin\ghostty.exe with resources under
; {app}\share, which `resourcesDir()` discovers by walking up from the exe to
; share\terminfo\ghostty.terminfo. No environment variable is required.

#ifndef BuildDir
  #define BuildDir "..\..\zig-out"
#endif
#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif

#define AppName "Ghostty"
#define AppPublisher "Ghostty"
#define AppURL "https://ghostty.org"
#define AppExeName "ghostty.exe"

[Setup]
; A stable, Ghostty-specific upgrade GUID so upgrades replace in place.
AppId={{6E2B3F4A-7C1D-4B5E-9A8F-2D3C4B5A6E7F}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\bin\{#AppExeName}
UninstallDisplayName={#AppName}
OutputDir={#SourcePath}\output
OutputBaseFilename=ghostty-setup-x86_64
SetupIconFile={#SourcePath}\ghostty.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Per-user install by default so no UAC elevation is required; the user may
; elevate to install for all machines from the install dialog.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#BuildDir}\bin\{#AppExeName}"; DestDir: "{app}\bin"; Flags: ignoreversion
; Ship the runtime resources (terminfo, shell-integration, themes). The
; pkgconfig metadata is for building against libghostty and is not shipped.
Source: "{#BuildDir}\share\*"; DestDir: "{app}\share"; Excludes: "pkgconfig,pkgconfig\*"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\bin\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\bin\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\bin\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
