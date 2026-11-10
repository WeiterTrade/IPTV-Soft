{ База логотипов каналов по названию.
  Источник — открытый проект iptv-org (https://github.com/iptv-org/api):
  channels.json (названия и альтернативные названия каналов) и logos.json
  (ссылки на логотипы). Файлы скачиваются в фоне раз в 7 дней и хранятся в
  кэше, поэтому база работает и без интернета. }
unit logodb;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  IPTVORG_CHANNELS = 'https://iptv-org.github.io/api/channels.json';
  IPTVORG_LOGOS = 'https://iptv-org.github.io/api/logos.json';

type
  TLogoDb = class
  private
    FMap: TStringList;   { нормализованное название (Objects = индекс в FUrls) }
    FUrls: TStringList;
  public
    procedure AddName(const AName, Url: string);
    constructor Create;
    destructor Destroy; override;
    function Find(const Name1, Name2: string): string;
    function Count: Integer;
  end;

  TLogoDbLoader = class(TThread)
  protected
    procedure Execute; override;
  public
    CacheDir: string;
    Db: TLogoDb;          { результат (передаётся основному потоку) }
    ErrorMsg: string;
    constructor Create(const ACacheDir: string);
    destructor Destroy; override;
  end;

{ Нормализация названия для сравнения: «Первый канал HD (+4)» -> «первыйканал» }
function LogoKey(const S: string): string;

implementation

uses
  fpjson, jsonparser, LazUTF8, netload, applog;

function LogoKey(const S: string): string;
var
  L, W: string;
  i, p: Integer;
  Words: TStringList;
begin
  L := UTF8LowerCase(Trim(S));
  { убираем то, что в скобках: (+4), (HD), (Москва) }
  p := Pos('(', L);
  while p > 0 do
  begin
    i := p;
    while (i <= Length(L)) and (L[i] <> ')') do Inc(i);
    Delete(L, p, i - p + 1);
    p := Pos('(', L);
  end;
  for i := 1 to Length(L) do
    if L[i] in ['-', '_', '.', ':', '|', '/', ',', '[', ']', '!', '''', '"', #9] then L[i] := ' ';
  Words := TStringList.Create;
  try
    Words.Delimiter := ' ';
    Words.StrictDelimiter := True;
    Words.DelimitedText := L;
    Result := '';
    for i := 0 to Words.Count - 1 do
    begin
      W := Words[i];
      if W = '' then Continue;
      { служебные слова о качестве и сдвиге времени }
      if (W = 'hd') or (W = 'fhd') or (W = 'uhd') or (W = 'sd') or (W = '4k') or (W = '8k') or
         (W = 'hevc') or (W = 'orig') or (W = 'original') or (W = 'tv') or (W = 'тв') or
         (W = 'channel') or (W = 'телеканал') or (W = 'backup') or (W = 'резерв') then
        Continue;
      if (W[1] = '+') or ((W[1] = '-') and (Length(W) > 1)) then Continue;
      Result := Result + W;
    end;
  finally
    Words.Free;
  end;
end;

{ TLogoDb }

constructor TLogoDb.Create;
begin
  inherited Create;
  FMap := TStringList.Create;
  FMap.Sorted := True;
  FMap.CaseSensitive := True;
  FMap.Duplicates := dupIgnore;
  FUrls := TStringList.Create;
end;

procedure TLogoDb.AddName(const AName, Url: string);
var
  K: string;
  i: Integer;
begin
  K := LogoKey(AName);
  if (K = '') or FMap.Find(K, i) then Exit;
  FMap.AddObject(K, TObject(PtrInt(FUrls.Add(Url))));
end;

destructor TLogoDb.Destroy;
begin
  FUrls.Free;
  FMap.Free;
  inherited Destroy;
end;

function TLogoDb.Count: Integer;
begin
  Result := FMap.Count;
end;

function TLogoDb.Find(const Name1, Name2: string): string;
var
  i: Integer;
  K: string;
begin
  Result := '';
  K := LogoKey(Name1);
  if (K <> '') and FMap.Find(K, i) then Exit(FUrls[PtrInt(FMap.Objects[i])]);
  K := LogoKey(Name2);
  if (K <> '') and FMap.Find(K, i) then Exit(FUrls[PtrInt(FMap.Objects[i])]);
end;

{ TLogoDbLoader }

constructor TLogoDbLoader.Create(const ACacheDir: string);
begin
  CacheDir := IncludeTrailingPathDelimiter(ACacheDir);
  FreeOnTerminate := True;
  inherited Create(True);
end;

destructor TLogoDbLoader.Destroy;
begin
  Db.Free;
  inherited Destroy;
end;

function FreshOrDownload(const Url, FileName: string; MaxAgeDays: Double): Boolean;
var
  Age: LongInt;
  Err: string;
begin
  if FileExists(FileName) then
  begin
    Age := FileAge(FileName);
    if (Age <> -1) and (Now - FileDateToDateTime(Age) < MaxAgeDays) then Exit(True);
  end;
  if FetchToFile(Url, FileName + '.part', Err) then
  begin
    if FileExists(FileName) then DeleteFile(FileName);
    RenameFile(FileName + '.part', FileName);
  end
  else
  begin
    if FileExists(FileName + '.part') then DeleteFile(FileName + '.part');
    Log('база логотипов: не удалось скачать ' + Url + ': ' + Err);
  end;
  Result := FileExists(FileName);   { без интернета — старая копия }
end;

function LoadJsonFile(const FileName: string): TJSONData;
var
  F: TFileStream;
begin
  Result := nil;
  if not FileExists(FileName) then Exit;
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    Result := GetJSON(F);
  finally
    F.Free;
  end;
end;

function GoodFormat(const Fmt, Url: string): Boolean;
var
  F, U: string;
begin
  F := LowerCase(Fmt);
  U := LowerCase(Url);
  if F <> '' then
    Result := (F = 'png') or (F = 'jpeg') or (F = 'jpg') or (F = 'gif')
  else
    Result := (Pos('.svg', U) = 0) and (Pos('.webp', U) = 0);
end;

procedure TLogoDbLoader.Execute;
const
  PREFERRED = ' ru kz by ua uz kg am az ge md ';
var
  ChFile, LgFile, Url, Id, Country: string;
  Channels, Logos: TJSONData;
  Arr, Alt: TJSONArray;
  O: TJSONObject;
  IdLogo: TStringList;   { id канала (Objects = индекс в IdUrls) }
  IdUrls: TStringList;
  Pass, i, j, k: Integer;
  D: TJSONData;
begin
  MaskFloatExceptions;
  Channels := nil;
  Logos := nil;
  IdLogo := TStringList.Create;
  IdUrls := TStringList.Create;
  try
    try
      ChFile := CacheDir + 'iptvorg_channels.json';
      LgFile := CacheDir + 'iptvorg_logos.json';
      if not FreshOrDownload(IPTVORG_CHANNELS, ChFile, 7) then
      begin
        ErrorMsg := 'база логотипов недоступна';
        Exit;
      end;
      FreshOrDownload(IPTVORG_LOGOS, LgFile, 7);

      IdLogo.Sorted := True;
      IdLogo.CaseSensitive := False;
      IdLogo.Duplicates := dupIgnore;

      { logos.json: channel, feed, url, format, width }
      try
        Logos := LoadJsonFile(LgFile);
      except
        Logos := nil;
      end;
      if (Logos <> nil) and (Logos.JSONType = jtArray) then
      begin
        Arr := TJSONArray(Logos);
        { первыми — логотипы без привязки к отдельной версии канала (feed) }
        for Pass := 0 to 1 do
          for i := 0 to Arr.Count - 1 do
          begin
            if Terminated then Exit;
            if Arr.Items[i].JSONType <> jtObject then Continue;
            O := Arr.Objects[i];
            Id := O.Get('channel', '');
            Url := O.Get('url', '');
            if (Id = '') or (Url = '') then Continue;
            if (Pass = 0) and (O.Get('feed', '') <> '') then Continue;
            if not GoodFormat(O.Get('format', ''), Url) then Continue;
            if not IdLogo.Find(Id, k) then
              IdLogo.AddObject(Id, TObject(PtrInt(IdUrls.Add(Url))));
          end;
      end;
      FreeAndNil(Logos);

      Channels := LoadJsonFile(ChFile);
      if (Channels = nil) or (Channels.JSONType <> jtArray) then
      begin
        ErrorMsg := 'неверный формат базы каналов';
        Exit;
      end;
      Arr := TJSONArray(Channels);
      Db := TLogoDb.Create;
      { сначала каналы стран СНГ — при совпадении названий они в приоритете }
      for Pass := 0 to 1 do
        for i := 0 to Arr.Count - 1 do
        begin
          if Terminated then Exit;
          if Arr.Items[i].JSONType <> jtObject then Continue;
          O := Arr.Objects[i];
          Country := LowerCase(O.Get('country', ''));
          if (Pass = 0) <> (Pos(' ' + Country + ' ', PREFERRED) > 0) then Continue;
          if O.Get('closed', '') <> '' then Continue;
          Id := O.Get('id', '');
          Url := '';
          if (Id <> '') and IdLogo.Find(Id, k) then Url := IdUrls[PtrInt(IdLogo.Objects[k])];
          if Url = '' then
          begin
            Url := O.Get('logo', '');   { старый формат базы }
            if (Url <> '') and not GoodFormat('', Url) then Url := '';
          end;
          if Url = '' then Continue;
          Db.AddName(O.Get('name', ''), Url);
          D := O.Find('alt_names');
          if (D <> nil) and (D.JSONType = jtArray) then
          begin
            Alt := TJSONArray(D);
            for j := 0 to Alt.Count - 1 do
              if Alt.Items[j].JSONType = jtString then
                Db.AddName(Alt.Strings[j], Url);
          end;
        end;
      Log('база логотипов: ' + IntToStr(Db.Count) + ' названий');
    except
      on E: Exception do
      begin
        ErrorMsg := E.Message;
        FreeAndNil(Db);
      end;
    end;
  finally
    Channels.Free;
    Logos.Free;
    IdUrls.Free;
    IdLogo.Free;
  end;
end;

end.
