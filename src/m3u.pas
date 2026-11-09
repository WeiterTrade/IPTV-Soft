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
    Options: string;   { параметры VLC (#EXTVLCOPT), по одному на строку }
    Epg: TObject;      { TEpgChannel — проставляется после загрузки телепрограммы }
  end;

  TPlaylistData = class
  private
    FChannels: TFPObjectList;
    FGroups: TStringList;
  public
    EpgUrl: string;
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
end;

destructor TPlaylistData.Destroy;
begin
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

function ParseM3UFile(const FileName: string; Data: TPlaylistData; out ErrorMsg: string): Boolean;
var
  Raw, Line, Up, Tvg, PendingOpts: string;
  SL, GroupSet: TStringList;
  F: TFileStream;
  Cur: TChannel;
  i, p, Num: Integer;
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
        Tvg := GetAttr(Line, 'url-tvg');
        if Tvg = '' then Tvg := GetAttr(Line, 'x-tvg-url');
        if Tvg <> '' then
        begin
          p := Pos(',', Tvg);
          if p > 0 then Tvg := Copy(Tvg, 1, p - 1);
          Data.EpgUrl := Trim(Tvg);
        end;
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
