{ Своя рамка окна: перетаскивание за заголовок и изменение размера
  средствами самой системы (плавно, с привязкой к краям экрана). }
unit winframe;

{$mode objfpc}{$H+}

interface

uses
  Forms, Controls;

type
  TResizeEdge = (reLeft, reRight, reTop, reBottom,
                 reTopLeft, reTopRight, reBottomLeft, reBottomRight);

procedure BeginWindowMove(F: TCustomForm);
procedure BeginWindowResize(F: TCustomForm; Edge: TResizeEdge);
{ Возвращает окну без рамки кнопку на панели задач и сворачивание. }
procedure PrepareBorderless(F: TCustomForm);

implementation

{$IFDEF WINDOWS}
uses
  Windows, Messages;

procedure BeginWindowMove(F: TCustomForm);
begin
  SetCaptureControl(nil);
  Windows.ReleaseCapture;
  SendMessage(F.Handle, WM_SYSCOMMAND, $F012, 0);   { SC_MOVE + HTCAPTION }
end;

procedure BeginWindowResize(F: TCustomForm; Edge: TResizeEdge);
const
  Codes: array[TResizeEdge] of Integer = (1, 2, 3, 6, 4, 5, 7, 8);  { WMSZ_* }
begin
  SetCaptureControl(nil);
  Windows.ReleaseCapture;
  SendMessage(F.Handle, WM_SYSCOMMAND, $F000 + Codes[Edge], 0);    { SC_SIZE }
end;

procedure PrepareBorderless(F: TCustomForm);
var
  St: LongInt;
begin
  if not F.HandleAllocated then Exit;
  St := GetWindowLong(F.Handle, GWL_STYLE);
  SetWindowLong(F.Handle, GWL_STYLE, St or WS_MINIMIZEBOX or WS_SYSMENU);
end;
{$ELSE}
{$IFDEF LCLGTK2}
procedure gtk_window_begin_move_drag(window: Pointer; button, root_x, root_y: LongInt;
  timestamp: LongWord); cdecl; external 'gtk-x11-2.0';
procedure gtk_window_begin_resize_drag(window: Pointer; edge, button, root_x, root_y: LongInt;
  timestamp: LongWord); cdecl; external 'gtk-x11-2.0';
{$ENDIF}

procedure BeginWindowMove(F: TCustomForm);
begin
{$IFDEF LCLGTK2}
  SetCaptureControl(nil);
  gtk_window_begin_move_drag(Pointer(F.Handle), 1, Mouse.CursorPos.X, Mouse.CursorPos.Y, 0);
{$ENDIF}
end;

procedure BeginWindowResize(F: TCustomForm; Edge: TResizeEdge);
{$IFDEF LCLGTK2}
const
  { GdkWindowEdge }
  Codes: array[TResizeEdge] of Integer = (3, 4, 1, 6, 0, 2, 5, 7);
{$ENDIF}
begin
{$IFDEF LCLGTK2}
  SetCaptureControl(nil);
  gtk_window_begin_resize_drag(Pointer(F.Handle), Codes[Edge], 1,
    Mouse.CursorPos.X, Mouse.CursorPos.Y, 0);
{$ENDIF}
end;

procedure PrepareBorderless(F: TCustomForm);
begin
end;
{$ENDIF}

end.
