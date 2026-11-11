; Установщик IPTV Aristocrat для Windows XP / Vista (Inno Setup 5.6 — последняя
; версия, установщики которой запускаются на XP).
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
DefaultDirName={pf}\IPTV Aristocrat
DefaultGroupName=IPTV
DisableProgramGroupPage=yes
UninstallDisplayName=IPTV Aristocrat
UninstallDisplayIcon={app}\IPTV.exe
OutputDir=..\..\out
OutputBaseFilename=IPTV-Aristocrat-{#AppVersion}-windows-xp-setup
SetupIconFile=..\..\src\iptvaristocrat.ico
Compression=lzma2/max
SolidCompression=yes
MinVersion=5.1

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "startmenuicon"; Description: "Добавить ярлык в меню «Пуск»"; GroupDescription: "Ярлыки:"
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Ярлыки:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{commonprograms}\IPTV"; Filename: "{app}\IPTV.exe"; Tasks: startmenuicon
Name: "{commondesktop}\IPTV"; Filename: "{app}\IPTV.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\IPTV.exe"; Description: "Запустить IPTV"; Flags: nowait postinstall skipifsilent
