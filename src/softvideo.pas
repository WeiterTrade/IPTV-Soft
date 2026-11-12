{ Программный вывод видео («совместимый режим»).
  VLC отдаёт готовые кадры в память, а программа сама рисует их в окне —
  без Direct3D, DirectDraw и OpenGL. Так видео показывается даже там, где
  видеокарта не умеет ускорение: виртуальные машины (VirtualBox, VMware),
  старые компьютеры с Windows XP, Linux без драйверов.
  Нагрузка на процессор чуть выше, поэтому кадр больше 1280 точек по
  ширине VLC заранее уменьшает. }
unit softvideo;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, Graphics, SyncObjs;

type
  TSoftRenderer = class
  private
    FLock: TCriticalSection;
    FBuf, FBack: array of Byte;     { FBuf — сюда пишет VLC, FBack — последний готовый кадр }
    FW, FH: Integer;
    FFresh: Boolean;
    FBox: TPaintBox;
    FTimer: TTimer;
    FFrameW, FFrameH: Integer;      { размер кадра, показанного в окне }
    FShow: array of Byte;           { копия кадра для рисования в главном потоке }
    {$IFNDEF WINDOWS}
    FBmp: TBitmap;
    {$ENDIF}
    procedure BoxPaint(Sender: TObject);
    procedure TimerTick(Sender: TObject);
  public
    constructor Create(Host: TWinControl; DblClick: TNotifyEvent);
    destructor Destroy; override;
    { подключить к плееру (до libvlc_media_player_play) }
    procedure Attach(Player: Pointer);
    procedure Clear;
    property Box: TPaintBox read FBox;
  end;

var
  { формат кадра: 0 авто, 1 — 16:9, 2 — 4:3, 3 — растянуть, 4 — заполнить }
  SoftAspect: Integer = 0;

{ Есть ли в этой версии libVLC вывод кадров в память. }
function SoftVideoAvailable: Boolean;

implementation

uses
  Types, vlcdyn{$IFDEF WINDOWS}, Windows{$ENDIF};

const
  MAX_W = 1280;

function SoftVideoAvailable: Boolean;
begin
  Result := Assigned(libvlc_video_set_callbacks) and Assigned(libvlc_video_set_format_callbacks);
end;

{ ---------- обратные вызовы VLC (выполняются в потоке VLC) ---------- }

function CbSetup(opaque: PPointer; chroma: PAnsiChar; width, height, pitches, lines: PCardinal): Cardinal; cdecl;
var
  R: TSoftRenderer;
  W, H: Cardinal;
begin
  R := TSoftRenderer(opaque^);
  W := width^;
  H := height^;
  if (W = 0) or (H = 0) then
  begin
    W := 640;
    H := 360;
  end;
  if W > MAX_W then
  begin
    H := Cardinal(Int64(H) * MAX_W div W);
    W := MAX_W;
  end;
  W := W and not 1;
  H := H and not 1;
  if W < 2 then W := 2;
  if H < 2 then H := 2;
  Move(PAnsiChar('RV32')^, chroma^, 4);
  width^ := W;
  height^ := H;
  pitches^ := W * 4;
  lines^ := H;
  R.FLock.Enter;
  try
    R.FW := W;
    R.FH := H;
    SetLength(R.FBuf, W * H * 4 + 64);
    SetLength(R.FBack, W * H * 4);
    R.FFresh := False;
  finally
    R.FLock.Leave;
  end;
  Result := 1;
end;

procedure CbCleanup(opaque: Pointer); cdecl;
begin
end;

function CbLock(opaque: Pointer; planes: PPointer): Pointer; cdecl;
var
  R: TSoftRenderer;
begin
  R := TSoftRenderer(opaque);
  planes^ := @R.FBuf[0];
  Result := nil;
end;

procedure CbUnlock(opaque: Pointer; picture: Pointer; planes: PPointer); cdecl;
begin
end;

procedure CbDisplay(opaque: Pointer; picture: Pointer); cdecl;
var
  R: TSoftRenderer;
begin
  R := TSoftRenderer(opaque);
  R.FLock.Enter;
  try
    if Length(R.FBack) >= R.FW * R.FH * 4 then
      Move(R.FBuf[0], R.FBack[0], R.FW * R.FH * 4);
    R.FFresh := True;
  finally
    R.FLock.Leave;
  end;
end;

{ ---------- TSoftRenderer ---------- }

constructor TSoftRenderer.Create(Host: TWinControl; DblClick: TNotifyEvent);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FBox := TPaintBox.Create(Host);
  FBox.Parent := Host;
  FBox.Align := alClient;
  FBox.OnPaint := @BoxPaint;
  FBox.OnDblClick := DblClick;
  FBox.Visible := False;
  FTimer := TTimer.Create(Host);
  FTimer.Interval := 20;
  FTimer.OnTimer := @TimerTick;
  FTimer.Enabled := False;
end;

destructor TSoftRenderer.Destroy;
begin
  FTimer.Enabled := False;
  {$IFNDEF WINDOWS}
  FBmp.Free;
  {$ENDIF}
  FLock.Free;
  inherited Destroy;
end;

procedure TSoftRenderer.Attach(Player: Pointer);
begin
  if (Player = nil) or not SoftVideoAvailable then Exit;
  Clear;
  libvlc_video_set_callbacks(Player, @CbLock, @CbUnlock, @CbDisplay, Pointer(Self));
  libvlc_video_set_format_callbacks(Player, @CbSetup, @CbCleanup);
  FBox.Visible := True;
  FBox.BringToFront;
  FTimer.Enabled := True;
end;

procedure TSoftRenderer.Clear;
begin
  FFrameW := 0;
  FFrameH := 0;
  SetLength(FShow, 0);
  FBox.Invalidate;
end;

procedure TSoftRenderer.TimerTick(Sender: TObject);
var
  Got: Boolean;
begin
  if not FBox.Parent.Visible then Exit;
  Got := False;
  FLock.Enter;
  try
    if FFresh and (FW > 0) and (FH > 0) then
    begin
      if Length(FShow) <> FW * FH * 4 then SetLength(FShow, FW * FH * 4);
      Move(FBack[0], FShow[0], FW * FH * 4);
      FFrameW := FW;
      FFrameH := FH;
      FFresh := False;
      Got := True;
    end;
  finally
    FLock.Leave;
  end;
  if Got then FBox.Invalidate;
end;

{ Где рисовать кадр с учётом выбранного формата. Src — часть кадра (для «заполнить»). }
procedure CalcRects(BW, BH, FW, FH: Integer; out Dst, Src: Types.TRect);
var
  A, BA: Double;
  W, H: Integer;
begin
  Src := Types.Rect(0, 0, FW, FH);
  case SoftAspect of
    1: A := 16 / 9;
    2: A := 4 / 3;
    3:
      begin
        Dst := Types.Rect(0, 0, BW, BH);
        Exit;
      end;
  else
    A := FW / FH;
  end;
  BA := BW / BH;
  if SoftAspect = 4 then
  begin
    { заполнить экран: обрезаем края кадра }
    A := FW / FH;
    Dst := Types.Rect(0, 0, BW, BH);
    if A > BA then
    begin
      W := Round(FH * BA);
      Src := Types.Rect((FW - W) div 2, 0, (FW - W) div 2 + W, FH);
    end
    else
    begin
      H := Round(FW / BA);
      Src := Types.Rect(0, (FH - H) div 2, FW, (FH - H) div 2 + H);
    end;
    Exit;
  end;
  if A > BA then
  begin
    H := Round(BW / A);
    Dst := Types.Rect(0, (BH - H) div 2, BW, (BH - H) div 2 + H);
  end
  else
  begin
    W := Round(BH * A);
    Dst := Types.Rect((BW - W) div 2, 0, (BW - W) div 2 + W, BH);
  end;
end;

procedure TSoftRenderer.BoxPaint(Sender: TObject);
var
  C: TCanvas;
  Dst, Src: Types.TRect;
{$IFDEF WINDOWS}
  BI: Windows.TBitmapInfo;
{$ELSE}
  y: Integer;
  P: PByte;
  BPL: PtrUInt;
{$ENDIF}
begin
  C := FBox.Canvas;
  C.Brush.Color := clBlack;
  C.Brush.Style := bsSolid;
  if (FFrameW <= 0) or (FFrameH <= 0) or (Length(FShow) < FFrameW * FFrameH * 4) then
  begin
    C.FillRect(Types.Rect(0, 0, FBox.Width, FBox.Height));
    Exit;
  end;
  CalcRects(FBox.Width, FBox.Height, FFrameW, FFrameH, Dst, Src);
  { чёрные поля вокруг кадра }
  if Dst.Top > 0 then C.FillRect(Types.Rect(0, 0, FBox.Width, Dst.Top));
  if Dst.Bottom < FBox.Height then C.FillRect(Types.Rect(0, Dst.Bottom, FBox.Width, FBox.Height));
  if Dst.Left > 0 then C.FillRect(Types.Rect(0, Dst.Top, Dst.Left, Dst.Bottom));
  if Dst.Right < FBox.Width then C.FillRect(Types.Rect(Dst.Right, Dst.Top, FBox.Width, Dst.Bottom));
{$IFDEF WINDOWS}
  FillChar(BI, SizeOf(BI), 0);
  BI.bmiHeader.biSize := SizeOf(BI.bmiHeader);
  BI.bmiHeader.biWidth := FFrameW;
  BI.bmiHeader.biHeight := -FFrameH;   { строки сверху вниз }
  BI.bmiHeader.biPlanes := 1;
  BI.bmiHeader.biBitCount := 32;
  BI.bmiHeader.biCompression := BI_RGB;
  Windows.SetStretchBltMode(C.Handle, HALFTONE);
  Windows.SetBrushOrgEx(C.Handle, 0, 0, nil);
  Windows.StretchDIBits(C.Handle, Dst.Left, Dst.Top, Dst.Right - Dst.Left, Dst.Bottom - Dst.Top,
    Src.Left, FFrameH - Src.Bottom, Src.Right - Src.Left, Src.Bottom - Src.Top,
    @FShow[0], BI, DIB_RGB_COLORS, SRCCOPY);
{$ELSE}
  if FBmp = nil then
  begin
    FBmp := TBitmap.Create;
    FBmp.PixelFormat := pf32bit;
  end;
  if (FBmp.Width <> FFrameW) or (FBmp.Height <> FFrameH) then FBmp.SetSize(FFrameW, FFrameH);
  FBmp.BeginUpdate(False);
  try
    P := FBmp.RawImage.Data;
    BPL := FBmp.RawImage.Description.BytesPerLine;
    if (P <> nil) and (FBmp.RawImage.Description.BitsPerPixel = 32) then
      for y := 0 to FFrameH - 1 do
        Move(FShow[y * FFrameW * 4], P[PtrUInt(y) * BPL], FFrameW * 4);
  finally
    FBmp.EndUpdate(False);
  end;
  if (Src.Left = 0) and (Src.Top = 0) and (Src.Right = FFrameW) and (Src.Bottom = FFrameH) then
    C.StretchDraw(Dst, FBmp)
  else
    C.CopyRect(Dst, FBmp.Canvas, Src);
{$ENDIF}
end;

end.
