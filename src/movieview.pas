{ Сетка фильмов с постерами — как в онлайн-кинотеатрах. }
unit movieview;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, Math, LazUTF8,
  movies, widgets, logos, channelview;

type
  TMovieEvent = procedure(Sender: TObject; Index: Integer) of object;
  TMovieFavQuery = function(M: TMovie): Boolean of object;

  TMovieView = class(TCustomControl)
  private
    FItems: TFPList;
    FLogos: TLogoCache;
    FCurrent: TMovie;
    FScrollY, FSelected, FHover, FDownIndex: Integer;
    FLarge: Boolean;
    FDragThumb: Boolean;
    FDragStartY, FDragStartScroll: Integer;
    FEmptyText: string;
    FIsFavorite: TMovieFavQuery;
    FOnMovieClick, FOnMovieActivate: TMovieEvent;
    procedure Metrics(out Cols, CellW, CellH, PW, PH: Integer);
    function ViewW: Integer;
    function ContentHeight: Integer;
    function ItemRect(Index: Integer): TRect;
    function IndexAt(X, Y: Integer): Integer;
    function ThumbRect: TRect;
    procedure ClampScroll;
    procedure SetLarge(V: Boolean);
    procedure SetCurrent(V: TMovie);
    procedure DrawMovie(C: TCanvas; Index: Integer; const R: TRect);
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
    procedure SetMovies(List: TFPList);
    procedure ScrollToTop;
    procedure EnsureVisible(Index: Integer);
    function ItemCount: Integer;
    function MovieAt(Index: Integer): TMovie;
    function SelectedMovie: TMovie;
    function IndexOfMovie(M: TMovie): Integer;
    property Logos: TLogoCache read FLogos write FLogos;
    property Current: TMovie read FCurrent write SetCurrent;
    property Large: Boolean read FLarge write SetLarge;
    property EmptyText: string read FEmptyText write FEmptyText;
    property IsFavorite: TMovieFavQuery read FIsFavorite write FIsFavorite;
    property OnMovieClick: TMovieEvent read FOnMovieClick write FOnMovieClick;
    property OnMovieActivate: TMovieEvent read FOnMovieActivate write FOnMovieActivate;
    property PopupMenu;
    property Align;
    property BorderSpacing;
  end;

implementation

const
  SB_W = 10;
  PAD = 6;
  POSTER_COLORS: array[0..5] of TColor = (
    TColor($00503A2A), TColor($002A4A3A), TColor($00483050), TColor($00304858),
    TColor($00403A50), TColor($00384030));

constructor TMovieView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TFPList.Create;
  FSelected := -1;
  FHover := -1;
  FDownIndex := -1;
  TabStop := True;
  DoubleBuffered := True;
  Color := clrSide;
end;

destructor TMovieView.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TMovieView.SetMovies(List: TFPList);
var
  Old: TMovie;
begin
  Old := SelectedMovie;
  FItems.Clear;
  if List <> nil then FItems.Assign(List);
  FSelected := FItems.IndexOf(Old);
  FHover := -1;
  ClampScroll;
  Invalidate;
end;

function TMovieView.ItemCount: Integer;
begin
  Result := FItems.Count;
end;

function TMovieView.MovieAt(Index: Integer): TMovie;
begin
  if (Index < 0) or (Index >= FItems.Count) then Exit(nil);
  Result := TMovie(FItems[Index]);
end;

function TMovieView.SelectedMovie: TMovie;
begin
  Result := MovieAt(FSelected);
end;

function TMovieView.IndexOfMovie(M: TMovie): Integer;
begin
  Result := FItems.IndexOf(M);
end;

procedure TMovieView.SetLarge(V: Boolean);
begin
  if V = FLarge then Exit;
  FLarge := V;
  ClampScroll;
  Invalidate;
end;

procedure TMovieView.SetCurrent(V: TMovie);
begin
  if V = FCurrent then Exit;
  FCurrent := V;
  Invalidate;
end;

function TMovieView.ViewW: Integer;
begin
  Result := ClientWidth - SB_W;
  if Result < 60 then Result := 60;
end;

procedure TMovieView.Metrics(out Cols, CellW, CellH, PW, PH: Integer);
var
  W, Base: Integer;
begin
  W := ViewW - 2 * PAD;
  if FLarge then Base := 190 else Base := 150;
  Cols := Math.Max(1, W div Base);
  CellW := W div Cols;
  PW := CellW - 16;
  PH := PW * 3 div 2;
  CellH := PH + 60;
end;

function TMovieView.ContentHeight: Integer;
var
  Cols, CW, CH, PW, PH: Integer;
begin
  Metrics(Cols, CW, CH, PW, PH);
  Result := ((ItemCount + Cols - 1) div Cols) * CH + 2 * PAD;
end;

function TMovieView.ItemRect(Index: Integer): TRect;
var
  Cols, CW, CH, PW, PH: Integer;
begin
  Metrics(Cols, CW, CH, PW, PH);
  Result.Left := PAD + (Index mod Cols) * CW;
  Result.Top := PAD + (Index div Cols) * CH - FScrollY;
  Result.Right := Result.Left + CW;
  Result.Bottom := Result.Top + CH;
end;

function TMovieView.IndexAt(X, Y: Integer): Integer;
var
  Cols, CW, CH, PW, PH, Row, Col: Integer;
begin
  Result := -1;
  if (X >= ViewW) or (X < PAD) or (Y + FScrollY - PAD < 0) then Exit;
  Metrics(Cols, CW, CH, PW, PH);
  Row := (Y + FScrollY - PAD) div CH;
  Col := (X - PAD) div CW;
  if Col >= Cols then Exit;
  Result := Row * Cols + Col;
  if Result >= ItemCount then Result := -1;
end;

function TMovieView.ThumbRect: TRect;
var
  Total, H, T: Integer;
begin
  Total := ContentHeight;
  if Total <= ClientHeight then Exit(Rect(0, 0, 0, 0));
  H := Math.Max(30, ClientHeight * ClientHeight div Total);
  T := Round((ClientHeight - H) * FScrollY / Math.Max(1, Total - ClientHeight));
  Result := Rect(ClientWidth - SB_W + 3, T + 2, ClientWidth - 3, T + H - 2);
end;

procedure TMovieView.ClampScroll;
var
  MaxY: Integer;
begin
  MaxY := ContentHeight - ClientHeight;
  if MaxY < 0 then MaxY := 0;
  if FScrollY > MaxY then FScrollY := MaxY;
  if FScrollY < 0 then FScrollY := 0;
end;

procedure TMovieView.ScrollToTop;
begin
  FScrollY := 0;
  Invalidate;
end;

procedure TMovieView.EnsureVisible(Index: Integer);
var
  R: TRect;
begin
  if (Index < 0) or (Index >= ItemCount) then Exit;
  R := ItemRect(Index);
  if R.Top < 0 then Inc(FScrollY, R.Top - PAD)
  else if R.Bottom > ClientHeight then Inc(FScrollY, R.Bottom - ClientHeight + PAD);
  ClampScroll;
  Invalidate;
end;

procedure TMovieView.DrawMovie(C: TCanvas; Index: Integer; const R: TRect);
var
  M: TMovie;
  Cols, CW, CH, PW, PH, X, Y, TW: Integer;
  B: TBitmap;
  PR: TRect;
  S: string;
begin
  M := TMovie(FItems[Index]);
  Metrics(Cols, CW, CH, PW, PH);
  X := R.Left + (CW - PW) div 2;
  Y := R.Top + 6;
  PR := Rect(X, Y, X + PW, Y + PH);

  { подсветка выбранного / под мышью }
  if (Index = FSelected) or (Index = FHover) or (M = FCurrent) then
  begin
    C.Brush.Style := bsSolid;
    if Index = FSelected then C.Brush.Color := clrSel else C.Brush.Color := clrHover;
    if M = FCurrent then C.Pen.Color := clrAccent else C.Pen.Color := C.Brush.Color;
    C.Pen.Width := 2;
    C.RoundRect(R.Left + 2, R.Top + 1, R.Right - 2, R.Bottom - 1, 12, 12);
    C.Pen.Width := 1;
  end;

  B := nil;
  if (FLogos <> nil) and (M.Poster <> '') then
    B := FLogos.GetPoster(M.Poster, PW, PH, clrCard);
  if B <> nil then
    C.Draw(PR.Left, PR.Top, B)
  else
  begin
    { заглушка: цветной прямоугольник с названием }
    C.Brush.Style := bsSolid;
    C.Brush.Color := POSTER_COLORS[Length(M.Title) mod 6];
    C.Pen.Color := C.Brush.Color;
    C.RoundRect(PR.Left, PR.Top, PR.Right, PR.Bottom, 8, 8);
    C.Brush.Style := bsClear;
    C.Font.Size := 10;
    C.Font.Style := [fsBold];
    C.Font.Color := clrText;
    S := UTF8UpperCase(UTF8Copy(M.Title, 1, 1));
    C.Font.Height := -Math.Max(14, PW div 3);
    TW := C.TextWidth(S);
    C.TextOut((PR.Left + PR.Right - TW) div 2, PR.Top + PH div 3, S);
    C.Font.Height := 0;
  end;

  if Assigned(FIsFavorite) and FIsFavorite(M) then
    DrawIcon(C, ikStar, Rect(PR.Right - 26, PR.Top + 4, PR.Right - 4, PR.Top + 26), clrStar, True);
  if M.Sources.Count > 1 then
  begin
    { число источников }
    S := IntToStr(M.Sources.Count);
    C.Font.Size := 7;
    C.Font.Style := [fsBold];
    TW := C.TextWidth(S) + 10;
    C.Brush.Style := bsSolid;
    C.Brush.Color := clrBg;
    C.Pen.Color := clrBg;
    C.RoundRect(PR.Left + 4, PR.Top + 4, PR.Left + 4 + TW, PR.Top + 20, 8, 8);
    C.Brush.Style := bsClear;
    C.Font.Color := clrText;
    C.TextOut(PR.Left + 9, PR.Top + 5, S);
  end;

  { название и год }
  C.Brush.Style := bsClear;
  C.Font.Size := 9;
  C.Font.Style := [];
  if M = FCurrent then C.Font.Color := clrAccent else C.Font.Color := clrText;
  C.TextOut(PR.Left, PR.Bottom + 6, Ellipsize(C, M.Title, PW));
  C.Font.Size := 8;
  C.Font.Color := clrDim;
  S := M.Year;
  if (M.Groups.Count > 0) then
  begin
    if S <> '' then S := S + ' · ';
    S := S + M.Groups[0];
  end;
  C.TextOut(PR.Left, PR.Bottom + 26, Ellipsize(C, S, PW));
end;

procedure TMovieView.Paint;
var
  C: TCanvas;
  Cols, CW, CH, PW, PH, First, i, TW: Integer;
  R, TR: TRect;
begin
  C := Canvas;
  C.Brush.Style := bsSolid;
  C.Brush.Color := clrSide;
  C.FillRect(ClientRect);
  C.Font.Assign(Font);
  if ItemCount = 0 then
  begin
    C.Font.Size := 9;
    C.Font.Color := clrDim;
    C.Brush.Style := bsClear;
    TW := C.TextWidth(FEmptyText);
    C.TextOut(Math.Max(8, (ClientWidth - TW) div 2), 40, FEmptyText);
    Exit;
  end;
  Metrics(Cols, CW, CH, PW, PH);
  First := Math.Max(0, (FScrollY - PAD) div CH) * Cols;
  for i := First to ItemCount - 1 do
  begin
    R := ItemRect(i);
    if R.Top > ClientHeight then Break;
    if R.Bottom < 0 then Continue;
    DrawMovie(C, i, R);
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

procedure TMovieView.Resize;
begin
  inherited Resize;
  ClampScroll;
  Invalidate;
end;

procedure TMovieView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
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
      if Y < TR.Top then Dec(FScrollY, ClientHeight)
      else if Y > TR.Bottom then Inc(FScrollY, ClientHeight);
      ClampScroll;
      FDragThumb := True;
      FDragStartY := Y;
      FDragStartScroll := FScrollY;
      Invalidate;
    end;
    Exit;
  end;
  Idx := IndexAt(X, Y);
  if Idx >= 0 then
  begin
    FSelected := Idx;
    FDownIndex := Idx;
    Invalidate;
  end;
end;

procedure TMovieView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Idx: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if FDragThumb then
  begin
    if ClientHeight > 0 then
      FScrollY := FDragStartScroll + Round((Y - FDragStartY) * ContentHeight / ClientHeight);
    ClampScroll;
    Invalidate;
    Exit;
  end;
  Idx := IndexAt(X, Y);
  if Idx <> FHover then
  begin
    FHover := Idx;
    Invalidate;
  end;
end;

procedure TMovieView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
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
  if (Idx >= 0) and (Idx = FDownIndex) and Assigned(FOnMovieClick) then
    FOnMovieClick(Self, Idx);
  FDownIndex := -1;
end;

procedure TMovieView.MouseLeave;
begin
  inherited MouseLeave;
  if FHover <> -1 then
  begin
    FHover := -1;
    Invalidate;
  end;
end;

procedure TMovieView.DblClick;
begin
  inherited DblClick;
  if (FSelected >= 0) and Assigned(FOnMovieActivate) then FOnMovieActivate(Self, FSelected);
end;

procedure TMovieView.KeyDown(var Key: Word; Shift: TShiftState);
var
  Cols, CW, CH, PW, PH, N: Integer;
begin
  inherited KeyDown(Key, Shift);
  if (Key = 0) or (ItemCount = 0) then Exit;
  Metrics(Cols, CW, CH, PW, PH);
  N := FSelected;
  case Key of
    VK_LEFT: Dec(N);
    VK_RIGHT: Inc(N);
    VK_UP: Dec(N, Cols);
    VK_DOWN: Inc(N, Cols);
    VK_HOME: N := 0;
    VK_END: N := ItemCount - 1;
    VK_RETURN:
      begin
        if (FSelected >= 0) and Assigned(FOnMovieActivate) then FOnMovieActivate(Self, FSelected);
        Key := 0;
        Exit;
      end;
  else
    Exit;
  end;
  Key := 0;
  if N < 0 then N := 0;
  if N >= ItemCount then N := ItemCount - 1;
  FSelected := N;
  EnsureVisible(N);
  Invalidate;
end;

function TMovieView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  Cols, CW, CH, PW, PH: Integer;
begin
  Metrics(Cols, CW, CH, PW, PH);
  if WheelDelta > 0 then Dec(FScrollY, CH div 2) else Inc(FScrollY, CH div 2);
  ClampScroll;
  Invalidate;
  Result := True;
end;

end.
