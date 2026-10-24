; Morph's installer for GitHub releases: per-user by default (no admin prompt), with a Start menu entry,
; "Open in Morph" on the right-click menu for every file and folder, and a clean uninstall.
; scripts/package.ps1 builds it: iscc /DVersion=1.0.0 /DArch=x64 /DSource=<publish folder> installer\Morph.iss

#ifndef Version
  #define Version "1.0.0"
#endif
#ifndef Arch
  #define Arch "x64"
#endif
#ifndef Source
  #define Source "..\build\publish-" + Arch
#endif

[Setup]
AppId={{0465FD3B-C003-492C-A47B-64667DEAA975}
AppName=Morph
AppVersion={#Version}
AppVerName=Morph {#Version}
AppPublisher=Geetansh Goyal
AppPublisherURL=https://morph.geetanshgoyal.in
AppSupportURL=https://morph.geetanshgoyal.in/support.html
AppUpdatesURL=https://github.com/geetxnshgoyal/morph/releases
VersionInfoVersion={#Version}.0
VersionInfoProductName=Morph
VersionInfoProductVersion={#Version}.0
VersionInfoProductTextVersion={#Version}
VersionInfoDescription=Morph Setup
DefaultDirName={autopf}\Morph
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
#if Arch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
MinVersion=10.0.17763
OutputBaseFilename=Morph-{#Version}-{#Arch}-setup
SetupIconFile=..\src\Morph.App\Assets\Morph.ico
UninstallDisplayIcon={app}\Morph.exe
UninstallDisplayName=Morph
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Restart Manager closes a running Morph before files are replaced or removed.
CloseApplications=yes
ChangesAssociations=yes

[Files]
Source: "{#Source}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\Morph"; Filename: "{app}\Morph.exe"; Comment: "Convert, compress and clean up files"

[Registry]
; "Open in Morph" for every file and every folder. On Windows 11 it's under Show more options.
Root: HKA; Subkey: "Software\Classes\*\shell\Morph"; ValueType: string; ValueName: ""; ValueData: "Open in Morph"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\*\shell\Morph"; ValueType: string; ValueName: "Icon"; ValueData: """{app}\Morph.exe"",0"
Root: HKA; Subkey: "Software\Classes\*\shell\Morph"; ValueType: string; ValueName: "MultiSelectModel"; ValueData: "Player"
Root: HKA; Subkey: "Software\Classes\*\shell\Morph\command"; ValueType: string; ValueName: ""; ValueData: """{app}\Morph.exe"" ""%1"""
Root: HKA; Subkey: "Software\Classes\Directory\shell\Morph"; ValueType: string; ValueName: ""; ValueData: "Open in Morph"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Directory\shell\Morph"; ValueType: string; ValueName: "Icon"; ValueData: """{app}\Morph.exe"",0"
Root: HKA; Subkey: "Software\Classes\Directory\shell\Morph"; ValueType: string; ValueName: "MultiSelectModel"; ValueData: "Player"
Root: HKA; Subkey: "Software\Classes\Directory\shell\Morph\command"; ValueType: string; ValueName: ""; ValueData: """{app}\Morph.exe"" ""%1"""
; "Open at login" writes this from Settings; uninstalling removes it.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "Morph"; Flags: uninsdeletevalue dontcreatekey

[Run]
Filename: "{app}\Morph.exe"; Description: "Open Morph"; Flags: nowait postinstall skipifsilent
