#define MyAppName "Wasel"
#define MyAppVersion "0.8.0"
#define MyAppPublisher "Wasel"
#define MyAppExeName "wasel.exe"

[Setup]
AppId={{B1A9B0A1-6D12-4F9B-8F30-5B52A0F7E8D1}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Wasel
DefaultGroupName=Wasel
OutputDir=installer-output
OutputBaseFilename=Wasel-Setup-{#MyAppVersion}-x64
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest
WizardStyle=modern
Uninstallable=yes

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\Wasel"; Filename: "{app}\{#MyAppExeName}"
Name: "{commondesktop}\Wasel"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "إنشاء اختصار على سطح المكتب"; GroupDescription: "اختصارات إضافية:"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "تشغيل واصل"; Flags: nowait postinstall skipifsilent
