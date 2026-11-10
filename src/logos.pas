{ Логотипы каналов: фоновая загрузка в кэш на диске и подготовка
  уменьшенных картинок для списка/сетки/плитки. }
unit logos;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, syncobjs;

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
    { Готовая картинка Size x Size, нарисованная на фоне Bg с учётом прозрачности,
      или nil (тогда будет загружена позже). }
    function Get(const Url: string; Size: Integer; Bg: TColor): TBitmap;
    procedure Delivered(List: TStrings);
    procedure ClearMemory;
    property OnLoaded: TNotifyEvent read FOnLoaded write FOnLoaded;
  end;

implementation

uses
  IntfGraphics, FPImage, GraphType, netload, appsettings;

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

{ Сглаженное уменьшение с учётом прозрачности: каждый пиксель результата —
  среднее по области исходника, смешанное с цветом фона. Подложки нет. }
function RenderLogo(Src: TLazIntfImage; Size: Integer; Bg: TColor): TBitmap;
var
  Dst: TLazIntfImage;
  W, H, TW, TH, OX, OY, Pad, dx, dy, sx, sy, sx0, sx1, sy0, sy1, n: Integer;
  C: TFPColor;
  SR, SG, SB, SA, A, BR, BGr, BB: Double;
  BC: TColor;

  function Clamp16(V: Double): Word;
  begin
    if V < 0 then V := 0;
    if V > 65535 then V := 65535;
    Result := Round(V);
  end;

begin
  W := Src.Width;
  H := Src.Height;
  Pad := Size div 16;
  TW := Size - 2 * Pad;
  TH := Round(H * TW / W);
  if TH > Size - 2 * Pad then
  begin
    TH := Size - 2 * Pad;
    TW := Round(W * TH / H);
  end;
  if TW < 1 then TW := 1;
  if TH < 1 then TH := 1;
  OX := (Size - TW) div 2;
  OY := (Size - TH) div 2;
  BC := ColorToRGB(Bg);
  BR := Red(BC) * 257.0;
  BGr := Green(BC) * 257.0;
  BB := Blue(BC) * 257.0;

  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(Size, Size);
  Result.Canvas.Brush.Color := Bg;
  Result.Canvas.FillRect(0, 0, Size, Size);
  Dst := Result.CreateIntfImage;
  try
    for dy := 0 to TH - 1 do
    begin
      sy0 := dy * H div TH;
      sy1 := (dy + 1) * H div TH;
      if sy1 <= sy0 then sy1 := sy0 + 1;
      if sy1 > H then sy1 := H;
      for dx := 0 to TW - 1 do
      begin
        sx0 := dx * W div TW;
        sx1 := (dx + 1) * W div TW;
        if sx1 <= sx0 then sx1 := sx0 + 1;
        if sx1 > W then sx1 := W;
        SR := 0; SG := 0; SB := 0; SA := 0; n := 0;
        for sy := sy0 to sy1 - 1 do
          for sx := sx0 to sx1 - 1 do
          begin
            C := Src.Colors[sx, sy];
            A := C.alpha / 65535;
            SR := SR + C.red * A;
            SG := SG + C.green * A;
            SB := SB + C.blue * A;
            SA := SA + A;
            Inc(n);
          end;
        if n = 0 then Continue;
        A := SA / n;
        C.red := Clamp16(SR / n + BR * (1 - A));
        C.green := Clamp16(SG / n + BGr * (1 - A));
        C.blue := Clamp16(SB / n + BB * (1 - A));
        C.alpha := alphaOpaque;
        Dst.Colors[OX + dx, OY + dy] := C;
      end;
    end;
    Result.LoadFromIntfImage(Dst);
  finally
    Dst.Free;
  end;
end;

function LoadScaled(const Path: string; Size: Integer; Bg: TColor): TBitmap;
var
  P: TPicture;
  Src: TLazIntfImage;
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

    { основной путь: свой рендер с прозрачностью }
    if P.Graphic is TRasterImage then
    try
      Src := TRasterImage(P.Graphic).CreateIntfImage;
      try
        Result := RenderLogo(Src, Size, Bg);
      finally
        Src.Free;
      end;
      Exit;
    except
      FreeAndNil(Result);
    end;

    { запасной путь }
    Pad := Size div 16;
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
    Result.Canvas.Brush.Color := Bg;
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

function TLogoCache.Get(const Url: string; Size: Integer; Bg: TColor): TBitmap;
var
  Key, Path: string;
  i: Integer;
  B: TBitmap;
begin
  Result := nil;
  if Url = '' then Exit;
  Key := IntToStr(Size) + '#' + IntToHex(ColorToRGB(Bg), 6) + '#' + Url;
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
  if Path <> '' then B := LoadScaled(Path, Size, Bg);
  FBitmaps.AddObject(Key, B);   { nil — запоминаем неудачу }
  Result := B;
end;

end.
