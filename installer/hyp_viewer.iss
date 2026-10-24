#define AppName "HYP Viewer"
#define AppExe "hyp_viewer.exe"
#ifndef MyAppVersion
  #define MyAppVersion "0.2.0"
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
SetupIconFile=..\windows\runner\resources\app_icon.ico
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExe}
CloseApplications=yes
RestartApplications=yes
UsePreviousAppDir=yes

[Files]
; Extracted into a temporary folder *before* any installed files are replaced.
Source: "..\scripts\windows_update_cleanup.ps1"; Flags: dontcopy
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\HYP Viewer"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\HYP Viewer"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "바탕화면 바로가기 만들기"; GroupDescription: "추가 작업:"

[Run]
Filename: "{app}\{#AppExe}"; Description: "HYP Viewer 실행"; Flags: nowait postinstall skipifsilent

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  PowerShell: String;
  Params: String;
  ExitCode: Integer;
begin
  Result := '';
  ExtractTemporaryFile('windows_update_cleanup.ps1');
  PowerShell := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    ExpandConstant('{tmp}\windows_update_cleanup.ps1') + '" ' +
    '-AppExecutable "' + ExpandConstant('{app}\hyp_viewer.exe') + '" ' +
    '-DpiExecutable "' + ExpandConstant('{app}\tools\goodbyedpi.exe') + '" ' +
    '-RuntimeRoot "' + ExpandConstant('{userappdata}\HYP Viewer\dpi_runtime') + '"';
  if not Exec(PowerShell, Params, '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then
  begin
    Result := 'Cannot start HYP Viewer update cleanup. Close HYP Viewer and retry.';
    Exit;
  end;
  if ExitCode <> 0 then
    Result := 'HYP Viewer or its DPI engine could not be stopped. ' +
      'Close HYP Viewer and its bundled DPI helper, then retry installation. ' +
      'Other GoodbyeDPI or WinDivert processes are never terminated.';
end;
