{ Логотипы каналов.
  Всё тяжёлое (скачивание, распаковка PNG/JPEG, уменьшение) делается в
  фоновом потоке. В основном потоке остаётся только быстрое наложение
  маленькой заготовки на цвет фона карточки — интерфейс не подвисает. }
unit logos;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, syncobjs;

const
  MASTER_SIZE = 72;   { размер заготовки, из которой делаются все остальные }

type
  { Уменьшенная копия логотипа с прозрачностью: RGBA, premultiplied }
  TLogoMaster = class
  public
    W, H: Integer;
    Px: array of Byte;   { W*H*4: R*A, G*A, B*A, A }
  end;

  TLogoCache = class;

  TLogoWorker = class(TThread)
  private
    FLock: TCriticalSection;
    FQueue: TStringList;
    FDone: TList;            { TDoneItem }
    FEvent: PRTLEvent;
    FDir: string;
    FNotifyPending: Boolean;
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
    FMasters: TStringList;  { url -> TLogoMaster (nil — не удалось), владеет }
    FPending: TStringList;
    FBitmaps: TStringList;  { 'size#bg#url' -> TBitmap }
    FWorker: TLogoWorker;
    FChanged: Boolean;
  public
    constructor Create(const ACacheDir: string);
    destructor Destroy; override;
    { Готовая картинка Size x Size на фоне Bg или nil (будет готова позже). }
    function Get(const Url: string; Size: Integer; Bg: TColor): TBitmap;
    procedure Delivered(List: TList);
    { True, если с прошлого вызова появились новые логотипы (сбрасывает флаг). }
    function TakeChanged: Boolean;
    procedure ClearMemory;
  end;

implementation

uses
  IntfGraphics, FPImage, FPReadPNG, FPReadJPEG, FPReadBMP, FPReadGif,
  netload, appsettings, applog;

type
  TDoneItem = class
  public
    Url: string;
    Master: TLogoMaster;
  end;

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
  else if (B[0] = $42) and (B[1] = $4D) then Result := '.bmp';
end;

function FindCached(const Base: string): string;
const
  Exts: array[0..3] of string = ('.png', '.jpg', '.gif', '.bmp');
var
  i: Integer;
begin
  for i := 0 to High(Exts) do
    if FileExists(Base + Exts[i]) then
      Exit(Base + Exts[i]);
  Result := '';
end;

{ Загрузка файла и уменьшение до MASTER_SIZE с усреднением (в фоне). }
function MakeMaster(const Path: string): TLogoMaster;
var
  Img: TFPMemoryImage;
  W, H, TW, TH, dx, dy, sx, sy, sx0, sx1, sy0, sy1, n, k: Integer;
  C: TFPColor;
  SR, SG, SB, SA, A: Double;
begin
  Result := nil;
  Img := TFPMemoryImage.Create(0, 0);
  try
    try
      Img.LoadFromFile(Path);
    except
      Exit;
    end;
    W := Img.Width;
    H := Img.Height;
    if (W <= 0) or (H <= 0) then Exit;
    if W >= H then
    begin
      TW := MASTER_SIZE;
      TH := Round(H * MASTER_SIZE / W);
    end
    else
    begin
      TH := MASTER_SIZE;
      TW := Round(W * MASTER_SIZE / H);
    end;
    if TW < 1 then TW := 1;
    if TH < 1 then TH := 1;
    if (TW > W) or (TH > H) then
    begin
      { маленький исходник — не увеличиваем }
      TW := W;
      TH := H;
    end;
    Result := TLogoMaster.Create;
    Result.W := TW;
    Result.H := TH;
    SetLength(Result.Px, TW * TH * 4);
    for dy := 0 to TH - 1 do
    begin
      sy0 := dy * H div TH;
      sy1 := (dy + 1) * H div TH;
      if sy1 <= sy0 then sy1 := sy0 + 1;
      for dx := 0 to TW - 1 do
      begin
        sx0 := dx * W div TW;
        sx1 := (dx + 1) * W div TW;
        if sx1 <= sx0 then sx1 := sx0 + 1;
        SR := 0; SG := 0; SB := 0; SA := 0; n := 0;
        for sy := sy0 to sy1 - 1 do
          for sx := sx0 to sx1 - 1 do
          begin
            C := Img.Colors[sx, sy];
            A := C.alpha / 65535;
            SR := SR + (C.red shr 8) * A;
            SG := SG + (C.green shr 8) * A;
            SB := SB + (C.blue shr 8) * A;
            SA := SA + A;
            Inc(n);
          end;
        k := (dy * TW + dx) * 4;
        Result.Px[k] := Round(SR / n);
        Result.Px[k + 1] := Round(SG / n);
        Result.Px[k + 2] := Round(SB / n);
        Result.Px[k + 3] := Round(SA / n * 255);
      end;
    end;
  finally
    Img.Free;
  end;
end;

{ Быстрое наложение заготовки на фон нужного размера (основной поток). }
function RenderFromMaster(M: TLogoMaster; Size: Integer; Bg: TColor): TBitmap;
var
  Dst: TLazIntfImage;
  TW, TH, OX, OY, Pad, dx, dy, sx, sy, sx0, sx1, sy0, sy1, n, k: Integer;
  SR, SG, SB, SA, A: Integer;
  BR, BGr, BB: Integer;
  BC: TColor;
  C: TFPColor;
begin
  Pad := Size div 16;
  TW := Size - 2 * Pad;
  TH := Round(M.H * TW / M.W);
  if TH > Size - 2 * Pad then
  begin
    TH := Size - 2 * Pad;
    TW := Round(M.W * TH / M.H);
  end;
  if TW < 1 then TW := 1;
  if TH < 1 then TH := 1;
  OX := (Size - TW) div 2;
  OY := (Size - TH) div 2;
  BC := ColorToRGB(Bg);
  BR := Red(BC);
  BGr := Green(BC);
  BB := Blue(BC);

  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(Size, Size);
  Result.Canvas.Brush.Color := Bg;
  Result.Canvas.FillRect(0, 0, Size, Size);
  Dst := Result.CreateIntfImage;
  try
    for dy := 0 to TH - 1 do
    begin
      sy0 := dy * M.H div TH;
      sy1 := (dy + 1) * M.H div TH;
      if sy1 <= sy0 then sy1 := sy0 + 1;
      if sy1 > M.H then sy1 := M.H;
      for dx := 0 to TW - 1 do
      begin
        sx0 := dx * M.W div TW;
        sx1 := (dx + 1) * M.W div TW;
        if sx1 <= sx0 then sx1 := sx0 + 1;
        if sx1 > M.W then sx1 := M.W;
        SR := 0; SG := 0; SB := 0; SA := 0; n := 0;
        for sy := sy0 to sy1 - 1 do
          for sx := sx0 to sx1 - 1 do
          begin
            k := (sy * M.W + sx) * 4;
            Inc(SR, M.Px[k]);
            Inc(SG, M.Px[k + 1]);
            Inc(SB, M.Px[k + 2]);
            Inc(SA, M.Px[k + 3]);
            Inc(n);
          end;
        if n = 0 then Continue;
        A := SA div n;
        C.red := (SR div n + BR * (255 - A) div 255) * 257;
        C.green := (SG div n + BGr * (255 - A) div 255) * 257;
        C.blue := (SB div n + BB * (255 - A) div 255) * 257;
        C.alpha := alphaOpaque;
        Dst.Colors[OX + dx, OY + dy] := C;
      end;
    end;
    Result.LoadFromIntfImage(Dst);
  finally
    Dst.Free;
  end;
end;

{ TLogoWorker }

constructor TLogoWorker.Create(const ADir: string);
begin
  FLock := TCriticalSection.Create;
  FQueue := TStringList.Create;
  FDone := TList.Create;
  FEvent := RTLEventCreate;
  FDir := ADir;
  FreeOnTerminate := True;
  inherited Create(False);
end;

destructor TLogoWorker.Destroy;
var
  i: Integer;
begin
  for i := 0 to FDone.Count - 1 do
  begin
    TDoneItem(FDone[i]).Master.Free;
    TDoneItem(FDone[i]).Free;
  end;
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
    while FQueue.Count > 400 do FQueue.Delete(FQueue.Count - 1);
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
  L: TList;
  i: Integer;
begin
  L := TList.Create;
  try
    FLock.Enter;
    try
      for i := 0 to FDone.Count - 1 do L.Add(FDone[i]);
      FDone.Clear;
      FNotifyPending := False;
    finally
      FLock.Leave;
    end;
    if Owner <> nil then
      Owner.Delivered(L)
    else
      for i := 0 to L.Count - 1 do
      begin
        TDoneItem(L[i]).Master.Free;
        TDoneItem(L[i]).Free;
      end;
  finally
    L.Free;
  end;
end;

procedure TLogoWorker.Execute;
var
  Url, Base, Path, Ext, Err: string;
  D: TDoneItem;
  NeedNotify: Boolean;
begin
  MaskFloatExceptions;
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
          if (Ext <> '') and RenameFile(Base + '.part', Base + Ext) then
            Path := Base + Ext
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

      D := TDoneItem.Create;
      D.Url := Url;
      D.Master := nil;
      if Path <> '' then
      try
        D.Master := MakeMaster(Path);
      except
        D.Master := nil;
      end;

      FLock.Enter;
      try
        FDone.Add(D);
        NeedNotify := not FNotifyPending;
        FNotifyPending := True;
      finally
        FLock.Leave;
      end;
      if NeedNotify then Queue(@NotifyMain);
    end;
  end;
end;

{ TLogoCache }

constructor TLogoCache.Create(const ACacheDir: string);
begin
  inherited Create;
  FDir := IncludeTrailingPathDelimiter(ACacheDir) + 'logos' + PathDelim;
  ForceDirectories(FDir);
  FMasters := TStringList.Create;
  FMasters.Sorted := True;
  FMasters.CaseSensitive := True;
  FMasters.OwnsObjects := True;
  FPending := TStringList.Create;
  FPending.Sorted := True;
  FPending.CaseSensitive := True;
  FBitmaps := TStringList.Create;
  FBitmaps.Sorted := True;
  FBitmaps.CaseSensitive := True;
  FBitmaps.OwnsObjects := True;
  FWorker := TLogoWorker.Create(FDir);
  FWorker.Owner := Self;
end;

destructor TLogoCache.Destroy;
begin
  FWorker.Owner := nil;
  FWorker.Terminate;
  FWorker.Wake;
  FBitmaps.Free;
  FPending.Free;
  FMasters.Free;
  inherited Destroy;
end;

procedure TLogoCache.ClearMemory;
begin
  FBitmaps.Clear;
end;

function TLogoCache.TakeChanged: Boolean;
begin
  Result := FChanged;
  FChanged := False;
end;

procedure TLogoCache.Delivered(List: TList);
var
  i, k: Integer;
  D: TDoneItem;
begin
  for i := 0 to List.Count - 1 do
  begin
    D := TDoneItem(List[i]);
    if FPending.Find(D.Url, k) then FPending.Delete(k);
    if FMasters.Find(D.Url, k) then
      D.Master.Free
    else
      FMasters.AddObject(D.Url, D.Master);
    D.Free;
  end;
  FChanged := True;
end;

function TLogoCache.Get(const Url: string; Size: Integer; Bg: TColor): TBitmap;
var
  Key: string;
  i: Integer;
  M: TLogoMaster;
begin
  Result := nil;
  if Url = '' then Exit;
  Key := IntToStr(Size) + '#' + IntToHex(ColorToRGB(Bg), 6) + '#' + Url;
  if FBitmaps.Find(Key, i) then
    Exit(TBitmap(FBitmaps.Objects[i]));

  if not FMasters.Find(Url, i) then
  begin
    { ещё не готов — ставим в очередь фоновому потоку }
    if not FPending.Find(Url, i) then
    begin
      FPending.Add(Url);
      FWorker.Request(Url);
    end;
    Exit;
  end;

  M := TLogoMaster(FMasters.Objects[i]);
  if M <> nil then
  try
    Result := RenderFromMaster(M, Size, Bg);
  except
    Result := nil;
  end;
  FBitmaps.AddObject(Key, Result);   { nil — запоминаем неудачу }
end;

end.
