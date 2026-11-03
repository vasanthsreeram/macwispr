; Inno Setup 6 script. build.ps1 passes /DAppVersion=x.y.z.
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6E1F5C7A-6B1E-4C59-9A8E-2D6A5B0F7C11}
AppName=MacWispr
AppVersion={#AppVersion}
AppPublisher=Lint Labs
AppPublisherURL=https://fuckwisprflow.com
DefaultDirName={localappdata}\Programs\MacWispr
DefaultGroupName=MacWispr
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=out
OutputBaseFilename=MacWispr-{#AppVersion}-windows-x64-setup
SetupIconFile=assets\MacWispr.ico
UninstallDisplayIcon={app}\MacWispr.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Tasks]
Name: "startup"; Description: "Start MacWispr when I sign in"; Flags: unchecked

[Files]
Source: "dist\MacWispr\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\MacWispr"; Filename: "{app}\MacWispr.exe"
Name: "{userstartup}\MacWispr"; Filename: "{app}\MacWispr.exe"; Tasks: startup

[Run]
Filename: "{app}\MacWispr.exe"; Description: "Start MacWispr now"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "taskkill.exe"; Parameters: "/IM MacWispr.exe /F"; Flags: runhidden; RunOnceId: "KillMacWispr"
