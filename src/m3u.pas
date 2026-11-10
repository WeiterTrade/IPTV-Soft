{ Разбор плейлистов M3U / M3U8 (расширенный формат IPTV). }
unit m3u;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, contnrs;

type
  TChannel = class
  public
    Number: Integer;
    Name: string;
    NameLower: string;
    URL: string;
    Group: string;
    TvgId: string;
    TvgName: string;
    Logo: string;
    LogoAlt: string;   { логотип по шаблону из настроек }
    LogoDb: string;    { логотип из базы по названию }
    IsVod: Boolean;    { фильм / сериал, а не телеканал }
    Hidden: Boolean;   { удалён пользователем из списка }
    Locked: Boolean;   { защищён паролем (родительский контроль) }
    Data: TObject;     { для локальных файлов: связанная загрузка (TDownloadItem) }
    Options: string;   { параметры VLC (#EXTVLCOPT), по одному на строку }
    CatchupType: string;    { архив: shift, append, default, flussonic, xc }
    CatchupSource: string;  { шаблон ссылки на архив }
    CatchupDays: Integer;   { глубина архива, дней }
    Epg: TObject;      { TEpgChannel — проставляется после загрузки телепрограммы }
  end;

  TPlaylistData = class
  private
    FChannels: TFPObjectList;
    FGroups: TStringList;
  public
    EpgUrl: string;          { первая ссылка на телепрограмму из плейлиста }
    EpgUrls: TStringList;    { все ссылки на телепрограмму из плейлиста }
    DefCatchupType, DefCatchupSource: string;
    DefCatchupDays: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure Add(Ch: TChannel);
    function Count: Integer;
    function Get(Index: Integer): TChannel;
    function FindByUrl(const AUrl: string): TChannel;
    property Groups: TStringList read FGroups;
  end;

function ParseM3UFile(const FileName: string; Data: TPlaylistData; out ErrorMsg: string): Boolean;
function IsValidUTF8(const S: string): Boolean;

implementation

uses
  StrUtils, LazUTF8, LConvEncoding;

{ TPlaylistData }

constructor TPlaylistData.Create;
begin
  inherited Create;
  FChannels := TFPObjectList.Create(True);
  FGroups := TStringList.Create;
  EpgUrls := TStringList.Create;
end;

destructor TPlaylistData.Destroy;
begin
  EpgUrls.Free;
  FGroups.Free;
  FChannels.Free;
  inherited Destroy;
end;

procedure TPlaylistData.Add(Ch: TChannel);
begin
  FChannels.Add(Ch);
end;

function TPlaylistData.Count: Integer;
begin
  Result := FChannels.Count;
end;

function TPlaylistData.Get(Index: Integer): TChannel;
begin
  Result := TChannel(FChannels[Index]);
end;

function TPlaylistData.FindByUrl(const AUrl: string): TChannel;
var
  i: Integer;
begin
  Result := nil;
  if AUrl = '' then Exit;
  for i := 0 to FChannels.Count - 1 do
    if TChannel(FChannels[i]).URL = AUrl then
      Exit(TChannel(FChannels[i]));
end;

{ Вспомогательные функции }

function IsValidUTF8(const S: string): Boolean;
var
  i, n, k: Integer;
  c: Byte;
begin
  Result := False;
  i := 1;
  n := Length(S);
  while i <= n do
  begin
    c := Ord(S[i]);
    if c < $80 then k := 0
    else if (c and $E0) = $C0 then k := 1
    else if (c and $F0) = $E0 then k := 2
    else if (c and $F8) = $F0 then k := 3
    else Exit;
    if i + k > n then Exit;
    Inc(i);
    while k > 0 do
    begin
      if (Ord(S[i]) and $C0) <> $80 then Exit;
      Inc(i);
      Dec(k);
    end;
  end;
  Result := True;
end;

{ Значение атрибута вида name="value" (регистр имени не важен). }
function GetAttr(const Line, AName: string): string;
var
  L, Key: string;
  p, q: Integer;
  Quote: Char;
begin
  Result := '';
  L := LowerCase(Line);
  Key := LowerCase(AName) + '=';
  p := Pos(Key, L);
  while p > 0 do
  begin
    if (p = 1) or (L[p - 1] in [' ', #9, ',', ':']) then Break;
    p := PosEx(Key, L, p + 1);
  end;
  if p = 0 then Exit;
  p := p + Length(Key);
  if p > Length(Line) then Exit;
  if Line[p] in ['"', ''''] then
  begin
    Quote := Line[p];
    Inc(p);
    q := PosEx(Quote, Line, p);
    if q = 0 then q := Length(Line) + 1;
  end
  else
  begin
    q := p;
    while (q <= Length(Line)) and not (Line[q] in [' ', #9, ',']) do Inc(q);
  end;
  Result := Trim(Copy(Line, p, q - p));
end;

{ Название канала — всё после первой запятой вне кавычек. }
function ExtinfTitle(const Line: string): string;
var
  i: Integer;
  InQ: Boolean;
begin
  Result := '';
  InQ := False;
  for i := 9 to Length(Line) do
  begin
    if Line[i] = '"' then
      InQ := not InQ
    else if (Line[i] = ',') and not InQ then
      Exit(Trim(Copy(Line, i + 1, MaxInt)));
  end;
end;

procedure AddEpgUrls(Data: TPlaylistData; const S: string);
var
  L: TStringList;
  i: Integer;
  U: string;
begin
  if Trim(S) = '' then Exit;
  L := TStringList.Create;
  try
    L.Delimiter := ',';
    L.StrictDelimiter := True;
    L.DelimitedText := S;
    for i := 0 to L.Count - 1 do
    begin
      U := Trim(L[i]);
      if (U <> '') and (Data.EpgUrls.IndexOf(U) < 0) then
        Data.EpgUrls.Add(U);
    end;
  finally
    L.Free;
  end;
end;

{ Глубина архива: catchup-days, tvg-rec или timeshift (в днях). }
function DaysAttr(const Line: string): Integer;
begin
  Result := StrToIntDef(GetAttr(Line, 'catchup-days'), 0);
  if Result <= 0 then Result := StrToIntDef(GetAttr(Line, 'tvg-rec'), 0);
  if Result <= 0 then Result := StrToIntDef(GetAttr(Line, 'timeshift'), 0);
  if Result > 60 then Result := 60;
end;

function ParseM3UFile(const FileName: string; Data: TPlaylistData; out ErrorMsg: string): Boolean;
var
  Raw, Line, Up, PendingOpts: string;
  SL, GroupSet: TStringList;
  F: TFileStream;
  Cur: TChannel;
  i, Num: Integer;
begin
  Result := False;
  ErrorMsg := '';
  Cur := nil;
  PendingOpts := '';
  Num := 0;

  try
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Raw, F.Size);
      if F.Size > 0 then
        F.ReadBuffer(Raw[1], F.Size);
    finally
      F.Free;
    end;
  except
    on E: Exception do
    begin
      ErrorMsg := E.Message;
      Exit;
    end;
  end;

  if Copy(Raw, 1, 3) = #$EF#$BB#$BF then
    Delete(Raw, 1, 3);
  if not IsValidUTF8(Raw) then
    Raw := ConvertEncoding(Raw, 'cp1251', 'utf8');   { старые русские плейлисты }

  SL := TStringList.Create;
  GroupSet := TStringList.Create;
  try
    GroupSet.Sorted := True;
    GroupSet.CaseSensitive := True;
    GroupSet.Duplicates := dupIgnore;
    SL.Text := Raw;
    Raw := '';

    for i := 0 to SL.Count - 1 do
    begin
      Line := Trim(SL[i]);
      if Line = '' then Continue;
      Up := UpperCase(Copy(Line, 1, 12));

      if Pos('#EXTM3U', Up) = 1 then
      begin
        { ссылки на телепрограмму: url-tvg, x-tvg-url, tvg-url — можно несколько через запятую }
        AddEpgUrls(Data, GetAttr(Line, 'url-tvg'));
        AddEpgUrls(Data, GetAttr(Line, 'x-tvg-url'));
        AddEpgUrls(Data, GetAttr(Line, 'tvg-url'));
        if Data.EpgUrls.Count > 0 then Data.EpgUrl := Data.EpgUrls[0];
        Data.DefCatchupType := LowerCase(GetAttr(Line, 'catchup'));
        if Data.DefCatchupType = '' then Data.DefCatchupType := LowerCase(GetAttr(Line, 'catchup-type'));
        Data.DefCatchupSource := GetAttr(Line, 'catchup-source');
        Data.DefCatchupDays := DaysAttr(Line);
      end
      else if Pos('#EXTINF', Up) = 1 then
      begin
        FreeAndNil(Cur);
        Cur := TChannel.Create;
        Cur.Name := ExtinfTitle(Line);
        Cur.TvgId := GetAttr(Line, 'tvg-id');
        Cur.TvgName := GetAttr(Line, 'tvg-name');
        Cur.Logo := GetAttr(Line, 'tvg-logo');
        Cur.Group := GetAttr(Line, 'group-title');
        Cur.CatchupType := LowerCase(GetAttr(Line, 'catchup'));
        if Cur.CatchupType = '' then Cur.CatchupType := LowerCase(GetAttr(Line, 'catchup-type'));
        Cur.CatchupSource := GetAttr(Line, 'catchup-source');
        Cur.CatchupDays := DaysAttr(Line);
        if Cur.Name = '' then Cur.Name := Cur.TvgName;
      end
      else if Pos('#EXTGRP:', Up) = 1 then
      begin
        if (Cur <> nil) and (Cur.Group = '') then
          Cur.Group := Trim(Copy(Line, 9, MaxInt));
      end
      else if Pos('#EXTVLCOPT:', Up) = 1 then
      begin
        if PendingOpts <> '' then PendingOpts := PendingOpts + LineEnding;
        PendingOpts := PendingOpts + Trim(Copy(Line, 12, MaxInt));
      end
      else if Line[1] = '#' then
        Continue
      else
      begin
        if Cur = nil then
        begin
          Cur := TChannel.Create;
          Cur.Name := Line;
        end;
        Inc(Num);
        Cur.URL := Line;
        Cur.Options := PendingOpts;
        PendingOpts := '';
        if Cur.Name = '' then Cur.Name := 'Канал ' + IntToStr(Num);
        Cur.Number := Num;
        Cur.NameLower := UTF8LowerCase(Cur.Name);
        if Cur.CatchupType = '' then Cur.CatchupType := Data.DefCatchupType;
        if Cur.CatchupSource = '' then Cur.CatchupSource := Data.DefCatchupSource;
        if Cur.CatchupDays <= 0 then Cur.CatchupDays := Data.DefCatchupDays;
        Data.Add(Cur);
        if (Cur.Group <> '') and (GroupSet.IndexOf(Cur.Group) < 0) then
        begin
          GroupSet.Add(Cur.Group);
          Data.Groups.Add(Cur.Group);
        end;
        Cur := nil;
      end;
    end;
  finally
    Cur.Free;
    GroupSet.Free;
    SL.Free;
  end;

  if Data.Count = 0 then
    ErrorMsg := 'в плейлисте не найдено ни одного канала'
  else
    Result := True;
end;

end.
