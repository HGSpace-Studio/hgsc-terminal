#define MyAppName "哈小信"
#define MyAppExeName "hgsc.exe"
#define MyAppPublisher "HGSpace Studio"
#define MyAppURL "https://github.com/HGSpace-Studio/hgsc-terminal"
#define MyAppSupportURL "https://github.com/HGSpace-Studio/hgsc-terminal/issues"
#ifndef MyAppVersion
#define MyAppVersion "1.0.0"
#endif

[Setup]
AppId={{8D0AA9D1-7B1F-4E12-BD6E-7A9C5F3B2E10}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppSupportURL}
AppCopyright=Copyright (C) {#MyAppPublisher}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Windows installer
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
DisableWelcomePage=yes
OutputDir={#OutputDir}
OutputBaseFilename=hgsc-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
WizardResizable=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "languages\ChineseSimplified.isl"

[Messages]
english.WelcomeLabel1=Install [name]
english.WelcomeLabel2=This wizard will install [name/ver] on your computer.
english.SelectDirDesc=Choose where [name] should be installed.
english.SelectDirLabel3=Setup will install [name] into the following folder.
english.ReadyLabel1=Setup is ready to install [name].
english.FinishedHeadingLabel=Installation complete
english.FinishedLabel=哈小信 has been installed. You can start it now or from the Start menu.
chinesesimplified.WelcomeLabel1=安装 [name]
chinesesimplified.WelcomeLabel2=此向导将把 [name/ver] 安装到你的电脑。
chinesesimplified.SelectDirDesc=选择 [name] 的安装位置。
chinesesimplified.SelectDirLabel3=安装程序会把 [name] 安装到下列文件夹。
chinesesimplified.ReadyLabel1=安装程序已准备好安装 [name]。
chinesesimplified.FinishedHeadingLabel=安装完成
chinesesimplified.FinishedLabel=哈小信 已安装完成。你可以立即启动，或稍后从开始菜单打开。

[CustomMessages]
english.AppSubtitle=A modern HGSC chat client for Windows.
english.CustomWelcomeTitle=哈小信 for Windows
english.CustomWelcomeBody=Install the desktop client, create shortcuts, and choose the launch behavior that fits this device.
english.InstallOptionsTitle=Installation options
english.InstallOptionsSubtitle=Choose shortcuts and first-run behavior.
english.DesktopShortcutOption=Create a desktop shortcut
english.StartMenuShortcutOption=Create Start menu shortcuts
english.LaunchAfterInstallOption=Launch 哈小信 after installation
english.OptionsHint=You can change application preferences inside 哈小信 after signing in.
english.ReadyTitle=Ready to install
english.InstallLocationLabel=Install location:
english.SelectedOptionsLabel=Selected options:
english.OptionDesktopShortcut=Desktop shortcut
english.OptionStartMenuShortcut=Start menu shortcuts
english.OptionLaunchAfterInstall=Launch after installation
english.OptionNone=None
english.UninstallShortcut=Uninstall 哈小信
english.LaunchProgram=Launch 哈小信

chinesesimplified.AppSubtitle=适用于 Windows 的现代 HGSC 聊天客户端。
chinesesimplified.CustomWelcomeTitle=哈小信 Windows 客户端
chinesesimplified.CustomWelcomeBody=安装桌面客户端，创建快捷方式，并选择适合这台设备的首次启动行为。
chinesesimplified.InstallOptionsTitle=安装选项
chinesesimplified.InstallOptionsSubtitle=选择快捷方式和安装后的行为。
chinesesimplified.DesktopShortcutOption=创建桌面快捷方式
chinesesimplified.StartMenuShortcutOption=创建开始菜单快捷方式
chinesesimplified.LaunchAfterInstallOption=安装完成后启动 哈小信
chinesesimplified.OptionsHint=登录后可在 哈小信 内继续调整应用偏好设置。
chinesesimplified.ReadyTitle=准备安装
chinesesimplified.InstallLocationLabel=安装位置：
chinesesimplified.SelectedOptionsLabel=已选择选项：
chinesesimplified.OptionDesktopShortcut=桌面快捷方式
chinesesimplified.OptionStartMenuShortcut=开始菜单快捷方式
chinesesimplified.OptionLaunchAfterInstall=安装后启动
chinesesimplified.OptionNone=无
chinesesimplified.UninstallShortcut=卸载 哈小信
chinesesimplified.LaunchProgram=启动 哈小信

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Check: ShouldCreateStartMenuShortcuts
Name: "{group}\{cm:UninstallShortcut}"; Filename: "{uninstallexe}"; Check: ShouldCreateStartMenuShortcuts
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Check: ShouldCreateDesktopShortcut

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram}"; Flags: nowait postinstall skipifsilent; Check: ShouldLaunchAfterInstall

[Code]
var
  IntroPage: TWizardPage;
  OptionsPage: TWizardPage;
  IntroTitleLabel: TLabel;
  IntroBodyLabel: TLabel;
  IntroMetaLabel: TLabel;
  OptionsTitleLabel: TLabel;
  OptionsSubtitleLabel: TLabel;
  DesktopShortcutCheck: TNewCheckBox;
  StartMenuShortcutCheck: TNewCheckBox;
  LaunchAfterInstallCheck: TNewCheckBox;
  OptionsHintLabel: TLabel;

function ShouldCreateDesktopShortcut: Boolean;
begin
  Result := Assigned(DesktopShortcutCheck) and DesktopShortcutCheck.Checked;
end;

function ShouldCreateStartMenuShortcuts: Boolean;
begin
  Result := Assigned(StartMenuShortcutCheck) and StartMenuShortcutCheck.Checked;
end;

function ShouldLaunchAfterInstall: Boolean;
begin
  Result := Assigned(LaunchAfterInstallCheck) and LaunchAfterInstallCheck.Checked;
end;

procedure StyleTitle(LabelControl: TLabel);
begin
  LabelControl.AutoSize := False;
  LabelControl.WordWrap := True;
  LabelControl.Font.Size := 18;
  LabelControl.Font.Style := [fsBold];
  LabelControl.Font.Color := $6B3F00;
end;

procedure StyleSubtitle(LabelControl: TLabel);
begin
  LabelControl.AutoSize := False;
  LabelControl.WordWrap := True;
  LabelControl.Font.Size := 10;
  LabelControl.Font.Color := $555555;
end;

procedure AddSeparator(Page: TWizardPage; Top: Integer);
var
  Separator: TPanel;
begin
  Separator := TPanel.Create(Page);
  Separator.Parent := Page.Surface;
  Separator.Left := 0;
  Separator.Top := ScaleY(Top);
  Separator.Width := Page.SurfaceWidth;
  Separator.Height := ScaleY(1);
  Separator.BevelOuter := bvNone;
  Separator.Color := $DDDDDD;
end;

procedure InitializeWizard;
begin
  WizardForm.Caption := '{#MyAppName} Setup';

  IntroPage := CreateCustomPage(
    wpWelcome,
    ExpandConstant('{cm:CustomWelcomeTitle}'),
    ExpandConstant('{cm:AppSubtitle}')
  );

  IntroTitleLabel := TLabel.Create(IntroPage);
  IntroTitleLabel.Parent := IntroPage.Surface;
  IntroTitleLabel.Left := 0;
  IntroTitleLabel.Top := ScaleY(10);
  IntroTitleLabel.Width := IntroPage.SurfaceWidth;
  IntroTitleLabel.Height := ScaleY(28);
  IntroTitleLabel.Caption := ExpandConstant('{cm:CustomWelcomeTitle}');
  StyleTitle(IntroTitleLabel);

  IntroBodyLabel := TLabel.Create(IntroPage);
  IntroBodyLabel.Parent := IntroPage.Surface;
  IntroBodyLabel.Left := 0;
  IntroBodyLabel.Top := ScaleY(52);
  IntroBodyLabel.Width := IntroPage.SurfaceWidth;
  IntroBodyLabel.Height := ScaleY(66);
  IntroBodyLabel.Caption := ExpandConstant('{cm:CustomWelcomeBody}');
  StyleSubtitle(IntroBodyLabel);

  AddSeparator(IntroPage, 132);

  IntroMetaLabel := TLabel.Create(IntroPage);
  IntroMetaLabel.Parent := IntroPage.Surface;
  IntroMetaLabel.Left := 0;
  IntroMetaLabel.Top := ScaleY(154);
  IntroMetaLabel.Width := IntroPage.SurfaceWidth;
  IntroMetaLabel.Height := ScaleY(70);
  IntroMetaLabel.Caption :=
    '{#MyAppName} ' + ExpandConstant('{#MyAppVersion}') + #13#10 +
    'Windows x64' + #13#10 +
    '{#MyAppURL}';
  StyleSubtitle(IntroMetaLabel);

  OptionsPage := CreateCustomPage(
    wpSelectDir,
    ExpandConstant('{cm:InstallOptionsTitle}'),
    ExpandConstant('{cm:InstallOptionsSubtitle}')
  );

  OptionsTitleLabel := TLabel.Create(OptionsPage);
  OptionsTitleLabel.Parent := OptionsPage.Surface;
  OptionsTitleLabel.Left := 0;
  OptionsTitleLabel.Top := ScaleY(6);
  OptionsTitleLabel.Width := OptionsPage.SurfaceWidth;
  OptionsTitleLabel.Height := ScaleY(28);
  OptionsTitleLabel.Caption := ExpandConstant('{cm:InstallOptionsTitle}');
  StyleTitle(OptionsTitleLabel);

  OptionsSubtitleLabel := TLabel.Create(OptionsPage);
  OptionsSubtitleLabel.Parent := OptionsPage.Surface;
  OptionsSubtitleLabel.Left := 0;
  OptionsSubtitleLabel.Top := ScaleY(42);
  OptionsSubtitleLabel.Width := OptionsPage.SurfaceWidth;
  OptionsSubtitleLabel.Height := ScaleY(34);
  OptionsSubtitleLabel.Caption := ExpandConstant('{cm:InstallOptionsSubtitle}');
  StyleSubtitle(OptionsSubtitleLabel);

  AddSeparator(OptionsPage, 86);

  DesktopShortcutCheck := TNewCheckBox.Create(OptionsPage);
  DesktopShortcutCheck.Parent := OptionsPage.Surface;
  DesktopShortcutCheck.Left := 0;
  DesktopShortcutCheck.Top := ScaleY(112);
  DesktopShortcutCheck.Width := OptionsPage.SurfaceWidth;
  DesktopShortcutCheck.Height := ScaleY(22);
  DesktopShortcutCheck.Caption := ExpandConstant('{cm:DesktopShortcutOption}');
  DesktopShortcutCheck.Checked := False;

  StartMenuShortcutCheck := TNewCheckBox.Create(OptionsPage);
  StartMenuShortcutCheck.Parent := OptionsPage.Surface;
  StartMenuShortcutCheck.Left := 0;
  StartMenuShortcutCheck.Top := ScaleY(144);
  StartMenuShortcutCheck.Width := OptionsPage.SurfaceWidth;
  StartMenuShortcutCheck.Height := ScaleY(22);
  StartMenuShortcutCheck.Caption := ExpandConstant('{cm:StartMenuShortcutOption}');
  StartMenuShortcutCheck.Checked := True;

  LaunchAfterInstallCheck := TNewCheckBox.Create(OptionsPage);
  LaunchAfterInstallCheck.Parent := OptionsPage.Surface;
  LaunchAfterInstallCheck.Left := 0;
  LaunchAfterInstallCheck.Top := ScaleY(176);
  LaunchAfterInstallCheck.Width := OptionsPage.SurfaceWidth;
  LaunchAfterInstallCheck.Height := ScaleY(22);
  LaunchAfterInstallCheck.Caption := ExpandConstant('{cm:LaunchAfterInstallOption}');
  LaunchAfterInstallCheck.Checked := True;

  OptionsHintLabel := TLabel.Create(OptionsPage);
  OptionsHintLabel.Parent := OptionsPage.Surface;
  OptionsHintLabel.Left := 0;
  OptionsHintLabel.Top := ScaleY(254);
  OptionsHintLabel.Width := OptionsPage.SurfaceWidth;
  OptionsHintLabel.Height := ScaleY(52);
  OptionsHintLabel.Caption := ExpandConstant('{cm:OptionsHint}');
  StyleSubtitle(OptionsHintLabel);

end;

function SelectedOptionsText: String;
begin
  Result := '';
  if ShouldCreateDesktopShortcut then
    Result := Result + '- ' + ExpandConstant('{cm:OptionDesktopShortcut}') + #13#10;
  if ShouldCreateStartMenuShortcuts then
    Result := Result + '- ' + ExpandConstant('{cm:OptionStartMenuShortcut}') + #13#10;
  if ShouldLaunchAfterInstall then
    Result := Result + '- ' + ExpandConstant('{cm:OptionLaunchAfterInstall}') + #13#10;
  if Result = '' then
    Result := '- ' + ExpandConstant('{cm:OptionNone}') + #13#10;
end;

function UpdateReadyMemo(
  Space: String;
  NewLine: String;
  MemoUserInfoInfo: String;
  MemoDirInfo: String;
  MemoTypeInfo: String;
  MemoComponentsInfo: String;
  MemoGroupInfo: String;
  MemoTasksInfo: String
): String;
begin
  Result :=
    ExpandConstant('{cm:InstallLocationLabel}') + NewLine +
    Space + ExpandConstant('{app}') + NewLine + NewLine +
    ExpandConstant('{cm:SelectedOptionsLabel}') + NewLine +
    SelectedOptionsText;
end;
