#ifndef AppVersion
  #error AppVersion must be supplied by build_windows.ps1
#endif
#ifndef AppFileVersion
  #error AppFileVersion must be supplied by build_windows.ps1
#endif
#ifndef BundleDir
  #error BundleDir must point at the complete Flutter Release bundle
#endif
#ifndef OutputDir
  #error OutputDir must be supplied by build_windows.ps1
#endif
#ifndef OutputName
  #error OutputName must be supplied by build_windows.ps1
#endif

[Setup]
; Keep this identity unchanged in all future installers for in-place upgrades.
AppId={{65BC24F2-FB4C-46DA-BF02-A868471E7F9F}
AppName=Ripot
AppVersion={#AppVersion}
AppVerName=Ripot {#AppVersion}
AppPublisher=Ripot
AppPublisherURL=https://ripot.app/
AppSupportURL=https://ripot.app/contact.html
AppUpdatesURL=https://ripot.app/#download
DefaultDirName={localappdata}\Programs\Ripot
DefaultGroupName=Ripot
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\ripot.exe
VersionInfoVersion={#AppFileVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
CloseApplicationsFilter=ripot.exe
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Ripot"; Filename: "{app}\ripot.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Ripot"; Filename: "{app}\ripot.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\ripot.exe"; Description: "Open Ripot"; Flags: nowait postinstall skipifsilent

; No UninstallDelete entries: user reports, registry and backups are outside
; {app} and must survive upgrades and uninstall/reinstall.
