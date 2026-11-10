{ Список каналов с четырьмя видами: список, компактный список, сетка, плитка.
  Также умеет показывать список категорий. Полностью рисуется программой. }
unit channelview;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, Math, LazUTF8,
  m3u, epg, widgets, logos;

type
  TViewMode = (vmList, vmCompact, vmGrid, vmTiles);

  TItemEvent = procedure(Sender: TObject; Index: Integer) of object;
  TFavoriteQuery = function(Ch: TChannel): Boolean of object;

  TChannelView = class(TCustomControl)
  private
    FChannels: TFPList;
    FCategories: TStringList;   { Objects = количество каналов }
    FCatMode: Boolean;
    FMode: TViewMode;
    FShowNumbers, FShowLogos: Boolean;
    FScrollY, FSelected, FHover: Integer;
    FCurrent: TChannel;
    FNowUtc: TDateTime;
    FLogos: TLogoCache;
    FIsFavorite: TFavoriteQuery;
    FOnItemClick, FOnItemActivate, FOnSelectionMoved: TItemEvent;
    FDragThumb: Boolean;
    FDragStartY, FDragStartScroll: Integer;
    FEmptyText: string;
    FDownIndex: Integer;
    FHoverGuide, FDownGuide: Boolean;
    FLarge: Boolean;
    FOnGuideClick: TItemEvent;
    procedure SetLarge(V: Boolean);
    function GuideRect(const R: TRect): TRect;
    function HasGuideButton: Boolean;
    procedure SetMode(V: TViewMode);
    procedure SetShowNumbers(V: Boolean);
    procedure SetShowLogos(V: Boolean);
    procedure SetCurrent(V: TChannel);
    procedure SetSelected(V: Integer);
    function ViewW: Integer;
    procedure Metrics(out Cols, CellW, CellH: Integer);
    function ContentHeight: Integer;
    function ItemRect(Index: Integer): TRect;
    function IndexAt(X, Y: Integer): Integer;
    function ThumbRect: TRect;
    procedure ClampScroll;
    procedure DrawLogo(C: TCanvas; Ch: TChannel; const R: TRect; Bg: TColor);
    procedure DrawChannel(C: TCanvas; Index: Integer; const R: TRect);
    procedure DrawCategory(C: TCanvas; Index: Integer; const R: TRect);
    function ItemBg(Index: Integer; Card: Boolean): TColor;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetChannels(List: TFPList);
    procedure SetCategories(Names: TStrings);
    procedure EnsureVisible(Index: Integer);
    procedure ScrollToTop;
    function ItemCount: Integer;
    function ChannelAt(Index: Integer): TChannel;
    function SelectedChannel: TChannel;
    function SelectedCategory: string;
    function IndexOfChannel(Ch: TChannel): Integer;
    property CatMode: Boolean read FCatMode;
    property Mode: TViewMode read FMode write SetMode;
    property ShowNumbers: Boolean read FShowNumbers write SetShowNumbers;
    property ShowLogos: Boolean read FShowLogos write SetShowLogos;
    property Current: TChannel read FCurrent write SetCurrent;
    property Selected: Integer read FSelected write SetSelected;
    property NowUtc: TDateTime read FNowUtc write FNowUtc;
    property Logos: TLogoCache read FLogos write FLogos;
    property IsFavorite: TFavoriteQuery read FIsFavorite write FIsFavorite;
    property EmptyText: string read FEmptyText write FEmptyText;
    property OnItemClick: TItemEvent read FOnItemClick write FOnItemClick;
    property OnItemActivate: TItemEvent read FOnItemActivate write FOnItemActivate;
    property OnSelectionMoved: TItemEvent read FOnSelectionMoved write FOnSelectionMoved;
    { стрелка «телепрограмма» в конце строки (виды «список» и «компактный») }
    property OnGuideClick: TItemEvent read FOnGuideClick write FOnGuideClick;
    { крупные карточки (режим «все каналы на весь экран») }
    property Large: Boolean read FLarge write SetLarge;
    property PopupMenu;
    property Align;
    property BorderSpacing;
  end;

function Ellipsize(C: TCanvas; const S: string; MaxW: Integer): string;

implementation

const
  SB_W = 10;     { зона полосы прокрутки }
  PAD = 6;

  PLACEHOLDER_COLORS: array[0..7] of TColor = (
    TColor($00A0704A), TColor($006A8A3E), TColor($00446FB0), TColor($008C5A8C),
    TColor($00507A9A), TColor($00828246), TColor($004A4AA0), TColor($00967050));

function Ellipsize(C: TCanvas; const S: string; MaxW: Integer): string;
var
  L: Integer;
begin
  Result := S;
  if MaxW <= 0 then Exit('');
  if C.TextWidth(S) <= MaxW then Exit;
  L := UTF8Length(S);
  while (L > 0) and (C.TextWidth(UTF8Copy(S, 1, L) + '...') > MaxW) do
    Dec(L, Math.Max(1, L div 8));
  if L < 0 then L := 0;
  Result := UTF8Copy(S, 1, L) + '...';
end;

function Initials(const Name: string): string;
var
  S: string;
  p: Integer;
begin
  S := Trim(Name);
  Result := UTF8UpperCase(UTF8Copy(S, 1, 1));
  p := Pos(' ', S);
  if (p > 0) and (p < Length(S)) then
    Result := Result + UTF8UpperCase(UTF8Copy(Trim(Copy(S, p + 1, MaxInt)), 1, 1));
end;

{ TChannelView }

constructor TChannelView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FChannels := TFPList.Create;
  FCategories := TStringList.Create;
  FShowNumbers := True;
  FShowLogos := True;
  FSelected := -1;
  FHover := -1;
  FDownIndex := -1;
  TabStop := True;
  DoubleBuffered := True;
  Color := clrSide;
end;

destructor TChannelView.Destroy;
begin
  FCategories.Free;
  FChannels.Free;
  inherited Destroy;
end;

procedure TChannelView.SetChannels(List: TFPList);
var
  OldSel: TChannel;
begin
  OldSel := SelectedChannel;
  FCatMode := False;
  FCategories.Clear;
  FChannels.Clear;
  if List <> nil then FChannels.Assign(List);
  FSelected := -1;
  if OldSel <> nil then FSelected := FChannels.IndexOf(OldSel);
  if (FSelected < 0) and (FCurrent <> nil) then FSelected := FChannels.IndexOf(FCurrent);
  FHover := -1;
  ClampScroll;
  Invalidate;
end;

procedure TChannelView.SetCategories(Names: TStrings);
begin
  FCatMode := True;
  FChannels.Clear;
  FCategories.Assign(Names);
  FSelected := -1;
  FHover := -1;
  ClampScroll;
  Invalidate;
end;

function TChannelView.ItemCount: Integer;
begin
  if FCatMode then Result := FCategories.Count else Result := FChannels.Count;
end;

function TChannelView.ChannelAt(Index: Integer): TChannel;
begin
  if FCatMode or (Index < 0) or (Index >= FChannels.Count) then Exit(nil);
  Result := TChannel(FChannels[Index]);
end;

function TChannelView.SelectedChannel: TChannel;
begin
  Result := ChannelAt(FSelected);
end;

function TChannelView.SelectedCategory: string;
begin
  if FCatMode and (FSelected >= 0) and (FSelected < FCategories.Count) then
    Result := FCategories[FSelected]
  else
    Result := '';
end;

function TChannelView.IndexOfChannel(Ch: TChannel): Integer;
begin
  if FCatMode then Exit(-1);
  Result := FChannels.IndexOf(Ch);
end;

procedure TChannelView.SetMode(V: TViewMode);
begin
  if V = FMode then Exit;
  FMode := V;
  ClampScroll;
  if FSelected >= 0 then EnsureVisible(FSelected);
  Invalidate;
end;

procedure TChannelView.SetShowNumbers(V: Boolean);
begin
  if V = FShowNumbers then Exit;
  FShowNumbers := V;
  Invalidate;
end;

procedure TChannelView.SetShowLogos(V: Boolean);
begin
  if V = FShowLogos then Exit;
  FShowLogos := V;
  Invalidate;
end;

procedure TChannelView.SetCurrent(V: TChannel);
begin
  if V = FCurrent then Exit;
  FCurrent := V;
  Invalidate;
end;

procedure TChannelView.SetSelected(V: Integer);
begin
  if (V < -1) or (V >= ItemCount) then V := -1;
  if V = FSelected then Exit;
  FSelected := V;
  if V >= 0 then EnsureVisible(V);
  Invalidate;
end;

function TChannelView.ViewW: Integer;
begin
  Result := ClientWidth - SB_W;
  if Result < 40 then Result := 40;
end;

procedure TChannelView.Metrics(out Cols, CellW, CellH: Integer);
var
  W: Integer;
begin
  W := ViewW - 2 * PAD;
  if FCatMode then
  begin
    Cols := 1; CellW := W; CellH := 44;
    Exit;
  end;
  case FMode of
    vmList:
      begin Cols := 1; CellW := W; CellH := 54; end;
    vmCompact:
      begin Cols := 1; CellW := W; CellH := 30; end;
    vmGrid:
      if FLarge then
      begin
        Cols := Math.Max(1, W div 160);
        CellW := W div Cols;
        CellH := 170;
      end
      else
      begin
        Cols := Math.Max(1, W div 118);
        CellW := W div Cols;
        CellH := 124;
      end;
  else { vmTiles }
    begin
      if FLarge then Cols := Math.Max(1, W div 330) else Cols := Math.Max(1, W div 270);
      CellW := W div Cols;
      if FLarge then CellH := 96 else CellH := 80;
    end;
  end;
end;

function TChannelView.ContentHeight: Integer;
var
  Cols, CW, CH, Rows: Integer;
begin
  Metrics(Cols, CW, CH);
  Rows := (ItemCount + Cols - 1) div Cols;
  Result := Rows * CH + 2 * PAD;
end;

function TChannelView.ItemRect(Index: Integer): TRect;
var
  Cols, CW, CH, Row, Col: Integer;
begin
  Metrics(Cols, CW, CH);
  Row := Index div Cols;
  Col := Index mod Cols;
  Result.Left := PAD + Col * CW;
  Result.Top := PAD + Row * CH - FScrollY;
  Result.Right := Result.Left + CW;
  Result.Bottom := Result.Top + CH;
end;

function TChannelView.IndexAt(X, Y: Integer): Integer;
var
  Cols, CW, CH, Row, Col: Integer;
begin
  Result := -1;
  if (X >= ViewW) or (X < PAD) then Exit;
  Metrics(Cols, CW, CH);
  Row := (Y + FScrollY - PAD) div CH;
  Col := (X - PAD) div CW;
  if (Y + FScrollY - PAD < 0) or (Col >= Cols) then Exit;
  Result := Row * Cols + Col;
  if Result >= ItemCount then Result := -1;
end;

function TChannelView.ThumbRect: TRect;
var
  Total, H, T: Integer;
begin
  Total := ContentHeight;
  if Total <= ClientHeight then Exit(Rect(0, 0, 0, 0));
  H := Math.Max(30, ClientHeight * ClientHeight div Total);
  T := Round((ClientHeight - H) * FScrollY / Math.Max(1, Total - ClientHeight));
  Result := Rect(ClientWidth - SB_W + 3, T + 2, ClientWidth - 3, T + H - 2);
end;

procedure TChannelView.ClampScroll;
var
  MaxY: Integer;
begin
  MaxY := ContentHeight - ClientHeight;
  if MaxY < 0 then MaxY := 0;
  if FScrollY > MaxY then FScrollY := MaxY;
  if FScrollY < 0 then FScrollY := 0;
end;

procedure TChannelView.EnsureVisible(Index: Integer);
var
  R: TRect;
begin
  if (Index < 0) or (Index >= ItemCount) then Exit;
  R := ItemRect(Index);
  if R.Top < 0 then
    Inc(FScrollY, R.Top - PAD)
  else if R.Bottom > ClientHeight then
    Inc(FScrollY, R.Bottom - ClientHeight + PAD);
  ClampScroll;
  Invalidate;
end;

procedure TChannelView.ScrollToTop;
begin
  FScrollY := 0;
  Invalidate;
end;

function TChannelView.HasGuideButton: Boolean;
begin
  Result := (not FCatMode) and (FMode in [vmList, vmCompact, vmTiles]);
end;

function TChannelView.GuideRect(const R: TRect): TRect;
var
  cy: Integer;
begin
  cy := (R.Top + R.Bottom) div 2;
  if FMode = vmTiles then
    Result := Rect(R.Right - 40, cy - 14, R.Right - 10, cy + 14)
  else
    Result := Rect(R.Right - 34, cy - 13, R.Right - 4, cy + 13);
end;

procedure TChannelView.SetLarge(V: Boolean);
begin
  if V = FLarge then Exit;
  FLarge := V;
  ClampScroll;
  Invalidate;
end;

function TChannelView.ItemBg(Index: Integer; Card: Boolean): TColor;
begin
  if Index = FSelected then Result := clrSel
  else if Index = FHover then Result := clrHover
  else if Card then Result := clrCard
  else Result := clrSide;
end;

procedure TChannelView.DrawLogo(C: TCanvas; Ch: TChannel; const R: TRect; Bg: TColor);
var
  B: TBitmap;
  Sz, TW, TH: Integer;
  S: string;
begin
  Sz := R.Right - R.Left;
  B := nil;
  if (FLogos <> nil) and (Ch.Logo <> '') then
    B := FLogos.Get(Ch.Logo, Sz, Bg);
  if B <> nil then
  begin
    C.Draw(R.Left, R.Top, B);
    Exit;
  end;
  { заглушка: цветной квадрат с инициалами }
  C.Brush.Style := bsSolid;
  C.Brush.Color := PLACEHOLDER_COLORS[Abs(Ch.Number * 7 + Length(Ch.Name)) mod 8];
  C.Pen.Color := C.Brush.Color;
  C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Sz div 4, Sz div 4);
  S := Initials(Ch.Name);
  C.Font.Style := [fsBold];
  C.Font.Color := clWhite;
  C.Font.Height := -Math.Max(8, Sz * 2 div 5);
  C.Brush.Style := bsClear;
  TW := C.TextWidth(S);
  TH := C.TextHeight(S);
  C.TextOut((R.Left + R.Right - TW) div 2, (R.Top + R.Bottom - TH) div 2, S);
  C.Font.Height := 0;
  C.Brush.Style := bsSolid;
end;

procedure TChannelView.DrawChannel(C: TCanvas; Index: Integer; const R: TRect);
var
  Ch: TChannel;
  It: TEpgItem;
  IsCur, IsFav: Boolean;
  X, Y, W, NameH, LS, TW: Integer;
  Card: TRect;
  Sub, Num: string;
  Frac: Double;
begin
  Ch := TChannel(FChannels[Index]);
  IsCur := Ch = FCurrent;
  IsFav := Assigned(FIsFavorite) and FIsFavorite(Ch);
  It := nil;
  if Ch.Epg <> nil then It := TEpgChannel(Ch.Epg).Current(FNowUtc);
  Num := IntToStr(Ch.Number);

  C.Font.Style := [];
  C.Font.Size := 9;

  case FMode of
    vmList, vmCompact:
      begin
        C.Brush.Style := bsSolid;
        C.Brush.Color := ItemBg(Index, False);
        C.Pen.Color := C.Brush.Color;
        C.RoundRect(R.Left, R.Top + 1, R.Right, R.Bottom - 1, 8, 8);
        if IsCur then
        begin
          C.Brush.Color := clrAccent;
          C.FillRect(Rect(R.Left, R.Top + 8, R.Left + 3, R.Bottom - 8));
        end;
        C.Brush.Style := bsClear;
        X := R.Left + 10;
        if FShowNumbers then
        begin
          C.Font.Size := 8;
          C.Font.Color := clrDim;
          C.TextOut(X, (R.Top + R.Bottom - C.TextHeight(Num)) div 2, Num);
          Inc(X, 34);
        end;
        if FShowLogos then
        begin
          if FMode = vmList then LS := 38 else LS := 20;
          DrawLogo(C, Ch, Rect(X, (R.Top + R.Bottom - LS) div 2, X + LS, (R.Top + R.Bottom - LS) div 2 + LS), ItemBg(Index, False));
          C.Brush.Style := bsClear;
          Inc(X, LS + 10);
        end;
        W := R.Right - X - 64;
        C.Font.Size := 10;
        if IsCur then
        begin
          C.Font.Style := [fsBold];
          C.Font.Color := clrAccent;
        end
        else
        begin
          C.Font.Style := [];
          C.Font.Color := clrText;
        end;
        NameH := C.TextHeight('Ag');
        if FMode = vmCompact then
          C.TextOut(X, (R.Top + R.Bottom - NameH) div 2, Ellipsize(C, Ch.Name, W))
        else
        begin
          Sub := '';
          if It <> nil then Sub := It.Title else Sub := Ch.Group;
          if Sub = '' then
            C.TextOut(X, (R.Top + R.Bottom - NameH) div 2, Ellipsize(C, Ch.Name, W))
          else
          begin
            Y := (R.Top + R.Bottom) div 2 - NameH;
            C.TextOut(X, Y, Ellipsize(C, Ch.Name, W));
            C.Font.Size := 8;
            C.Font.Style := [];
            C.Font.Color := clrDim;
            C.TextOut(X, Y + NameH + 1, Ellipsize(C, Sub, W));
          end;
        end;
        if IsFav then
          DrawIcon(C, ikStar, Rect(R.Right - 60, (R.Top + R.Bottom) div 2 - 11,
            R.Right - 38, (R.Top + R.Bottom) div 2 + 11), clrStar, True);
        { стрелка «телепрограмма» }
        Card := GuideRect(R);
        if (Index = FHover) and FHoverGuide then
        begin
          C.Brush.Style := bsSolid;
          C.Brush.Color := clrPress;
          C.Pen.Color := clrPress;
          C.RoundRect(Card.Left, Card.Top, Card.Right, Card.Bottom, 8, 8);
        end;
        if Ch.Epg <> nil then
          DrawIcon(C, ikChevron, Card, clrText, False)
        else
          DrawIcon(C, ikChevron, Card, clrDisabled, False);
      end;

    vmGrid:
      begin
        Card := Rect(R.Left + 4, R.Top + 4, R.Right - 4, R.Bottom - 4);
        C.Brush.Style := bsSolid;
        C.Brush.Color := ItemBg(Index, True);
        if IsCur then C.Pen.Color := clrAccent else C.Pen.Color := C.Brush.Color;
        C.Pen.Width := 2;
        C.RoundRect(Card.Left, Card.Top, Card.Right, Card.Bottom, 14, 14);
        C.Pen.Width := 1;
        if FLarge then LS := 92 else LS := 60;
        X := (Card.Left + Card.Right - LS) div 2;
        Y := Card.Top + 12;
        if FShowLogos then
          DrawLogo(C, Ch, Rect(X, Y, X + LS, Y + LS), ItemBg(Index, True))
        else
        begin
          C.Font.Size := 18;
          C.Font.Style := [fsBold];
          C.Font.Color := clrDim;
          C.Brush.Style := bsClear;
          TW := C.TextWidth(Num);
          C.TextOut((Card.Left + Card.Right - TW) div 2, Y + 14, Num);
        end;
        C.Brush.Style := bsClear;
        if FLarge then C.Font.Size := 11 else C.Font.Size := 9;
        if IsCur then
        begin
          C.Font.Style := [fsBold];
          C.Font.Color := clrAccent;
        end
        else
        begin
          C.Font.Style := [];
          C.Font.Color := clrText;
        end;
        Sub := Ellipsize(C, Ch.Name, Card.Right - Card.Left - 12);
        TW := C.TextWidth(Sub);
        C.TextOut((Card.Left + Card.Right - TW) div 2, Y + LS + 10, Sub);
        if FShowNumbers and FShowLogos then
        begin
          C.Font.Size := 7;
          C.Font.Style := [];
          C.Font.Color := clrDim;
          C.TextOut(Card.Left + 8, Card.Top + 6, Num);
        end;
        if IsFav then
          DrawIcon(C, ikStar, Rect(Card.Right - 24, Card.Top + 4, Card.Right - 4, Card.Top + 24), clrStar, True);
      end;

    vmTiles:
      begin
        Card := Rect(R.Left + 4, R.Top + 4, R.Right - 4, R.Bottom - 4);
        C.Brush.Style := bsSolid;
        C.Brush.Color := ItemBg(Index, True);
        if IsCur then C.Pen.Color := clrAccent else C.Pen.Color := C.Brush.Color;
        C.Pen.Width := 2;
        C.RoundRect(Card.Left, Card.Top, Card.Right, Card.Bottom, 14, 14);
        C.Pen.Width := 1;
        X := Card.Left + 10;
        if FShowLogos then
        begin
          LS := Card.Bottom - Card.Top - 20;
          DrawLogo(C, Ch, Rect(X, Card.Top + 10, X + LS, Card.Top + 10 + LS), ItemBg(Index, True));
          Inc(X, LS + 12);
        end;
        C.Brush.Style := bsClear;
        W := Card.Right - X - 48;
        Y := Card.Top + 9;
        if FShowNumbers then
        begin
          C.Font.Size := 8;
          C.Font.Style := [];
          C.Font.Color := clrDim;
          C.TextOut(X, Y + 2, Num);
          TW := C.TextWidth(Num) + 8;
        end
        else
          TW := 0;
        C.Font.Size := 10;
        if IsCur then
        begin
          C.Font.Style := [fsBold];
          C.Font.Color := clrAccent;
        end
        else
        begin
          C.Font.Style := [fsBold];
          C.Font.Color := clrText;
        end;
        NameH := C.TextHeight('Ag');
        C.TextOut(X + TW, Y, Ellipsize(C, Ch.Name, W - TW));
        Inc(Y, NameH + 3);
        C.Font.Size := 8;
        C.Font.Style := [];
        C.Font.Color := clrDim;
        if It <> nil then Sub := It.Title else Sub := Ch.Group;
        C.TextOut(X, Y, Ellipsize(C, Sub, W));
        Inc(Y, C.TextHeight('Ag') + 5);
        if It <> nil then
        begin
          Frac := (FNowUtc - It.Start) / Math.Max(1e-9, It.Stop - It.Start);
          if Frac < 0 then Frac := 0;
          if Frac > 1 then Frac := 1;
          C.Brush.Style := bsSolid;
          C.Brush.Color := clrTrack;
          C.FillRect(Rect(X, Y, Card.Right - 48, Y + 3));
          C.Brush.Color := clrAccent;
          C.FillRect(Rect(X, Y, X + Round((Card.Right - 48 - X) * Frac), Y + 3));
        end;
        if IsFav then
          DrawIcon(C, ikStar, Rect(Card.Right - 62, Card.Top + 4, Card.Right - 44, Card.Top + 22), clrStar, True);
        { стрелка «телепрограмма» }
        Card := GuideRect(R);
        if (Index = FHover) and FHoverGuide then
        begin
          C.Brush.Style := bsSolid;
          C.Brush.Color := clrPress;
          C.Pen.Color := clrPress;
          C.RoundRect(Card.Left, Card.Top, Card.Right, Card.Bottom, 8, 8);
        end;
        if Ch.Epg <> nil then
          DrawIcon(C, ikChevron, Card, clrText, False)
        else
          DrawIcon(C, ikChevron, Card, clrDisabled, False);
      end;
  end;
  C.Brush.Style := bsSolid;
end;

procedure TChannelView.DrawCategory(C: TCanvas; Index: Integer; const R: TRect);
var
  S, Cnt: string;
  TW, TH: Integer;
begin
  C.Brush.Style := bsSolid;
  C.Brush.Color := ItemBg(Index, False);
  C.Pen.Color := C.Brush.Color;
  C.RoundRect(R.Left, R.Top + 1, R.Right, R.Bottom - 1, 8, 8);
  C.Brush.Style := bsClear;
  S := FCategories[Index];
  Cnt := IntToStr(PtrInt(FCategories.Objects[Index]));
  C.Font.Size := 8;
  C.Font.Style := [];
  C.Font.Color := clrDim;
  TW := C.TextWidth(Cnt);
  TH := C.TextHeight(Cnt);
  C.TextOut(R.Right - 34 - TW, (R.Top + R.Bottom - TH) div 2, Cnt);
  C.Font.Size := 10;
  C.Font.Color := clrText;
  TH := C.TextHeight('Ag');
  C.TextOut(R.Left + 14, (R.Top + R.Bottom - TH) div 2, Ellipsize(C, S, R.Right - R.Left - 70 - TW));
  DrawIcon(C, ikChevron, Rect(R.Right - 28, R.Top + 6, R.Right - 6, R.Bottom - 6), clrDim, False);
  C.Brush.Style := bsSolid;
end;

procedure TChannelView.Paint;
var
  C: TCanvas;
  Cols, CW, CH, First, i, TW: Integer;
  R, TR: TRect;
begin
  C := Canvas;
  C.Brush.Style := bsSolid;
  C.Brush.Color := clrSide;
  C.FillRect(ClientRect);
  C.Font.Assign(Font);

  if ItemCount = 0 then
  begin
    if FEmptyText <> '' then
    begin
      C.Font.Size := 9;
      C.Font.Color := clrDim;
      C.Brush.Style := bsClear;
      TW := C.TextWidth(FEmptyText);
      C.TextOut(Math.Max(8, (ClientWidth - TW) div 2), 40, FEmptyText);
    end;
    Exit;
  end;

  Metrics(Cols, CW, CH);
  First := Math.Max(0, (FScrollY - PAD) div CH) * Cols;
  for i := First to ItemCount - 1 do
  begin
    R := ItemRect(i);
    if R.Top > ClientHeight then Break;
    if R.Bottom < 0 then Continue;
    if FCatMode then DrawCategory(C, i, R) else DrawChannel(C, i, R);
  end;

  TR := ThumbRect;
  if TR.Bottom > TR.Top then
  begin
    C.Brush.Style := bsSolid;
    if FDragThumb then C.Brush.Color := clrDim else C.Brush.Color := clrTrack;
    C.Pen.Color := C.Brush.Color;
    C.RoundRect(TR.Left, TR.Top, TR.Right, TR.Bottom, 4, 4);
  end;
end;

procedure TChannelView.Resize;
begin
  inherited Resize;
  ClampScroll;
  Invalidate;
end;

procedure TChannelView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Idx: Integer;
  TR: TRect;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then SetFocus;
  FDownIndex := -1;
  if X >= ClientWidth - SB_W then
  begin
    TR := ThumbRect;
    if (Button = mbLeft) and (TR.Bottom > TR.Top) then
    begin
      if (Y < TR.Top) or (Y > TR.Bottom) then
      begin
        { щелчок по дорожке — прокрутка на страницу }
        if Y < TR.Top then Dec(FScrollY, ClientHeight) else Inc(FScrollY, ClientHeight);
        ClampScroll;
        Invalidate;
      end;
      FDragThumb := True;
      FDragStartY := Y;
      FDragStartScroll := FScrollY;
    end;
    Exit;
  end;
  Idx := IndexAt(X, Y);
  FDownGuide := False;
  if Idx >= 0 then
  begin
    FSelected := Idx;
    FDownIndex := Idx;
    FDownGuide := HasGuideButton and PtInRect(GuideRect(ItemRect(Idx)), Point(X, Y));
    Invalidate;
  end;
end;

procedure TChannelView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Idx, Total: Integer;
  G: Boolean;
begin
  inherited MouseMove(Shift, X, Y);
  if FDragThumb then
  begin
    Total := ContentHeight;
    if ClientHeight > 0 then
      FScrollY := FDragStartScroll + Round((Y - FDragStartY) * Total / ClientHeight);
    ClampScroll;
    Invalidate;
    Exit;
  end;
  Idx := IndexAt(X, Y);
  G := (Idx >= 0) and HasGuideButton and PtInRect(GuideRect(ItemRect(Idx)), Point(X, Y));
  if (Idx <> FHover) or (G <> FHoverGuide) then
  begin
    FHover := Idx;
    FHoverGuide := G;
    Invalidate;
  end;
end;

procedure TChannelView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Idx: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FDragThumb then
  begin
    FDragThumb := False;
    Invalidate;
    Exit;
  end;
  if Button <> mbLeft then Exit;
  Idx := IndexAt(X, Y);
  if (Idx >= 0) and (Idx = FDownIndex) then
  begin
    if FDownGuide and PtInRect(GuideRect(ItemRect(Idx)), Point(X, Y)) then
    begin
      if Assigned(FOnGuideClick) then FOnGuideClick(Self, Idx);
    end
    else if Assigned(FOnItemClick) then
      FOnItemClick(Self, Idx);
  end;
  FDownIndex := -1;
  FDownGuide := False;
end;

procedure TChannelView.MouseLeave;
begin
  inherited MouseLeave;
  if FHover <> -1 then
  begin
    FHover := -1;
    Invalidate;
  end;
end;

procedure TChannelView.DblClick;
begin
  inherited DblClick;
  if (FSelected >= 0) and Assigned(FOnItemActivate) then
    FOnItemActivate(Self, FSelected);
end;

procedure TChannelView.KeyDown(var Key: Word; Shift: TShiftState);
var
  Cols, CW, CH, N, Rows: Integer;
begin
  inherited KeyDown(Key, Shift);
  if Key = 0 then Exit;
  if ItemCount = 0 then Exit;
  Metrics(Cols, CW, CH);
  N := FSelected;
  case Key of
    VK_UP:    if N < 0 then N := 0 else N := N - Cols;
    VK_DOWN:  if N < 0 then N := 0 else N := N + Cols;
    VK_LEFT:  if Cols > 1 then N := N - 1 else Exit;
    VK_RIGHT: if Cols > 1 then N := N + 1 else Exit;
    VK_HOME:  N := 0;
    VK_END:   N := ItemCount - 1;
    VK_RETURN:
      begin
        if (FSelected >= 0) and Assigned(FOnItemActivate) then FOnItemActivate(Self, FSelected);
        Key := 0;
        Exit;
      end;
  else
    Exit;
  end;
  Key := 0;
  Rows := ItemCount;
  if N < 0 then N := 0;
  if N >= Rows then N := Rows - 1;
  if N <> FSelected then
  begin
    FSelected := N;
    EnsureVisible(N);
    Invalidate;
    if Assigned(FOnSelectionMoved) then FOnSelectionMoved(Self, N);
  end;
end;

function TChannelView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  Cols, CW, CH: Integer;
begin
  Metrics(Cols, CW, CH);
  if WheelDelta > 0 then
    Dec(FScrollY, Math.Max(CH, 90))
  else
    Inc(FScrollY, Math.Max(CH, 90));
  ClampScroll;
  Invalidate;
  Result := True;
end;

end.
