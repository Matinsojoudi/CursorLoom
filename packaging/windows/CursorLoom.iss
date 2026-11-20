#define MyAppName "CursorLoom Alpha"
#define MyAppVersion "0.4.0"
#define MyAppExeName "InputBridge.Windows.exe"

[Setup]
AppId={{BD40C5FC-060A-4F18-A68C-ED724D97A70F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=CursorLoom contributors
DefaultDirName={localappdata}\Programs\CursorLoomAlpha
DefaultGroupName={#MyAppName}
PrivilegesRequired=lowest
OutputDir=..\..\installer-output
OutputBaseFilename=CursorLoom-Windows-x64-Setup-alpha
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}

[Files]
Source: "..\..\publish-windows\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch CursorLoom Alpha"; Flags: nowait postinstall skipifsilent
