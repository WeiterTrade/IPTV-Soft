{ Скачивание фильмов из медиатеки и список локальных видео
  (скачанные фильмы и записи эфира).
  Windows: WinINet (есть в любой Windows, начиная с XP), Linux: curl.
  Пока файл качается, он называется «*.part»; готовый — переименовывается.
  Название и постер фильма хранятся в media.ini в папке настроек. }
unit downloads;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, contnrs;

type
  TDlState = (dsQueued, dsRunning, dsDone, dsError, dsCancelled);

  TDownloadItem = class
  public
    Title, Url, Poster, FileName: string;
    State: TDlState;
    Done, Total: Int64;
    Parts, PartsDone: Integer;   { для фильмов из частей (HLS) }
    MaxHeight: Integer;          { наибольшая высота кадра для HLS (0 — лучшее качество) }
    Error: string;
    Cancelled: Boolean;
    Thread: TThread;
  end;

  TDownloadThread = class(TThread)
  protected
    procedure Execute; override;
    procedure DirectDownload;
    procedure DownloadHls(const AUrl, AText: string);
  public
    Item: TDownloadItem;
    Ok: Boolean;
    ErrMsg: string;
    constructor Create(AItem: TDownloadItem);
  end;

  TDownloadManager = class
  private
    FItems: TFPObjectList;
    FIndexFile: string;
  public
    MaxParallel: Integer;
    MaxHeight: Integer;   { качество скачивания HLS: 480, 720, 1080 или 0 — лучшее }
    constructor Create(const AIndexFile: string);
    destructor Destroy; override;
    { ставит фильм в очередь; Dir — папка загрузок }
    function Add(const ATitle, AUrl, APoster, Dir: string): TDownloadItem;
    procedure Cancel(Item: TDownloadItem);
    { вызывать по таймеру: запускает очередь, завершает готовые. True — что-то изменилось }
    function Poll: Boolean;
    function ActiveCount: Integer;
    function Count: Integer;
    function Get(Index: Integer): TDownloadItem;
    function FindByFile(const AFileName: string): TDownloadItem;
    function FindByUrl(const AUrl: string): TDownloadItem;
    procedure StopAll;
    { остались работающие потоки (после StopAll) }
    function Busy: Boolean;
    property IndexFile: string read FIndexFile;
  end;

const
  VIDEO_EXTS: array[0..11] of string =
    ('.ts', '.mp4', '.mkv', '.avi', '.mov', '.m4v', '.wmv', '.flv', '.mpg', '.mpeg', '.webm', '.m2ts');

{ Видеофайлы в папке (новые — первыми). }
procedure ListVideoFiles(const Dir: string; L: TStrings);
procedure SaveMediaInfo(const IndexFile, AFileName, ATitle, APoster: string);
function LoadMediaInfo(const IndexFile, AFileName: string; out ATitle, APoster: string): Boolean;
procedure ForgetMediaInfo(const IndexFile, AFileName: string);
function SizeText(B: Int64): string;
function SafeName(const S: string): string;

implementation

uses
  IniFiles, netload{$IFDEF WINDOWS}, Windows{$ELSE}, Process{$ENDIF};

function SizeText(B: Int64): string;
begin
  if B >= Int64(1024) * 1024 * 1024 then
    Result := FormatFloat('0.00', B / (1024.0 * 1024 * 1024)) + ' ГБ'
  else if B >= 1024 * 1024 then
    Result := FormatFloat('0', B / (1024.0 * 1024)) + ' МБ'
  else
    Result := FormatFloat('0', B / 1024.0) + ' КБ';
end;

function SafeName(const S: string): string;
var
  i: Integer;
begin
  Result := Trim(S);
  for i := 1 to Length(Result) do
    if Result[i] in ['\', '/', ':', '*', '?', '"', '<', '>', '|', #0..#31] then Result[i] := '_';
  if Result = '' then Result := 'film';
  if Length(Result) > 120 then Result := Copy(Result, 1, 120);
end;

function IsVideoFile(const FileName: string): Boolean;
var
  E: string;
  i: Integer;
begin
  E := LowerCase(ExtractFileExt(FileName));
  for i := 0 to High(VIDEO_EXTS) do
    if E = VIDEO_EXTS[i] then Exit(True);
  Result := False;
end;

function CompareByAge(List: TStringList; I1, I2: Integer): Integer;
var
  A, B: PtrInt;
begin
  A := PtrInt(List.Objects[I1]);
  B := PtrInt(List.Objects[I2]);
  if A > B then Result := -1 else if A < B then Result := 1 else Result := 0;
end;

procedure ListVideoFiles(const Dir: string; L: TStrings);
var
  SR: TSearchRec;
  D: string;
  T: TStringList;
begin
  L.Clear;
  D := IncludeTrailingPathDelimiter(Dir);
  if not DirectoryExists(D) then Exit;
  T := TStringList.Create;
  try
    if SysUtils.FindFirst(D + '*', faAnyFile, SR) = 0 then
    try
      repeat
        if (SR.Attr and faDirectory) <> 0 then Continue;
        if IsVideoFile(SR.Name) then
          T.AddObject(D + SR.Name, TObject(PtrInt(SR.Time)));
      until SysUtils.FindNext(SR) <> 0;
    finally
      SysUtils.FindClose(SR);
    end;
    T.CustomSort(@CompareByAge);
    L.Assign(T);
  finally
    T.Free;
  end;
end;

function InfoKey(const AFileName: string): string;
begin
  Result := ExtractFileName(AFileName);
end;

procedure SaveMediaInfo(const IndexFile, AFileName, ATitle, APoster: string);
var
  Ini: TIniFile;
begin
  try
    Ini := TIniFile.Create(IndexFile);
    try
      Ini.WriteString(InfoKey(AFileName), 'Title', ATitle);
      Ini.WriteString(InfoKey(AFileName), 'Poster', APoster);
    finally
      Ini.Free;
    end;
  except
  end;
end;

function LoadMediaInfo(const IndexFile, AFileName: string; out ATitle, APoster: string): Boolean;
var
  Ini: TIniFile;
begin
  ATitle := '';
  APoster := '';
  Result := False;
  if not FileExists(IndexFile) then Exit;
  try
    Ini := TIniFile.Create(IndexFile);
    try
      ATitle := Ini.ReadString(InfoKey(AFileName), 'Title', '');
      APoster := Ini.ReadString(InfoKey(AFileName), 'Poster', '');
      Result := ATitle <> '';
    finally
      Ini.Free;
    end;
  except
  end;
end;

procedure ForgetMediaInfo(const IndexFile, AFileName: string);
var
  Ini: TIniFile;
begin
  if not FileExists(IndexFile) then Exit;
  try
    Ini := TIniFile.Create(IndexFile);
    try
      Ini.EraseSection(InfoKey(AFileName));
    finally
      Ini.Free;
    end;
  except
  end;
end;

{ ---------- поток загрузки ---------- }

constructor TDownloadThread.Create(AItem: TDownloadItem);
begin
  Item := AItem;
  inherited Create(True);
  FreeOnTerminate := False;
end;

{$IFDEF WINDOWS}
type
  HINTERNET = Pointer;

const
  INTERNET_OPEN_TYPE_PRECONFIG = 0;
  INTERNET_FLAG_RELOAD = DWORD($80000000);
  INTERNET_FLAG_NO_CACHE_WRITE = DWORD($04000000);
  INTERNET_OPTION_CONNECT_TIMEOUT = 2;
  INTERNET_OPTION_RECEIVE_TIMEOUT = 6;
  HTTP_QUERY_CONTENT_LENGTH = 5;
  HTTP_QUERY_STATUS_CODE = 19;
  HTTP_QUERY_FLAG_NUMBER = DWORD($20000000);

function InternetOpenW(lpszAgent: PWideChar; dwAccessType: DWORD; lpszProxy,
  lpszProxyBypass: PWideChar; dwFlags: DWORD): HINTERNET; stdcall; external 'wininet.dll';
function InternetOpenUrlW(hInet: HINTERNET; lpszUrl, lpszHeaders: PWideChar;
  dwHeadersLength, dwFlags: DWORD; dwContext: PtrUInt): HINTERNET; stdcall; external 'wininet.dll';
function InternetReadFile(hFile: HINTERNET; lpBuffer: Pointer; dwToRead: DWORD;
  var dwRead: DWORD): BOOL; stdcall; external 'wininet.dll';
function InternetCloseHandle(hInet: HINTERNET): BOOL; stdcall; external 'wininet.dll';
function InternetSetOptionW(hInet: HINTERNET; dwOption: DWORD; lpBuffer: Pointer;
  dwBufferLength: DWORD): BOOL; stdcall; external 'wininet.dll';
function HttpQueryInfoW(hRequest: HINTERNET; dwInfoLevel: DWORD; lpBuffer: Pointer;
  var lpdwBufferLength: DWORD; var lpdwIndex: DWORD): BOOL; stdcall; external 'wininet.dll';

procedure TDownloadThread.DirectDownload;
var
  hNet, hUrl: HINTERNET;
  Buf: array[0..65535] of Byte;
  N, Code, Len, Idx, T: DWORD;
  LenBuf: array[0..63] of WideChar;
  F: TFileStream;
  Part: string;
begin
  Ok := False;
  Part := Item.FileName + '.part';
  hNet := InternetOpenW(PWideChar(UnicodeString(BROWSER_UA)), INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if hNet = nil then
  begin
    ErrMsg := 'WinINet недоступен';
    Exit;
  end;
  try
    T := 30000;
    InternetSetOptionW(hNet, INTERNET_OPTION_CONNECT_TIMEOUT, @T, SizeOf(T));
    T := 120000;
    InternetSetOptionW(hNet, INTERNET_OPTION_RECEIVE_TIMEOUT, @T, SizeOf(T));
    hUrl := InternetOpenUrlW(hNet, PWideChar(UTF8Decode(Item.Url)), nil, 0,
      INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE, 0);
    if hUrl = nil then
    begin
      ErrMsg := 'нет соединения с сервером';
      Exit;
    end;
    try
      Code := 0;
      Len := SizeOf(Code);
      Idx := 0;
      if HttpQueryInfoW(hUrl, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @Code, Len, Idx)
        and (Code >= 400) then
      begin
        ErrMsg := 'сервер ответил ошибкой HTTP ' + IntToStr(Code);
        Exit;
      end;
      Len := SizeOf(LenBuf);
      Idx := 0;
      FillChar(LenBuf, SizeOf(LenBuf), 0);
      if HttpQueryInfoW(hUrl, HTTP_QUERY_CONTENT_LENGTH, @LenBuf[0], Len, Idx) then
        Item.Total := StrToInt64Def(UTF8Encode(WideString(PWideChar(@LenBuf[0]))), 0);
      F := TFileStream.Create(Part, fmCreate);
      try
        repeat
          if Terminated then Exit;
          N := 0;
          if not InternetReadFile(hUrl, @Buf[0], SizeOf(Buf), N) then
          begin
            ErrMsg := 'загрузка прервалась (нет связи)';
            Exit;
          end;
          if N > 0 then
          begin
            F.WriteBuffer(Buf[0], N);
            Item.Done := Item.Done + N;
          end;
        until N = 0;
      finally
        F.Free;
      end;
      Ok := Item.Done > 0;
      if not Ok then ErrMsg := 'сервер не отдал файл';
    finally
      InternetCloseHandle(hUrl);
    end;
  finally
    InternetCloseHandle(hNet);
  end;
end;
{$ELSE}
function FileSize64(const FileName: string): Int64;
var
  SR: TSearchRec;
begin
  Result := 0;
  if SysUtils.FindFirst(FileName, faAnyFile, SR) = 0 then
  begin
    Result := SR.Size;
    SysUtils.FindClose(SR);
  end;
end;

procedure TDownloadThread.DirectDownload;
var
  P: TProcess;
  Outp, Line: string;
  L: TStringList;
  i: Integer;
  Part: string;
begin
  Ok := False;
  Part := Item.FileName + '.part';
  { размер файла — из заголовков (последний Content-Length после переадресаций) }
  try
    if RunCommand('curl', ['-sIL', '--connect-timeout', '20', '--max-time', '40', '-A', BROWSER_UA,
      Item.Url], Outp) then
    begin
      L := TStringList.Create;
      try
        L.Text := Outp;
        for i := 0 to L.Count - 1 do
        begin
          Line := LowerCase(Trim(L[i]));
          if Pos('content-length:', Line) = 1 then
            Item.Total := StrToInt64Def(Trim(Copy(Line, 16, MaxInt)), Item.Total);
        end;
      finally
        L.Free;
      end;
    end;
  except
  end;
  P := TProcess.Create(nil);
  try
    P.Executable := 'curl';
    P.Parameters.Add('-fsSL');
    P.Parameters.Add('--connect-timeout');
    P.Parameters.Add('30');
    P.Parameters.Add('-A');
    P.Parameters.Add(BROWSER_UA);
    P.Parameters.Add('-o');
    P.Parameters.Add(Part);
    P.Parameters.Add(Item.Url);
    P.Options := [];
    try
      P.Execute;
    except
      ErrMsg := 'не найдена программа curl (установите: sudo apt install curl)';
      Exit;
    end;
    while P.Running do
    begin
      if Terminated then
      begin
        P.Terminate(1);
        Exit;
      end;
      Item.Done := FileSize64(Part);
      Sleep(300);
    end;
    Item.Done := FileSize64(Part);
    Ok := (P.ExitStatus = 0) and (Item.Done > 0);
    if not Ok then ErrMsg := 'загрузка не удалась (код curl ' + IntToStr(P.ExitStatus) + ')';
  finally
    P.Free;
  end;
end;
{$ENDIF}

{ ---------- HLS (.m3u8): фильм из частей собирается в один файл .ts ---------- }

function IsHlsUrl(const Url: string): Boolean;
var
  U: string;
  p: Integer;
begin
  U := LowerCase(Url);
  p := Pos('?', U);
  if p > 0 then U := Copy(U, 1, p - 1);
  Result := (Pos('.m3u8', U) > 0) or (Copy(U, Length(U) - 3, 4) = '.m3u') or (Pos('/hls/', U) > 0);
end;

{ Полная ссылка на часть по ссылке на список (относительные пути, «/путь», «//хост»). }
function ResolveUrl(const Base, Rel: string): string;
var
  B, Scheme: string;
  p, i: Integer;
begin
  if Pos('://', Rel) > 0 then Exit(Rel);
  p := Pos('://', Base);
  Scheme := Copy(Base, 1, p - 1);
  if Copy(Rel, 1, 2) = '//' then Exit(Scheme + ':' + Rel);
  B := Base;
  i := Pos('?', B);
  if i > 0 then B := Copy(B, 1, i - 1);
  if Copy(Rel, 1, 1) = '/' then
  begin
    i := p + 3;
    while (i <= Length(B)) and (B[i] <> '/') do Inc(i);
    Exit(Copy(B, 1, i - 1) + Rel);
  end;
  i := Length(B);
  while (i > p + 2) and (B[i] <> '/') do Dec(i);
  Result := Copy(B, 1, i) + Rel;
end;

function AttrValue(const Line, Name: string): string;
var
  p, q: Integer;
begin
  Result := '';
  p := Pos(UpperCase(Name) + '=', UpperCase(Line));
  if p = 0 then Exit;
  Inc(p, Length(Name) + 1);
  if (p <= Length(Line)) and (Line[p] = '"') then
  begin
    Inc(p);
    q := p;
    while (q <= Length(Line)) and (Line[q] <> '"') do Inc(q);
  end
  else
  begin
    q := p;
    while (q <= Length(Line)) and (Line[q] <> ',') do Inc(q);
  end;
  Result := Copy(Line, p, q - p);
end;

function FetchText(const Url, Tmp: string; out Text, Err: string): Boolean;
var
  L: TStringList;
begin
  Text := '';
  Result := FetchToFileUA(Url, Tmp, BROWSER_UA, Err);
  if not Result then Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(Tmp);
      Text := L.Text;
    except
      Result := False;
    end;
  finally
    L.Free;
  end;
  SysUtils.DeleteFile(Tmp);
end;

function FileStartsWithM3U(const FileName: string): Boolean;
var
  F: TFileStream;
  B: array[0..15] of Char;
  N: Integer;
  S: string;
begin
  Result := False;
  if not FileExists(FileName) then Exit;
  try
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      if F.Size > 20 * 1024 * 1024 then Exit;   { список частей — маленький текстовый файл }
      FillChar(B, SizeOf(B), 0);
      N := F.Read(B, SizeOf(B));
      SetString(S, PChar(@B[0]), N);
      S := TrimLeft(StringReplace(S, #$EF#$BB#$BF, '', []));
      Result := Pos('#EXTM3U', UpperCase(S)) = 1;
    finally
      F.Free;
    end;
  except
    Result := False;
  end;
end;

procedure TDownloadThread.DownloadHls(const AUrl, AText: string);
var
  Pl, Segs: TStringList;
  Base, Txt, Line, Best, Tmp, Part, Err, InitUrl, Key: string;
  i, j, Depth, Tries, Hgt: Integer;
  Bw, Score, BestScore, LowScore: Int64;
  Res, LowUrl: string;
  Fits: Boolean;
  F, S: TFileStream;
  Got: Boolean;
begin
  Ok := False;
  Tmp := Item.FileName + '.seg';
  Part := Item.FileName + '.part';
  Base := AUrl;
  Txt := AText;
  Pl := TStringList.Create;
  Segs := TStringList.Create;
  try
    { главный список может ссылаться на списки разного качества — берём лучший }
    for Depth := 0 to 3 do
    begin
      if Txt = '' then
        if not FetchText(Base, Tmp, Txt, Err) then
        begin
          ErrMsg := 'не удалось получить список частей фильма (' + Err + ')';
          Exit;
        end;
      Pl.Text := Txt;
      if Pos('#EXT-X-STREAM-INF', UpperCase(Txt)) = 0 then Break;
      { выбираем качество: лучшее, но не выше заданного (по умолчанию 720p);
        если все варианты выше — самый лёгкий }
      Best := '';
      BestScore := -1;
      LowUrl := '';
      LowScore := High(Int64);
      for i := 0 to Pl.Count - 1 do
        if Pos('#EXT-X-STREAM-INF', UpperCase(Pl[i])) = 1 then
        begin
          Bw := StrToInt64Def(AttrValue(Pl[i], 'BANDWIDTH'), 0);
          Res := AttrValue(Pl[i], 'RESOLUTION');
          Hgt := 0;
          if Pos('x', LowerCase(Res)) > 0 then
            Hgt := StrToIntDef(Copy(Res, Pos('x', LowerCase(Res)) + 1, 6), 0);
          for j := i + 1 to Pl.Count - 1 do
          begin
            Line := Trim(Pl[j]);
            if (Line = '') or (Line[1] = '#') then Continue;
            Score := Int64(Hgt) * 100000000 + Bw;
            if Item.MaxHeight <= 0 then
              Fits := True
            else if Hgt > 0 then
              Fits := Hgt <= Item.MaxHeight
            else
              Fits := Bw <= Int64(Item.MaxHeight) * 5000;   { 720p ≈ до 3,6 Мбит/с }
            if Fits and (Score >= BestScore) then
            begin
              BestScore := Score;
              Best := ResolveUrl(Base, Line);
            end;
            if Score < LowScore then
            begin
              LowScore := Score;
              LowUrl := ResolveUrl(Base, Line);
            end;
            Break;
          end;
        end;
      if Best = '' then Best := LowUrl;
      if Best = '' then
      begin
        ErrMsg := 'в списке нет ни одного варианта качества';
        Exit;
      end;
      Base := Best;
      Txt := '';
    end;

    if Pos('#EXT-X-ENDLIST', UpperCase(Txt)) = 0 then
    begin
      ErrMsg := 'это прямой эфир, а не фильм — его можно только записать (Ctrl+R)';
      Exit;
    end;
    InitUrl := '';
    for i := 0 to Pl.Count - 1 do
    begin
      Line := Trim(Pl[i]);
      if Line = '' then Continue;
      if Pos('#EXT-X-KEY', UpperCase(Line)) = 1 then
      begin
        Key := UpperCase(AttrValue(Line, 'METHOD'));
        if (Key <> '') and (Key <> 'NONE') then
        begin
          ErrMsg := 'фильм зашифрован провайдером — скачать его нельзя, но можно записать (Ctrl+R)';
          Exit;
        end;
      end
      else if Pos('#EXT-X-MAP', UpperCase(Line)) = 1 then
        InitUrl := ResolveUrl(Base, AttrValue(Line, 'URI'))
      else if Line[1] <> '#' then
        Segs.Add(ResolveUrl(Base, Line));
    end;
    if Segs.Count = 0 then
    begin
      ErrMsg := 'в списке нет частей фильма';
      Exit;
    end;
    if InitUrl <> '' then Segs.Insert(0, InitUrl);
    Item.Parts := Segs.Count;
    Item.PartsDone := 0;
    Item.Done := 0;

    F := TFileStream.Create(Part, fmCreate);
    try
      for i := 0 to Segs.Count - 1 do
      begin
        if Terminated then Exit;
        Got := False;
        for Tries := 1 to 3 do
        begin
          if Terminated then Exit;
          if FetchToFileUA(Segs[i], Tmp, BROWSER_UA, Err) then
          begin
            Got := True;
            Break;
          end;
          Sleep(1000 * Tries);
        end;
        if not Got then
        begin
          ErrMsg := 'не удалось скачать часть ' + IntToStr(i + 1) + ' из ' + IntToStr(Segs.Count) +
            ' (' + Err + ')';
          Exit;
        end;
        S := TFileStream.Create(Tmp, fmOpenRead or fmShareDenyNone);
        try
          F.CopyFrom(S, 0);
          Item.Done := Item.Done + S.Size;
        finally
          S.Free;
        end;
        SysUtils.DeleteFile(Tmp);
        Item.PartsDone := i + 1;
      end;
    finally
      F.Free;
    end;
    Ok := Item.Done > 0;
    if not Ok then ErrMsg := 'сервер не отдал фильм';
  finally
    SysUtils.DeleteFile(Tmp);
    Segs.Free;
    Pl.Free;
  end;
end;

procedure TDownloadThread.Execute;
var
  Txt, Err, Part: string;
begin
  Ok := False;
  Part := Item.FileName + '.part';
  if IsHlsUrl(Item.Url) then
  begin
    DownloadHls(Item.Url, '');
    Exit;
  end;
  DirectDownload;
  { сервер мог отдать не сам фильм, а список его частей (HLS) }
  if Ok and FileStartsWithM3U(Part) then
  begin
    Ok := False;
    if FetchText(Item.Url, Item.FileName + '.seg', Txt, Err) then
    begin
      SysUtils.DeleteFile(Part);
      Item.Total := 0;
      DownloadHls(Item.Url, Txt);
    end
    else
      ErrMsg := 'не удалось разобрать список частей фильма';
  end;
end;

{ ---------- менеджер ---------- }

constructor TDownloadManager.Create(const AIndexFile: string);
begin
  inherited Create;
  FItems := TFPObjectList.Create(True);
  FIndexFile := AIndexFile;
  MaxParallel := 2;
  MaxHeight := 720;
end;

destructor TDownloadManager.Destroy;
begin
  StopAll;
  if Busy then FItems.OwnsObjects := False;
  FItems.Free;
  inherited Destroy;
end;

function TDownloadManager.Add(const ATitle, AUrl, APoster, Dir: string): TDownloadItem;
var
  Ext, Base, D, Path: string;
  p, n: Integer;
begin
  Result := FindByUrl(AUrl);
  if (Result <> nil) and (Result.State in [dsQueued, dsRunning]) then Exit;
  Path := AUrl;
  p := Pos('?', Path);
  if p > 0 then Path := Copy(Path, 1, p - 1);
  Ext := LowerCase(ExtractFileExt(Path));
  if IsHlsUrl(AUrl) then Ext := '.ts'
  else if (Ext = '') or (Length(Ext) > 6) or not ((Ext = '.mp4') or (Ext = '.mkv') or (Ext = '.avi') or
     (Ext = '.mov') or (Ext = '.m4v') or (Ext = '.wmv') or (Ext = '.flv') or (Ext = '.mpg') or
     (Ext = '.mpeg') or (Ext = '.webm') or (Ext = '.ts')) then
    Ext := '.mp4';
  D := IncludeTrailingPathDelimiter(Dir);
  ForceDirectories(D);
  Base := SafeName(ATitle);
  n := 1;
  Path := D + Base + Ext;
  while FileExists(Path) or FileExists(Path + '.part') or (FindByFile(Path) <> nil) do
  begin
    Inc(n);
    Path := D + Base + ' (' + IntToStr(n) + ')' + Ext;
  end;
  Result := TDownloadItem.Create;
  Result.Title := ATitle;
  Result.Url := AUrl;
  Result.Poster := APoster;
  Result.FileName := Path;
  Result.State := dsQueued;
  Result.MaxHeight := MaxHeight;
  FItems.Add(Result);
  SaveMediaInfo(FIndexFile, Path, ATitle, APoster);
end;

procedure TDownloadManager.Cancel(Item: TDownloadItem);
begin
  if Item = nil then Exit;
  if Item.State = dsQueued then
    Item.State := dsCancelled
  else if (Item.State = dsRunning) and (Item.Thread <> nil) then
  begin
    Item.Cancelled := True;
    Item.Thread.Terminate;
  end;
end;

function TDownloadManager.Poll: Boolean;
var
  i, Running: Integer;
  It: TDownloadItem;
  T: TDownloadThread;
begin
  Result := False;
  Running := 0;
  for i := 0 to FItems.Count - 1 do
  begin
    It := Get(i);
    if (It.State = dsRunning) and (It.Thread <> nil) and It.Thread.Finished then
    begin
      T := TDownloadThread(It.Thread);
      T.WaitFor;
      if It.Cancelled and not T.Ok then
      begin
        It.State := dsCancelled;
        SysUtils.DeleteFile(It.FileName + '.part');
        ForgetMediaInfo(FIndexFile, It.FileName);
      end
      else if T.Ok and SysUtils.RenameFile(It.FileName + '.part', It.FileName) then
        It.State := dsDone
      else
      begin
        It.State := dsError;
        It.Error := T.ErrMsg;
        if It.Error = '' then It.Error := 'не удалось сохранить файл';
        SysUtils.DeleteFile(It.FileName + '.part');
      end;
      It.Thread := nil;
      T.Free;
      Result := True;
    end;
    if It.State = dsRunning then Inc(Running);
  end;
  for i := 0 to FItems.Count - 1 do
  begin
    if Running >= MaxParallel then Break;
    It := Get(i);
    if It.State <> dsQueued then Continue;
    It.State := dsRunning;
    It.Done := 0;
    T := TDownloadThread.Create(It);
    It.Thread := T;
    T.Start;
    Inc(Running);
    Result := True;
  end;
end;

function TDownloadManager.ActiveCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to FItems.Count - 1 do
    if Get(i).State in [dsQueued, dsRunning] then Inc(Result);
end;

function TDownloadManager.Count: Integer;
begin
  Result := FItems.Count;
end;

function TDownloadManager.Get(Index: Integer): TDownloadItem;
begin
  Result := TDownloadItem(FItems[Index]);
end;

function TDownloadManager.FindByFile(const AFileName: string): TDownloadItem;
var
  i: Integer;
begin
  for i := 0 to FItems.Count - 1 do
    if Get(i).FileName = AFileName then Exit(Get(i));
  Result := nil;
end;

function TDownloadManager.FindByUrl(const AUrl: string): TDownloadItem;
var
  i: Integer;
begin
  for i := FItems.Count - 1 downto 0 do
    if Get(i).Url = AUrl then Exit(Get(i));
  Result := nil;
end;

procedure TDownloadManager.StopAll;
var
  i, Tries: Integer;
  It: TDownloadItem;
  AllDone: Boolean;
begin
  for i := 0 to FItems.Count - 1 do
  begin
    It := Get(i);
    if It.State = dsQueued then It.State := dsCancelled;
    if It.Thread <> nil then
    begin
      It.Cancelled := True;
      It.Thread.Terminate;
    end;
  end;
  { ждём не больше 2 секунд, чтобы не задерживать закрытие программы }
  Tries := 0;
  repeat
    AllDone := True;
    for i := 0 to FItems.Count - 1 do
      if (Get(i).Thread <> nil) and not Get(i).Thread.Finished then AllDone := False;
    if AllDone then Break;
    Sleep(100);
    Inc(Tries);
  until Tries > 20;
  for i := 0 to FItems.Count - 1 do
  begin
    It := Get(i);
    if (It.Thread <> nil) and It.Thread.Finished then
    begin
      It.Thread.Free;
      It.Thread := nil;
      SysUtils.DeleteFile(It.FileName + '.part');
      ForgetMediaInfo(FIndexFile, It.FileName);
    end;
  end;
end;

function TDownloadManager.Busy: Boolean;
var
  i: Integer;
begin
  for i := 0 to FItems.Count - 1 do
    if Get(i).Thread <> nil then Exit(True);
  Result := False;
end;

end.
