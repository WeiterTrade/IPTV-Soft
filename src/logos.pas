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
  { открытый сервис преобразования картинок (WebP, SVG и др. -> PNG) }
  PROXY_URL = 'https://images.weserv.nl/?url=';
  PROXY_PARAMS = '&w=144&h=144&fit=inside&output=png';
  POSTER_SIZE = 300;
  POSTER_PARAMS = '&w=300&h=450&fit=inside&output=png';

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
    UseProxy: Boolean;
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
    { Постер фильма W x H (обрезается по центру, как в онлайн-кинотеатрах). }
    function GetPoster(const Url: string; W, H: Integer; Bg: TColor): TBitmap;
    procedure Delivered(List: TList);
    { True — логотип по этой ссылке получить не удалось (формат или ошибка сети). }
    function IsFailed(const Url: string): Boolean;
    { True, если с прошлого вызова появились новые логотипы (сбрасывает флаг). }
    function TakeChanged: Boolean;
    procedure ClearMemory;
    { забыть все логотипы (после очистки кэша на диске) }
    procedure Reset;
    procedure SetUseProxy(V: Boolean);
  end;

implementation

uses
  Math, IntfGraphics, FPImage, FPReadPNG, FPReadJPEG, FPReadBMP, FPReadGif,
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
function MakeMaster(const Path: string; MaxSize: Integer = MASTER_SIZE): TLogoMaster;
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
      TW := MaxSize;
      TH := Round(H * MaxSize / W);
    end
    else
    begin
      TH := MaxSize;
      TW := Round(W * MaxSize / H);
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

{ Постер: изображение заполняет W x H целиком, лишнее обрезается по центру. }
function RenderPoster(M: TLogoMaster; W, H: Integer; Bg: TColor): TBitmap;
var
  Dst: TLazIntfImage;
  SW, SH, OX, OY, dx, dy, sx, sy, sx0, sx1, sy0, sy1, n, k: Integer;
  SR, SG, SB, SA, A, BR, BGr, BB: Integer;
  Scale: Double;
  BC: TColor;
  C: TFPColor;
begin
  { какая часть заготовки попадёт в карточку }
  Scale := Math.Max(W / M.W, H / M.H);
  SW := Math.Min(M.W, Round(W / Scale));
  SH := Math.Min(M.H, Round(H / Scale));
  if SW < 1 then SW := 1;
  if SH < 1 then SH := 1;
  OX := (M.W - SW) div 2;
  OY := (M.H - SH) div 2;
  BC := ColorToRGB(Bg);
  BR := Red(BC);
  BGr := Green(BC);
  BB := Blue(BC);
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(W, H);
  Result.Canvas.Brush.Color := Bg;
  Result.Canvas.FillRect(0, 0, W, H);
  Dst := Result.CreateIntfImage;
  try
    for dy := 0 to H - 1 do
    begin
      sy0 := OY + dy * SH div H;
      sy1 := OY + (dy + 1) * SH div H;
      if sy1 <= sy0 then sy1 := sy0 + 1;
      if sy1 > M.H then sy1 := M.H;
      for dx := 0 to W - 1 do
      begin
        sx0 := OX + dx * SW div W;
        sx1 := OX + (dx + 1) * SW div W;
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
        Dst.Colors[dx, dy] := C;
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

function UrlEnc(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if S[i] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~'] then
      Result := Result + S[i]
    else
      Result := Result + '%' + IntToHex(Ord(S[i]), 2);
end;

function TryMaster(const Path: string; MaxSize: Integer = MASTER_SIZE): TLogoMaster;
begin
  Result := nil;
  if Path = '' then Exit;
  try
    Result := MakeMaster(Path, MaxSize);
  except
    Result := nil;
  end;
end;

{ Скачать в Base+расширение; True — получилась картинка известного формата. }
function DownloadImage(const Url, Base: string; out Path: string; out GotFile: Boolean): Boolean;
var
  Ext, Err: string;
begin
  Result := False;
  Path := '';
  GotFile := False;
  if not FetchToFileUA(Url, Base + '.part', BROWSER_UA, Err) then
  begin
    if FileExists(Base + '.part') then DeleteFile(Base + '.part');
    Exit;
  end;
  GotFile := True;
  Ext := DetectExt(Base + '.part');
  if Ext = '' then
  begin
    DeleteFile(Base + '.part');
    Exit;
  end;
  if FileExists(Base + Ext) then DeleteFile(Base + Ext);
  if RenameFile(Base + '.part', Base + Ext) then
  begin
    Path := Base + Ext;
    Result := True;
  end;
end;

procedure TLogoWorker.Execute;
var
  Url, Base, Path, RealUrl, Params: string;
  MaxSz: Integer;
  D: TDoneItem;
  M: TLogoMaster;
  NeedNotify, Got: Boolean;
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

      { 'P#ссылка' — постер фильма: заготовка крупнее }
      RealUrl := Url;
      MaxSz := MASTER_SIZE;
      Params := PROXY_PARAMS;
      if Copy(Url, 1, 2) = 'P#' then
      begin
        RealUrl := Copy(Url, 3, MaxInt);
        MaxSz := POSTER_SIZE;
        Params := POSTER_PARAMS;
      end;
      Base := FDir + 'logo_' + HashStr(RealUrl);
      Got := False;
      { 1) сохранённая копия }
      M := TryMaster(FindCached(Base), MaxSz);
      if M = nil then
      begin
        Path := FindCached(Base);
        if Path <> '' then DeleteFile(Path);   { испорченная или нечитаемая копия }
        { 2) напрямую, как браузер }
        if not FileExists(Base + '.fail') or UseProxy then
          if DownloadImage(RealUrl, Base, Path, Got) then
            M := TryMaster(Path, MaxSz);
        { 3) через сервис преобразования: WebP, SVG, ICO, HTTPS на старых Windows }
        if (M = nil) and UseProxy and not FileExists(Base + '.fail2') then
        begin
          Path := FindCached(Base);
          if Path <> '' then DeleteFile(Path);
          if DownloadImage(PROXY_URL + UrlEnc(RealUrl) + Params, Base, Path, Got) then
            M := TryMaster(Path, MaxSz)
          else if Got then
            with TFileStream.Create(Base + '.fail2', fmCreate) do Free;
        end
        else if (M = nil) and not UseProxy and Got then
          with TFileStream.Create(Base + '.fail', fmCreate) do Free;
      end;

      D := TDoneItem.Create;
      D.Url := Url;
      D.Master := M;

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

procedure TLogoCache.SetUseProxy(V: Boolean);
begin
  FWorker.UseProxy := V;
end;

procedure TLogoCache.Reset;
begin
  FBitmaps.Clear;
  FMasters.Clear;
  FPending.Clear;
  FChanged := True;
end;

function TLogoCache.IsFailed(const Url: string): Boolean;
var
  i: Integer;
begin
  Result := (Url = '') or (FMasters.Find(Url, i) and (FMasters.Objects[i] = nil));
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

function TLogoCache.GetPoster(const Url: string; W, H: Integer; Bg: TColor): TBitmap;
var
  Key, MUrl: string;
  i: Integer;
  M: TLogoMaster;
begin
  Result := nil;
  if Url = '' then Exit;
  MUrl := 'P#' + Url;
  Key := 'P' + IntToStr(W) + 'x' + IntToStr(H) + '#' + IntToHex(ColorToRGB(Bg), 6) + '#' + Url;
  if FBitmaps.Find(Key, i) then
    Exit(TBitmap(FBitmaps.Objects[i]));
  if not FMasters.Find(MUrl, i) then
  begin
    if not FPending.Find(MUrl, i) then
    begin
      FPending.Add(MUrl);
      FWorker.Request(MUrl);
    end;
    Exit;
  end;
  M := TLogoMaster(FMasters.Objects[i]);
  if M <> nil then
  try
    Result := RenderPoster(M, W, H, Bg);
  except
    Result := nil;
  end;
  FBitmaps.AddObject(Key, Result);
end;

end.
