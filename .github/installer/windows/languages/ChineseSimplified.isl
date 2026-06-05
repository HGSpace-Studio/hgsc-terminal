; Simplified Chinese messages for the CsAC Windows installer.
; Keep this file small: messages not listed here fall back to Inno Setup's
; built-in English defaults, while app-specific copy lives in csac.iss.

[LangOptions]
LanguageName=中文（简体）
LanguageID=$0804
LanguageCodePage=65001
DialogFontName=Microsoft YaHei UI
DialogFontSize=9
WelcomeFontName=Microsoft YaHei UI
WelcomeFontSize=13

[Messages]
SetupAppTitle=安装程序
SetupWindowTitle=安装 - %1
UninstallAppTitle=卸载
UninstallAppFullTitle=%1 卸载

InformationTitle=信息
ConfirmTitle=确认
ErrorTitle=错误

SetupLdrStartupMessage=即将安装 %1。是否继续？
LdrCannotCreateTemp=无法创建临时文件。安装已中止。
LdrCannotExecTemp=无法执行临时目录中的文件。安装已中止。

SetupAlreadyRunning=安装程序已在运行。
WindowsVersionNotSupported=此程序不支持你当前运行的 Windows 版本。
OnlyOnTheseArchitectures=此程序只能安装到下列处理器架构对应的 Windows 版本：%n%n%1
AdminPrivilegesRequired=安装此程序需要管理员权限。
SetupAppRunningError=安装程序检测到 %1 正在运行。%n%n请关闭它的所有实例，然后点击“确定”继续，或点击“取消”退出。
UninstallAppRunningError=卸载程序检测到 %1 正在运行。%n%n请关闭它的所有实例，然后点击“确定”继续，或点击“取消”退出。

ExitSetupTitle=退出安装
ExitSetupMessage=安装尚未完成。如果现在退出，程序将不会被安装。%n%n你可以稍后重新运行安装程序完成安装。%n%n是否退出安装？
AboutSetupMenuItem=关于安装程序(&A)...
AboutSetupTitle=关于安装程序

ButtonBack=< 上一步(&B)
ButtonNext=下一步(&N) >
ButtonInstall=安装(&I)
ButtonOK=确定
ButtonCancel=取消
ButtonYes=是(&Y)
ButtonNo=否(&N)
ButtonFinish=完成(&F)
ButtonBrowse=浏览(&B)...
ButtonWizardBrowse=浏览(&B)...
ButtonNewFolder=新建文件夹(&M)

SelectLanguageTitle=选择安装语言
SelectLanguageLabel=请选择安装过程中使用的语言。

WelcomeLabel1=欢迎使用 [name] 安装向导
WelcomeLabel2=此向导将在你的电脑上安装 [name/ver]。%n%n建议继续前关闭其它应用程序。
SelectDirDesc=要将 [name] 安装到哪里？
SelectDirLabel3=安装程序会把 [name] 安装到下列文件夹。
SelectDirBrowseLabel=点击“下一步”继续。如需选择其它文件夹，请点击“浏览”。
ReadyLabel1=安装程序已准备好在你的电脑上安装 [name]。
ReadyLabel2a=点击“安装”继续；如需检查或更改设置，请点击“上一步”。
ReadyLabel2b=点击“安装”继续。
ReadyMemoDir=目标位置：
ReadyMemoGroup=开始菜单文件夹：
ReadyMemoTasks=附加任务：

InstallingLabel=请稍候，安装程序正在安装 [name]。
StatusClosingApplications=正在关闭应用程序...
StatusCreateDirs=正在创建目录...
StatusExtractFiles=正在解压文件...
StatusCreateIcons=正在创建快捷方式...
StatusCreateRegistryEntries=正在写入注册表...
StatusSavingUninstall=正在保存卸载信息...
StatusRunProgram=正在完成安装...
StatusRollback=正在回滚更改...

FinishedHeadingLabel=正在完成 [name] 安装向导
FinishedLabelNoIcons=安装程序已在你的电脑上安装 [name]。
FinishedLabel=安装程序已在你的电脑上安装 [name]。你可以通过已安装的快捷方式启动应用。

ErrorCreatingDir=安装程序无法创建目录 "%1"
ErrorCloseApplications=安装程序无法自动关闭所有应用。建议关闭正在使用待更新文件的应用后再继续。
ErrorFunctionFailedNoCode=%1 失败
ErrorFunctionFailed=%1 失败；错误代码 %2
ErrorExecutingProgram=无法执行文件：%n%1
