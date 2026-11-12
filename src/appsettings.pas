{ Настройки IPTV Aristocrat: плейлисты, источники телепрограмм, избранное,
  вид, плеер, запись. Хранятся в одном INI-файле; этот же формат
  используется для экспорта и импорта конфигурации. }
unit appsettings;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, contnrs, IniFiles;

const
  CONFIG_SIGNATURE = 'IPTV Aristocrat configuration';

type
  TPlaylistEntry = class
  public
    Name, Source, Epg: string;
    Kind: Integer;   { 0 — ТВ-каналы, 1 — медиатека (фильмы) }
    { удалённые пользователем каналы и категории этого плейлиста:
      c:<ссылка>, n:<название|категория>, g:<категория>.
      При обновлении плейлиста они не возвращаются; пропадают только
      вместе с самим плейлистом. }
    Hidden: TStringList;
    constructor Create;
    destructor Destroy; override;
  end;

  TAppSettings = class
  private
    FPlaylists: TFPObjectList;
    FFavorites: TStringList;
    FRecent: TStringList;
    FEpgSources: TStringList;
    FLocks: TStringList;
    procedure ReadAll(Ini: TCustomIniFile; WithWindow: Boolean);
    procedure WriteAll(Ini: TCustomIniFile; WithWindow: Boolean);
    procedure ReadList(Ini: TCustomIniFile; const Sec: string; L: TStrings);
    procedure WriteList(Ini: TCustomIniFile; const Sec: string; L: TStrings);
  public
    { общее }
    Volume: Integer;
    Muted: Boolean;
    LastPlaylist: Integer;
    LastMediaPlaylist: Integer;
    LastUrl: string;
    LastTab: Integer;
    LastMode: Integer;           { 0 — каналы, 1 — фильмы }
    { вид }
    ViewMode: Integer;           { 0 список, 1 компактный, 2 сетка, 3 плитка }
    ShowNumbers: Boolean;
    ShowLogos: Boolean;
    Accent: Integer;
    OpenMaximized: Boolean;
    SystemFrame: Boolean;
    AutoPlayLast: Boolean;
    { плеер }
    UseExternalPlayer: Boolean;
    ExternalPlayer: string;
    ExternalArgs: string;
    NetworkCaching: Integer;
    { запись }
    RecordDir: string;
    DownloadDir: string;         { папка для скачанных фильмов }
    DownloadQuality: Integer;    { 0 — 480p, 1 — 720p, 2 — 1080p, 3 — лучшее }
    CompatVideo: Boolean;        { совместимый видеовывод (виртуальные машины, старые видеокарты) }
    { телепрограмма }
    UsePlaylistEpg: Boolean;
    EpgPastDays: Integer;        { сколько дней прошедшей программы хранить (архив) }
    DefaultCatchup: Integer;     { тип архива, если в плейлисте не указан (индекс CATCHUP_NAMES) }
    LogoDbEnabled: Boolean;      { подбирать логотипы по названию из базы iptv-org }
    LogoProxy: Boolean;          { преобразовывать неподдерживаемые логотипы через images.weserv.nl }
    LogoTemplate: string;        // свой источник логотипов: ссылка с подстановкой name или id в фигурных скобках
    { родительский контроль: хэш PIN-кода (пусто — не задан) }
    ParentPin: string;
    { окно }
    SideWidth: Integer;
    InfoHeight: Integer;         { высота расписания под видео }
    WinLeft, WinTop, WinWidth, WinHeight: Integer;
    WinMaximized: Boolean;
    { пути }
    AppDir, ConfigDir, CacheDir: string;

    constructor Create;
    destructor Destroy; override;
    procedure Load;
    procedure Save;
    function ExportTo(const FileName: string; out ErrorMsg: string): Boolean;
    function ImportFrom(const FileName: string; out ErrorMsg: string): Boolean;

    function PlaylistCount: Integer;
    function Playlist(Index: Integer): TPlaylistEntry;
    function AddPlaylist(const AName, ASource, AEpg: string; AKind: Integer = 0): Integer;
    function CountOfKind(AKind: Integer): Integer;
    function FirstOfKind(AKind: Integer): Integer;
    procedure DeletePlaylist(Index: Integer);
    function IsFavorite(const Url: string): Boolean;
    procedure ToggleFavorite(const Url: string);
    procedure PushRecent(const Url: string);
    property Recent: TStringList read FRecent;
    property Favorites: TStringList read FFavorites;
    property EpgSources: TStringList read FEpgSources;
    { защищённые паролем каналы и категории (c:/n:/g: — как в Hidden) }
    property Locks: TStringList read FLocks;
    function PinHash(const Pin: string): string;
    function CheckPin(const Pin: string): Boolean;
  end;

function HashStr(const S: string): string;
function DefaultRecordDir: string;
function DefaultDownloadDir: string;
function DownloadMaxHeight(Quality: Integer): Integer;
{ Программа запущена в VirtualBox, VMware, QEMU и т. п. (только Linux; в Windows — False). }
function IsVirtualMachine: Boolean;

implementation

uses
  Forms, netload{$IFDEF WINDOWS}, Registry, Windows{$ENDIF};

constructor TPlaylistEntry.Create;
begin
  inherited Create;
  Hidden := TStringList.Create;
  Hidden.Sorted := True;
  Hidden.CaseSensitive := True;
  Hidden.Duplicates := dupIgnore;
end;

destructor TPlaylistEntry.Destroy;
begin
  Hidden.Free;
  inherited Destroy;
end;

function TAppSettings.PinHash(const Pin: string): string;
begin
  Result := HashStr('aristocrat-pin:' + Pin) + HashStr(Pin + ':parent');
end;

function TAppSettings.CheckPin(const Pin: string): Boolean;
begin
  Result := (ParentPin <> '') and (PinHash(Pin) = ParentPin);
end;

const
  MAX_RECENT = 40;

{$PUSH}{$R-}{$Q-}
function HashStr(const S: string): string;
var
  h: LongWord;
  i: Integer;
begin
  h := 2166136261;
  for i := 1 to Length(S) do
    h := LongWord((h xor Ord(S[i])) * 16777619);
  Result := IntToHex(h, 8);
end;
{$POP}

function DefaultRecordDir: string;
var
  Home: string;
begin
  Home := IncludeTrailingPathDelimiter(GetUserDir);
  if DirectoryExists(Home + 'Videos') then
    Result := Home + 'Videos' + PathDelim + 'IPTV Aristocrat'
  else if DirectoryExists(Home + 'Видео') then
    Result := Home + 'Видео' + PathDelim + 'IPTV Aristocrat'
  else if DirectoryExists(Home + 'My Documents' + PathDelim + 'My Videos') then
    Result := Home + 'My Documents' + PathDelim + 'My Videos' + PathDelim + 'IPTV Aristocrat'
  else
    Result := Home + 'IPTV Aristocrat Records';
end;

function DefaultDownloadDir: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFileDir(ExcludeTrailingPathDelimiter(DefaultRecordDir)));
  if Pos('IPTV Aristocrat Records', DefaultRecordDir) > 0 then
    Result := Result + 'IPTV Aristocrat Downloads'
  else
    Result := Result + 'IPTV Aristocrat Загрузки';
end;

function DownloadMaxHeight(Quality: Integer): Integer;
begin
  case Quality of
    0: Result := 480;
    2: Result := 1080;
    3: Result := 0;
  else
    Result := 720;
  end;
end;

function IsVirtualMachine: Boolean;
{$IFDEF LINUX}
var
  L: TStringList;
  S: string;
{$ENDIF}
{$IFDEF WINDOWS}
const
  VM_DRIVERS: array[0..6] of string = ('VBoxGuest.sys', 'VBoxMouse.sys', 'VBoxVideo.sys',
    'VBoxWddm.sys', 'vmmouse.sys', 'vmhgfs.sys', 'vm3dmp.sys');
var
  D, S: string;
  i: Integer;
  R: TRegistry;
{$ENDIF}
begin
  Result := False;
{$IFDEF WINDOWS}
  { в Windows 7–11 видео работает обычным способом — совместимый режим сам
    включается только на Windows XP / Vista в виртуальной машине }
  if Win32MajorVersion >= 6 then Exit;
  { драйверы VirtualBox / VMware }
  D := IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('SystemRoot')) + 'System32\drivers\';
  for i := 0 to High(VM_DRIVERS) do
    if FileExists(D + VM_DRIVERS[i]) then Exit(True);
  { название «компьютера» в BIOS (Windows Vista и новее) }
  R := TRegistry.Create(KEY_READ);
  try
    try
      R.RootKey := HKEY_LOCAL_MACHINE;
      if R.OpenKeyReadOnly('HARDWARE\DESCRIPTION\System\BIOS') then
      begin
        S := LowerCase(R.ReadString('SystemProductName') + ' ' + R.ReadString('SystemManufacturer'));
        Result := (Pos('virtualbox', S) > 0) or (Pos('vmware', S) > 0) or (Pos('qemu', S) > 0) or
          (Pos('virtual machine', S) > 0) or (Pos('innotek', S) > 0);
      end;
    except
      Result := False;
    end;
  finally
    R.Free;
  end;
{$ENDIF}
{$IFDEF LINUX}
  if not FileExists('/sys/class/dmi/id/product_name') then Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile('/sys/class/dmi/id/product_name');
      S := LowerCase(L.Text);
      Result := (Pos('virtualbox', S) > 0) or (Pos('vmware', S) > 0) or (Pos('qemu', S) > 0) or
        (Pos('kvm', S) > 0) or (Pos('virtual machine', S) > 0) or (Pos('bochs', S) > 0);
    except
      Result := False;
    end;
  finally
    L.Free;
  end;
{$ENDIF}
end;

constructor TAppSettings.Create;
begin
  inherited Create;
  FPlaylists := TFPObjectList.Create(True);
  FFavorites := TStringList.Create;
  FFavorites.Sorted := True;
  FFavorites.Duplicates := dupIgnore;
  FFavorites.CaseSensitive := True;
  FRecent := TStringList.Create;
  FEpgSources := TStringList.Create;
  FLocks := TStringList.Create;
  FLocks.Sorted := True;
  FLocks.CaseSensitive := True;
  FLocks.Duplicates := dupIgnore;

  AppDir := ExtractFilePath(Application.ExeName);
  { Переносной режим: файл portable.txt рядом с программой }
  if FileExists(AppDir + 'portable.txt') then
    ConfigDir := AppDir + 'data' + PathDelim
  else
    ConfigDir := IncludeTrailingPathDelimiter(GetAppConfigDir(False));
  CacheDir := ConfigDir + 'cache' + PathDelim;
  ForceDirectories(CacheDir);

  Volume := 80;
  LastTab := 1;
  ViewMode := 0;
  ShowNumbers := True;
  ShowLogos := True;
  OpenMaximized := True;
  AutoPlayLast := True;
  NetworkCaching := 1000;
  RecordDir := DefaultRecordDir;
  DownloadDir := DefaultDownloadDir;
  DownloadQuality := 1;
  CompatVideo := IsVirtualMachine;
  UsePlaylistEpg := True;
  EpgPastDays := 7;
  DefaultCatchup := 0;
  LogoDbEnabled := True;
  LogoProxy := True;
  SideWidth := 360;
  InfoHeight := 80;
  WinWidth := 1180;
  WinHeight := 720;
  WinLeft := -1;
  WinTop := -1;
end;

destructor TAppSettings.Destroy;
begin
  FEpgSources.Free;
  FLocks.Free;
  FRecent.Free;
  FFavorites.Free;
  FPlaylists.Free;
  inherited Destroy;
end;

procedure TAppSettings.ReadList(Ini: TCustomIniFile; const Sec: string; L: TStrings);
var
  i, n: Integer;
  S: string;
begin
  L.Clear;
  n := Ini.ReadInteger(Sec, 'Count', 0);
  for i := 1 to n do
  begin
    S := Ini.ReadString(Sec, 'Item' + IntToStr(i), '');
    if S <> '' then L.Add(S);
  end;
end;

procedure TAppSettings.WriteList(Ini: TCustomIniFile; const Sec: string; L: TStrings);
var
  i: Integer;
begin
  Ini.EraseSection(Sec);
  Ini.WriteInteger(Sec, 'Count', L.Count);
  for i := 0 to L.Count - 1 do
    Ini.WriteString(Sec, 'Item' + IntToStr(i + 1), L[i]);
end;

procedure TAppSettings.ReadAll(Ini: TCustomIniFile; WithWindow: Boolean);
var
  i, n: Integer;
  Sec: string;
begin
  Volume := Ini.ReadInteger('General', 'Volume', Volume);
  Muted := Ini.ReadBool('General', 'Muted', Muted);
  LastPlaylist := Ini.ReadInteger('General', 'LastPlaylist', 0);
  LastMediaPlaylist := Ini.ReadInteger('General', 'LastMediaPlaylist', -1);
  LastUrl := Ini.ReadString('General', 'LastUrl', '');
  LastTab := Ini.ReadInteger('General', 'LastTab', LastTab);
  LastMode := Ini.ReadInteger('General', 'LastMode', LastMode);

  ViewMode := Ini.ReadInteger('View', 'Mode', ViewMode);
  ShowNumbers := Ini.ReadBool('View', 'ShowNumbers', ShowNumbers);
  ShowLogos := Ini.ReadBool('View', 'ShowLogos', ShowLogos);
  Accent := Ini.ReadInteger('View', 'Accent', Accent);
  OpenMaximized := Ini.ReadBool('View', 'OpenMaximized', OpenMaximized);
  SystemFrame := Ini.ReadBool('View', 'SystemFrame', SystemFrame);
  AutoPlayLast := Ini.ReadBool('View', 'AutoPlayLast', AutoPlayLast);

  UseExternalPlayer := Ini.ReadBool('Player', 'UseExternal', UseExternalPlayer);
  ExternalPlayer := Ini.ReadString('Player', 'ExternalPath', ExternalPlayer);
  ExternalArgs := Ini.ReadString('Player', 'ExternalArgs', ExternalArgs);
  NetworkCaching := Ini.ReadInteger('Player', 'NetworkCaching', NetworkCaching);

  RecordDir := Ini.ReadString('Record', 'Folder', RecordDir);
  DownloadDir := Ini.ReadString('Record', 'DownloadFolder', DownloadDir);
  DownloadQuality := Ini.ReadInteger('Record', 'DownloadQuality', DownloadQuality);
  if (DownloadQuality < 0) or (DownloadQuality > 3) then DownloadQuality := 1;
  CompatVideo := Ini.ReadBool('Player', 'SafeVideo', CompatVideo);
  UsePlaylistEpg := Ini.ReadBool('Epg', 'UsePlaylistEpg', UsePlaylistEpg);
  EpgPastDays := Ini.ReadInteger('Epg', 'PastDays', EpgPastDays);
  DefaultCatchup := Ini.ReadInteger('Epg', 'DefaultCatchup', DefaultCatchup);
  LogoDbEnabled := Ini.ReadBool('Logos', 'UseDatabase', LogoDbEnabled);
  LogoProxy := Ini.ReadBool('Logos', 'UseProxy', LogoProxy);
  LogoTemplate := Ini.ReadString('Logos', 'Template', LogoTemplate);

  if WithWindow then
  begin
    SideWidth := Ini.ReadInteger('Window', 'SideWidth', SideWidth);
    InfoHeight := Ini.ReadInteger('Window', 'InfoHeight', InfoHeight);
    WinLeft := Ini.ReadInteger('Window', 'Left', WinLeft);
    WinTop := Ini.ReadInteger('Window', 'Top', WinTop);
    WinWidth := Ini.ReadInteger('Window', 'Width', WinWidth);
    WinHeight := Ini.ReadInteger('Window', 'Height', WinHeight);
    WinMaximized := Ini.ReadBool('Window', 'Maximized', WinMaximized);
  end;

  FPlaylists.Clear;
  n := Ini.ReadInteger('Playlists', 'Count', 0);
  for i := 1 to n do
  begin
    Sec := 'Playlist' + IntToStr(i);
    AddPlaylist(Ini.ReadString(Sec, 'Name', 'Плейлист ' + IntToStr(i)),
                Ini.ReadString(Sec, 'Source', ''),
                Ini.ReadString(Sec, 'Epg', ''),
                Ini.ReadInteger(Sec, 'Kind', 0));
    ReadList(Ini, Sec + 'Hidden', Playlist(FPlaylists.Count - 1).Hidden);
  end;
  ParentPin := Ini.ReadString('Parental', 'Pin', '');
  ReadList(Ini, 'ParentalLocks', FLocks);
  ReadList(Ini, 'EpgSources', FEpgSources);
  { Windows XP: сохранённые ссылки https:// переводим на http:// }
  if HttpsUnsupported then
  begin
    for i := 0 to FPlaylists.Count - 1 do
    begin
      Playlist(i).Source := FixUrlForSystem(Playlist(i).Source);
      Playlist(i).Epg := FixUrlForSystem(Playlist(i).Epg);
    end;
    for i := 0 to FEpgSources.Count - 1 do
      FEpgSources[i] := FixUrlForSystem(FEpgSources[i]);
  end;
  ReadList(Ini, 'Favorites', FFavorites);
  ReadList(Ini, 'Recent', FRecent);

  if Volume < 0 then Volume := 0;
  if Volume > 100 then Volume := 100;
  if (ViewMode < 0) or (ViewMode > 3) then ViewMode := 0;
  if (LastTab < 0) or (LastTab > 2) then LastTab := 1;
  if NetworkCaching = 1500 then NetworkCaching := 1000;   { старое значение по умолчанию }
  if NetworkCaching < 100 then NetworkCaching := 100;
  if NetworkCaching > 60000 then NetworkCaching := 60000;
  if RecordDir = '' then RecordDir := DefaultRecordDir;
  if DownloadDir = '' then DownloadDir := DefaultDownloadDir;
  if EpgPastDays < 0 then EpgPastDays := 0;
  if EpgPastDays > 14 then EpgPastDays := 14;
  if (DefaultCatchup < 0) or (DefaultCatchup > 4) then DefaultCatchup := 0;
end;

procedure TAppSettings.WriteAll(Ini: TCustomIniFile; WithWindow: Boolean);
var
  i: Integer;
  Sec: string;
begin
  Ini.WriteString('About', 'Format', CONFIG_SIGNATURE);
  Ini.WriteInteger('About', 'Version', 1);

  Ini.WriteInteger('General', 'Volume', Volume);
  Ini.WriteBool('General', 'Muted', Muted);
  Ini.WriteInteger('General', 'LastPlaylist', LastPlaylist);
  Ini.WriteInteger('General', 'LastMediaPlaylist', LastMediaPlaylist);
  Ini.WriteString('General', 'LastUrl', LastUrl);
  Ini.WriteInteger('General', 'LastTab', LastTab);
  Ini.WriteInteger('General', 'LastMode', LastMode);

  Ini.WriteInteger('View', 'Mode', ViewMode);
  Ini.WriteBool('View', 'ShowNumbers', ShowNumbers);
  Ini.WriteBool('View', 'ShowLogos', ShowLogos);
  Ini.WriteInteger('View', 'Accent', Accent);
  Ini.WriteBool('View', 'OpenMaximized', OpenMaximized);
  Ini.WriteBool('View', 'SystemFrame', SystemFrame);
  Ini.WriteBool('View', 'AutoPlayLast', AutoPlayLast);

  Ini.WriteBool('Player', 'UseExternal', UseExternalPlayer);
  Ini.WriteString('Player', 'ExternalPath', ExternalPlayer);
  Ini.WriteString('Player', 'ExternalArgs', ExternalArgs);
  Ini.WriteInteger('Player', 'NetworkCaching', NetworkCaching);

  Ini.WriteString('Record', 'Folder', RecordDir);
  Ini.WriteString('Record', 'DownloadFolder', DownloadDir);
  Ini.WriteInteger('Record', 'DownloadQuality', DownloadQuality);
  Ini.WriteBool('Player', 'SafeVideo', CompatVideo);
  Ini.WriteBool('Epg', 'UsePlaylistEpg', UsePlaylistEpg);
  Ini.WriteInteger('Epg', 'PastDays', EpgPastDays);
  Ini.WriteInteger('Epg', 'DefaultCatchup', DefaultCatchup);
  Ini.WriteBool('Logos', 'UseDatabase', LogoDbEnabled);
  Ini.WriteBool('Logos', 'UseProxy', LogoProxy);
  Ini.WriteString('Logos', 'Template', LogoTemplate);

  if WithWindow then
  begin
    Ini.WriteInteger('Window', 'SideWidth', SideWidth);
    Ini.WriteInteger('Window', 'InfoHeight', InfoHeight);
    Ini.WriteInteger('Window', 'Left', WinLeft);
    Ini.WriteInteger('Window', 'Top', WinTop);
    Ini.WriteInteger('Window', 'Width', WinWidth);
    Ini.WriteInteger('Window', 'Height', WinHeight);
    Ini.WriteBool('Window', 'Maximized', WinMaximized);
  end;

  i := 1;
  while Ini.SectionExists('Playlist' + IntToStr(i)) or Ini.SectionExists('Playlist' + IntToStr(i) + 'Hidden') do
  begin
    Ini.EraseSection('Playlist' + IntToStr(i));
    Ini.EraseSection('Playlist' + IntToStr(i) + 'Hidden');
    Inc(i);
  end;
  Ini.WriteInteger('Playlists', 'Count', FPlaylists.Count);
  for i := 0 to FPlaylists.Count - 1 do
  begin
    Sec := 'Playlist' + IntToStr(i + 1);
    Ini.WriteString(Sec, 'Name', Playlist(i).Name);
    Ini.WriteString(Sec, 'Source', Playlist(i).Source);
    Ini.WriteString(Sec, 'Epg', Playlist(i).Epg);
    Ini.WriteInteger(Sec, 'Kind', Playlist(i).Kind);
    if Playlist(i).Hidden.Count > 0 then
      WriteList(Ini, Sec + 'Hidden', Playlist(i).Hidden);
  end;
  Ini.WriteString('Parental', 'Pin', ParentPin);
  WriteList(Ini, 'ParentalLocks', FLocks);
  WriteList(Ini, 'EpgSources', FEpgSources);
  WriteList(Ini, 'Favorites', FFavorites);
  WriteList(Ini, 'Recent', FRecent);
end;

procedure TAppSettings.Load;
var
  Ini: TIniFile;
begin
  if not FileExists(ConfigDir + 'aristocrat.ini') then Exit;
  try
    Ini := TIniFile.Create(ConfigDir + 'aristocrat.ini');
    try
      ReadAll(Ini, True);
    finally
      Ini.Free;
    end;
  except
    { повреждённый файл настроек — работаем с настройками по умолчанию }
  end;
end;

procedure TAppSettings.Save;
var
  Ini: TIniFile;
begin
  try
    ForceDirectories(ConfigDir);
    Ini := TIniFile.Create(ConfigDir + 'aristocrat.ini');
    try
      Ini.CacheUpdates := True;
      WriteAll(Ini, True);
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
  except
    { не удалось сохранить — не критично }
  end;
end;

function TAppSettings.ExportTo(const FileName: string; out ErrorMsg: string): Boolean;
var
  Ini: TIniFile;
begin
  Result := False;
  ErrorMsg := '';
  try
    if FileExists(FileName) then SysUtils.DeleteFile(FileName);
    Ini := TIniFile.Create(FileName);
    try
      Ini.CacheUpdates := True;
      WriteAll(Ini, False);
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
    Result := True;
  except
    on E: Exception do ErrorMsg := E.Message;
  end;
end;

function TAppSettings.ImportFrom(const FileName: string; out ErrorMsg: string): Boolean;
var
  Ini: TIniFile;
begin
  Result := False;
  ErrorMsg := '';
  try
    Ini := TIniFile.Create(FileName);
    try
      if Ini.ReadString('About', 'Format', '') <> CONFIG_SIGNATURE then
      begin
        ErrorMsg := 'это не файл конфигурации IPTV Aristocrat';
        Exit;
      end;
      ReadAll(Ini, False);
    finally
      Ini.Free;
    end;
    Save;
    Result := True;
  except
    on E: Exception do ErrorMsg := E.Message;
  end;
end;

function TAppSettings.PlaylistCount: Integer;
begin
  Result := FPlaylists.Count;
end;

function TAppSettings.Playlist(Index: Integer): TPlaylistEntry;
begin
  Result := TPlaylistEntry(FPlaylists[Index]);
end;

function TAppSettings.AddPlaylist(const AName, ASource, AEpg: string; AKind: Integer): Integer;
var
  E: TPlaylistEntry;
begin
  E := TPlaylistEntry.Create;
  E.Name := AName;
  E.Source := ASource;
  E.Epg := AEpg;
  E.Kind := AKind;
  Result := FPlaylists.Add(E);
end;

function TAppSettings.CountOfKind(AKind: Integer): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to FPlaylists.Count - 1 do
    if Playlist(i).Kind = AKind then Inc(Result);
end;

function TAppSettings.FirstOfKind(AKind: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to FPlaylists.Count - 1 do
    if Playlist(i).Kind = AKind then Exit(i);
  Result := -1;
end;

procedure TAppSettings.DeletePlaylist(Index: Integer);
begin
  if (Index >= 0) and (Index < FPlaylists.Count) then
    FPlaylists.Delete(Index);
end;

function TAppSettings.IsFavorite(const Url: string): Boolean;
var
  i: Integer;
begin
  Result := FFavorites.Find(Url, i);
end;

procedure TAppSettings.ToggleFavorite(const Url: string);
var
  i: Integer;
begin
  if Url = '' then Exit;
  if FFavorites.Find(Url, i) then
    FFavorites.Delete(i)
  else
    FFavorites.Add(Url);
end;

procedure TAppSettings.PushRecent(const Url: string);
var
  i: Integer;
begin
  if Url = '' then Exit;
  i := FRecent.IndexOf(Url);
  if i >= 0 then FRecent.Delete(i);
  FRecent.Insert(0, Url);
  while FRecent.Count > MAX_RECENT do
    FRecent.Delete(FRecent.Count - 1);
end;

end.
