{ Привязка окна видео VLC к панели программы. }
unit videohost;

{$mode objfpc}{$H+}

interface

uses
  Controls;

procedure AttachVideoTo(Player: Pointer; Host: TWinControl);

implementation

uses
  vlcdyn;

{$IFDEF LCLGTK2}
procedure gtk_widget_realize(widget: Pointer); cdecl; external 'gtk-x11-2.0';
function gtk_widget_get_window(widget: Pointer): Pointer; cdecl; external 'gtk-x11-2.0';
function gdk_x11_drawable_get_xid(drawable: Pointer): LongWord; cdecl; external 'gdk-x11-2.0';
{$ENDIF}

procedure AttachVideoTo(Player: Pointer; Host: TWinControl);
{$IFDEF LCLGTK2}
var
  W: Pointer;
  Xid: LongWord;
{$ENDIF}
begin
  if (Player = nil) or (Host = nil) then Exit;
{$IFDEF WINDOWS}
  libvlc_media_player_set_hwnd(Player, Pointer(Host.Handle));
{$ENDIF}
{$IFDEF LCLGTK2}
  W := Pointer(Host.Handle);
  if W = nil then Exit;
  gtk_widget_realize(W);
  Xid := 0;
  if gtk_widget_get_window(W) <> nil then
    Xid := gdk_x11_drawable_get_xid(gtk_widget_get_window(W));
  if Xid <> 0 then
    libvlc_media_player_set_xwindow(Player, Xid);
{$ENDIF}
end;

end.
