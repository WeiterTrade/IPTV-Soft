; Установщик IPTV Aristocrat для Windows 7 и новее (Inno Setup 6).
; Внутри программа называется «IPTV Aristocrat», а ярлыки — просто «IPTV».
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\dist\IPTV"
#endif

[Setup]
AppId={{6C1E3E5A-9A3B-4F3E-9D2C-A15E0C7B4F21}
AppName=IPTV Aristocrat
AppVersion={#AppVersion}
AppVerName=IPTV Aristocrat {#AppVersion}
AppPublisher=Aristocrat TEAM
DefaultDirName={autopf}\IPTV Aristocrat
DefaultGroupName=IPTV
DisableProgramGroupPage=yes
UninstallDisplayName=IPTV Aristocrat
UninstallDisplayIcon={app}\IPTV.exe
OutputDir=..\..\out
OutputBaseFilename=IPTV-Aristocrat-{#AppVersion}-windows-setup
SetupIconFile=..\..\src\iptvaristocrat.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "startmenuicon"; Description: "Добавить ярлык в меню «Пуск»"; GroupDescription: "Ярлыки:"
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Ярлыки:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\IPTV"; Filename: "{app}\IPTV.exe"; Tasks: startmenuicon
Name: "{autodesktop}\IPTV"; Filename: "{app}\IPTV.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\IPTV.exe"; Description: "Запустить IPTV"; Flags: nowait postinstall skipifsilent
