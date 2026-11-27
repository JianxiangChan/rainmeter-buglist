; Buglist for Rainmeter —— 一键安装包
; 编译：ISCC.exe buglist.iss
; 依赖安装脚本生成的 staging\skin\ 和 rainmeter\Rainmeter-4.5.28.exe

[Setup]
AppId={{8C2F3E71-5B4A-4E2B-9F1C-7A6D5E4C3B21}
AppName=Buglist for Rainmeter
AppVersion=1.0.2
AppPublisher=JianxiangChan
DefaultDirName={autopf}\BuglistRainmeter
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=BuglistSetup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
UninstallDisplayName=Buglist for Rainmeter

[Languages]
Name: "zhcn"; MessagesFile: "ChineseSimplified.isl"

[Files]
; 皮肤文件装到 Rainmeter 的 SkinPath 下（读取 Rainmeter.ini，缺省用“文档\Rainmeter\Skins”）
Source: "staging\skin\*"; DestDir: "{code:GetSkinPath}\buglist"; Flags: ignoreversion recursesubdirs createallsubdirs
; 启动/激活脚本
Source: "start_buglist.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "start_buglist.vbs"; DestDir: "{app}"; Flags: ignoreversion
; 仅在目标机没有 Rainmeter 时用于静默安装
Source: "rainmeter\Rainmeter-4.5.28.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Tasks]
Name: "autostart"; Description: "开机自动启动 Rainmeter 并显示 Buglist"; GroupDescription: "附加任务:"

[Icons]
Name: "{autoprograms}\Buglist"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\start_buglist.vbs"""; IconFilename: "{code:GetRainmeterExe}"; Comment: "启动 Rainmeter 并显示 Buglist"
Name: "{userstartup}\Buglist"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\start_buglist.vbs"""; IconFilename: "{code:GetRainmeterExe}"; Comment: "开机启动 Rainmeter 并显示 Buglist"; Tasks: autostart

[Run]
; 1) 没有 Rainmeter 时静默安装（安装程序已提权）
Filename: "{tmp}\Rainmeter-4.5.28.exe"; Parameters: "/S"; StatusMsg: "正在安装 Rainmeter 4.5.28..."; Flags: waituntilterminated; Check: not IsRainmeterInstalled

; 2) 通过 explorer 以登录用户身份启动 Rainmeter（避免 Rainmeter 继承管理员权限）
Filename: "{sys}\explorer.exe"; Parameters: """{app}\start_buglist.vbs"""; Flags: nowait; Check: IsRainmeterInstalled

; 3) 首次安装时打开 config.json，让用户填写账号与 API Key
Filename: "{sys}\notepad.exe"; Parameters: """{code:GetSkinPath}\buglist\config.json"""; Description: "现在填写 config.json（Bugzilla 地址、账号、API Key）"; Flags: postinstall nowait skipifsilent runasoriginaluser; Check: IsConfigCreated

[UninstallDelete]
; 只清理运行时文件，保留用户填写好的 config.json
Type: files; Name: "{code:GetSkinPath}\buglist\cache.txt"
Type: files; Name: "{code:GetSkinPath}\buglist\state.json"
Type: files; Name: "{code:GetSkinPath}\buglist\ack.txt"
Type: dirifempty; Name: "{code:GetSkinPath}\buglist"

[Code]
var
  ConfigCreated: Boolean;

function IsConfigCreated(): Boolean;
begin
  Result := ConfigCreated;
end;

function GetSkinPath(Param: String): String;
var
  P: String;
begin
  P := GetIniString('Rainmeter', 'SkinPath', '',
                    ExpandConstant('{userappdata}\Rainmeter\Rainmeter.ini'));
  if P = '' then
    P := ExpandConstant('{userdocs}\Rainmeter\Skins\');
  Result := AddBackslash(P);
end;

function IsRainmeterInstalled(): Boolean;
var
  Path: String;
begin
  Result :=
    (RegQueryStringValue(HKLM,
       'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Rainmeter',
       'InstallLocation', Path) and (Path <> ''))
    or (RegQueryStringValue(HKLM,
       'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Rainmeter',
       'InstallLocation', Path) and (Path <> ''))
    or FileExists(ExpandConstant('{pf}\Rainmeter\Rainmeter.exe'))
    or FileExists(ExpandConstant('{pf32}\Rainmeter\Rainmeter.exe'));
end;

function GetRainmeterExe(Param: String): String;
var
  Path: String;
begin
  if RegQueryStringValue(HKLM,
       'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Rainmeter',
       'InstallLocation', Path) and (Path <> '') then
    Result := AddBackslash(Path) + 'Rainmeter.exe'
  else if RegQueryStringValue(HKLM,
       'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Rainmeter',
       'InstallLocation', Path) and (Path <> '') then
    Result := AddBackslash(Path) + 'Rainmeter.exe'
  else if FileExists(ExpandConstant('{pf}\Rainmeter\Rainmeter.exe')) then
    Result := ExpandConstant('{pf}\Rainmeter\Rainmeter.exe')
  else if FileExists(ExpandConstant('{pf32}\Rainmeter\Rainmeter.exe')) then
    Result := ExpandConstant('{pf32}\Rainmeter\Rainmeter.exe')
  else
    Result := ExpandConstant('{pf}\Rainmeter\Rainmeter.exe');  { 还没装时用默认路径 }
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  SkinDir, Cfg: String;
begin
  if CurStep = ssPostInstall then
  begin
    SkinDir := AddBackslash(GetSkinPath('')) + 'buglist';
    Cfg := SkinDir + '\config.json';
    if (not FileExists(Cfg)) and FileExists(SkinDir + '\config.example.json') then
    begin
      if CopyFile(SkinDir + '\config.example.json', Cfg, False) then
        ConfigCreated := True;
    end;
  end;
end;
