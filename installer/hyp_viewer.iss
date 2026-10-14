#define AppName "HYP Viewer"
#define AppExe "hyp_viewer.exe"
#ifndef MyAppVersion
  #define MyAppVersion "0.1.3"
#endif

[Setup]
AppId={{DFB10F70-784C-4E58-A660-4550D02AB9EA}
AppName={#AppName}
AppVersion={#MyAppVersion}
AppPublisher=HYP Viewer
DefaultDirName={localappdata}\Programs\HYP Viewer
DefaultGroupName=HYP Viewer
PrivilegesRequired=lowest
OutputDir=Output
OutputBaseFilename=HYP_Viewer_Setup_v{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExe}
CloseApplications=yes
RestartApplications=yes
UsePreviousAppDir=yes

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\HYP Viewer"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\HYP Viewer"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "바탕화면 바로가기 만들기"; GroupDescription: "추가 작업:"

[Run]
Filename: "{app}\{#AppExe}"; Description: "HYP Viewer 실행"; Flags: nowait postinstall skipifsilent
