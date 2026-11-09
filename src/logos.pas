{ Логотипы каналов: фоновая загрузка в кэш на диске и подготовка
  уменьшенных картинок для списка/сетки/плитки. }
unit logos;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, syncobjs;

const
  LOGO_PLATE = TColor($00F1EEEC);   { светлая подложка под логотип }

type
  TLogoCache = class;

  TPathObj = class
  public
    Path: string;
  end;

  TLogoWorker = class(TThread)
  private
    FLock: TCriticalSection;
    FQueue, FDone: TStringList;
    FEvent: PRTLEvent;
    FDir: string;
    procedure NotifyMain;
  protected
    procedure Execute; override;
  public
    Owner: TLogoCache;   { используется только в основном потоке }
    constructor Create(const ADir: string);
    destructor Destroy; override;
    procedure Request(const Url: string);
    procedure Wake;
  end;

  TLogoCache = class
  private
    FDir: string;
    FFiles: TStringList;    { url -> путь к файлу ('' — не удалось) }
    FPending: TStringList;  { url, ожидающие загрузки }
    FBitmaps: TStringList;  { 'size#url' -> TBitmap (nil — ошибка) }
    FWorker: TLogoWorker;
    FOnLoaded: TNotifyEvent;
  public
    constructor Create(const ACacheDir: string);
    destructor Destroy; override;
    { Готовая картинка размера Size x Size или nil (тогда будет загружена позже). }
    function Get(const Url: string; Size: Integer): TBitmap;
    procedure Delivered(List: TStrings);
    procedure ClearMemory;
    property OnLoaded: TNotifyEvent read FOnLoaded write FOnLoaded;
  end;

implementation

uses
  netload, appsettings;

function DetectExt(const FileName: string): string;
var
  F: TFileStream;
  B: array[0..11] of Byte;
  N: Integer;
begin
  Result := '';
  FillChar(B, SizeOf(B), 0);
  try
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      N := F.Read(B, SizeOf(B));
    finally
      F.Free;
    end;
  except
    Exit;
  end;
  if N < 4 then Exit;
  if (B[0] = $89) and (B[1] = $50) and (B[2] = $4E) and (B[3] = $47) then Result := '.png'
  else if (B[0] = $FF) and (B[1] = $D8) then Result := '.jpg'
  else if (B[0] = $47) and (B[1] = $49) and (B[2] = $46) then Result := '.gif'
  else if (B[0] = $42) and (B[1] = $4D) then Result := '.bmp'
  else if (B[0] = 0) and (B[1] = 0) and (B[2] = 1) and (B[3] = 0) then Result := '.ico';
end;

function FindCached(const Base: string): string;
const
  Exts: array[0..4] of string = ('.png', '.jpg', '.gif', '.bmp', '.ico');
var
  i: Integer;
begin
  for i := 0 to High(Exts) do
    if FileExists(Base + Exts[i]) then
      Exit(Base + Exts[i]);
  Result := '';
end;

{ TLogoWorker }

constructor TLogoWorker.Create(const ADir: string);
begin
  FLock := TCriticalSection.Create;
  FQueue := TStringList.Create;
  FDone := TStringList.Create;
  FEvent := RTLEventCreate;
  FDir := ADir;
  FreeOnTerminate := True;
  inherited Create(False);
end;

destructor TLogoWorker.Destroy;
begin
  RTLEventDestroy(FEvent);
  FDone.Free;
  FQueue.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TLogoWorker.Request(const Url: string);
begin
  FLock.Enter;
  try
    FQueue.Insert(0, Url);   { последние запрошенные (видимые) — первыми }
  finally
    FLock.Leave;
  end;
  RTLEventSetEvent(FEvent);
end;

procedure TLogoWorker.Wake;
begin
  RTLEventSetEvent(FEvent);
end;

procedure TLogoWorker.NotifyMain;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    FLock.Enter;
    try
      L.Assign(FDone);
      FDone.Clear;
    finally
      FLock.Leave;
    end;
    if (Owner <> nil) and (L.Count > 0) then
      Owner.Delivered(L);
  finally
    L.Free;
  end;
end;

procedure TLogoWorker.Execute;
var
  Url, Base, Path, Ext, Err: string;
begin
  while not Terminated do
  begin
    RTLEventWaitFor(FEvent, 2000);
    while not Terminated do
    begin
      Url := '';
      FLock.Enter;
      try
        if FQueue.Count > 0 then
        begin
          Url := FQueue[0];
          FQueue.Delete(0);
        end;
      finally
        FLock.Leave;
      end;
      if Url = '' then Break;

      Base := FDir + 'logo_' + HashStr(Url);
      Path := FindCached(Base);
      if (Path = '') and not FileExists(Base + '.fail') then
      begin
        if FetchToFile(Url, Base + '.part', Err) then
        begin
          Ext := DetectExt(Base + '.part');
          if Ext <> '' then
          begin
            if RenameFile(Base + '.part', Base + Ext) then Path := Base + Ext;
          end
          else
          begin
            DeleteFile(Base + '.part');
            { формат не поддерживается (например, SVG) — запоминаем }
            with TFileStream.Create(Base + '.fail', fmCreate) do Free;
          end;
        end
        else if FileExists(Base + '.part') then
          DeleteFile(Base + '.part');
      end;

      FLock.Enter;
      try
        FDone.Add(Url + #1 + Path);
      finally
        FLock.Leave;
      end;
      Queue(@NotifyMain);
    end;
  end;
end;

{ TLogoCache }

constructor TLogoCache.Create(const ACacheDir: string);
begin
  inherited Create;
  FDir := IncludeTrailingPathDelimiter(ACacheDir) + 'logos' + PathDelim;
  ForceDirectories(FDir);
  FFiles := TStringList.Create;
  FFiles.Sorted := True;
  FFiles.CaseSensitive := True;
  FFiles.OwnsObjects := True;
  FPending := TStringList.Create;
  FPending.Sorted := True;
  FPending.CaseSensitive := True;
  FBitmaps := TStringList.Create;
  FBitmaps.Sorted := True;
  FBitmaps.CaseSensitive := True;
  FWorker := TLogoWorker.Create(FDir);
  FWorker.Owner := Self;
end;

destructor TLogoCache.Destroy;
begin
  FWorker.Owner := nil;
  FWorker.Terminate;
  FWorker.Wake;
  ClearMemory;
  FBitmaps.Free;
  FPending.Free;
  FFiles.Free;
  inherited Destroy;
end;

procedure TLogoCache.ClearMemory;
var
  i: Integer;
begin
  for i := 0 to FBitmaps.Count - 1 do
    FBitmaps.Objects[i].Free;
  FBitmaps.Clear;
end;

procedure TLogoCache.Delivered(List: TStrings);
var
  i, p, k: Integer;
  Url, Path: string;
  PO: TPathObj;
begin
  for i := 0 to List.Count - 1 do
  begin
    p := Pos(#1, List[i]);
    if p = 0 then Continue;
    Url := Copy(List[i], 1, p - 1);
    Path := Copy(List[i], p + 1, MaxInt);
    if FPending.Find(Url, k) then FPending.Delete(k);
    if not FFiles.Find(Url, k) then
    begin
      PO := TPathObj.Create;
      PO.Path := Path;
      FFiles.AddObject(Url, PO);
    end;
  end;
  if Assigned(FOnLoaded) then FOnLoaded(Self);
end;

function LoadScaled(const Path: string; Size: Integer): TBitmap;
var
  P: TPicture;
  W, H, TW, TH, Pad: Integer;
  R: TRect;
begin
  Result := nil;
  P := TPicture.Create;
  try
    try
      P.LoadFromFile(Path);
    except
      Exit;
    end;
    W := P.Width;
    H := P.Height;
    if (W <= 0) or (H <= 0) then Exit;
    Pad := Size div 10;
    TW := Size - 2 * Pad;
    TH := Round(H * TW / W);
    if TH > Size - 2 * Pad then
    begin
      TH := Size - 2 * Pad;
      TW := Round(W * TH / H);
    end;
    if TW < 1 then TW := 1;
    if TH < 1 then TH := 1;
    Result := TBitmap.Create;
    Result.SetSize(Size, Size);
    Result.Canvas.Brush.Color := LOGO_PLATE;
    Result.Canvas.FillRect(0, 0, Size, Size);
    R := Rect((Size - TW) div 2, (Size - TH) div 2, (Size - TW) div 2 + TW, (Size - TH) div 2 + TH);
    try
      Result.Canvas.StretchDraw(R, P.Graphic);
    except
      FreeAndNil(Result);
    end;
  finally
    P.Free;
  end;
end;

function TLogoCache.Get(const Url: string; Size: Integer): TBitmap;
var
  Key, Path: string;
  i: Integer;
  B: TBitmap;
begin
  Result := nil;
  if Url = '' then Exit;
  Key := IntToStr(Size) + '#' + Url;
  if FBitmaps.Find(Key, i) then
    Exit(TBitmap(FBitmaps.Objects[i]));

  { файл уже скачан? }
  Path := #0;
  if FFiles.Find(Url, i) then
    Path := TPathObj(FFiles.Objects[i]).Path;

  if Path = #0 then
  begin
    { ещё не загружали — ставим в очередь }
    if not FPending.Find(Url, i) then
    begin
      FPending.Add(Url);
      FWorker.Request(Url);
    end;
    Exit;
  end;

  B := nil;
  if Path <> '' then B := LoadScaled(Path, Size);
  FBitmaps.AddObject(Key, B);   { nil — запоминаем неудачу }
  Result := B;
end;

end.
