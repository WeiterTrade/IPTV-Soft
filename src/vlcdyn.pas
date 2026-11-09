{ Минимальная динамическая привязка к libVLC.
  Библиотека загружается во время работы программы, поэтому один и тот же
  исполняемый файл работает и с VLC 2.2 (Windows XP), и с VLC 3.x. }
unit vlcdyn;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, dynlibs{$IFDEF WINDOWS}, Windows{$ENDIF};

const
  VLC_STATE_NOTHING   = 0;
  VLC_STATE_OPENING   = 1;
  VLC_STATE_BUFFERING = 2;
  VLC_STATE_PLAYING   = 3;
  VLC_STATE_PAUSED    = 4;
  VLC_STATE_STOPPED   = 5;
  VLC_STATE_ENDED     = 6;
  VLC_STATE_ERROR     = 7;

var
  libvlc_new: function(argc: LongInt; argv: PPAnsiChar): Pointer; cdecl;
  libvlc_release: procedure(inst: Pointer); cdecl;
  libvlc_get_version: function: PAnsiChar; cdecl;
  libvlc_media_new_location: function(inst: Pointer; mrl: PAnsiChar): Pointer; cdecl;
  libvlc_media_new_path: function(inst: Pointer; path: PAnsiChar): Pointer; cdecl;
  libvlc_media_add_option: procedure(media: Pointer; option: PAnsiChar); cdecl;
  libvlc_media_release: procedure(media: Pointer); cdecl;
  libvlc_media_player_new: function(inst: Pointer): Pointer; cdecl;
  libvlc_media_player_release: procedure(mp: Pointer); cdecl;
  libvlc_media_player_set_media: procedure(mp, media: Pointer); cdecl;
  libvlc_media_player_play: function(mp: Pointer): LongInt; cdecl;
  libvlc_media_player_stop: procedure(mp: Pointer); cdecl;
  libvlc_media_player_get_state: function(mp: Pointer): LongInt; cdecl;
  libvlc_media_player_set_hwnd: procedure(mp: Pointer; drawable: Pointer); cdecl;
  libvlc_media_player_set_xwindow: procedure(mp: Pointer; drawable: LongWord); cdecl;
  libvlc_audio_set_volume: function(mp: Pointer; volume: LongInt): LongInt; cdecl;
  libvlc_audio_set_mute: procedure(mp: Pointer; status: LongInt); cdecl;
  libvlc_video_set_mouse_input: procedure(mp: Pointer; enable: LongWord); cdecl;
  libvlc_video_set_key_input: procedure(mp: Pointer; enable: LongWord); cdecl;

{ AppDir — папка программы (с завершающим разделителем). }
function LoadVlc(const AppDir: string; out ErrorMsg: string): Boolean;
function VlcVersion: string;

implementation

var
  VlcLib: TLibHandle = NilHandle;

function TryLoad(const FileName: string): TLibHandle;
begin
{$IFDEF WINDOWS}
  { LOAD_WITH_ALTERED_SEARCH_PATH = 8: зависимости (libvlccore.dll)
    ищутся в той же папке, что и libvlc.dll. Работает начиная с XP. }
  if Pos(PathDelim, FileName) > 0 then
    Result := TLibHandle(LoadLibraryExW(PWideChar(UTF8Decode(FileName)), 0, 8))
  else
    Result := dynlibs.LoadLibrary(FileName);
{$ELSE}
  Result := dynlibs.LoadLibrary(FileName);
{$ENDIF}
end;

function Need(const Name: AnsiString): Pointer;
begin
  Result := GetProcedureAddress(VlcLib, Name);
  if Result = nil then
    raise Exception.Create('в libVLC нет функции ' + Name);
end;

function LoadVlc(const AppDir: string; out ErrorMsg: string): Boolean;
var
  Candidates: array of string;
  i: Integer;
begin
  ErrorMsg := '';
  Result := VlcLib <> NilHandle;
  if Result then Exit;

{$IFDEF WINDOWS}
  SetLength(Candidates, 3);
  Candidates[0] := AppDir + 'libvlc.dll';
  Candidates[1] := AppDir + 'vlc' + PathDelim + 'libvlc.dll';
  Candidates[2] := 'libvlc.dll';
{$ELSE}
  SetLength(Candidates, 3);
  Candidates[0] := 'libvlc.so.5';
  Candidates[1] := 'libvlc.so';
  Candidates[2] := AppDir + 'libvlc.so.5';
{$ENDIF}

  for i := 0 to High(Candidates) do
  begin
    VlcLib := TryLoad(Candidates[i]);
    if VlcLib <> NilHandle then Break;
  end;

  if VlcLib = NilHandle then
  begin
{$IFDEF WINDOWS}
    ErrorMsg := 'Не найден libvlc.dll рядом с программой.';
{$ELSE}
    ErrorMsg := 'Не найдена библиотека libVLC. Установите пакет VLC (например: sudo apt install vlc).';
{$ENDIF}
    Exit;
  end;

  try
    Pointer(libvlc_new) := Need('libvlc_new');
    Pointer(libvlc_release) := Need('libvlc_release');
    Pointer(libvlc_get_version) := Need('libvlc_get_version');
    Pointer(libvlc_media_new_location) := Need('libvlc_media_new_location');
    Pointer(libvlc_media_new_path) := Need('libvlc_media_new_path');
    Pointer(libvlc_media_add_option) := Need('libvlc_media_add_option');
    Pointer(libvlc_media_release) := Need('libvlc_media_release');
    Pointer(libvlc_media_player_new) := Need('libvlc_media_player_new');
    Pointer(libvlc_media_player_release) := Need('libvlc_media_player_release');
    Pointer(libvlc_media_player_set_media) := Need('libvlc_media_player_set_media');
    Pointer(libvlc_media_player_play) := Need('libvlc_media_player_play');
    Pointer(libvlc_media_player_stop) := Need('libvlc_media_player_stop');
    Pointer(libvlc_media_player_get_state) := Need('libvlc_media_player_get_state');
    Pointer(libvlc_media_player_set_hwnd) := Need('libvlc_media_player_set_hwnd');
    Pointer(libvlc_media_player_set_xwindow) := Need('libvlc_media_player_set_xwindow');
    Pointer(libvlc_audio_set_volume) := Need('libvlc_audio_set_volume');
    Pointer(libvlc_audio_set_mute) := Need('libvlc_audio_set_mute');
    Pointer(libvlc_video_set_mouse_input) := Need('libvlc_video_set_mouse_input');
    Pointer(libvlc_video_set_key_input) := Need('libvlc_video_set_key_input');
    Result := True;
  except
    on E: Exception do
    begin
      ErrorMsg := 'Неподходящая версия libVLC: ' + E.Message;
      dynlibs.UnloadLibrary(VlcLib);
      VlcLib := NilHandle;
    end;
  end;
end;

function VlcVersion: string;
begin
  if (VlcLib <> NilHandle) and Assigned(libvlc_get_version) then
    Result := string(libvlc_get_version())
  else
    Result := '';
end;

end.
