{ Телепрограмма канала: список передач по дням с отметками
  «сейчас в эфире» и «архив» (можно посмотреть прошедшую передачу). }
unit guideview;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, Math,
  epg, widgets, channelview;

type
  TGuideEvent = procedure(Sender: TObject; Item: TEpgItem) of object;

  TGuideRow = class
  public
    IsDay: Boolean;
    Item: TEpgItem;
    Text: string;
    Top, Height: Integer;
  end;

  TGuideView = class(TCustomControl)
  private
    FRows: TFPList;
    FContentH: Integer;
    FScrollY, FSelected, FHover: Integer;
    FNowUtc: TDateTime;
    FArchive: Boolean;
    FArchiveFrom: TDateTime;
    FPlayingStart: TDateTime;
    FEmptyText: string;
    FDragThumb: Boolean;
    FDragStartY, FDragStartScroll, FDownRow: Integer;
    FOnItemClick, FOnItemActivate, FOnSelect: TGuideEvent;
    procedure ClearRows;
    function RowAt(Y: Integer): Integer;
    function ThumbRect: TRect;
    procedure ClampScroll;
    procedure EnsureVisible(Row: Integer);
    procedure MoveSelection(Delta: Integer);
    function SelectableRow(Row: Integer): Boolean;
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
    { Ch = nil — телепрограммы нет. ArchiveDays = 0 — архива нет. }
    procedure SetData(Ch: TEpgChannel; ArchiveDays: Integer; ANowUtc: TDateTime);
    procedure ScrollToNow;
    function SelectedItem: TEpgItem;
    function IsLive(It: TEpgItem): Boolean;
    function IsArchive(It: TEpgItem): Boolean;
    function IsFuture(It: TEpgItem): Boolean;
    property NowUtc: TDateTime read FNowUtc write FNowUtc;
    property PlayingStart: TDateTime read FPlayingStart write FPlayingStart;
    property EmptyText: string read FEmptyText write FEmptyText;
    property OnItemClick: TGuideEvent read FOnItemClick write FOnItemClick;
    property OnItemActivate: TGuideEvent read FOnItemActivate write FOnItemActivate;
    property OnSelect: TGuideEvent read FOnSelect write FOnSelect;
    property Align;
    property BorderSpacing;
    property PopupMenu;
  end;

function DayTitle(LocalDay: TDateTime): string;

implementation

const
  SB_W = 10;
  DAY_H = 32;
  PROG_H = 48;
  DAY_NAMES: array[1..7] of string =
    ('воскресенье', 'понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота');
  MONTH_NAMES: array[1..12] of string =
    ('января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа',
     'сентября', 'октября', 'ноября', 'декабря');

function DayTitle(LocalDay: TDateTime): string;
var
  Today: TDateTime;
  Y, M, D: Word;
begin
  Today := Trunc(Now);
  DecodeDate(LocalDay, Y, M, D);
  Result := IntToStr(D) + ' ' + MONTH_NAMES[M] + ', ' + DAY_NAMES[DayOfWeek(LocalDay)];
  if Trunc(LocalDay) = Today then Result := 'Сегодня, ' + Result
  else if Trunc(LocalDay) = Today - 1 then Result := 'Вчера, ' + Result
  else if Trunc(LocalDay) = Today + 1 then Result := 'Завтра, ' + Result;
end;

{ TGuideView }

constructor TGuideView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRows := TFPList.Create;
  FSelected := -1;
  FHover := -1;
  FDownRow := -1;
  TabStop := True;
  DoubleBuffered := True;
  Color := clrSide;
end;

destructor TGuideView.Destroy;
begin
  ClearRows;
  FRows.Free;
  inherited Destroy;
end;

procedure TGuideView.ClearRows;
var
  i: Integer;
begin
  for i := 0 to FRows.Count - 1 do
    TGuideRow(FRows[i]).Free;
  FRows.Clear;
  FContentH := 0;
end;

procedure TGuideView.SetData(Ch: TEpgChannel; ArchiveDays: Integer; ANowUtc: TDateTime);
var
  i, Y: Integer;
  It: TEpgItem;
  LastDay, Day: TDateTime;
  R: TGuideRow;
begin
  ClearRows;
  FNowUtc := ANowUtc;
  FArchive := ArchiveDays > 0;
  FArchiveFrom := ANowUtc - ArchiveDays;
  FSelected := -1;
  FHover := -1;
  FScrollY := 0;
  Y := 4;
  LastDay := -1;
  if Ch <> nil then
    for i := 0 to Ch.Items.Count - 1 do
    begin
      It := TEpgItem(Ch.Items[i]);
      Day := Trunc(UtcToLocal(It.Start));
      if Day <> LastDay then
      begin
        LastDay := Day;
        R := TGuideRow.Create;
        R.IsDay := True;
        R.Text := DayTitle(Day);
        R.Top := Y;
        R.Height := DAY_H;
        Inc(Y, DAY_H);
        FRows.Add(R);
      end;
      R := TGuideRow.Create;
      R.Item := It;
      R.Top := Y;
      R.Height := PROG_H;
      Inc(Y, PROG_H);
      FRows.Add(R);
    end;
  FContentH := Y + 4;
  Invalidate;
end;

function TGuideView.IsLive(It: TEpgItem): Boolean;
begin
  Result := (It <> nil) and (It.Start <= FNowUtc) and (FNowUtc < It.Stop);
end;

function TGuideView.IsArchive(It: TEpgItem): Boolean;
begin
  Result := FArchive and (It <> nil) and (It.Stop <= FNowUtc) and (It.Start >= FArchiveFrom);
end;

function TGuideView.IsFuture(It: TEpgItem): Boolean;
begin
  Result := (It <> nil) and (It.Start > FNowUtc);
end;

function TGuideView.SelectedItem: TEpgItem;
begin
  if (FSelected >= 0) and (FSelected < FRows.Count) then
    Result := TGuideRow(FRows[FSelected]).Item
  else
    Result := nil;
end;

function TGuideView.SelectableRow(Row: Integer): Boolean;
begin
  Result := (Row >= 0) and (Row < FRows.Count) and not TGuideRow(FRows[Row]).IsDay;
end;

procedure TGuideView.ScrollToNow;
var
  i: Integer;
  R: TGuideRow;
begin
  for i := 0 to FRows.Count - 1 do
  begin
    R := TGuideRow(FRows[i]);
    if (not R.IsDay) and (R.Item.Stop > FNowUtc) then
    begin
      FSelected := i;
      FScrollY := R.Top - ClientHeight div 3;
      ClampScroll;
      Invalidate;
      if Assigned(FOnSelect) then FOnSelect(Self, R.Item);
      Exit;
    end;
  end;
  FScrollY := Math.Max(0, FContentH - ClientHeight);
  Invalidate;
end;

function TGuideView.RowAt(Y: Integer): Integer;
var
  i, YY: Integer;
  R: TGuideRow;
begin
  Result := -1;
  YY := Y + FScrollY;
  for i := 0 to FRows.Count - 1 do
  begin
    R := TGuideRow(FRows[i]);
    if (YY >= R.Top) and (YY < R.Top + R.Height) then
      Exit(i);
  end;
end;

function TGuideView.ThumbRect: TRect;
var
  H, T: Integer;
begin
  if FContentH <= ClientHeight then Exit(Rect(0, 0, 0, 0));
  H := Math.Max(30, ClientHeight * ClientHeight div FContentH);
  T := Round((ClientHeight - H) * FScrollY / Math.Max(1, FContentH - ClientHeight));
  Result := Rect(ClientWidth - SB_W + 3, T + 2, ClientWidth - 3, T + H - 2);
end;

procedure TGuideView.ClampScroll;
var
  MaxY: Integer;
begin
  MaxY := FContentH - ClientHeight;
  if MaxY < 0 then MaxY := 0;
  if FScrollY > MaxY then FScrollY := MaxY;
  if FScrollY < 0 then FScrollY := 0;
end;

procedure TGuideView.EnsureVisible(Row: Integer);
var
  R: TGuideRow;
begin
  if (Row < 0) or (Row >= FRows.Count) then Exit;
  R := TGuideRow(FRows[Row]);
  if R.Top - FScrollY < 0 then FScrollY := R.Top - DAY_H
  else if R.Top + R.Height - FScrollY > ClientHeight then FScrollY := R.Top + R.Height - ClientHeight;
  ClampScroll;
end;

procedure TGuideView.MoveSelection(Delta: Integer);
var
  N: Integer;
begin
  N := FSelected;
  repeat
    N := N + Delta;
  until (N < 0) or (N >= FRows.Count) or SelectableRow(N);
  if SelectableRow(N) then
  begin
    FSelected := N;
    EnsureVisible(N);
    Invalidate;
    if Assigned(FOnSelect) then FOnSelect(Self, SelectedItem);
  end;
end;

procedure TGuideView.Paint;
var
  C: TCanvas;
  i, X, Y, W, TH: Integer;
  R: TGuideRow;
  RR, TR: TRect;
  It: TEpgItem;
  Live, Arch, Fut, Playing: Boolean;
  S, Lbl: string;
  Frac: Double;
begin
  C := Canvas;
  C.Brush.Style := bsSolid;
  C.Brush.Color := clrSide;
  C.FillRect(ClientRect);
  C.Font.Assign(Font);

  if FRows.Count = 0 then
  begin
    C.Font.Size := 9;
    C.Font.Color := clrDim;
    C.Brush.Style := bsClear;
    C.TextOut(14, 30, Ellipsize(C, FEmptyText, ClientWidth - 28));
    Exit;
  end;

  W := ClientWidth - SB_W;
  for i := 0 to FRows.Count - 1 do
  begin
    R := TGuideRow(FRows[i]);
    Y := R.Top - FScrollY;
    if Y > ClientHeight then Break;
    if Y + R.Height < 0 then Continue;
    RR := Rect(6, Y, W - 4, Y + R.Height);

    if R.IsDay then
    begin
      C.Brush.Style := bsClear;
      C.Font.Size := 9;
      C.Font.Style := [fsBold];
      C.Font.Color := clrAccent;
      TH := C.TextHeight('Ag');
      C.TextOut(RR.Left + 8, RR.Bottom - TH - 6, R.Text);
      Continue;
    end;

    It := R.Item;
    Live := IsLive(It);
    Arch := IsArchive(It);
    Fut := IsFuture(It);
    Playing := (FPlayingStart <> 0) and (Abs(It.Start - FPlayingStart) < 1 / 86400);

    C.Brush.Style := bsSolid;
    if i = FSelected then C.Brush.Color := clrSel
    else if i = FHover then C.Brush.Color := clrHover
    else if Live then C.Brush.Color := clrCard
    else C.Brush.Color := clrSide;
    C.Pen.Color := C.Brush.Color;
    C.RoundRect(RR.Left, RR.Top + 1, RR.Right, RR.Bottom - 1, 8, 8);
    if Playing or (Live and (FPlayingStart = 0)) then
    begin
      C.Brush.Color := clrAccent;
      C.FillRect(Rect(RR.Left, RR.Top + 9, RR.Left + 3, RR.Bottom - 9));
    end;
    C.Brush.Style := bsClear;

    { время }
    X := RR.Left + 12;
    C.Font.Size := 9;
    C.Font.Style := [];
    if Live then C.Font.Color := clrAccent
    else if Fut then C.Font.Color := clrText
    else C.Font.Color := clrDim;
    S := FormatDateTime('hh:nn', UtcToLocal(It.Start));
    C.TextOut(X, RR.Top + 7, S);

    { название }
    X := RR.Left + 64;
    C.Font.Size := 10;
    if Live then C.Font.Style := [fsBold] else C.Font.Style := [];
    if Fut or Live or Arch then C.Font.Color := clrText else C.Font.Color := clrDim;
    C.TextOut(X, RR.Top + 6, Ellipsize(C, It.Title, RR.Right - X - 10));

    { вторая строка }
    C.Font.Size := 8;
    C.Font.Style := [];
    TH := RR.Top + 6 + 20;
    if Live then
    begin
      Frac := (FNowUtc - It.Start) / Math.Max(1e-9, It.Stop - It.Start);
      if Frac < 0 then Frac := 0;
      if Frac > 1 then Frac := 1;
      C.Brush.Style := bsSolid;
      C.Brush.Color := clrTrack;
      C.FillRect(Rect(X, TH + 6, RR.Right - 70, TH + 9));
      C.Brush.Color := clrAccent;
      C.FillRect(Rect(X, TH + 6, X + Round((RR.Right - 70 - X) * Frac), TH + 9));
      C.Brush.Style := bsClear;
      C.Font.Color := clrAccent;
      C.TextOut(RR.Right - 62, TH, 'в эфире');
    end
    else if Arch then
    begin
      DrawIcon(C, ikPlay, Rect(X - 4, TH - 3, X + 16, TH + 17), clrAccent, True);
      C.Brush.Style := bsClear;
      C.Font.Color := clrAccent;
      if Playing then Lbl := 'смотрите сейчас (архив)' else Lbl := 'смотреть в записи';
      C.TextOut(X + 16, TH, Lbl + '  ·  до ' + FormatDateTime('hh:nn', UtcToLocal(It.Stop)));
    end
    else
    begin
      C.Font.Color := clrDim;
      C.TextOut(X, TH, 'до ' + FormatDateTime('hh:nn', UtcToLocal(It.Stop)));
    end;
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

procedure TGuideView.Resize;
begin
  inherited Resize;
  ClampScroll;
  Invalidate;
end;

procedure TGuideView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Row: Integer;
  TR: TRect;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then SetFocus;
  FDownRow := -1;
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
  Row := RowAt(Y);
  if SelectableRow(Row) then
  begin
    FSelected := Row;
    FDownRow := Row;
    Invalidate;
    if Assigned(FOnSelect) then FOnSelect(Self, SelectedItem);
  end;
end;

procedure TGuideView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Row: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if FDragThumb then
  begin
    if ClientHeight > 0 then
      FScrollY := FDragStartScroll + Round((Y - FDragStartY) * FContentH / ClientHeight);
    ClampScroll;
    Invalidate;
    Exit;
  end;
  Row := RowAt(Y);
  if not SelectableRow(Row) then Row := -1;
  if Row <> FHover then
  begin
    FHover := Row;
    Invalidate;
  end;
end;

procedure TGuideView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Row: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if FDragThumb then
  begin
    FDragThumb := False;
    Invalidate;
    Exit;
  end;
  if Button <> mbLeft then Exit;
  Row := RowAt(Y);
  if (Row >= 0) and (Row = FDownRow) and Assigned(FOnItemClick) then
    FOnItemClick(Self, SelectedItem);
  FDownRow := -1;
end;

procedure TGuideView.MouseLeave;
begin
  inherited MouseLeave;
  if FHover <> -1 then
  begin
    FHover := -1;
    Invalidate;
  end;
end;

procedure TGuideView.DblClick;
begin
  inherited DblClick;
  if (SelectedItem <> nil) and Assigned(FOnItemActivate) then
    FOnItemActivate(Self, SelectedItem);
end;

procedure TGuideView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_UP:
      begin
        MoveSelection(-1);
        Key := 0;
      end;
    VK_DOWN:
      begin
        MoveSelection(1);
        Key := 0;
      end;
    VK_RETURN:
      begin
        if (SelectedItem <> nil) and Assigned(FOnItemActivate) then
          FOnItemActivate(Self, SelectedItem);
        Key := 0;
      end;
  end;
end;

function TGuideView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  if WheelDelta > 0 then Dec(FScrollY, PROG_H * 2) else Inc(FScrollY, PROG_H * 2);
  ClampScroll;
  Invalidate;
  Result := True;
end;

end.
