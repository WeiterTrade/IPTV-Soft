{ Собственные элементы интерфейса IPTV Aristocrat: плоские кнопки с
  векторными иконками, ползунок, переключатель-плашки. Всё рисуется
  программой, поэтому выглядит одинаково на Windows XP, 11 и Linux. }
unit widgets;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Math;

const
  { Цвета в формате TColor ($00BBGGRR) }
  clrBg       = TColor($001A1614);  { 20,22,26  — фон }
  clrTitle    = TColor($00221C19);  { 25,28,34  — заголовок окна }
  clrSide     = TColor($0027211E);  { 30,33,39  — боковая панель }
  clrPanel    = TColor($002D2622);  { 34,38,45  — панели }
  clrCard     = TColor($00312A26);  { 38,42,49  — карточки }
  clrHover    = TColor($00403630);  { 48,54,64  — наведение }
  clrPress    = TColor($004E433B);  { 59,67,78  — нажатие }
  clrSel      = TColor($0048372D);  { 45,55,72  — выделение }
  clrTrack    = TColor($00504840);  { 64,72,80  — дорожка }
  clrFrame    = TColor($00463C35);  { 53,60,70  — рамка окна }
  clrText     = TColor($00EEEAE8);  { 232,234,238 }
  clrDim      = TColor($009E918A);  { 138,145,158 }
  clrDisabled = TColor($00605850);
  clrStar     = TColor($003DC4FF);  { 255,196,61 }
  clrDanger   = TColor($004848E0);  { 224,72,72 }

  ACCENT_NAMES: array[0..4] of string =
    ('Синий', 'Золотой', 'Изумрудный', 'Лавандовый', 'Коралловый');
  ACCENT_COLORS: array[0..4] of TColor =
    (TColor($00FFA34D), TColor($006AB2D6), TColor($008CBE40),
     TColor($00FF8CA0), TColor($006478FF));

var
  clrAccent: TColor = TColor($00FFA34D);

type
  TIconKind = (ikNone, ikPlay, ikStop, ikPrev, ikNext, ikVolume, ikMute,
    ikFullscreen, ikStar, ikPlus, ikMinus, ikRefresh, ikEdit, ikRecord,
    ikBack, ikChevron, ikViewList, ikViewCompact, ikViewGrid, ikViewTiles,
    ikWinMin, ikWinMax, ikWinRestore, ikClose, ikSettings, ikExternal, ikUp, ikDown, ikWall, ikPause,
    ikTv, ikFilm, ikHistory);

  TFlatButton = class(TGraphicControl)
  private
    FKind: TIconKind;
    FHover, FDown, FChecked: Boolean;
    FIconColor, FCheckedColor, FHoverColor, FHoverIconColor: TColor;
    FNavStyle, FBordered: Boolean;
    procedure SetKind(V: TIconKind);
    procedure SetChecked(V: Boolean);
  protected
    procedure Paint; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    property Kind: TIconKind read FKind write SetKind;
    property Checked: Boolean read FChecked write SetChecked;
    property IconColor: TColor read FIconColor write FIconColor;
    property CheckedColor: TColor read FCheckedColor write FCheckedColor;
    property HoverColor: TColor read FHoverColor write FHoverColor;
    property HoverIconColor: TColor read FHoverIconColor write FHoverIconColor;
    property OnClick;
    property OnDblClick;
    property Caption;
    property Align;
    property BorderSpacing;
    property Hint;
    property ShowHint;
    { пункт меню разделов: текст слева, выбранный — с подсветкой и полоской }
    property NavStyle: Boolean read FNavStyle write FNavStyle;
    { кнопка с рамкой и фоном (для страницы настроек) }
    property Bordered: Boolean read FBordered write FBordered;
  end;

  { Переключатель «вкл/выкл» с подписью — замена системным флажкам }
  TToggle = class(TGraphicControl)
  private
    FChecked, FHover: Boolean;
    FOnChange: TNotifyEvent;
    procedure SetChecked(V: Boolean);
  protected
    procedure Paint; override;
    procedure Click; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Checked: Boolean read FChecked write SetChecked;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Caption;
    property Align;
    property BorderSpacing;
    property Hint;
    property ShowHint;
  end;

  TFlatSlider = class(TGraphicControl)
  private
    FMax, FPosition: Integer;
    FDragging: Boolean;
    FOnChange: TNotifyEvent;
    procedure SetPosition(V: Integer);
    procedure SetFromX(X: Integer);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Position: Integer read FPosition write SetPosition;
    property Max: Integer read FMax write FMax;
    property Dragging: Boolean read FDragging;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Align;
    property BorderSpacing;
    property Hint;
    property ShowHint;
  end;

  { Переключатель-плашки: «Избранное | Все каналы | Категории» }
  TSegmentBar = class(TGraphicControl)
  private
    FItems: TStringList;
    FItemIndex, FHoverIndex: Integer;
    FOnChange: TNotifyEvent;
    procedure SetItemIndex(V: Integer);
    function IndexAt(X: Integer): Integer;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Items: TStringList read FItems;
    property ItemIndex: Integer read FItemIndex write SetItemIndex;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Align;
    property BorderSpacing;
  end;

procedure DrawIcon(C: TCanvas; Kind: TIconKind; const R: TRect; Col: TColor; Filled: Boolean);
procedure SetAccent(Index: Integer);
function BlendColor(A, B: TColor; T: Double): TColor;
{ Размер с учётом масштаба экрана Windows (100 %, 125 %, 150 %...). }
function Sc(V: Integer): Integer;
{ Ширина и высота текста шрифтом F. }
function MeasureText(F: TFont; const S: string): TSize;

implementation

uses
  Forms;

function Sc(V: Integer): Integer;
var
  Dpi: Integer;
begin
  Dpi := Screen.PixelsPerInch;
  if Dpi < 96 then Dpi := 96;
  Result := MulDiv(V, Dpi, 96);
end;

var
  GMeasureBmp: TBitmap = nil;

function MeasureText(F: TFont; const S: string): TSize;
begin
  if GMeasureBmp = nil then
  begin
    GMeasureBmp := TBitmap.Create;
    GMeasureBmp.SetSize(8, 8);
  end;
  GMeasureBmp.Canvas.Font.Assign(F);
  Result := GMeasureBmp.Canvas.TextExtent(S);
end;

procedure SetAccent(Index: Integer);
begin
  if (Index < Low(ACCENT_COLORS)) or (Index > High(ACCENT_COLORS)) then Index := 0;
  clrAccent := ACCENT_COLORS[Index];
end;

function BlendColor(A, B: TColor; T: Double): TColor;
var
  ra, ga, ba, rb, gb, bb: Integer;
begin
  A := ColorToRGB(A);
  B := ColorToRGB(B);
  ra := A and $FF; ga := (A shr 8) and $FF; ba := (A shr 16) and $FF;
  rb := B and $FF; gb := (B shr 8) and $FF; bb := (B shr 16) and $FF;
  Result := RGBToColor(Round(ra + (rb - ra) * T), Round(ga + (gb - ga) * T),
    Round(ba + (bb - ba) * T));
end;

procedure DrawGear(C: TCanvas; cx, cy, Ro, Ri: Integer);
const
  TEETH = 8;
var
  P: array of TPoint;
  i, k: Integer;
  A, Step: Double;

  procedure Add(Ang: Double; R: Integer);
  begin
    P[k] := Point(cx + Round(R * Cos(Ang)), cy + Round(R * Sin(Ang)));
    Inc(k);
  end;

begin
  SetLength(P, TEETH * 4);
  k := 0;
  Step := 2 * Pi / TEETH;
  for i := 0 to TEETH - 1 do
  begin
    A := i * Step - Pi / 2;
    Add(A - Step * 0.30, Ri);
    Add(A - Step * 0.17, Ro);
    Add(A + Step * 0.17, Ro);
    Add(A + Step * 0.30, Ri);
  end;
  C.Polygon(P);
end;

procedure DrawStar(C: TCanvas; cx, cy, r: Integer; Filled: Boolean);
var
  P: array[0..9] of TPoint;
  i: Integer;
  a, rr: Double;
begin
  for i := 0 to 9 do
  begin
    a := -Pi / 2 + i * Pi / 5;
    if Odd(i) then rr := r * 0.45 else rr := r;
    P[i] := Point(cx + Round(rr * Cos(a)), cy + Round(rr * Sin(a)) + 1);
  end;
  if Filled then C.Brush.Style := bsSolid else C.Brush.Style := bsClear;
  C.Pen.Width := 1;
  C.Polygon(P);
end;

procedure DrawSpeaker(C: TCanvas; cx, cy, r: Integer);
var
  t: Integer;
begin
  t := r div 3;
  C.Polygon([Point(cx - r, cy - t), Point(cx - t, cy - t), Point(cx + t div 2, cy - r),
             Point(cx + t div 2, cy + r), Point(cx - t, cy + t), Point(cx - r, cy + t)]);
end;

procedure DrawIcon(C: TCanvas; Kind: TIconKind; const R: TRect; Col: TColor; Filled: Boolean);
var
  cx, cy, s, d, i: Integer;
begin
  cx := (R.Left + R.Right) div 2;
  cy := (R.Top + R.Bottom) div 2;
  s := Min(R.Right - R.Left, R.Bottom - R.Top) * 2 div 9;
  if s < 5 then s := 5;
  C.Pen.Color := Col;
  C.Pen.Width := 1;
  C.Pen.Style := psSolid;
  C.Brush.Color := Col;
  C.Brush.Style := bsSolid;
  case Kind of
    ikPlay:
      C.Polygon([Point(cx - s + 2, cy - s), Point(cx - s + 2, cy + s), Point(cx + s, cy)]);
    ikStop:
      C.Rectangle(cx - s + 1, cy - s + 1, cx + s, cy + s);
    ikPrev:
      begin
        C.Rectangle(cx - s, cy - s, cx - s + 3, cy + s + 1);
        C.Polygon([Point(cx + s, cy - s), Point(cx + s, cy + s), Point(cx - s + 3, cy)]);
      end;
    ikNext:
      begin
        C.Rectangle(cx + s - 2, cy - s, cx + s + 1, cy + s + 1);
        C.Polygon([Point(cx - s, cy - s), Point(cx - s, cy + s), Point(cx + s - 3, cy)]);
      end;
    ikVolume:
      begin
        DrawSpeaker(C, cx - 2, cy, s);
        C.Pen.Width := 2;
        C.Line(cx + s div 2 + 1, cy - s div 3, cx + s div 2 + 1, cy + s div 3 + 1);
        C.Line(cx + s + 1, cy - s * 2 div 3, cx + s + 1, cy + s * 2 div 3 + 1);
      end;
    ikMute:
      begin
        DrawSpeaker(C, cx - 3, cy, s);
        C.Pen.Width := 2;
        C.Line(cx + s div 2, cy - s div 2, cx + s + 2, cy + s div 2);
        C.Line(cx + s div 2, cy + s div 2, cx + s + 2, cy - s div 2);
      end;
    ikFullscreen:
      begin
        d := s * 2 div 3;
        C.Pen.Width := 2;
        C.Brush.Style := bsClear;
        C.Polyline([Point(cx - s, cy - s + d), Point(cx - s, cy - s), Point(cx - s + d, cy - s)]);
        C.Polyline([Point(cx + s - d, cy - s), Point(cx + s, cy - s), Point(cx + s, cy - s + d)]);
        C.Polyline([Point(cx + s, cy + s - d), Point(cx + s, cy + s), Point(cx + s - d, cy + s)]);
        C.Polyline([Point(cx - s + d, cy + s), Point(cx - s, cy + s), Point(cx - s, cy + s - d)]);
      end;
    ikStar:
      DrawStar(C, cx, cy, s + 2, Filled);
    ikPlus:
      begin
        C.Pen.Width := 2;
        C.Line(cx - s, cy, cx + s + 1, cy);
        C.Line(cx, cy - s, cx, cy + s + 1);
      end;
    ikMinus:
      begin
        C.Pen.Width := 2;
        C.Line(cx - s, cy, cx + s + 1, cy);
      end;
    ikRefresh:
      begin
        C.Pen.Width := 2;
        C.Brush.Style := bsClear;
        C.Arc(cx - s, cy - s, cx + s + 1, cy + s + 1, 90 * 16, 270 * 16);
        C.Brush.Style := bsSolid;
        C.Pen.Width := 1;
        C.Polygon([Point(cx - 1, cy - s - 4), Point(cx + 4, cy - s), Point(cx - 1, cy - s + 4)]);
      end;
    ikEdit:
      begin
        C.Pen.Width := 3;
        C.Line(cx - s + 2, cy + s - 2, cx + s - 1, cy - s + 1);
        C.Pen.Width := 1;
        C.Polygon([Point(cx - s, cy + s), Point(cx - s + 1, cy + s - 4), Point(cx - s + 4, cy + s - 1)]);
      end;
    ikRecord:
      C.Ellipse(cx - s + 1, cy - s + 1, cx + s, cy + s);
    ikBack:
      begin
        C.Pen.Width := 2;
        C.Polyline([Point(cx + s div 2, cy - s), Point(cx - s div 2, cy), Point(cx + s div 2, cy + s)]);
      end;
    ikChevron:
      begin
        C.Pen.Width := 2;
        C.Polyline([Point(cx - s div 2, cy - s), Point(cx + s div 2, cy), Point(cx - s div 2, cy + s)]);
      end;
    ikViewList:
      for i := -1 to 1 do
      begin
        C.Rectangle(cx - s, cy + i * (s * 2 div 3) - 1, cx - s + 3, cy + i * (s * 2 div 3) + 2);
        C.Rectangle(cx - s + 5, cy + i * (s * 2 div 3) - 1, cx + s + 1, cy + i * (s * 2 div 3) + 2);
      end;
    ikViewCompact:
      for i := -2 to 2 do
        C.Rectangle(cx - s, cy + i * (s * 2 div 5), cx + s + 1, cy + i * (s * 2 div 5) + 2);
    ikViewGrid:
      begin
        d := s - 1;
        C.Rectangle(cx - s, cy - s, cx - 1, cy - 1);
        C.Rectangle(cx + 1, cy - s, cx + s + 1, cy - 1);
        C.Rectangle(cx - s, cy + 1, cx - 1, cy + s + 1);
        C.Rectangle(cx + 1, cy + 1, cx + s + 1, cy + s + 1);
        if d < 0 then d := 0;
      end;
    ikViewTiles:
      begin
        C.Rectangle(cx - s, cy - s, cx - s + s * 2 div 3, cy - 1);
        C.Rectangle(cx - s + s * 2 div 3 + 2, cy - s + 1, cx + s + 1, cy - 2);
        C.Rectangle(cx - s, cy + 1, cx - s + s * 2 div 3, cy + s + 1);
        C.Rectangle(cx - s + s * 2 div 3 + 2, cy + 2, cx + s + 1, cy + s);
      end;
    ikWinMin:
      C.Rectangle(cx - s, cy + s div 2, cx + s + 1, cy + s div 2 + 1);
    ikWinMax:
      begin
        C.Brush.Style := bsClear;
        C.Rectangle(cx - s, cy - s, cx + s + 1, cy + s + 1);
      end;
    ikWinRestore:
      begin
        C.Brush.Style := bsClear;
        C.Rectangle(cx - s + 3, cy - s, cx + s + 1, cy + s - 2);
        C.Brush.Style := bsSolid;
        C.Brush.Color := clrTitle;
        C.Rectangle(cx - s, cy - s + 3, cx + s - 2, cy + s + 1);
      end;
    ikClose:
      begin
        C.Line(cx - s, cy - s, cx + s + 1, cy + s + 1);
        C.Line(cx + s, cy - s, cx - s - 1, cy + s + 1);
      end;
    ikSettings:
      begin
        { шестерёнка: 8 зубцов контуром и кольцо в центре }
        C.Pen.Width := 2;
        C.Brush.Style := bsClear;
        DrawGear(C, cx, cy, s + 3, s);
        C.Ellipse(cx - s div 2 + 1, cy - s div 2 + 1, cx + s div 2, cy + s div 2);
      end;
    ikUp:
      begin
        C.Pen.Width := 2;
        C.Polyline([Point(cx - s, cy + s div 2), Point(cx, cy - s div 2), Point(cx + s, cy + s div 2)]);
      end;
    ikDown:
      begin
        C.Pen.Width := 2;
        C.Polyline([Point(cx - s, cy - s div 2), Point(cx, cy + s div 2), Point(cx + s, cy - s div 2)]);
      end;
    ikTv:
      begin
        C.Pen.Width := 2;
        C.Brush.Style := bsClear;
        C.RoundRect(cx - s - 2, cy - s + 1, cx + s + 3, cy + s - 2, 4, 4);
        C.Line(cx - s div 2, cy + s + 2, cx + s div 2 + 1, cy + s + 2);
      end;
    ikFilm:
      begin
        C.Pen.Width := 2;
        C.Brush.Style := bsClear;
        C.Rectangle(cx - s, cy - s, cx + s + 1, cy + s + 1);
        C.Brush.Style := bsSolid;
        C.Pen.Width := 1;
        for i := 0 to 2 do
        begin
          C.Rectangle(cx - s + 2, cy - s + 3 + i * (2 * s - 4) div 2, cx - s + 5, cy - s + 6 + i * (2 * s - 4) div 2);
          C.Rectangle(cx + s - 4, cy - s + 3 + i * (2 * s - 4) div 2, cx + s - 1, cy - s + 6 + i * (2 * s - 4) div 2);
        end;
        C.Polygon([Point(cx - 2, cy - s div 2), Point(cx - 2, cy + s div 2), Point(cx + s div 2, cy)]);
      end;
    ikHistory:
      begin
        C.Pen.Width := 2;
        C.Brush.Style := bsClear;
        C.Arc(cx - s, cy - s, cx + s + 1, cy + s + 1, 150 * 16, 300 * 16);
        C.Line(cx, cy - s div 2, cx, cy);
        C.Line(cx, cy, cx + s div 2, cy + s div 3);
        C.Brush.Style := bsSolid;
        C.Pen.Width := 1;
        C.Polygon([Point(cx - s - 4, cy - 3), Point(cx - s + 3, cy - 3), Point(cx - s, cy + 3)]);
      end;
    ikPause:
      begin
        C.Rectangle(cx - s + 1, cy - s, cx - 1, cy + s + 1);
        C.Rectangle(cx + 2, cy - s, cx + s, cy + s + 1);
      end;
    ikWall:
      begin
        { сетка 3x3 — «все каналы на весь экран» }
        d := (2 * s) div 3;
        for i := 0 to 8 do
          C.Rectangle(cx - s + (i mod 3) * d, cy - s + (i div 3) * d,
                      cx - s + (i mod 3) * d + d - 2, cy - s + (i div 3) * d + d - 2);
      end;
    ikExternal:
      begin
        C.Brush.Style := bsClear;
        C.Polyline([Point(cx - 1, cy - s), Point(cx - s, cy - s), Point(cx - s, cy + s),
                    Point(cx + s, cy + s), Point(cx + s, cy + 1)]);
        C.Pen.Width := 2;
        C.Line(cx - 1, cy + 1, cx + s, cy - s);
        C.Line(cx + 2, cy - s, cx + s, cy - s);
        C.Line(cx + s, cy - s, cx + s, cy - 2);
      end;
  end;
  C.Pen.Width := 1;
  C.Brush.Style := bsSolid;
end;

{ TFlatButton }

constructor TFlatButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ParentColor := True;
  ShowHint := True;
  FIconColor := clrText;
  FCheckedColor := clNone;
  FHoverColor := clrHover;
  FHoverIconColor := clNone;
  Width := 36;
  Height := 36;
end;

procedure TFlatButton.SetKind(V: TIconKind);
begin
  if FKind = V then Exit;
  FKind := V;
  Invalidate;
end;

procedure TFlatButton.SetChecked(V: Boolean);
begin
  if FChecked = V then Exit;
  FChecked := V;
  Invalidate;
end;

procedure TFlatButton.Paint;
var
  R, IR: TRect;
  Bg, Ic: TColor;
  S, TH: Integer;
begin
  R := ClientRect;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Color;
  Canvas.FillRect(R);
  if FNavStyle and FChecked then
  begin
    Canvas.Brush.Color := clrSel;
    Canvas.Pen.Color := clrSel;
    Canvas.RoundRect(R.Left + 2, R.Top + 2, R.Right - 2, R.Bottom - 2, 8, 8);
    Canvas.Brush.Color := clrAccent;
    Canvas.FillRect(Rect(R.Left + 2, R.Top + 9, R.Left + 5, R.Bottom - 9));
  end
  else if FBordered then
  begin
    if FChecked then
    begin
      { главная кнопка — залита акцентным цветом }
      if FHover then Canvas.Brush.Color := BlendColor(clrAccent, clWhite, 0.12)
      else Canvas.Brush.Color := clrAccent;
      Canvas.Pen.Color := Canvas.Brush.Color;
    end
    else
    begin
      if FHover then Canvas.Brush.Color := clrHover else Canvas.Brush.Color := clrCard;
      Canvas.Pen.Color := clrFrame;
    end;
    Canvas.RoundRect(R.Left + 1, R.Top + 1, R.Right - 1, R.Bottom - 1, 8, 8);
  end
  else if Enabled and (FHover or FDown) then
  begin
    if FDown then Bg := BlendColor(FHoverColor, clWhite, 0.08) else Bg := FHoverColor;
    Canvas.Brush.Color := Bg;
    Canvas.Pen.Color := Bg;
    if FHoverColor = clrDanger then
      Canvas.FillRect(R)
    else
      Canvas.RoundRect(R.Left + 2, R.Top + 2, R.Right - 2, R.Bottom - 2, 8, 8);
  end;
  if not Enabled then Ic := clrDisabled
  else if FHover and (FHoverIconColor <> clNone) then Ic := FHoverIconColor
  else if FChecked and not FNavStyle then
  begin
    if FCheckedColor <> clNone then Ic := FCheckedColor else Ic := clrAccent;
  end
  else if FNavStyle and FChecked then Ic := clrAccent
  else Ic := FIconColor;

  if Caption = '' then
    IR := R
  else
  begin
    S := R.Bottom - R.Top;
    IR := Rect(R.Left + 2, R.Top, R.Left + 2 + S, R.Bottom);
  end;
  if FKind <> ikNone then
    DrawIcon(Canvas, FKind, IR, Ic, FChecked);
  if Caption <> '' then
  begin
    Canvas.Font.Assign(Font);
    Canvas.Font.Color := clrText;
    Canvas.Brush.Style := bsClear;
    if FNavStyle and FChecked then Canvas.Font.Style := [fsBold];
    if FBordered and FChecked then
    begin
      Canvas.Font.Color := clrBg;
      Canvas.Font.Style := [fsBold];
    end;
    if not Enabled then Canvas.Font.Color := clrDisabled;
    TH := Canvas.TextHeight(Caption);
    if FKind = ikNone then
    begin
      if FBordered then
        Canvas.TextOut((R.Left + R.Right - Canvas.TextWidth(Caption)) div 2, (R.Top + R.Bottom - TH) div 2, Caption)
      else
        Canvas.TextOut(R.Left + 12, (R.Top + R.Bottom - TH) div 2, Caption);
    end
    else
      Canvas.TextOut(IR.Right, (R.Top + R.Bottom - TH) div 2, Caption);
  end;
end;

procedure TFlatButton.MouseEnter;
begin
  inherited MouseEnter;
  FHover := True;
  Invalidate;
end;

procedure TFlatButton.MouseLeave;
begin
  inherited MouseLeave;
  FHover := False;
  FDown := False;
  Invalidate;
end;

procedure TFlatButton.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
  begin
    FDown := True;
    Invalidate;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TFlatButton.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FDown := False;
  Invalidate;
  inherited MouseUp(Button, Shift, X, Y);
end;

{ TToggle }

constructor TToggle.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ParentColor := True;
  Width := 400;
  Height := 30;
end;

procedure TToggle.SetChecked(V: Boolean);
begin
  if V = FChecked then Exit;
  FChecked := V;
  Invalidate;
end;

procedure TToggle.Click;
begin
  FChecked := not FChecked;
  Invalidate;
  inherited Click;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TToggle.MouseEnter;
begin
  inherited MouseEnter;
  FHover := True;
  Invalidate;
end;

procedure TToggle.MouseLeave;
begin
  inherited MouseLeave;
  FHover := False;
  Invalidate;
end;

procedure TToggle.Paint;
var
  R: TRect;
  cy, x0, TH: Integer;
  Track, Knob: TColor;
begin
  R := ClientRect;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Color;
  Canvas.FillRect(R);
  cy := (R.Top + R.Bottom) div 2;
  x0 := R.Left + 2;
  if FChecked then Track := clrAccent
  else if FHover then Track := clrPress
  else Track := clrTrack;
  if not Enabled then Track := clrDisabled;
  Knob := clrText;
  Canvas.Brush.Color := Track;
  Canvas.Pen.Color := Track;
  Canvas.RoundRect(x0, cy - 10, x0 + 38, cy + 10, 20, 20);
  Canvas.Brush.Color := Knob;
  Canvas.Pen.Color := Knob;
  if FChecked then
    Canvas.Ellipse(x0 + 21, cy - 7, x0 + 35, cy + 7)
  else
    Canvas.Ellipse(x0 + 3, cy - 7, x0 + 17, cy + 7);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  if Enabled then Canvas.Font.Color := clrText else Canvas.Font.Color := clrDisabled;
  TH := Canvas.TextHeight('Ag');
  Canvas.TextOut(x0 + 50, cy - TH div 2, Caption);
end;

{ TFlatSlider }

constructor TFlatSlider.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ParentColor := True;
  ShowHint := True;
  FMax := 100;
  FPosition := 80;
  Width := 110;
  Height := 36;
end;

procedure TFlatSlider.SetPosition(V: Integer);
begin
  if V < 0 then V := 0;
  if V > FMax then V := FMax;
  if V = FPosition then Exit;
  FPosition := V;
  Invalidate;
end;

procedure TFlatSlider.SetFromX(X: Integer);
var
  x0, x1, V: Integer;
begin
  x0 := 7;
  x1 := Width - 7;
  if x1 <= x0 then Exit;
  V := Round((X - x0) / (x1 - x0) * FMax);
  if V < 0 then V := 0;
  if V > FMax then V := FMax;
  if V <> FPosition then
  begin
    FPosition := V;
    Invalidate;
    if Assigned(FOnChange) then FOnChange(Self);
  end;
end;

procedure TFlatSlider.Paint;
var
  R: TRect;
  cy, x0, x1, xp, kr: Integer;
begin
  R := ClientRect;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Color;
  Canvas.FillRect(R);
  kr := 6;
  x0 := R.Left + kr + 1;
  x1 := R.Right - kr - 1;
  cy := (R.Top + R.Bottom) div 2;
  xp := x0 + Round((x1 - x0) * FPosition / Math.Max(1, FMax));
  Canvas.Brush.Color := clrTrack;
  Canvas.FillRect(Rect(x0, cy - 2, x1, cy + 2));
  Canvas.Brush.Color := clrAccent;
  Canvas.FillRect(Rect(x0, cy - 2, xp, cy + 2));
  Canvas.Pen.Color := clrText;
  Canvas.Brush.Color := clrText;
  Canvas.Ellipse(xp - kr, cy - kr, xp + kr, cy + kr);
end;

procedure TFlatSlider.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragging := True;
    SetFromX(X);
  end;
end;

procedure TFlatSlider.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging then SetFromX(X);
end;

procedure TFlatSlider.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
end;

function TFlatSlider.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if WheelDelta > 0 then SetPosition(FPosition + 5) else SetPosition(FPosition - 5);
  if Assigned(FOnChange) then FOnChange(Self);
  Result := True;
end;

{ TSegmentBar }

constructor TSegmentBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ParentColor := True;
  FItems := TStringList.Create;
  FItemIndex := 0;
  FHoverIndex := -1;
  Height := 34;
end;

destructor TSegmentBar.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TSegmentBar.SetItemIndex(V: Integer);
begin
  if V = FItemIndex then Exit;
  FItemIndex := V;
  Invalidate;
end;

function TSegmentBar.IndexAt(X: Integer): Integer;
begin
  if (FItems.Count = 0) or (Width <= 0) then Exit(-1);
  Result := X * FItems.Count div Width;
  if Result < 0 then Result := 0;
  if Result >= FItems.Count then Result := FItems.Count - 1;
end;

procedure TSegmentBar.Paint;
var
  R, SR: TRect;
  i, W, TW, TH: Integer;
begin
  R := ClientRect;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Color;
  Canvas.FillRect(R);
  Canvas.Brush.Color := clrBg;
  Canvas.Pen.Color := clrBg;
  Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, 10, 10);
  if FItems.Count = 0 then Exit;
  W := Width div FItems.Count;
  Canvas.Font.Assign(Font);
  Canvas.Font.Size := 9;
  for i := 0 to FItems.Count - 1 do
  begin
    SR := Rect(R.Left + i * W + 3, R.Top + 3, R.Left + (i + 1) * W - 3, R.Bottom - 3);
    if i = FItems.Count - 1 then SR.Right := R.Right - 3;
    if i = FItemIndex then
    begin
      Canvas.Brush.Color := clrAccent;
      Canvas.Pen.Color := clrAccent;
      Canvas.RoundRect(SR.Left, SR.Top, SR.Right, SR.Bottom, 8, 8);
      Canvas.Font.Color := clrBg;
      Canvas.Font.Style := [fsBold];
    end
    else
    begin
      if i = FHoverIndex then
      begin
        Canvas.Brush.Color := clrHover;
        Canvas.Pen.Color := clrHover;
        Canvas.RoundRect(SR.Left, SR.Top, SR.Right, SR.Bottom, 8, 8);
      end;
      Canvas.Font.Color := clrText;
      Canvas.Font.Style := [];
    end;
    Canvas.Brush.Style := bsClear;
    TW := Canvas.TextWidth(FItems[i]);
    TH := Canvas.TextHeight(FItems[i]);
    Canvas.TextOut((SR.Left + SR.Right - TW) div 2, (SR.Top + SR.Bottom - TH) div 2, FItems[i]);
    Canvas.Brush.Style := bsSolid;
  end;
end;

procedure TSegmentBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  I := IndexAt(X);
  if I <> FHoverIndex then
  begin
    FHoverIndex := I;
    Invalidate;
  end;
end;

procedure TSegmentBar.MouseLeave;
begin
  inherited MouseLeave;
  FHoverIndex := -1;
  Invalidate;
end;

procedure TSegmentBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  I := IndexAt(X);
  if (I >= 0) and (I <> FItemIndex) then
  begin
    FItemIndex := I;
    Invalidate;
    if Assigned(FOnChange) then FOnChange(Self);
  end;
end;

finalization
  GMeasureBmp.Free;

end.
