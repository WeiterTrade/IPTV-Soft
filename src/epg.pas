{ Телепрограмма в формате XMLTV (обычный или сжатый .gz).
  Файл читается потоково, поэтому даже очень большие EPG не занимают
  много памяти: сохраняются только передачи в окне «-12 ч … +2 сут». }
unit epg;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, contnrs;

type
  TEpgItem = class
  public
    Start, Stop: TDateTime;   { UTC }
    Title, Desc: string;
  end;

  TEpgChannel = class
  public
    Id: string;
    Items: TFPObjectList;
    constructor Create;
    destructor Destroy; override;
    function Current(NowUtc: TDateTime): TEpgItem;
    function NextAfter(NowUtc: TDateTime): TEpgItem;
  end;

  TEpgData = class
  private
    FChannels: TStringList;   { id -> TEpgChannel (владеет объектами) }
    FNames: TStringList;      { нормализованное имя -> TEpgChannel }
    FProgCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function GetOrAdd(const Id: string): TEpgChannel;
    procedure AddName(const AName: string; Ch: TEpgChannel);
    procedure AddItem(const ChannelId: string; Item: TEpgItem);
    procedure SortAll;
    function FindChannel(const TvgId, TvgName, AName: string): TEpgChannel;
    property ProgrammeCount: Integer read FProgCount;
  end;

function LoadXmltvFile(const FileName: string; Data: TEpgData; out ErrorMsg: string): Boolean;
function NowUtc: TDateTime;
function UtcToLocal(T: TDateTime): TDateTime;
function NormalizeName(const S: string): string;

implementation

uses
  zstream, StrUtils, LazUTF8;

function NowUtc: TDateTime;
begin
  Result := Now + GetLocalTimeOffset / 1440;
end;

function UtcToLocal(T: TDateTime): TDateTime;
begin
  Result := T - GetLocalTimeOffset / 1440;
end;

function NormalizeName(const S: string): string;
var
  i: Integer;
  L: string;
begin
  L := UTF8LowerCase(Trim(S));
  Result := '';
  for i := 1 to Length(L) do
    if not (L[i] in [' ', '-', '_', '.', ':', '|', #9]) then
      Result := Result + L[i];
end;

function CompareItems(Item1, Item2: Pointer): Integer;
var
  A, B: TDateTime;
begin
  A := TEpgItem(Item1).Start;
  B := TEpgItem(Item2).Start;
  if A < B then Result := -1
  else if A > B then Result := 1
  else Result := 0;
end;

{ TEpgChannel }

constructor TEpgChannel.Create;
begin
  inherited Create;
  Items := TFPObjectList.Create(True);
end;

destructor TEpgChannel.Destroy;
begin
  Items.Free;
  inherited Destroy;
end;

function TEpgChannel.Current(NowUtc: TDateTime): TEpgItem;
var
  i: Integer;
  It: TEpgItem;
begin
  Result := nil;
  for i := 0 to Items.Count - 1 do
  begin
    It := TEpgItem(Items[i]);
    if It.Start > NowUtc then Exit;
    if NowUtc < It.Stop then Exit(It);
  end;
end;

function TEpgChannel.NextAfter(NowUtc: TDateTime): TEpgItem;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to Items.Count - 1 do
    if TEpgItem(Items[i]).Start > NowUtc then
      Exit(TEpgItem(Items[i]));
end;

{ TEpgData }

constructor TEpgData.Create;
begin
  inherited Create;
  FChannels := TStringList.Create;
  FChannels.Sorted := True;
  FChannels.CaseSensitive := False;
  FChannels.Duplicates := dupIgnore;
  FChannels.OwnsObjects := True;
  FNames := TStringList.Create;
  FNames.Sorted := True;
  FNames.CaseSensitive := True;
  FNames.Duplicates := dupIgnore;
end;

destructor TEpgData.Destroy;
begin
  FNames.Free;
  FChannels.Free;
  inherited Destroy;
end;

function TEpgData.GetOrAdd(const Id: string): TEpgChannel;
var
  i: Integer;
begin
  if FChannels.Find(Id, i) then
    Exit(TEpgChannel(FChannels.Objects[i]));
  Result := TEpgChannel.Create;
  Result.Id := Id;
  FChannels.AddObject(Id, Result);
end;

procedure TEpgData.AddName(const AName: string; Ch: TEpgChannel);
var
  K: string;
begin
  K := NormalizeName(AName);
  if K <> '' then
    FNames.AddObject(K, Ch);
end;

procedure TEpgData.AddItem(const ChannelId: string; Item: TEpgItem);
begin
  GetOrAdd(ChannelId).Items.Add(Item);
  Inc(FProgCount);
end;

procedure TEpgData.SortAll;
var
  i: Integer;
begin
  for i := 0 to FChannels.Count - 1 do
    TEpgChannel(FChannels.Objects[i]).Items.Sort(@CompareItems);
end;

function TEpgData.FindChannel(const TvgId, TvgName, AName: string): TEpgChannel;
var
  i: Integer;
  K: string;
begin
  Result := nil;
  if (TvgId <> '') and FChannels.Find(TvgId, i) then
    Exit(TEpgChannel(FChannels.Objects[i]));
  K := NormalizeName(TvgName);
  if (K <> '') and FNames.Find(K, i) then
    Exit(TEpgChannel(FNames.Objects[i]));
  K := NormalizeName(AName);
  if (K <> '') and FNames.Find(K, i) then
    Exit(TEpgChannel(FNames.Objects[i]));
  if (AName <> '') and FChannels.Find(AName, i) then
    Exit(TEpgChannel(FChannels.Objects[i]));
end;

{ Простой потоковый сканер XML }

type
  TXmlScanner = class
  private
    FStream: TStream;
    FBuf: array[0..65535] of Char;
    FPos, FLen: Integer;
    function Fill: Boolean;
  public
    constructor Create(AStream: TStream);
    { Читает до символа Stop (сам символ пропускается). False — конец файла. }
    function ReadUntil(Stop: Char; out S: string; MaxLen: Integer): Boolean;
  end;

constructor TXmlScanner.Create(AStream: TStream);
begin
  inherited Create;
  FStream := AStream;
end;

function TXmlScanner.Fill: Boolean;
begin
  FLen := FStream.Read(FBuf[0], SizeOf(FBuf));
  FPos := 0;
  Result := FLen > 0;
end;

function TXmlScanner.ReadUntil(Stop: Char; out S: string; MaxLen: Integer): Boolean;
var
  i, Start, Cnt, Old: Integer;
begin
  S := '';
  Result := False;
  while True do
  begin
    if FPos >= FLen then
      if not Fill then Exit;
    Start := FPos;
    i := FPos;
    while (i < FLen) and (FBuf[i] <> Stop) do Inc(i);
    Cnt := i - Start;
    Old := Length(S);
    if Old + Cnt > MaxLen then Cnt := MaxLen - Old;
    if Cnt > 0 then
    begin
      SetLength(S, Old + Cnt);
      Move(FBuf[Start], S[Old + 1], Cnt);
    end;
    FPos := i;
    if i < FLen then
    begin
      Inc(FPos);
      Exit(True);
    end;
  end;
end;

{ Обрезает «хвост» незавершённого UTF-8 символа. }
function FixUtf8Tail(const S: string): string;
var
  n: Integer;
begin
  Result := S;
  n := Length(Result);
  while (n > 0) and ((Ord(Result[n]) and $C0) = $80) do Dec(n);
  if (n > 0) and (Ord(Result[n]) >= $C0) then
    SetLength(Result, n - 1);
end;

function DecodeEntities(const S: string): string;
var
  i, j, Code: Integer;
  Ent: string;
begin
  if Pos('&', S) = 0 then Exit(S);
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if S[i] = '&' then
    begin
      j := i + 1;
      while (j <= Length(S)) and (j - i < 12) and (S[j] <> ';') do Inc(j);
      if (j <= Length(S)) and (S[j] = ';') then
      begin
        Ent := Copy(S, i + 1, j - i - 1);
        if Ent = 'amp' then Result := Result + '&'
        else if Ent = 'lt' then Result := Result + '<'
        else if Ent = 'gt' then Result := Result + '>'
        else if Ent = 'quot' then Result := Result + '"'
        else if Ent = 'apos' then Result := Result + ''''
        else if (Length(Ent) > 1) and (Ent[1] = '#') then
        begin
          if (Ent[2] = 'x') or (Ent[2] = 'X') then
            Code := StrToIntDef('$' + Copy(Ent, 3, 8), 63)
          else
            Code := StrToIntDef(Copy(Ent, 2, 8), 63);
          Result := Result + UnicodeToUTF8(Cardinal(Code));
        end
        else
          Result := Result + '&' + Ent + ';';
        i := j + 1;
        Continue;
      end;
    end;
    Result := Result + S[i];
    Inc(i);
  end;
end;

function TagName(const Tag: string): string;
var
  i: Integer;
begin
  i := 1;
  while (i <= Length(Tag)) and not (Tag[i] in [' ', #9, #10, #13, '/', '>']) do Inc(i);
  if (i = 1) and (Length(Tag) > 0) and (Tag[1] = '/') then
  begin
    i := 2;
    while (i <= Length(Tag)) and not (Tag[i] in [' ', #9, #10, #13, '>']) do Inc(i);
  end;
  Result := LowerCase(Copy(Tag, 1, i - 1));
end;

function TagAttr(const Tag, AName: string): string;
var
  p, q, n: Integer;
  Quote: Char;
begin
  Result := '';
  n := Length(AName);
  p := PosEx(AName + '=', Tag, 1);
  while (p > 0) and not ((p > 1) and (Tag[p - 1] in [' ', #9, #10, #13])) do
    p := PosEx(AName + '=', Tag, p + 1);
  if (p <= 0) or (p + n + 1 > Length(Tag)) then Exit;
  p := p + n + 1;
  Quote := Tag[p];
  if not (Quote in ['"', '''']) then Exit;
  Inc(p);
  q := p;
  while (q <= Length(Tag)) and (Tag[q] <> Quote) do Inc(q);
  Result := DecodeEntities(Copy(Tag, p, q - p));
end;

function ParseXmltvTime(const S: string; out T: TDateTime): Boolean;
var
  Y, Mo, D, H, Mi, Se, Off: Integer;
  Tz: string;
  DPart, TPart: TDateTime;
  p: Integer;
begin
  Result := False;
  T := 0;
  if Length(S) < 12 then Exit;
  Y := StrToIntDef(Copy(S, 1, 4), -1);
  Mo := StrToIntDef(Copy(S, 5, 2), -1);
  D := StrToIntDef(Copy(S, 7, 2), -1);
  H := StrToIntDef(Copy(S, 9, 2), -1);
  Mi := StrToIntDef(Copy(S, 11, 2), -1);
  Se := 0;
  if (Length(S) >= 14) and (S[13] in ['0'..'9']) then
    Se := StrToIntDef(Copy(S, 13, 2), 0);
  if not TryEncodeDate(Word(Y), Word(Mo), Word(D), DPart) then Exit;
  if not TryEncodeTime(Word(H), Word(Mi), Word(Se), 0, TPart) then Exit;
  T := DPart + TPart;

  Tz := '';
  p := Pos(' ', S);
  if p > 0 then
    Tz := Trim(Copy(S, p + 1, 5))
  else if (Length(S) >= 19) and (S[15] in ['+', '-']) then
    Tz := Copy(S, 15, 5);
  if (Length(Tz) = 5) and (Tz[1] in ['+', '-']) then
  begin
    Off := StrToIntDef(Copy(Tz, 2, 2), 0) * 60 + StrToIntDef(Copy(Tz, 4, 2), 0);
    if Tz[1] = '-' then Off := -Off;
    T := T - Off / 1440;
  end;
  Result := True;
end;

function LoadXmltvFile(const FileName: string; Data: TEpgData; out ErrorMsg: string): Boolean;
var
  Src: TStream;
  Sc: TXmlScanner;
  Magic: array[0..1] of Byte;
  F: TFileStream;
  Tag, Name, Txt, ProgChan: string;
  CurChan: TEpgChannel;
  InProg, ProgOk: Boolean;
  PStart, PStop, WinFrom, WinTo: TDateTime;
  PTitle, PDesc: string;
  Expect: Integer;   { 1 — ждём CDATA для title, 2 — для desc }
  It: TEpgItem;
begin
  Result := False;
  ErrorMsg := '';
  Src := nil;
  try
    Magic[0] := 0;
    Magic[1] := 0;
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      if F.Size >= 2 then F.ReadBuffer(Magic, 2);
    finally
      F.Free;
    end;
    if (Magic[0] = $1F) and (Magic[1] = $8B) then
      Src := TGZFileStream.Create(FileName, gzopenread)
    else
      Src := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  except
    on E: Exception do
    begin
      ErrorMsg := E.Message;
      Src.Free;
      Exit;
    end;
  end;

  WinFrom := NowUtc - 0.5;
  WinTo := NowUtc + 2;
  CurChan := nil;
  InProg := False;
  ProgOk := False;
  Expect := 0;
  PStart := 0;
  PStop := 0;
  Sc := TXmlScanner.Create(Src);
  try
    try
      while Sc.ReadUntil('<', Txt, 0) do
      begin
        if not Sc.ReadUntil('>', Tag, 16384) then Break;
        if Tag = '' then Continue;

        if Copy(Tag, 1, 3) = '!--' then
        begin
          { комментарий: читаем до «-->» }
          while not ((Length(Tag) >= 2) and (Copy(Tag, Length(Tag) - 1, 2) = '--')) do
            if not Sc.ReadUntil('>', Tag, 16384) then Break;
          Continue;
        end;

        if Copy(Tag, 1, 8) = '![CDATA[' then
        begin
          Txt := Copy(Tag, 9, Length(Tag) - 10);
          if InProg and (Expect = 1) then PTitle := FixUtf8Tail(Copy(Trim(Txt), 1, 300))
          else if InProg and (Expect = 2) then PDesc := FixUtf8Tail(Copy(Trim(Txt), 1, 800));
          Expect := 0;
          Continue;
        end;
        Expect := 0;

        if Tag[1] in ['?', '!'] then Continue;
        Name := TagName(Tag);

        if Name = 'channel' then
          CurChan := Data.GetOrAdd(TagAttr(Tag, 'id'))
        else if Name = '/channel' then
          CurChan := nil
        else if Name = 'display-name' then
        begin
          if (CurChan <> nil) and (Tag[Length(Tag)] <> '/') and Sc.ReadUntil('<', Txt, 1000) then
            Data.AddName(DecodeEntities(FixUtf8Tail(Txt)), CurChan);
        end
        else if Name = 'programme' then
        begin
          InProg := True;
          PTitle := '';
          PDesc := '';
          ProgChan := TagAttr(Tag, 'channel');
          ProgOk := ParseXmltvTime(TagAttr(Tag, 'start'), PStart) and
                    ParseXmltvTime(TagAttr(Tag, 'stop'), PStop);
          if ProgOk then
            ProgOk := (PStop > WinFrom) and (PStart < WinTo) and (PStop > PStart);
        end
        else if Name = '/programme' then
        begin
          if InProg and ProgOk and (PTitle <> '') and (ProgChan <> '') then
          begin
            It := TEpgItem.Create;
            It.Start := PStart;
            It.Stop := PStop;
            It.Title := PTitle;
            It.Desc := PDesc;
            Data.AddItem(ProgChan, It);
          end;
          InProg := False;
        end
        else if InProg and ProgOk and (Name = 'title') and (PTitle = '') and (Tag[Length(Tag)] <> '/') then
        begin
          if Sc.ReadUntil('<', Txt, 1000) then
          begin
            PTitle := DecodeEntities(FixUtf8Tail(Trim(Txt)));
            if PTitle = '' then Expect := 1;
          end;
        end
        else if InProg and ProgOk and (Name = 'desc') and (PDesc = '') and (Tag[Length(Tag)] <> '/') then
        begin
          if Sc.ReadUntil('<', Txt, 800) then
          begin
            PDesc := DecodeEntities(FixUtf8Tail(Trim(Txt)));
            if PDesc = '' then Expect := 2;
          end;
        end;
      end;
      Data.SortAll;
      Result := Data.ProgrammeCount > 0;
      if not Result then
        ErrorMsg := 'в файле телепрограммы нет актуальных передач';
    except
      on E: Exception do
        ErrorMsg := 'ошибка чтения телепрограммы: ' + E.Message;
    end;
  finally
    Sc.Free;
    Src.Free;
  end;
end;

end.
