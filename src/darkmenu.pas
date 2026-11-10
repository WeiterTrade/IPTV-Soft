{ Контекстные меню в цветах программы (тёмный фон, светлый текст,
  подсветка пункта под мышью). На Windows пункты рисуются программой;
  в Linux меню остаются системными (там их цвет задаёт тема). }
unit darkmenu;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Menus;

{ Вызывать после создания меню и каждый раз после добавления пунктов. }
procedure StyleMenu(PM: TPopupMenu);

implementation

uses
  Graphics, Types, LCLType, widgets{$IFDEF WINDOWS}, Windows{$ENDIF};

type
  TMenuPainter = class
    procedure Measure(Sender: TObject; ACanvas: TCanvas; var AWidth, AHeight: Integer);
    procedure Draw(Sender: TObject; ACanvas: TCanvas; ARect: Types.TRect; AState: LCLType.TOwnerDrawState);
  end;

var
  Painter: TMenuPainter = nil;

{$IFDEF WINDOWS}
type
  TDarkMenuInfo = record
    cbSize, fMask, dwStyle, cyMax: DWORD;
    hbrBack: HBRUSH;
    dwContextHelpID: DWORD;
    dwMenuData: PtrUInt;
  end;

const
  MIM_BACKGROUND = $00000002;
  MIM_APPLYTOSUBMENUS = $80000000;

function SetMenuInfo(hMenu: HMENU; const mi: TDarkMenuInfo): BOOL; stdcall; external 'user32.dll';

var
  MenuBrush: HBRUSH = 0;
{$ENDIF}

function ItemText(Mi: TMenuItem): string;
begin
  Result := StringReplace(Mi.Caption, '&&', #1, [rfReplaceAll]);
  Result := StringReplace(Result, '&', '', [rfReplaceAll]);
  Result := StringReplace(Result, #1, '&', [rfReplaceAll]);
end;

procedure TMenuPainter.Measure(Sender: TObject; ACanvas: TCanvas; var AWidth, AHeight: Integer);
var
  Mi: TMenuItem;
begin
  Mi := TMenuItem(Sender);
  if Mi.IsLine then
  begin
    AHeight := Sc(9);
    Exit;
  end;
  ACanvas.Font.Size := 9;
  AWidth := ACanvas.TextWidth(ItemText(Mi)) + Sc(54);
  if Mi.Count > 0 then Inc(AWidth, Sc(16));
  AHeight := Sc(30);
end;

procedure TMenuPainter.Draw(Sender: TObject; ACanvas: TCanvas; ARect: Types.TRect; AState: LCLType.TOwnerDrawState);
var
  Mi: TMenuItem;
  Y, X, H: Integer;
begin
  Mi := TMenuItem(Sender);
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := clrPanel;
  ACanvas.FillRect(ARect);
  if Mi.IsLine then
  begin
    Y := (ARect.Top + ARect.Bottom) div 2;
    ACanvas.Pen.Color := clrFrame;
    ACanvas.Pen.Width := 1;
    ACanvas.Line(ARect.Left + Sc(10), Y, ARect.Right - Sc(10), Y);
    Exit;
  end;
  if (LCLType.odSelected in AState) and Mi.Enabled then
  begin
    ACanvas.Brush.Color := clrHover;
    ACanvas.Pen.Color := clrHover;
    ACanvas.RoundRect(ARect.Left + 3, ARect.Top + 1, ARect.Right - 3, ARect.Bottom - 1, 6, 6);
    { тонкая полоска акцентного цвета слева }
    ACanvas.Brush.Color := clrAccent;
    ACanvas.FillRect(Types.Rect(ARect.Left + 3, ARect.Top + 6, ARect.Left + 6, ARect.Bottom - 6));
  end;
  H := ARect.Bottom - ARect.Top;
  X := ARect.Left + Sc(30);
  if Mi.Checked then
  begin
    ACanvas.Pen.Color := clrAccent;
    ACanvas.Pen.Width := 2;
    Y := ARect.Top + H div 2;
    if Mi.RadioItem then
    begin
      ACanvas.Brush.Color := clrAccent;
      ACanvas.Ellipse(ARect.Left + Sc(12), Y - 3, ARect.Left + Sc(12) + 7, Y + 4);
    end
    else
      ACanvas.Polyline([Types.Point(ARect.Left + Sc(11), Y), Types.Point(ARect.Left + Sc(14), Y + 3),
        Types.Point(ARect.Left + Sc(20), Y - 4)]);
    ACanvas.Pen.Width := 1;
  end;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Size := 9;
  ACanvas.Font.Style := [];
  if not Mi.Enabled then
    ACanvas.Font.Color := clrDisabled
  else if (LCLType.odSelected in AState) then
    ACanvas.Font.Color := clWhite
  else
    ACanvas.Font.Color := clrText;
  ACanvas.TextOut(X, ARect.Top + (H - ACanvas.TextHeight('Ag')) div 2, ItemText(Mi));
end;

procedure StyleItems(Mi: TMenuItem);
var
  i: Integer;
begin
  for i := 0 to Mi.Count - 1 do
  begin
    Mi.Items[i].OnMeasureItem := @Painter.Measure;
    Mi.Items[i].OnDrawItem := @Painter.Draw;
    if Mi.Items[i].Count > 0 then StyleItems(Mi.Items[i]);
  end;
end;

procedure StyleMenu(PM: TPopupMenu);
{$IFDEF WINDOWS}
var
  Info: TDarkMenuInfo;
{$ENDIF}
begin
  if PM = nil then Exit;
{$IFDEF WINDOWS}
  if Painter = nil then Painter := TMenuPainter.Create;
  PM.OwnerDraw := True;
  StyleItems(PM.Items);
  { фон самого меню (поля вокруг пунктов) — тоже тёмный }
  try
    if MenuBrush = 0 then MenuBrush := CreateSolidBrush(ColorToRGB(clrPanel));
    FillChar(Info, SizeOf(Info), 0);
    Info.cbSize := SizeOf(Info);
    Info.fMask := MIM_BACKGROUND or MIM_APPLYTOSUBMENUS;
    Info.hbrBack := MenuBrush;
    SetMenuInfo(PM.Handle, Info);
  except
  end;
{$ENDIF}
end;

finalization
  Painter.Free;

end.
