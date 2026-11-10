{ Главное окно IPTV Aristocrat. Интерфейс создаётся кодом. }
unit mainform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
  Menus, Dialogs, LCLType, Clipbrd, Math, LazUTF8, FileUtil, Process,
  m3u, epg, vlcdyn, netload, appsettings, widgets, playlistdlg, videohost,
  channelview, logos, winframe, settingspage, applog, guideview, catchup, logodb;

type
  TLoadKind = (lkPlaylist, lkEpg);

  { Фоновая загрузка плейлиста или телепрограммы }
  TLoaderThread = class(TThread)
  private
    function Fetch(const ASource, ACache: string; MaxAgeHours: Double; out Err: string): Boolean;
  public
    Kind: TLoadKind;
    Source: string;
    Sources: TStringList;
    Want: TStringList;       { каналы плейлиста: id#1tvg-name#1имя }
    PastDays: Integer;
    CacheOnly: Boolean;      { только прочитать сохранённую копию плейлиста }
    Refresh: Boolean;        { фоновое обновление после показа копии }
    Unchanged: Boolean;      { плейлист на сервере не изменился }
    CacheDir: string;
    Force: Boolean;
    Generation: Integer;
    Playlist: TPlaylistData;
    Epg: TEpgData;
    ErrorMsg, Warning: string;
    Ok: Boolean;
    constructor Create;
    destructor Destroy; override;
  protected
    procedure Execute; override;
  end;

  TMainForm = class(TForm)
  private
    FSettings: TAppSettings;
    FPlaylist: TPlaylistData;
    FEpg: TEpgData;
    FEpgKey: string;
    FLogos: TLogoCache;
    FView: TFPList;
    FCurrent: TChannel;
    FCurrentUrl: string;
    FPlaying: Boolean;
    FVlc, FPlayer: Pointer;
    FVlcError: string;
    FLastState: Integer;
    { окно }
    FSystemFrame: Boolean;
    FMaxed: Boolean;
    FNormalBounds: TRect;
    FFullscreen: Boolean;
    FFullPrevBounds: TRect;
    FFullPrevState: TWindowState;
    { категории }
    FCategory: string;
    FCategoryNone: Boolean;
    FInCategory: Boolean;
    { запись }
    FRecPlayer: Pointer;
    FRecFile, FRecName: string;
    FRecStart: TDateTime;
    { архив и телепрограмма }
    FArchive: Boolean;
    FArchiveStart, FArchiveStop: TDateTime;
    FArchiveTitle: string;
    FGuideOpen: Boolean;
    FGuideChannel: TChannel;
    FInfoOffset, FInfoIdle: Integer;
    FInfoItems: array of TEpgItem;     { передачи, показанные в расписании под видео }
    FInfoLinesTop, FInfoLineH, FInfoX: Integer;
    { «все каналы на весь экран» }
    FWall: Boolean;
    FWallPrevMode: TViewMode;
    FWallSideWidth: Integer;
    FAlignOff: Boolean;
    { настройки внутри окна и база логотипов }
    pgSettings: TSettingsPage;
    FSettingsOpen: Boolean;
    FSettingsOldFrame, FSettingsOldProxy: Boolean;
    FLogoDb: TLogoDb;
    FLogoDbLoading: Boolean;
    { разное }
    FPlGen, FEpgGen: Integer;
    FUpdating, FAutoPlayDone, FForceEpg, FShown: Boolean;
    FTick: Integer;
    FNowUtc: TDateTime;
    FPlayerStatus, FInfoText: string;

    { элементы }
    gripTop, gripBottom, gripLeft, gripRight: TPanel;
    pnlRoot, pnlTitle, pnlSide, pnlPl, pnlViewRow, pnlBack, pnlMain, pnlVideo, pnlInfo, pnlControls: TPanel;
    pnlBottom: TPanel;
    FSlots: array[0..3] of TPanel;   { отдельная область видео для каждого плеера }
    FSlot: Integer;
    splInfo: TSplitter;
    pbTitle, pbInfo, pbLogo: TPaintBox;
    btnMenuSettings: TFlatButton;
    btnWinMin, btnWinMax, btnWinClose: TFlatButton;
    splSide: TSplitter;
    segTabs: TSegmentBar;
    cbPlaylists: TComboBox;
    btnAdd, btnEdit, btnRemove, btnReload: TFlatButton;
    edSearch: TEdit;
    btnViewList, btnViewCompact, btnViewGrid, btnViewTiles, btnBack: TFlatButton;
    lblCount, lblBack, lblEmpty, lblStatus, lblRec: TLabel;
    chView: TChannelView;
    pnlGuide, pnlGuideHead: TPanel;
    btnGuideBack, btnLive: TFlatButton;
    lblGuideTitle, lblGuideDesc: TLabel;
    guide: TGuideView;
    btnInfoUp, btnInfoDown, btnWall: TFlatButton;
    btnPrev, btnStop, btnNext, btnFav, btnRec, btnExt, btnMute, btnFull, btnSettings: TFlatButton;
    sldVolume: TFlatSlider;
    tmrStatus, tmrSelect, tmrSearch: TTimer;
    pmChannel: TPopupMenu;
    miPlay, miGuide, miExternal, miRecord, miFav, miCopy: TMenuItem;

    procedure BuildUI;
    function AcquireSlot: Integer;
    procedure BuildFrame;
    function MakeButton(AParent: TWinControl; AKind: TIconKind; AAlign: TAlign;
      const AHint: string; AHandler: TNotifyEvent): TFlatButton;
    function MakePanel(AParent: TWinControl; AAlign: TAlign; AColor: TColor; AHeight: Integer): TPanel;
    function MakeGrip(AAlign: TAlign; ACursor: TCursor): TPanel;
    procedure InitVlc;
    procedure ApplyVolume;
    procedure ApplyViewSettings;
    procedure InvalidateAll(C: TWinControl);
    procedure UpdateStatusLabel;
    procedure SetInfo(const S: string);
    procedure UpdateTransport;
    procedure UpdateEmptyState;
    procedure UpdateViewButtons;
    procedure UpdateFrameControls;

    procedure RefreshPlaylistCombo;
    procedure LoadPlaylist(Index: Integer; ForceEpg: Boolean);
    procedure LoadEpg(Force: Boolean);
    procedure LoaderDone(Sender: TObject);
    procedure ResolveEpg;
    procedure ApplyFilter;
    procedure OpenCategory(Index: Integer);

    procedure PlayChannel(Ch: TChannel; ForceInternal: Boolean = False);
    function StartMedia(Ch: TChannel; const Url: string): Boolean;
    procedure AfterPlayStarted(Ch: TChannel);
    procedure PlayArchive(Ch: TChannel; It: TEpgItem);
    procedure OpenGuide(Ch: TChannel);
    procedure RefreshGuide;
    procedure CloseGuide;
    procedure UpdateGuideDesc(It: TEpgItem);
    procedure OpenExternal(Ch: TChannel; const AUrl: string = '');
    procedure SetChannelWall(Value: Boolean);
    procedure UpdateSideMax;
    function InfoItem(Offset: Integer): TEpgItem;
    function ItemInArchive(Ch: TChannel; It: TEpgItem): Boolean;
    procedure StopPlayback;
    procedure StepChannel(Delta: Integer);
    procedure SetFullscreen(Value: Boolean);
    procedure SetMaximized(Value: Boolean);
    procedure ToggleMute;
    procedure ToggleFavorite(Ch: TChannel);
    procedure StartRecording(Ch: TChannel);
    procedure StopRecording(const Reason: string);
    procedure OpenSettings(Page: Integer);
    procedure CloseSettings;
    procedure PlaceSettings;
    procedure ApplyAfterImport;
    procedure ResolveLogos;
    procedure StartLogoDb;
    procedure LoadPlaylistRefresh(Index: Integer);
    function IsFav(Ch: TChannel): Boolean;
    function TargetChannel: TChannel;

    { обработчики }
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TitleMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure TitlePaint(Sender: TObject);
    procedure GripMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure GripMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure WinMinClick(Sender: TObject);
    procedure WinMaxClick(Sender: TObject);
    procedure WinCloseClick(Sender: TObject);
    procedure TabsChange(Sender: TObject);
    procedure BackClick(Sender: TObject);
    procedure ViewModeClick(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure EditClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure ReloadClick(Sender: TObject);
    procedure PrevClick(Sender: TObject);
    procedure NextClick(Sender: TObject);
    procedure StopClick(Sender: TObject);
    procedure FavClick(Sender: TObject);
    procedure RecClick(Sender: TObject);
    procedure ExtClick(Sender: TObject);
    procedure MuteClick(Sender: TObject);
    procedure FullClick(Sender: TObject);
    procedure SettingsClick(Sender: TObject);
    procedure SettingsPageClose(Sender: TObject);
    procedure SettingsPageImported(Sender: TObject);
    procedure SettingsClearLogos(Sender: TObject);
    procedure LogoDbDone(Sender: TObject);
    procedure LogoPaint(Sender: TObject);
    procedure VolumeChange(Sender: TObject);
    procedure PlaylistChange(Sender: TObject);
    procedure SearchChange(Sender: TObject);
    procedure ViewItemClick(Sender: TObject; Index: Integer);
    procedure ViewItemActivate(Sender: TObject; Index: Integer);
    procedure ViewSelectionMoved(Sender: TObject; Index: Integer);
    procedure VideoDblClick(Sender: TObject);
    procedure InfoPaint(Sender: TObject);
    procedure LiveClick(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure FormWindowStateChange(Sender: TObject);
    procedure WallClick(Sender: TObject);
    procedure InfoUpClick(Sender: TObject);
    procedure InfoDownClick(Sender: TObject);
    procedure InfoWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
    procedure InfoClick(Sender: TObject);
    procedure InfoDblClick(Sender: TObject);
    procedure GuideBackClick(Sender: TObject);
    procedure GuideSelect(Sender: TObject; Item: TEpgItem);
    procedure GuideItemClick(Sender: TObject; Item: TEpgItem);
    procedure ViewGuideClick(Sender: TObject; Index: Integer);
    procedure MenuGuideClick(Sender: TObject);
    procedure StatusTimer(Sender: TObject);
    procedure SelectTimer(Sender: TObject);
    procedure SearchTimer(Sender: TObject);
    procedure MenuPopup(Sender: TObject);
    procedure MenuPlayClick(Sender: TObject);
    procedure MenuExternalClick(Sender: TObject);
    procedure MenuRecordClick(Sender: TObject);
    procedure MenuFavClick(Sender: TObject);
    procedure MenuCopyClick(Sender: TObject);
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  AppMainForm: TMainForm;

implementation

const
  APP_NAME = 'IPTV Aristocrat';
  TAB_FAV = 0;
  TAB_ALL = 1;
  TAB_CAT = 2;
  NO_CATEGORY = 'Без категории';
  GRIP = 5;

var
  GFormAlive: Boolean = False;
  GPendingReleases: LongInt = 0;

const
  VIDEO_SLOTS = 4;

var
  { 1 — в области видео ещё работает (или останавливается) плеер }
  GSlotBusy: array[0..VIDEO_SLOTS - 1] of LongInt;

type
  { Остановка и освобождение плеера VLC в фоне (stop может занимать секунды) }
  TReleaseThread = class(TThread)
  public
    P: Pointer;
    Slot: Integer;
  protected
    procedure Execute; override;
  end;

procedure TReleaseThread.Execute;
begin
  try
    libvlc_media_player_stop(P);
    libvlc_media_player_release(P);
  except
  end;
  if (Slot >= 0) and (Slot < VIDEO_SLOTS) then
    InterLockedExchange(GSlotBusy[Slot], 0);
  InterLockedDecrement(GPendingReleases);
end;

procedure ReleasePlayerAsync(P: Pointer; Slot: Integer = -1);
var
  T: TReleaseThread;
begin
  if P = nil then Exit;
  InterLockedIncrement(GPendingReleases);
  T := TReleaseThread.Create(True);
  T.P := P;
  T.Slot := Slot;
  T.FreeOnTerminate := True;
  T.Start;
end;

function SafeFileName(const S: string): string;
var
  i: Integer;
begin
  Result := Trim(S);
  for i := 1 to Length(Result) do
    if Result[i] in ['\', '/', ':', '*', '?', '"', '<', '>', '|', #0..#31] then
      Result[i] := '_';
  if UTF8Length(Result) > 60 then Result := UTF8Copy(Result, 1, 60);
  if Result = '' then Result := 'channel';
end;

{ Разбивает строку параметров по пробелам, учитывая кавычки. }
procedure SplitArgs(const S: string; L: TStrings);
var
  i: Integer;
  Cur: string;
  InQ: Boolean;
begin
  Cur := '';
  InQ := False;
  for i := 1 to Length(S) do
  begin
    if S[i] = '"' then
      InQ := not InQ
    else if (S[i] = ' ') and not InQ then
    begin
      if Cur <> '' then L.Add(Cur);
      Cur := '';
    end
    else
      Cur := Cur + S[i];
  end;
  if Cur <> '' then L.Add(Cur);
end;

function FindExternalPlayer(const Configured: string): string;
{$IFDEF WINDOWS}
const
  Rel: array[0..4] of string = ('\VideoLAN\VLC\vlc.exe', '\MPC-HC\mpc-hc64.exe',
    '\MPC-HC\mpc-hc.exe', '\K-Lite Codec Pack\MPC-HC64\mpc-hc64.exe', '\mpv\mpv.exe');
var
  Roots: array[0..2] of string;
  i, j: Integer;
{$ELSE}
const
  Names: array[0..4] of string = ('mpv', 'vlc', 'celluloid', 'smplayer', 'mplayer');
var
  i: Integer;
{$ENDIF}
begin
  Result := Trim(Configured);
  if Result <> '' then Exit;
{$IFDEF WINDOWS}
  Roots[0] := GetEnvironmentVariable('ProgramFiles');
  Roots[1] := GetEnvironmentVariable('ProgramFiles(x86)');
  Roots[2] := GetEnvironmentVariable('ProgramW6432');
  for i := 0 to High(Rel) do
    for j := 0 to High(Roots) do
      if (Roots[j] <> '') and FileExists(Roots[j] + Rel[i]) then
        Exit(Roots[j] + Rel[i]);
{$ELSE}
  for i := 0 to High(Names) do
  begin
    Result := FindDefaultExecutablePath(Names[i]);
    if Result <> '' then Exit;
  end;
{$ENDIF}
  Result := '';
end;

function FilesEqual(const A, B: string): Boolean;
var
  FA, FB: TFileStream;
  BufA, BufB: array[0..16383] of Byte;
  NA, NB: Integer;
begin
  Result := False;
  try
    FA := TFileStream.Create(A, fmOpenRead or fmShareDenyNone);
    try
      FB := TFileStream.Create(B, fmOpenRead or fmShareDenyNone);
      try
        if FA.Size <> FB.Size then Exit;
        repeat
          NA := FA.Read(BufA, SizeOf(BufA));
          NB := FB.Read(BufB, SizeOf(BufB));
          if (NA <> NB) or not CompareMem(@BufA[0], @BufB[0], NA) then Exit;
        until NA = 0;
        Result := True;
      finally
        FB.Free;
      end;
    finally
      FA.Free;
    end;
  except
    Result := False;
  end;
end;

function UrlEncode(const S: string): string;
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

{ ====================================================================== }
{ TLoaderThread }

constructor TLoaderThread.Create;
begin
  Sources := TStringList.Create;
  Want := TStringList.Create;
  FreeOnTerminate := True;
  inherited Create(True);
end;

destructor TLoaderThread.Destroy;
begin
  Playlist.Free;
  Epg.Free;
  Sources.Free;
  Want.Free;
  inherited Destroy;
end;

function TLoaderThread.Fetch(const ASource, ACache: string; MaxAgeHours: Double;
  out Err: string): Boolean;
var
  Tmp: string;
  Age: LongInt;
begin
  Err := '';
  if (MaxAgeHours > 0) and FileExists(ACache) then
  begin
    Age := FileAge(ACache);
    if (Age <> -1) and ((Now - FileDateToDateTime(Age)) * 24 < MaxAgeHours) then
      Exit(True);
  end;
  Tmp := ACache + '.part';
  if FetchToFile(ASource, Tmp, Err) then
  begin
    if FileExists(ACache) then DeleteFile(ACache);
    Result := RenameFile(Tmp, ACache);
    if not Result then Err := 'не удалось сохранить файл в кэш';
  end
  else
  begin
    if FileExists(Tmp) then DeleteFile(Tmp);
    Result := FileExists(ACache);
    if Result then
      Warning := 'Нет связи (' + Err + '). Показана сохранённая копия.';
  end;
end;

procedure TLoaderThread.Execute;
var
  Err, Cache, Errors, W: string;
  i, p1, p2: Integer;
  MaxAge: Double;
begin
  Ok := False;
  MaskFloatExceptions;
  try
    if Kind = lkPlaylist then
    begin
      Cache := CacheDir + 'pl_' + HashStr(Source) + '.m3u';
      if CacheOnly then
      begin
        if not FileExists(Cache) then
        begin
          ErrorMsg := 'нет сохранённой копии';
          Exit;
        end;
      end
      else if Refresh then
      begin
        if not FetchToFile(Source, Cache + '.part', Err) then
        begin
          if FileExists(Cache + '.part') then DeleteFile(Cache + '.part');
          ErrorMsg := Err;
          Exit;
        end;
        if FileExists(Cache) and FilesEqual(Cache + '.part', Cache) then
        begin
          DeleteFile(Cache + '.part');
          Unchanged := True;
          Ok := True;
          Exit;
        end;
        if FileExists(Cache) then DeleteFile(Cache);
        RenameFile(Cache + '.part', Cache);
      end
      else if not Fetch(Source, Cache, 0, Err) then
      begin
        ErrorMsg := Err;
        Exit;
      end;
      Playlist := TPlaylistData.Create;
      Ok := ParseM3UFile(Cache, Playlist, Err);
      if not Ok then
      begin
        ErrorMsg := Err;
        FreeAndNil(Playlist);
      end;
    end
    else
    begin
      if Force then MaxAge := 0 else MaxAge := 12;
      Epg := TEpgData.Create;
      for i := 0 to Want.Count - 1 do
      begin
        W := Want[i];
        p1 := Pos(#1, W);
        p2 := Pos(#1, Copy(W, p1 + 1, MaxInt)) + p1;
        if (p1 > 0) and (p2 > p1) then
          Epg.AddWanted(Copy(W, 1, p1 - 1), Copy(W, p1 + 1, p2 - p1 - 1), Copy(W, p2 + 1, MaxInt));
      end;
      Errors := '';
      for i := 0 to Sources.Count - 1 do
      begin
        if Terminated then Break;
        Cache := CacheDir + 'epg_' + HashStr(Sources[i]) + '.xml';
        if Fetch(Sources[i], Cache, MaxAge, Err) then
        begin
          if not LoadXmltvFile(Cache, Epg, PastDays, 3, Err) then
            Errors := Errors + Err + '; ';
        end
        else
          Errors := Errors + Err + '; ';
      end;
      Ok := Epg.ProgrammeCount > 0;
      if not Ok then
      begin
        ErrorMsg := Errors;
        if ErrorMsg = '' then ErrorMsg := 'нет данных';
        FreeAndNil(Epg);
      end;
    end;
  except
    on E: Exception do
    begin
      ErrorMsg := E.Message;
      Ok := False;
    end;
  end;
end;

{ ====================================================================== }
{ TMainForm — создание }

constructor TMainForm.Create(TheOwner: TComponent);
begin
  inherited CreateNew(TheOwner);
  GFormAlive := True;
  FView := TFPList.Create;
  FSettings := TAppSettings.Create;
  FSettings.Load;
  SetAccent(FSettings.Accent);
  FSystemFrame := FSettings.SystemFrame;
  FLastState := -1;
  FNowUtc := NowUtc;

  Caption := APP_NAME;
  Color := clrFrame;
  Font.Color := clrText;
  KeyPreview := True;
  OnShow := @FormShow;
  OnClose := @FormClose;
  OnKeyDown := @FormKeyDown;
  OnResize := @FormResize;
  OnWindowStateChange := @FormWindowStateChange;
  if not FSystemFrame then
    BorderStyle := bsNone;

  { защита от неправдоподобных сохранённых размеров }
  if (FSettings.WinWidth < 760) or (FSettings.WinWidth > Screen.DesktopWidth) then
    FSettings.WinWidth := Math.Min(1180, Screen.Width);
  if (FSettings.WinHeight < 460) or (FSettings.WinHeight > Screen.DesktopHeight) then
    FSettings.WinHeight := Math.Min(720, Screen.Height);
  if (FSettings.SideWidth < 250) or (FSettings.SideWidth > 1200) then
    FSettings.SideWidth := 360;
  if (FSettings.InfoHeight < 60) or (FSettings.InfoHeight > 700) then
    FSettings.InfoHeight := 80;
  if (FSettings.WinLeft > Screen.DesktopWidth - 100) or (FSettings.WinTop > Screen.DesktopHeight - 100) then
  begin
    FSettings.WinLeft := -1;
    FSettings.WinTop := -1;
  end;
  Width := FSettings.WinWidth;
  Height := FSettings.WinHeight;
  if (FSettings.WinLeft >= 0) and (FSettings.WinTop >= 0) and
     (FSettings.WinLeft < Screen.Width - 100) and (FSettings.WinTop < Screen.Height - 100) then
  begin
    Position := poDesigned;
    Left := FSettings.WinLeft;
    Top := FSettings.WinTop;
  end
  else
    Position := poScreenCenter;
  Constraints.MinWidth := 760;
  Constraints.MinHeight := 460;

  Log('настройки: ' + FSettings.ConfigDir);
  FLogos := TLogoCache.Create(FSettings.CacheDir);
  FLogos.SetUseProxy(FSettings.LogoProxy);

  Log('построение интерфейса');
  BuildFrame;
  BuildUI;
  ApplyViewSettings;
  Log('запуск видеодвижка');
  try
    InitVlc;
  except
    on E: Exception do
    begin
      FVlcError := 'Ошибка запуска видеодвижка: ' + E.Message;
      Log(FVlcError);
      FPlayer := nil;
      FVlc := nil;
      pnlVideo.Caption := FVlcError;
    end;
  end;
  UpdateTransport;
  Log('окно готово');
end;

destructor TMainForm.Destroy;
var
  i: Integer;
begin
  GFormAlive := False;
  if FRecPlayer <> nil then
  begin
    libvlc_media_player_stop(FRecPlayer);
    libvlc_media_player_release(FRecPlayer);
    FRecPlayer := nil;
  end;
  if FPlayer <> nil then
  begin
    libvlc_media_player_stop(FPlayer);
    libvlc_media_player_release(FPlayer);
    FPlayer := nil;
  end;
  { ждём фоновые остановки плееров (не дольше 3 секунд) }
  i := 0;
  while (GPendingReleases > 0) and (i < 60) do
  begin
    Sleep(50);
    Inc(i);
  end;
  if (FVlc <> nil) and (GPendingReleases = 0) then
  begin
    libvlc_release(FVlc);
    FVlc := nil;
  end;
  if chView <> nil then chView.Logos := nil;
  FLogos.Free;
  FLogoDb.Free;
  FView.Free;
  FPlaylist.Free;
  FEpg.Free;
  FSettings.Free;
  inherited Destroy;
end;

function TMainForm.MakeButton(AParent: TWinControl; AKind: TIconKind; AAlign: TAlign;
  const AHint: string; AHandler: TNotifyEvent): TFlatButton;
begin
  Result := TFlatButton.Create(Self);
  Result.Parent := AParent;
  Result.Kind := AKind;
  Result.Width := 38;
  Result.Align := AAlign;
  Result.Hint := AHint;
  Result.OnClick := AHandler;
  Result.BorderSpacing.Around := 3;
end;

function TMainForm.MakePanel(AParent: TWinControl; AAlign: TAlign; AColor: TColor;
  AHeight: Integer): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := AParent;
  Result.BevelOuter := bvNone;
  Result.Color := AColor;
  Result.ParentColor := False;
  if AHeight > 0 then Result.Height := AHeight;
  Result.Align := AAlign;
end;

function TMainForm.MakeGrip(AAlign: TAlign; ACursor: TCursor): TPanel;
begin
  Result := MakePanel(Self, AAlign, clrFrame, 0);
  if AAlign in [alTop, alBottom] then Result.Height := GRIP else Result.Width := GRIP;
  Result.Cursor := ACursor;
  Result.OnMouseMove := @GripMouseMove;
  Result.OnMouseDown := @GripMouseDown;
end;

procedure TMainForm.BuildFrame;
begin
  { рамка для изменения размера (только в режиме своей рамки) }
  gripTop := MakeGrip(alTop, crSizeNS);
  gripBottom := MakeGrip(alBottom, crSizeNS);
  gripLeft := MakeGrip(alLeft, crSizeWE);
  gripRight := MakeGrip(alRight, crSizeWE);

  pnlRoot := MakePanel(Self, alClient, clrBg, 0);

  { заголовок окна }
  pnlTitle := MakePanel(pnlRoot, alTop, clrTitle, 40);
  btnWinClose := MakeButton(pnlTitle, ikClose, alRight, 'Закрыть', @WinCloseClick);
  btnWinClose.Width := 46;
  btnWinClose.BorderSpacing.Around := 0;
  btnWinClose.HoverColor := clrDanger;
  btnWinClose.HoverIconColor := clWhite;
  btnWinClose.Left := 3000;
  btnWinMax := MakeButton(pnlTitle, ikWinMax, alRight, 'Развернуть', @WinMaxClick);
  btnWinMax.Width := 46;
  btnWinMax.BorderSpacing.Around := 0;
  btnWinMax.Left := 2900;
  btnWinMin := MakeButton(pnlTitle, ikWinMin, alRight, 'Свернуть', @WinMinClick);
  btnWinMin.Width := 46;
  btnWinMin.BorderSpacing.Around := 0;
  btnWinMin.Left := 2800;

  { слева: знак и название, затем пункты меню }
  pbLogo := TPaintBox.Create(Self);
  pbLogo.Parent := pnlTitle;
  pbLogo.Width := 190;
  pbLogo.Left := 0;
  pbLogo.Align := alLeft;
  pbLogo.OnPaint := @LogoPaint;
  pbLogo.OnMouseDown := @TitleMouseDown;
  btnMenuSettings := MakeButton(pnlTitle, ikSettings, alLeft, 'Настройки программы', @SettingsClick);
  btnMenuSettings.Caption := 'Настройки';
  btnMenuSettings.NavStyle := True;
  btnMenuSettings.Width := 130;
  btnMenuSettings.Left := 300;
  btnMenuSettings.BorderSpacing.Around := 2;

  pbTitle := TPaintBox.Create(Self);
  pbTitle.Parent := pnlTitle;
  pbTitle.Align := alClient;
  pbTitle.OnPaint := @TitlePaint;
  pbTitle.OnMouseDown := @TitleMouseDown;

  if FSystemFrame then
  begin
    pnlTitle.Visible := False;
    gripTop.Visible := False;
    gripBottom.Visible := False;
    gripLeft.Visible := False;
    gripRight.Visible := False;
  end;
end;

procedure TMainForm.BuildUI;
var
  NextTop, i: Integer;

  procedure StackTop(C: TControl);
  begin
    C.Top := NextTop;
    Inc(NextTop, 1000);
    C.Align := alTop;
  end;

begin
  NextTop := 0;

  { ---------- боковая панель ---------- }
  pnlSide := MakePanel(pnlRoot, alLeft, clrSide, 0);
  pnlSide.Width := FSettings.SideWidth;
  pnlSide.Constraints.MinWidth := 250;

  splSide := TSplitter.Create(Self);
  splSide.Parent := pnlRoot;
  splSide.Align := alLeft;
  splSide.Left := pnlSide.Width + 1;
  splSide.Width := 4;
  splSide.Color := clrBg;
  splSide.ParentColor := False;
  splSide.ResizeStyle := rsUpdate;
  splSide.MinSize := 250;

  segTabs := TSegmentBar.Create(Self);
  segTabs.Parent := pnlSide;
  segTabs.Items.Add('Избранное');
  segTabs.Items.Add('Все каналы');
  segTabs.Items.Add('Категории');
  segTabs.ItemIndex := FSettings.LastTab;
  segTabs.Height := 36;
  segTabs.BorderSpacing.Left := 10;
  segTabs.BorderSpacing.Right := 10;
  segTabs.BorderSpacing.Top := 10;
  segTabs.OnChange := @TabsChange;
  StackTop(segTabs);

  { строка плейлиста }
  pnlPl := MakePanel(pnlSide, alNone, clrSide, 38);
  pnlPl.BorderSpacing.Left := 6;
  pnlPl.BorderSpacing.Right := 6;
  pnlPl.BorderSpacing.Top := 8;
  StackTop(pnlPl);
  btnReload := MakeButton(pnlPl, ikRefresh, alRight, 'Обновить плейлист и телепрограмму (F5)', @ReloadClick);
  btnReload.Left := 1000;
  btnRemove := MakeButton(pnlPl, ikMinus, alRight, 'Удалить плейлист', @RemoveClick);
  btnRemove.Left := 900;
  btnEdit := MakeButton(pnlPl, ikEdit, alRight, 'Изменить плейлист', @EditClick);
  btnEdit.Left := 800;
  btnAdd := MakeButton(pnlPl, ikPlus, alRight, 'Добавить плейлист', @AddClick);
  btnAdd.Left := 700;
  cbPlaylists := TComboBox.Create(Self);
  cbPlaylists.Parent := pnlPl;
  cbPlaylists.Style := csDropDownList;
  cbPlaylists.Font.Color := clWindowText;
  cbPlaylists.Align := alClient;
  cbPlaylists.BorderSpacing.Left := 4;
  cbPlaylists.BorderSpacing.Top := 6;
  cbPlaylists.BorderSpacing.Bottom := 4;
  cbPlaylists.OnChange := @PlaylistChange;

  edSearch := TEdit.Create(Self);
  edSearch.Parent := pnlSide;
  edSearch.TextHint := 'Поиск (Ctrl+F)';
  edSearch.Font.Color := clWindowText;
  edSearch.BorderSpacing.Left := 10;
  edSearch.BorderSpacing.Right := 10;
  edSearch.BorderSpacing.Top := 6;
  edSearch.OnChange := @SearchChange;
  StackTop(edSearch);

  { переключатель вида }
  pnlViewRow := MakePanel(pnlSide, alNone, clrSide, 38);
  pnlViewRow.BorderSpacing.Left := 6;
  pnlViewRow.BorderSpacing.Right := 10;
  pnlViewRow.BorderSpacing.Top := 4;
  StackTop(pnlViewRow);
  btnViewList := MakeButton(pnlViewRow, ikViewList, alLeft, 'Список', @ViewModeClick);
  btnViewList.Tag := Ord(vmList);
  btnViewList.Left := 0;
  btnViewCompact := MakeButton(pnlViewRow, ikViewCompact, alLeft, 'Компактный список', @ViewModeClick);
  btnViewCompact.Tag := Ord(vmCompact);
  btnViewCompact.Left := 100;
  btnViewGrid := MakeButton(pnlViewRow, ikViewGrid, alLeft, 'Сетка', @ViewModeClick);
  btnViewGrid.Tag := Ord(vmGrid);
  btnViewGrid.Left := 200;
  btnViewTiles := MakeButton(pnlViewRow, ikViewTiles, alLeft, 'Плитка', @ViewModeClick);
  btnViewTiles.Tag := Ord(vmTiles);
  btnViewTiles.Left := 300;
  btnWall := MakeButton(pnlViewRow, ikWall, alRight, 'Все каналы на весь экран (G)', @WallClick);
  btnWall.Left := 3000;
  lblCount := TLabel.Create(Self);
  lblCount.Parent := pnlViewRow;
  lblCount.Align := alClient;
  lblCount.AutoSize := False;
  lblCount.Alignment := taRightJustify;
  lblCount.Layout := tlCenter;
  lblCount.Font.Color := clrDim;
  lblCount.Font.Size := 8;

  { «назад» из категории }
  pnlBack := MakePanel(pnlSide, alNone, clrSide, 36);
  pnlBack.BorderSpacing.Left := 6;
  pnlBack.BorderSpacing.Right := 10;
  StackTop(pnlBack);
  btnBack := MakeButton(pnlBack, ikBack, alLeft, 'К списку категорий (Backspace)', @BackClick);
  lblBack := TLabel.Create(Self);
  lblBack.Parent := pnlBack;
  lblBack.Align := alClient;
  lblBack.AutoSize := False;
  lblBack.Layout := tlCenter;
  lblBack.Font.Color := clrText;
  lblBack.Font.Style := [fsBold];
  pnlBack.Visible := False;

  lblEmpty := TLabel.Create(Self);
  lblEmpty.Parent := pnlSide;
  lblEmpty.Align := alClient;
  lblEmpty.AutoSize := False;
  lblEmpty.WordWrap := True;
  lblEmpty.Alignment := taCenter;
  lblEmpty.Layout := tlCenter;
  lblEmpty.Font.Color := clrDim;
  lblEmpty.BorderSpacing.Around := 20;
  lblEmpty.Caption := 'Плейлистов пока нет.' + LineEnding + LineEnding +
    'Нажмите «+», чтобы добавить ссылку на плейлист M3U или файл.' + LineEnding + LineEnding +
    'Если у вас есть файл конфигурации .aristocrat — загрузите его в Настройках → Экспорт и импорт.';
  lblEmpty.Visible := False;

  chView := TChannelView.Create(Self);
  chView.Parent := pnlSide;
  chView.Align := alClient;
  chView.BorderSpacing.Top := 4;
  chView.Logos := FLogos;
  chView.IsFavorite := @IsFav;
  chView.OnItemClick := @ViewItemClick;
  chView.OnItemActivate := @ViewItemActivate;
  chView.OnSelectionMoved := @ViewSelectionMoved;
  chView.OnGuideClick := @ViewGuideClick;

  { телепрограмма канала (вместо списка каналов) }
  pnlGuide := MakePanel(pnlSide, alClient, clrSide, 0);
  pnlGuide.Visible := False;
  pnlGuideHead := MakePanel(pnlGuide, alTop, clrSide, 40);
  pnlGuideHead.BorderSpacing.Left := 6;
  pnlGuideHead.BorderSpacing.Top := 4;
  btnGuideBack := MakeButton(pnlGuideHead, ikBack, alLeft, 'Назад к каналам (Esc)', @GuideBackClick);
  lblGuideTitle := TLabel.Create(Self);
  lblGuideTitle.Parent := pnlGuideHead;
  lblGuideTitle.Align := alClient;
  lblGuideTitle.AutoSize := False;
  lblGuideTitle.Layout := tlCenter;
  lblGuideTitle.Font.Color := clrText;
  lblGuideTitle.Font.Style := [fsBold];
  lblGuideTitle.Font.Size := 10;
  lblGuideDesc := TLabel.Create(Self);
  lblGuideDesc.Parent := pnlGuide;
  lblGuideDesc.Align := alBottom;
  lblGuideDesc.AutoSize := False;
  lblGuideDesc.WordWrap := True;
  lblGuideDesc.Height := 120;
  lblGuideDesc.Font.Color := clrDim;
  lblGuideDesc.Font.Size := 8;
  lblGuideDesc.BorderSpacing.Around := 10;
  guide := TGuideView.Create(Self);
  guide.Parent := pnlGuide;
  guide.Align := alClient;
  guide.OnItemClick := @GuideItemClick;
  guide.OnItemActivate := @GuideItemClick;
  guide.OnSelect := @GuideSelect;

  pmChannel := TPopupMenu.Create(Self);
  pmChannel.OnPopup := @MenuPopup;
  miPlay := TMenuItem.Create(pmChannel);
  miPlay.Caption := 'Смотреть';
  miPlay.OnClick := @MenuPlayClick;
  pmChannel.Items.Add(miPlay);
  miGuide := TMenuItem.Create(pmChannel);
  miGuide.Caption := 'Телепрограмма и архив (E)';
  miGuide.OnClick := @MenuGuideClick;
  pmChannel.Items.Add(miGuide);
  miExternal := TMenuItem.Create(pmChannel);
  miExternal.Caption := 'Открыть во внешнем плеере';
  miExternal.OnClick := @MenuExternalClick;
  pmChannel.Items.Add(miExternal);
  miRecord := TMenuItem.Create(pmChannel);
  miRecord.Caption := 'Записать эфир';
  miRecord.OnClick := @MenuRecordClick;
  pmChannel.Items.Add(miRecord);
  miFav := TMenuItem.Create(pmChannel);
  miFav.Caption := 'В избранное';
  miFav.OnClick := @MenuFavClick;
  pmChannel.Items.Add(miFav);
  miCopy := TMenuItem.Create(pmChannel);
  miCopy.Caption := 'Копировать ссылку на поток';
  miCopy.OnClick := @MenuCopyClick;
  pmChannel.Items.Add(miCopy);
  chView.PopupMenu := pmChannel;

  { ---------- основная часть ---------- }
  pnlMain := MakePanel(pnlRoot, alClient, clrBg, 0);
  pnlMain.Constraints.MinWidth := 320;
  { нижняя часть: панель управления + расписание; высоту можно тянуть мышью }
  pnlBottom := MakePanel(pnlMain, alBottom, clrBg, 50 + FSettings.InfoHeight);
  pnlBottom.Constraints.MinHeight := 50 + 60;
  splInfo := TSplitter.Create(Self);
  splInfo.Parent := pnlMain;
  splInfo.Align := alBottom;
  splInfo.Height := 5;
  splInfo.Top := pnlBottom.Top - 6;
  splInfo.Color := clrFrame;
  splInfo.ParentColor := False;
  splInfo.ResizeStyle := rsUpdate;
  splInfo.MinSize := 60;
  pnlControls := MakePanel(pnlBottom, alBottom, clrPanel, 50);
  pnlInfo := MakePanel(pnlBottom, alClient, clrBg, 0);
  btnInfoDown := MakeButton(pnlInfo, ikDown, alRight, 'Следующие передачи (колёсико мыши)', @InfoDownClick);
  btnInfoDown.Width := 30;
  btnInfoDown.Left := 2000;
  btnInfoUp := MakeButton(pnlInfo, ikUp, alRight, 'Прошедшие передачи (колёсико мыши)', @InfoUpClick);
  btnInfoUp.Width := 30;
  btnInfoUp.Left := 1900;
  pbInfo := TPaintBox.Create(Self);
  pbInfo.Parent := pnlInfo;
  pbInfo.Align := alClient;
  pbInfo.OnPaint := @InfoPaint;
  pbInfo.OnMouseWheel := @InfoWheel;
  pbInfo.OnClick := @InfoClick;
  pbInfo.OnDblClick := @InfoDblClick;


  pnlVideo := MakePanel(pnlMain, alClient, clBlack, 0);
  pnlVideo.Font.Color := clrDim;
  pnlVideo.Caption := 'Выберите канал в списке слева';
  pnlVideo.OnDblClick := @VideoDblClick;
  for i := 0 to VIDEO_SLOTS - 1 do
  begin
    FSlots[i] := MakePanel(pnlVideo, alClient, clBlack, 0);
    FSlots[i].Visible := False;
    FSlots[i].OnDblClick := @VideoDblClick;
  end;
  FSlot := -1;

  btnPrev := MakeButton(pnlControls, ikPrev, alLeft, 'Предыдущий канал (PgUp)', @PrevClick);
  btnPrev.Left := 0;
  btnStop := MakeButton(pnlControls, ikStop, alLeft, 'Стоп / воспроизведение (Пробел)', @StopClick);
  btnStop.Left := 100;
  btnNext := MakeButton(pnlControls, ikNext, alLeft, 'Следующий канал (PgDn)', @NextClick);
  btnNext.Left := 200;
  btnFav := MakeButton(pnlControls, ikStar, alLeft, 'В избранное / убрать', @FavClick);
  btnFav.CheckedColor := clrStar;
  btnFav.Left := 300;
  btnRec := MakeButton(pnlControls, ikRecord, alLeft, 'Записать эфир (Ctrl+R)', @RecClick);
  btnRec.IconColor := BlendColor(clrDanger, clrText, 0.35);
  btnRec.CheckedColor := clrDanger;
  btnRec.Left := 400;
  btnExt := MakeButton(pnlControls, ikExternal, alLeft, 'Открыть во внешнем плеере', @ExtClick);
  btnExt.Left := 500;
  btnLive := MakeButton(pnlControls, ikNone, alLeft, 'Вернуться к прямому эфиру', @LiveClick);
  btnLive.Caption := 'В эфир';
  btnLive.Width := 90;
  btnLive.Left := 600;
  btnLive.Visible := False;

  btnSettings := MakeButton(pnlControls, ikSettings, alRight, 'Настройки', @SettingsClick);
  btnSettings.Left := 3100;
  btnFull := MakeButton(pnlControls, ikFullscreen, alRight, 'На весь экран без рамок (F11, двойной щелчок)', @FullClick);
  btnFull.Left := 3000;
  sldVolume := TFlatSlider.Create(Self);
  sldVolume.Parent := pnlControls;
  sldVolume.Align := alRight;
  sldVolume.Width := 110;
  sldVolume.Left := 2900;
  sldVolume.BorderSpacing.Right := 6;
  sldVolume.Position := FSettings.Volume;
  sldVolume.OnChange := @VolumeChange;
  sldVolume.Hint := 'Громкость';
  btnMute := MakeButton(pnlControls, ikVolume, alRight, 'Выключить звук (M)', @MuteClick);
  btnMute.Left := 2800;
  if FSettings.Muted then btnMute.Kind := ikMute;

  lblRec := TLabel.Create(Self);
  lblRec.Parent := pnlControls;
  lblRec.Align := alRight;
  lblRec.Left := 2700;
  lblRec.Layout := tlCenter;
  lblRec.Font.Color := clrDanger;
  lblRec.Font.Style := [fsBold];
  lblRec.BorderSpacing.Right := 12;
  lblRec.Caption := '';

  lblStatus := TLabel.Create(Self);
  lblStatus.Parent := pnlControls;
  lblStatus.Align := alClient;
  lblStatus.AutoSize := False;
  lblStatus.Layout := tlCenter;
  lblStatus.Font.Color := clrDim;
  lblStatus.BorderSpacing.Left := 14;

  { ---------- таймеры ---------- }
  tmrStatus := TTimer.Create(Self);
  tmrStatus.Interval := 500;
  tmrStatus.OnTimer := @StatusTimer;
  tmrSelect := TTimer.Create(Self);
  tmrSelect.Enabled := False;
  tmrSelect.Interval := 350;
  tmrSelect.OnTimer := @SelectTimer;
  tmrSearch := TTimer.Create(Self);
  tmrSearch.Enabled := False;
  tmrSearch.Interval := 250;
  tmrSearch.OnTimer := @SearchTimer;
end;

procedure TMainForm.InitVlc;
var
  Args: array[0..2] of PAnsiChar;
begin
  if FindCmdLineSwitch('novideo', ['-', '/'], True) then
  begin
    FVlcError := 'Видео отключено параметром --novideo';
    pnlVideo.Caption := FVlcError;
    Exit;
  end;
  if not LoadVlc(FSettings.AppDir, FVlcError) then
  begin
    Log('VLC не загружен: ' + FVlcError);
    pnlVideo.Caption := FVlcError;
    Exit;
  end;
  Log('libVLC загружен, версия ' + VlcVersion);
  MaskFloatExceptions;
  Args[0] := '--no-video-title-show';
  Args[1] := '--network-caching=1000';
  Args[2] := '--quiet';
  FVlc := libvlc_new(3, @Args[0]);
  if FVlc = nil then
  begin
    FVlcError := 'Не удалось запустить видеодвижок VLC ' + VlcVersion;
    pnlVideo.Caption := FVlcError;
    Exit;
  end;
  Log('libvlc_new выполнен');
end;

{ ====================================================================== }
{ вспомогательное }

procedure TMainForm.InvalidateAll(C: TWinControl);
var
  i: Integer;
begin
  C.Invalidate;
  for i := 0 to C.ControlCount - 1 do
    if C.Controls[i] is TWinControl then
      InvalidateAll(TWinControl(C.Controls[i]))
    else
      C.Controls[i].Invalidate;
end;

procedure TMainForm.ApplyViewSettings;
begin
  SetAccent(FSettings.Accent);
  chView.Mode := TViewMode(FSettings.ViewMode);
  chView.ShowNumbers := FSettings.ShowNumbers;
  chView.ShowLogos := FSettings.ShowLogos;
  UpdateViewButtons;
  InvalidateAll(Self);
end;

procedure TMainForm.UpdateViewButtons;
begin
  btnViewList.Checked := chView.Mode = vmList;
  btnViewCompact.Checked := chView.Mode = vmCompact;
  btnViewGrid.Checked := chView.Mode = vmGrid;
  btnViewTiles.Checked := chView.Mode = vmTiles;
end;

procedure TMainForm.ApplyVolume;
begin
  if FPlayer = nil then Exit;
  libvlc_audio_set_volume(FPlayer, FSettings.Volume);
  libvlc_audio_set_mute(FPlayer, Ord(FSettings.Muted));
end;

procedure TMainForm.UpdateStatusLabel;
begin
  if FPlayerStatus <> '' then
    lblStatus.Caption := FPlayerStatus
  else
    lblStatus.Caption := FInfoText;
end;

procedure TMainForm.SetInfo(const S: string);
begin
  FInfoText := S;
  UpdateStatusLabel;
end;

function TMainForm.IsFav(Ch: TChannel): Boolean;
begin
  Result := (Ch <> nil) and FSettings.IsFavorite(Ch.URL);
end;

function TMainForm.TargetChannel: TChannel;
begin
  Result := FCurrent;
  if Result = nil then Result := chView.SelectedChannel;
end;

procedure TMainForm.UpdateTransport;
var
  Ch: TChannel;
begin
  if FPlaying then btnStop.Kind := ikStop else btnStop.Kind := ikPlay;
  Ch := TargetChannel;
  btnFav.Enabled := Ch <> nil;
  btnFav.Checked := IsFav(Ch);
  btnExt.Enabled := Ch <> nil;
  btnRec.Checked := FRecPlayer <> nil;
  btnEdit.Enabled := cbPlaylists.ItemIndex >= 0;
  btnRemove.Enabled := cbPlaylists.ItemIndex >= 0;
  btnReload.Enabled := cbPlaylists.ItemIndex >= 0;
  pbTitle.Invalidate;
end;

procedure TMainForm.UpdateEmptyState;
var
  NoLists: Boolean;
begin
  NoLists := FSettings.PlaylistCount = 0;
  lblEmpty.Visible := NoLists and not FGuideOpen;
  chView.Visible := (not NoLists) and not FGuideOpen;
  cbPlaylists.Enabled := not NoLists;
  edSearch.Enabled := not NoLists;
end;

procedure TMainForm.UpdateFrameControls;
var
  ShowGrips: Boolean;
begin
  if FSystemFrame then Exit;
  ShowGrips := not FMaxed and not FFullscreen;
  gripTop.Visible := ShowGrips;
  gripBottom.Visible := ShowGrips;
  gripLeft.Visible := ShowGrips;
  gripRight.Visible := ShowGrips;
  pnlTitle.Visible := not FFullscreen;
  if FMaxed then
  begin
    btnWinMax.Kind := ikWinRestore;
    btnWinMax.Hint := 'Восстановить';
  end
  else
  begin
    btnWinMax.Kind := ikWinMax;
    btnWinMax.Hint := 'Развернуть';
  end;
end;

{ ====================================================================== }
{ окно: заголовок, рамка, развернуть, полный экран }

procedure TMainForm.LogoPaint(Sender: TObject);
var
  C: TCanvas;
  X, Y, H: Integer;
begin
  C := pbLogo.Canvas;
  H := pbLogo.Height;
  C.Brush.Style := bsSolid;
  C.Brush.Color := clrTitle;
  C.FillRect(Rect(0, 0, pbLogo.Width, H));
  X := 12;
  Y := (H - 22) div 2;
  C.Brush.Color := clrAccent;
  C.Pen.Color := clrAccent;
  C.RoundRect(X, Y, X + 22, Y + 22, 7, 7);
  C.Brush.Color := clrTitle;
  C.Pen.Color := clrTitle;
  C.Polygon([Point(X + 8, Y + 6), Point(X + 8, Y + 16), Point(X + 16, Y + 11)]);
  C.Brush.Style := bsClear;
  C.Font.Assign(Font);
  C.Font.Size := 10;
  C.Font.Style := [fsBold];
  C.Font.Color := clrText;
  C.TextOut(X + 32, (H - C.TextHeight('Ag')) div 2, 'IPTV Aristocrat');
end;

procedure TMainForm.TitlePaint(Sender: TObject);
var
  C: TCanvas;
  H: Integer;
begin
  C := pbTitle.Canvas;
  H := pbTitle.Height;
  C.Brush.Style := bsSolid;
  C.Brush.Color := clrTitle;
  C.FillRect(Rect(0, 0, pbTitle.Width, H));
  if FCurrent <> nil then
  begin
    C.Brush.Style := bsClear;
    C.Font.Assign(Font);
    C.Font.Size := 10;
    C.Font.Style := [];
    C.Font.Color := clrDim;
    C.TextOut(20, (H - C.TextHeight('Ag')) div 2, Ellipsize(C, FCurrent.Name, pbTitle.Width - 40));
  end;
end;

procedure TMainForm.TitleMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then Exit;
  if ssDouble in Shift then
  begin
    SetMaximized(not FMaxed);
    Exit;
  end;
  if FMaxed then Exit;   { развёрнутое окно не перетаскиваем }
  BeginWindowMove(Self);
end;

function EdgeAt(G, gTop, gBottom, gLeft: TPanel; X: Integer): TResizeEdge;
const
  C = 18;
begin
  if G = gTop then
  begin
    if X < C then Result := reTopLeft
    else if X > G.Width - C then Result := reTopRight
    else Result := reTop;
  end
  else if G = gBottom then
  begin
    if X < C then Result := reBottomLeft
    else if X > G.Width - C then Result := reBottomRight
    else Result := reBottom;
  end
  else if G = gLeft then
    Result := reLeft
  else
    Result := reRight;
end;

procedure TMainForm.GripMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  G: TPanel;
begin
  G := TPanel(Sender);
  case EdgeAt(G, gripTop, gripBottom, gripLeft, X) of
    reTopLeft, reBottomRight: G.Cursor := crSizeNWSE;
    reTopRight, reBottomLeft: G.Cursor := crSizeNESW;
    reTop, reBottom: G.Cursor := crSizeNS;
  else
    G.Cursor := crSizeWE;
  end;
end;

procedure TMainForm.GripMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and not FMaxed then
    BeginWindowResize(Self, EdgeAt(TPanel(Sender), gripTop, gripBottom, gripLeft, X));
end;

procedure TMainForm.WinMinClick(Sender: TObject);
begin
  WindowState := wsMinimized;
end;

procedure TMainForm.WinMaxClick(Sender: TObject);
begin
  SetMaximized(not FMaxed);
end;

procedure TMainForm.WinCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.SetMaximized(Value: Boolean);
begin
  if FFullscreen then SetFullscreen(False);
  if FSystemFrame then
  begin
    if Value then WindowState := wsMaximized else WindowState := wsNormal;
    FMaxed := Value;
    Exit;
  end;
  if Value = FMaxed then Exit;
  if Value then
  begin
    FNormalBounds := BoundsRect;
    if ((FNormalBounds.Right - FNormalBounds.Left) > Screen.DesktopWidth) or
       ((FNormalBounds.Bottom - FNormalBounds.Top) > Screen.DesktopHeight) or
       (FNormalBounds.Left < -2000) or (FNormalBounds.Left > Screen.DesktopWidth) then
      FNormalBounds := Bounds(80, 60, FSettings.WinWidth, FSettings.WinHeight);
    FMaxed := True;
    UpdateFrameControls;
    BoundsRect := Screen.MonitorFromWindow(Handle).WorkareaRect;
  end
  else
  begin
    FMaxed := False;
    UpdateFrameControls;
    if (FNormalBounds.Right - FNormalBounds.Left) < Constraints.MinWidth then
      FNormalBounds := Bounds(80, 60, FSettings.WinWidth, FSettings.WinHeight);
    BoundsRect := FNormalBounds;
  end;
end;

procedure TMainForm.SetFullscreen(Value: Boolean);
begin
  if Value = FFullscreen then Exit;
  if Value and FWall then SetChannelWall(False);
  FFullscreen := Value;
  if Value then
  begin
    FFullPrevBounds := BoundsRect;
    FFullPrevState := WindowState;
    pnlSide.Visible := False;
    splSide.Visible := False;
    pnlBottom.Visible := False;
    splInfo.Visible := False;
    UpdateFrameControls;
{$IFDEF WINDOWS}
    if FSystemFrame then
      WindowState := wsFullScreen
    else
      BoundsRect := Screen.MonitorFromWindow(Handle).BoundsRect;
{$ELSE}
    WindowState := wsFullScreen;
{$ENDIF}
  end
  else
  begin
{$IFDEF WINDOWS}
    if FSystemFrame then
    begin
      if FFullPrevState = wsFullScreen then FFullPrevState := wsNormal;
      WindowState := FFullPrevState;
    end
    else
      BoundsRect := FFullPrevBounds;
{$ELSE}
    if FFullPrevState = wsFullScreen then FFullPrevState := wsNormal;
    WindowState := FFullPrevState;
    if not FSystemFrame then BoundsRect := FFullPrevBounds;
{$ENDIF}
    pnlSide.Visible := True;
    splSide.Visible := True;
    splSide.Left := pnlSide.Left + pnlSide.Width + 1;
    pnlBottom.Visible := True;
    splInfo.Visible := True;
    splInfo.Top := pnlBottom.Top - 6;
    UpdateFrameControls;
    UpdateSideMax;
  end;
end;

{ ====================================================================== }
{ плейлисты и телепрограмма }

procedure TMainForm.RefreshPlaylistCombo;
var
  i: Integer;
begin
  FUpdating := True;
  try
    cbPlaylists.Items.BeginUpdate;
    try
      cbPlaylists.Items.Clear;
      for i := 0 to FSettings.PlaylistCount - 1 do
        cbPlaylists.Items.Add(FSettings.Playlist(i).Name);
    finally
      cbPlaylists.Items.EndUpdate;
    end;
    if FSettings.PlaylistCount > 0 then
    begin
      if (FSettings.LastPlaylist < 0) or (FSettings.LastPlaylist >= FSettings.PlaylistCount) then
        FSettings.LastPlaylist := 0;
      cbPlaylists.ItemIndex := FSettings.LastPlaylist;
    end;
  finally
    FUpdating := False;
  end;
  UpdateEmptyState;
  UpdateTransport;
end;

procedure TMainForm.LoadPlaylist(Index: Integer; ForceEpg: Boolean);
var
  T: TLoaderThread;
begin
  if (Index < 0) or (Index >= FSettings.PlaylistCount) then Exit;
  FSettings.LastPlaylist := Index;
  Inc(FPlGen);
  FForceEpg := ForceEpg;
  T := TLoaderThread.Create;
  T.Kind := lkPlaylist;
  T.Source := FSettings.Playlist(Index).Source;
  T.CacheDir := FSettings.CacheDir;
  T.Generation := FPlGen;
  T.OnTerminate := @LoaderDone;
  { есть сохранённая копия — показываем её сразу, а обновляем в фоне }
  T.CacheOnly := (not ForceEpg) and IsRemoteUrl(T.Source) and
    FileExists(FSettings.CacheDir + 'pl_' + HashStr(T.Source) + '.m3u');
  if T.CacheOnly then SetInfo('') else SetInfo('Загрузка плейлиста...');
  T.Start;
end;

procedure TMainForm.LoadPlaylistRefresh(Index: Integer);
var
  T: TLoaderThread;
begin
  if (Index < 0) or (Index >= FSettings.PlaylistCount) then Exit;
  T := TLoaderThread.Create;
  T.Kind := lkPlaylist;
  T.Source := FSettings.Playlist(Index).Source;
  T.CacheDir := FSettings.CacheDir;
  T.Generation := FPlGen;
  T.Refresh := True;
  T.OnTerminate := @LoaderDone;
  T.Start;
end;

procedure TMainForm.LoadEpg(Force: Boolean);
var
  L: TStringList;
  T: TLoaderThread;
  E, Key: string;
  i: Integer;
begin
  L := TStringList.Create;
  try
    if FSettings.UsePlaylistEpg then
    begin
      E := '';
      if (FSettings.LastPlaylist >= 0) and (FSettings.LastPlaylist < FSettings.PlaylistCount) then
        E := FSettings.Playlist(FSettings.LastPlaylist).Epg;
      if E <> '' then
        L.Add(E)
      else if FPlaylist <> nil then
        for i := 0 to FPlaylist.EpgUrls.Count - 1 do
          if L.IndexOf(FPlaylist.EpgUrls[i]) < 0 then L.Add(FPlaylist.EpgUrls[i]);
    end;
    for i := 0 to FSettings.EpgSources.Count - 1 do
      if L.IndexOf(FSettings.EpgSources[i]) < 0 then
        L.Add(FSettings.EpgSources[i]);

    if L.Count = 0 then
    begin
      Inc(FEpgGen);
      FEpgKey := '';
      guide.SetData(nil, 0, NowUtc);
      FreeAndNil(FEpg);
      ResolveEpg;
      RefreshGuide;
      Exit;
    end;
    Key := L.Text + '|' + IntToStr(FSettings.EpgPastDays) + '|' +
      HashStr(FSettings.Playlist(FSettings.LastPlaylist).Source);
    if (not Force) and (FEpg <> nil) and (FEpgKey = Key) then
    begin
      ResolveEpg;
      Exit;
    end;

    Inc(FEpgGen);
    T := TLoaderThread.Create;
    T.Kind := lkEpg;
    T.Sources.Assign(L);
    T.Source := Key;
    T.PastDays := FSettings.EpgPastDays;
    if FPlaylist <> nil then
      for i := 0 to FPlaylist.Count - 1 do
        T.Want.Add(FPlaylist.Get(i).TvgId + #1 + FPlaylist.Get(i).TvgName + #1 + FPlaylist.Get(i).Name);
    T.CacheDir := FSettings.CacheDir;
    T.Force := Force;
    T.Generation := FEpgGen;
    T.OnTerminate := @LoaderDone;
    SetInfo('Загрузка телепрограммы...');
    T.Start;
  finally
    L.Free;
  end;
end;

procedure TMainForm.LoaderDone(Sender: TObject);
var
  T: TLoaderThread;
  Ch: TChannel;
  Force: Boolean;
  GuideUrl: string;
begin
  if not GFormAlive then Exit;
  T := TLoaderThread(Sender);

  if T.Kind = lkPlaylist then
  begin
    if T.Generation <> FPlGen then Exit;
    if T.Refresh then
    begin
      { фоновое обновление: без интернета просто остаёмся на сохранённой копии }
      if not T.Ok then
      begin
        SetInfo('Нет связи — показан сохранённый плейлист');
        Exit;
      end;
      if T.Unchanged then Exit;
    end;
    if not T.Ok then
    begin
      if T.CacheOnly then
      begin
        LoadPlaylist(FSettings.LastPlaylist, True);
        Exit;
      end;
      SetInfo('');
      MessageDlg('Не удалось загрузить плейлист:' + LineEnding + T.ErrorMsg, mtError, [mbOK], 0);
      Exit;
    end;
    GuideUrl := '';
    if FGuideOpen and (FGuideChannel <> nil) then GuideUrl := FGuideChannel.URL;
    CloseGuide;
    FView.Clear;
    chView.SetChannels(nil);
    chView.Current := nil;
    FCurrent := nil;
    FreeAndNil(FPlaylist);
    FPlaylist := T.Playlist;
    T.Playlist := nil;
    if FPlaying then FCurrent := FPlaylist.FindByUrl(FCurrentUrl);
    chView.Current := FCurrent;
    if not T.Refresh then FInCategory := False;
    ApplyFilter;
    ResolveLogos;
    if GuideUrl <> '' then OpenGuide(FPlaylist.FindByUrl(GuideUrl));
    SetInfo(T.Warning);

    Force := FForceEpg;
    FForceEpg := False;
    LoadEpg(Force);
    if T.CacheOnly then LoadPlaylistRefresh(FSettings.LastPlaylist);

    if not FAutoPlayDone then
    begin
      FAutoPlayDone := True;
      if FSettings.AutoPlayLast and not FSettings.UseExternalPlayer then
      begin
        Ch := FPlaylist.FindByUrl(FSettings.LastUrl);
        if Ch <> nil then
        begin
          chView.Selected := chView.IndexOfChannel(Ch);
          PlayChannel(Ch);
        end;
      end;
    end;
    UpdateTransport;
  end
  else
  begin
    if T.Generation <> FEpgGen then Exit;
    if not T.Ok then
    begin
      SetInfo('Телепрограмма недоступна: ' + T.ErrorMsg);
      Exit;
    end;
    guide.SetData(nil, 0, NowUtc);
    FreeAndNil(FEpg);
    FEpg := T.Epg;
    T.Epg := nil;
    FEpgKey := T.Source;
    ResolveEpg;
    RefreshGuide;
    SetInfo(T.Warning);
  end;
end;

procedure TMainForm.ResolveEpg;
var
  i: Integer;
  Ch: TChannel;
begin
  if FPlaylist <> nil then
    for i := 0 to FPlaylist.Count - 1 do
    begin
      Ch := FPlaylist.Get(i);
      if FEpg <> nil then
        Ch.Epg := FEpg.FindChannel(Ch.TvgId, Ch.TvgName, Ch.Name)
      else
        Ch.Epg := nil;
    end;
  chView.Invalidate;
  pbInfo.Invalidate;
end;

procedure TMainForm.ApplyFilter;
var
  i, k, NoCatCount: Integer;
  Ch: TChannel;
  Q, Grp: string;
  Counts, Cats: TStringList;
  Tab: Integer;

  function Match(C: TChannel): Boolean;
  begin
    Result := (Q = '') or (Pos(Q, C.NameLower) > 0);
  end;

begin
  Tab := segTabs.ItemIndex;
  Q := UTF8LowerCase(Trim(edSearch.Text));
  FView.Clear;
  pnlBack.Visible := (Tab = TAB_CAT) and FInCategory and not FGuideOpen;
  if FInCategory then lblBack.Caption := FCategory;

  if FPlaylist = nil then
  begin
    chView.EmptyText := '';
    chView.SetChannels(nil);
    lblCount.Caption := '';
    Exit;
  end;

  { список категорий }
  if (Tab = TAB_CAT) and not FInCategory then
  begin
    Counts := TStringList.Create;
    Cats := TStringList.Create;
    try
      Counts.Sorted := True;
      Counts.CaseSensitive := True;
      NoCatCount := 0;
      for i := 0 to FPlaylist.Count - 1 do
      begin
        Grp := FPlaylist.Get(i).Group;
        if Grp = '' then
          Inc(NoCatCount)
        else if Counts.Find(Grp, k) then
          Counts.Objects[k] := TObject(PtrInt(Counts.Objects[k]) + 1)
        else
          Counts.AddObject(Grp, TObject(PtrInt(1)));
      end;
      for i := 0 to FPlaylist.Groups.Count - 1 do
      begin
        Grp := FPlaylist.Groups[i];
        if (Q <> '') and (Pos(Q, UTF8LowerCase(Grp)) = 0) then Continue;
        if Counts.Find(Grp, k) then
          Cats.AddObject(Grp, Counts.Objects[k]);
      end;
      if (NoCatCount > 0) and ((Q = '') or (Pos(Q, UTF8LowerCase(NO_CATEGORY)) > 0)) then
        Cats.AddObject(NO_CATEGORY, TObject(PtrInt(NoCatCount)));
      chView.EmptyText := 'В плейлисте нет категорий';
      chView.SetCategories(Cats);
      lblCount.Caption := Format('Категорий: %d', [Cats.Count]);
    finally
      Cats.Free;
      Counts.Free;
    end;
    Exit;
  end;

  { каналы }
  for i := 0 to FPlaylist.Count - 1 do
  begin
    Ch := FPlaylist.Get(i);
    case Tab of
      TAB_FAV: if not IsFav(Ch) then Continue;
      TAB_CAT:
        if FCategoryNone then
        begin
          if Ch.Group <> '' then Continue;
        end
        else if Ch.Group <> FCategory then Continue;
    end;
    if not Match(Ch) then Continue;
    FView.Add(Ch);
  end;

  if Tab = TAB_FAV then
    chView.EmptyText := 'Избранных каналов пока нет. Нажмите звёздочку под видео.'
  else
    chView.EmptyText := 'Ничего не найдено';
  chView.SetChannels(FView);

  if FView.Count = FPlaylist.Count then
    lblCount.Caption := Format('Каналов: %d', [FPlaylist.Count])
  else
    lblCount.Caption := Format('%d из %d', [FView.Count, FPlaylist.Count]);
end;

procedure TMainForm.OpenCategory(Index: Integer);
var
  CatName: string;
begin
  CatName := chView.SelectedCategory;
  if (Index >= 0) and chView.CatMode then
  begin
    FInCategory := True;
    FCategory := CatName;
    FCategoryNone := CatName = NO_CATEGORY;
    FUpdating := True;
    edSearch.Text := '';
    FUpdating := False;
    tmrSearch.Enabled := False;
    ApplyFilter;
    chView.ScrollToTop;
  end;
end;

{ ====================================================================== }
{ воспроизведение }

{ Новый проигрыватель создаётся для каждого канала, а старый останавливается
  и освобождается в фоновом потоке — окно не замирает при переключении. }
function TMainForm.StartMedia(Ch: TChannel; const Url: string): Boolean;
var
  M, Old: Pointer;
  SL: TStringList;
  i, NewSlot: Integer;
  Opt: string;
begin
  Result := False;
  if FVlc = nil then
  begin
    MessageDlg('Встроенный плеер недоступен.' + LineEnding + FVlcError + LineEnding + LineEnding +
      'Можно включить внешний плеер в Настройках → Плеер.', mtWarning, [mbOK], 0);
    Exit;
  end;
  if Pos('://', Url) > 0 then
    M := libvlc_media_new_location(FVlc, PAnsiChar(Url))
  else
    M := libvlc_media_new_path(FVlc, PAnsiChar(Url));
  if M = nil then
  begin
    FPlayerStatus := 'Неверная ссылка на поток';
    UpdateStatusLabel;
    Exit;
  end;
  libvlc_media_add_option(M, PAnsiChar(':network-caching=' + IntToStr(FSettings.NetworkCaching)));
  if Ch.Options <> '' then
  begin
    SL := TStringList.Create;
    try
      SL.Text := Ch.Options;
      for i := 0 to SL.Count - 1 do
      begin
        Opt := Trim(SL[i]);
        if Opt <> '' then libvlc_media_add_option(M, PAnsiChar(':' + Opt));
      end;
    finally
      SL.Free;
    end;
  end;

  NewSlot := AcquireSlot;
  if NewSlot < 0 then
  begin
    libvlc_media_release(M);
    FPlayerStatus := 'Предыдущий канал ещё закрывается, попробуйте через секунду';
    UpdateStatusLabel;
    Exit;
  end;
  Old := FPlayer;
  FPlayer := libvlc_media_player_new(FVlc);
  if FPlayer = nil then
  begin
    libvlc_media_release(M);
    FPlayer := Old;
    FVlcError := 'Не удалось создать проигрыватель';
    Exit;
  end;
  if Old <> nil then
  begin
    libvlc_audio_set_mute(Old, 1);
    ReleasePlayerAsync(Old, FSlot);
  end
  else if FSlot >= 0 then
    InterLockedExchange(GSlotBusy[FSlot], 0);
  libvlc_video_set_mouse_input(FPlayer, 0);
  libvlc_video_set_key_input(FPlayer, 0);
  pnlVideo.Caption := '';
  { новый плеер получает свою, свободную область видео }
  FSlot := NewSlot;
  InterLockedExchange(GSlotBusy[FSlot], 1);
  FSlots[FSlot].Visible := True;
  FSlots[FSlot].BringToFront;
  for i := 0 to VIDEO_SLOTS - 1 do
    if i <> FSlot then FSlots[i].Visible := False;
  AttachVideoTo(FPlayer, FSlots[FSlot]);
  libvlc_media_player_set_media(FPlayer, M);
  libvlc_media_release(M);
  libvlc_media_player_play(FPlayer);
  Result := True;
end;

function TMainForm.AcquireSlot: Integer;
var
  i, Tries: Integer;
begin
  for Tries := 0 to 150 do
  begin
    for i := 0 to VIDEO_SLOTS - 1 do
      if (i <> FSlot) and (GSlotBusy[i] = 0) then
        Exit(i);
    Sleep(20);
  end;
  Result := -1;
end;

procedure TMainForm.AfterPlayStarted(Ch: TChannel);
begin
  FInfoOffset := 0;
  FCurrent := Ch;
  FCurrentUrl := Ch.URL;
  FPlaying := True;
  FLastState := -1;
  FSettings.LastUrl := Ch.URL;
  FSettings.PushRecent(Ch.URL);
  if FArchive then
    FPlayerStatus := 'Архив: подключение...'
  else
    FPlayerStatus := 'Подключение...';
  UpdateStatusLabel;
  Caption := Ch.Name + ' — ' + APP_NAME;
  chView.Current := Ch;
  btnLive.Visible := FArchive;
  if FArchive then guide.PlayingStart := FArchiveStart else guide.PlayingStart := 0;
  guide.Invalidate;
  UpdateTransport;
  pbInfo.Invalidate;
end;

procedure TMainForm.PlayChannel(Ch: TChannel; ForceInternal: Boolean);
begin
  if Ch = nil then Exit;
  if FSettings.UseExternalPlayer and not ForceInternal then
  begin
    OpenExternal(Ch, Ch.URL);
    Exit;
  end;
  if StartMedia(Ch, Ch.URL) then
  begin
    FArchive := False;
    AfterPlayStarted(Ch);
  end;
end;

procedure TMainForm.PlayArchive(Ch: TChannel; It: TEpgItem);
var
  Url: string;
begin
  if (Ch = nil) or (It = nil) then Exit;
  Url := BuildArchiveUrl(Ch, FSettings.DefaultCatchup, It.Start, It.Stop, NowUtc);
  if Url = '' then
  begin
    MessageDlg('Для этого канала архив недоступен.' + LineEnding + LineEnding +
      'Если провайдер поддерживает архив, но не указал это в плейлисте, ' +
      'выберите тип архива в Настройках → Источники телепрограмм.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if FSettings.UseExternalPlayer then
  begin
    OpenExternal(Ch, Url);
    Exit;
  end;
  if StartMedia(Ch, Url) then
  begin
    FArchive := True;
    FArchiveStart := It.Start;
    FArchiveStop := It.Stop;
    FArchiveTitle := It.Title;
    AfterPlayStarted(Ch);
  end;
end;

procedure TMainForm.OpenExternal(Ch: TChannel; const AUrl: string);
var
  Exe, Url: string;
  P: TProcess;
  Args: TStringList;
  i: Integer;
  HasUrl: Boolean;
begin
  if Ch = nil then Exit;
  Url := AUrl;
  if Url = '' then Url := Ch.URL;
  Exe := FindExternalPlayer(FSettings.ExternalPlayer);
  if Exe = '' then
  begin
    if MessageDlg('Внешний плеер не найден. Указать программу в настройках?',
      mtConfirmation, [mbYes, mbNo], 0) = mrYes then
      OpenSettings(1);
    Exit;
  end;
  if FPlaying then StopPlayback;
  Args := TStringList.Create;
  P := TProcess.Create(nil);
  try
    SplitArgs(FSettings.ExternalArgs, Args);
    HasUrl := False;
    for i := 0 to Args.Count - 1 do
      if Pos('%u', Args[i]) > 0 then
      begin
        Args[i] := StringReplace(Args[i], '%u', Url, [rfReplaceAll]);
        HasUrl := True;
      end;
    if not HasUrl then Args.Add(Url);
    P.Executable := Exe;
    P.Parameters.Assign(Args);
    P.Options := [];
    try
      P.Execute;
      FCurrent := Ch;
      chView.Current := Ch;
      FSettings.LastUrl := Ch.URL;
      FSettings.PushRecent(Ch.URL);
      SetInfo('Открыто во внешнем плеере: ' + Ch.Name);
      pbInfo.Invalidate;
      UpdateTransport;
    except
      on E: Exception do
        MessageDlg('Не удалось запустить внешний плеер:' + LineEnding + Exe + LineEnding + E.Message,
          mtError, [mbOK], 0);
    end;
  finally
    P.Free;
    Args.Free;
  end;
end;

procedure TMainForm.StopPlayback;
begin
  if FPlayer <> nil then
  begin
    ReleasePlayerAsync(FPlayer, FSlot);
    FPlayer := nil;
  end;
  if FSlot >= 0 then FSlots[FSlot].Visible := False;
  FSlot := -1;
  FPlaying := False;
  FArchive := False;
  btnLive.Visible := False;
  guide.PlayingStart := 0;
  guide.Invalidate;
  FPlayerStatus := '';
  UpdateStatusLabel;
  pnlVideo.Caption := 'Остановлено';
  Caption := APP_NAME;
  UpdateTransport;
end;

procedure TMainForm.LiveClick(Sender: TObject);
begin
  if FCurrent <> nil then PlayChannel(FCurrent, True);
end;

{ ====================================================================== }
{ телепрограмма канала }

procedure TMainForm.OpenGuide(Ch: TChannel);
begin
  if Ch = nil then Exit;
  FGuideChannel := Ch;
  FGuideOpen := True;
  edSearch.Visible := False;
  pnlViewRow.Visible := False;
  pnlBack.Visible := False;
  chView.Visible := False;
  lblEmpty.Visible := False;
  pnlGuide.Visible := True;
  lblGuideTitle.Caption := Ch.Name;
  RefreshGuide;
  guide.ScrollToNow;
  if guide.CanFocus then guide.SetFocus;
end;

procedure TMainForm.RefreshGuide;
var
  Days: Integer;
  Ec: TEpgChannel;
begin
  if not FGuideOpen or (FGuideChannel = nil) then Exit;
  Days := 0;
  if HasArchive(FGuideChannel, FSettings.DefaultCatchup) then
    Days := ArchiveDays(FGuideChannel);
  Ec := nil;
  if FGuideChannel.Epg <> nil then Ec := TEpgChannel(FGuideChannel.Epg);
  if FEpg = nil then
    guide.EmptyText := 'Телепрограмма ещё не загружена или недоступна.'
  else
    guide.EmptyText := 'Для этого канала нет телепрограммы.';
  guide.SetData(Ec, Days, NowUtc);
  if FArchive and (FCurrent = FGuideChannel) then guide.PlayingStart := FArchiveStart
  else guide.PlayingStart := 0;
  if Days > 0 then
    lblGuideTitle.Hint := 'Архив: ' + IntToStr(Days) + ' дн.'
  else
    lblGuideTitle.Hint := 'Архив для этого канала не указан';
  lblGuideTitle.ShowHint := True;
  UpdateGuideDesc(guide.SelectedItem);
end;

procedure TMainForm.CloseGuide;
begin
  if not FGuideOpen then Exit;
  FGuideOpen := False;
  FGuideChannel := nil;
  pnlGuide.Visible := False;
  guide.SetData(nil, 0, NowUtc);
  edSearch.Visible := True;
  pnlViewRow.Visible := True;
  pnlBack.Visible := (segTabs.ItemIndex = TAB_CAT) and FInCategory;
  UpdateEmptyState;
  if chView.Visible and chView.CanFocus then chView.SetFocus;
end;

procedure TMainForm.UpdateGuideDesc(It: TEpgItem);
var
  S: string;
begin
  if It = nil then
  begin
    lblGuideDesc.Caption := '';
    Exit;
  end;
  S := FormatDateTime('dd.mm  hh:nn', UtcToLocal(It.Start)) + ' - ' +
       FormatDateTime('hh:nn', UtcToLocal(It.Stop)) + '   ' + It.Title;
  if guide.IsArchive(It) then S := S + LineEnding + 'Доступно в записи — щёлкните, чтобы смотреть.'
  else if guide.IsLive(It) then S := S + LineEnding + 'Сейчас в эфире — щёлкните, чтобы смотреть.';
  if It.Desc <> '' then S := S + LineEnding + LineEnding + It.Desc;
  lblGuideDesc.Caption := S;
end;

procedure TMainForm.GuideBackClick(Sender: TObject);
begin
  CloseGuide;
end;

procedure TMainForm.GuideSelect(Sender: TObject; Item: TEpgItem);
begin
  UpdateGuideDesc(Item);
end;

procedure TMainForm.GuideItemClick(Sender: TObject; Item: TEpgItem);
begin
  if (Item = nil) or (FGuideChannel = nil) then Exit;
  if guide.IsLive(Item) then
    PlayChannel(FGuideChannel)
  else if guide.IsArchive(Item) then
    PlayArchive(FGuideChannel, Item)
  else
    UpdateGuideDesc(Item);
end;

procedure TMainForm.ViewGuideClick(Sender: TObject; Index: Integer);
begin
  OpenGuide(chView.ChannelAt(Index));
end;

procedure TMainForm.MenuGuideClick(Sender: TObject);
begin
  OpenGuide(chView.SelectedChannel);
end;

procedure TMainForm.StepChannel(Delta: Integer);
var
  Idx: Integer;
  Ch: TChannel;
begin
  if chView.CatMode or (FView.Count = 0) then Exit;
  Idx := -1;
  if FCurrent <> nil then Idx := FView.IndexOf(FCurrent);
  if Idx < 0 then Idx := chView.Selected;
  if Idx < 0 then Idx := 0
  else Idx := (Idx + Delta + FView.Count) mod FView.Count;
  Ch := TChannel(FView[Idx]);
  chView.Selected := Idx;
  PlayChannel(Ch);
end;

procedure TMainForm.ToggleMute;
begin
  FSettings.Muted := not FSettings.Muted;
  if FSettings.Muted then btnMute.Kind := ikMute else btnMute.Kind := ikVolume;
  ApplyVolume;
end;

procedure TMainForm.ToggleFavorite(Ch: TChannel);
begin
  if Ch = nil then Exit;
  FSettings.ToggleFavorite(Ch.URL);
  if segTabs.ItemIndex = TAB_FAV then ApplyFilter else chView.Invalidate;
  UpdateTransport;
end;

{ ====================================================================== }
{ запись эфира }

procedure TMainForm.StartRecording(Ch: TChannel);
var
  M: Pointer;
  Dir, Dst: string;
  SL: TStringList;
  i: Integer;
begin
  if Ch = nil then
  begin
    MessageDlg('Сначала выберите канал.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if FVlc = nil then
  begin
    MessageDlg('Запись недоступна: ' + FVlcError, mtWarning, [mbOK], 0);
    Exit;
  end;
  if FRecPlayer <> nil then StopRecording('');

  Dir := IncludeTrailingPathDelimiter(FSettings.RecordDir);
  if not ForceDirectories(Dir) then
  begin
    if MessageDlg('Не удалось создать папку для записей:' + LineEnding + Dir + LineEnding +
      'Выбрать другую папку в настройках?', mtError, [mbYes, mbNo], 0) = mrYes then
      OpenSettings(2);
    Exit;
  end;
  FRecFile := Dir + SafeFileName(Ch.Name) + FormatDateTime('_yyyy-mm-dd_hh-nn-ss', Now) + '.ts';
  Dst := FRecFile;
{$IFDEF WINDOWS}
  Dst := StringReplace(Dst, '\', '/', [rfReplaceAll]);
{$ENDIF}

  if Pos('://', Ch.URL) > 0 then
    M := libvlc_media_new_location(FVlc, PAnsiChar(Ch.URL))
  else
    M := libvlc_media_new_path(FVlc, PAnsiChar(Ch.URL));
  if M = nil then Exit;
  if Ch.Options <> '' then
  begin
    SL := TStringList.Create;
    try
      SL.Text := Ch.Options;
      for i := 0 to SL.Count - 1 do
        if Trim(SL[i]) <> '' then
          libvlc_media_add_option(M, PAnsiChar(':' + Trim(SL[i])));
    finally
      SL.Free;
    end;
  end;
  libvlc_media_add_option(M, PAnsiChar(':network-caching=' + IntToStr(FSettings.NetworkCaching)));
  libvlc_media_add_option(M, PAnsiChar(':sout=#std{access=file,mux=ts,dst="' + Dst + '"}'));
  libvlc_media_add_option(M, ':sout-all');
  libvlc_media_add_option(M, ':sout-keep');

  FRecPlayer := libvlc_media_player_new(FVlc);
  if FRecPlayer = nil then
  begin
    libvlc_media_release(M);
    Exit;
  end;
  libvlc_media_player_set_media(FRecPlayer, M);
  libvlc_media_release(M);
  libvlc_media_player_play(FRecPlayer);
  FRecName := Ch.Name;
  FRecStart := Now;
  lblRec.Caption := 'ЗАПИСЬ 00:00:00';
  lblRec.Hint := FRecName + LineEnding + FRecFile;
  lblRec.ShowHint := True;
  UpdateTransport;
end;

procedure TMainForm.StopRecording(const Reason: string);
begin
  if FRecPlayer = nil then Exit;
  ReleasePlayerAsync(FRecPlayer);
  FRecPlayer := nil;
  lblRec.Caption := '';
  if Reason <> '' then
    MessageDlg(Reason, mtWarning, [mbOK], 0)
  else
    SetInfo('Запись сохранена: ' + FRecFile);
  UpdateTransport;
end;

{ ====================================================================== }
{ настройки }

{ Страница настроек открывается поверх основной части окна (ниже заголовка),
  остальные панели не прячутся и не перестраиваются. }
procedure TMainForm.PlaceSettings;
var
  T: Integer;
begin
  if pgSettings = nil then Exit;
  T := 0;
  if pnlTitle.Visible then T := pnlTitle.Top + pnlTitle.Height;
  pgSettings.SetBounds(0, T, pnlRoot.ClientWidth, Math.Max(100, pnlRoot.ClientHeight - T));
end;

procedure TMainForm.OpenSettings(Page: Integer);
begin
  try
    if FFullscreen then SetFullscreen(False);
    if FWall then SetChannelWall(False);
    if pgSettings = nil then
    begin
      Log('создание страницы настроек');
      pgSettings := TSettingsPage.CreatePage(Self, FSettings);
      pgSettings.Visible := False;
      pgSettings.Align := alNone;
      pgSettings.Parent := pnlRoot;
      pgSettings.OnClose := @SettingsPageClose;
      pgSettings.OnImported := @SettingsPageImported;
      pgSettings.OnClearLogos := @SettingsClearLogos;
    end;
    if not FSettingsOpen then
    begin
      FSettingsOldFrame := FSettings.SystemFrame;
      FSettingsOldProxy := FSettings.LogoProxy;
      pgSettings.LoadValues;
    end;
    pgSettings.ShowSection(Page);
    FSettingsOpen := True;
    PlaceSettings;
    { окно видео прячем, чтобы оно не просвечивало поверх настроек }
    if FSlot >= 0 then FSlots[FSlot].Visible := False;
    pgSettings.Visible := True;
    pgSettings.BringToFront;
    btnMenuSettings.Checked := True;
  except
    on E: Exception do
    begin
      FSettingsOpen := False;
      if pgSettings <> nil then pgSettings.Visible := False;
      ReportFatal(E, 'Открытие настроек');
    end;
  end;
end;

procedure TMainForm.CloseSettings;
begin
  if not FSettingsOpen then Exit;
  FSettingsOpen := False;
  pgSettings.Visible := False;
  if FSlot >= 0 then FSlots[FSlot].Visible := True;
  btnMenuSettings.Checked := False;
  ApplyViewSettings;
  FLogos.SetUseProxy(FSettings.LogoProxy);
  if FSettings.LogoProxy <> FSettingsOldProxy then FLogos.Reset;
  if FPlaylist <> nil then LoadEpg(False);
  ApplyFilter;
  if FSettings.LogoDbEnabled then StartLogoDb;
  ResolveLogos;
  if FSettings.SystemFrame <> FSettingsOldFrame then
    MessageDlg('Вид рамки окна изменится после перезапуска программы.', mtInformation, [mbOK], 0);
end;

procedure TMainForm.SettingsPageClose(Sender: TObject);
begin
  CloseSettings;
end;

procedure TMainForm.ApplyAfterImport;
begin
  ApplyViewSettings;
  sldVolume.Position := FSettings.Volume;
  if FSettings.Muted then btnMute.Kind := ikMute else btnMute.Kind := ikVolume;
  segTabs.ItemIndex := FSettings.LastTab;
  FInCategory := False;
  RefreshPlaylistCombo;
  if FSettings.PlaylistCount > 0 then
    LoadPlaylist(cbPlaylists.ItemIndex, True)
  else
  begin
    CloseGuide;
    FreeAndNil(FPlaylist);
    ApplyFilter;
  end;
end;

procedure TMainForm.SettingsPageImported(Sender: TObject);
begin
  ApplyAfterImport;
end;

procedure TMainForm.SettingsClearLogos(Sender: TObject);
var
  SR: TSearchRec;
  Dir: string;
begin
  Dir := FSettings.CacheDir + 'logos' + PathDelim;
  if FindFirst(Dir + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Attr and faDirectory) = 0 then DeleteFile(Dir + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  FLogos.Reset;
  chView.Invalidate;
  pbInfo.Invalidate;
end;

{ ---------- база логотипов по названию ---------- }

procedure TMainForm.StartLogoDb;
var
  T: TLogoDbLoader;
begin
  if (FLogoDb <> nil) or FLogoDbLoading or not FSettings.LogoDbEnabled then Exit;
  FLogoDbLoading := True;
  T := TLogoDbLoader.Create(FSettings.CacheDir);
  T.OnTerminate := @LogoDbDone;
  T.Start;
end;

procedure TMainForm.LogoDbDone(Sender: TObject);
var
  T: TLogoDbLoader;
begin
  if not GFormAlive then Exit;
  T := TLogoDbLoader(Sender);
  FLogoDbLoading := False;
  if T.Db <> nil then
  begin
    FreeAndNil(FLogoDb);
    FLogoDb := T.Db;
    T.Db := nil;
    ResolveLogos;
  end
  else if T.ErrorMsg <> '' then
    Log('база логотипов: ' + T.ErrorMsg);
end;

procedure TMainForm.ResolveLogos;
var
  i: Integer;
  Ch: TChannel;
  Tpl, U: string;
begin
  if FPlaylist = nil then Exit;
  Tpl := Trim(FSettings.LogoTemplate);
  for i := 0 to FPlaylist.Count - 1 do
  begin
    Ch := FPlaylist.Get(i);
    if Tpl <> '' then
    begin
      U := StringReplace(Tpl, '{name}', UrlEncode(Ch.Name), [rfReplaceAll]);
      U := StringReplace(U, '{key}', UrlEncode(LogoKey(Ch.Name)), [rfReplaceAll]);
      U := StringReplace(U, '{id}', UrlEncode(Ch.TvgId), [rfReplaceAll]);
      Ch.LogoAlt := U;
    end
    else
      Ch.LogoAlt := '';
    if FSettings.LogoDbEnabled and (FLogoDb <> nil) then
      Ch.LogoDb := FLogoDb.Find(Ch.TvgName, Ch.Name)
    else
      Ch.LogoDb := '';
  end;
  chView.Invalidate;
  pbInfo.Invalidate;
end;

{ ====================================================================== }
{ обработчики формы }

procedure TMainForm.FormShow(Sender: TObject);
begin
  if FShown then Exit;
  FShown := True;
  Log('показ окна');
  if not FSystemFrame then PrepareBorderless(Self);
  if FSettings.OpenMaximized or FSettings.WinMaximized then
    SetMaximized(True)
  else
    UpdateFrameControls;
  RefreshPlaylistCombo;
  ApplyFilter;
  if FSettings.PlaylistCount > 0 then
    LoadPlaylist(cbPlaylists.ItemIndex, False);
  StartLogoDb;
end;

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  if FRecPlayer <> nil then StopRecording('');
  if FFullscreen then SetFullscreen(False);
  if FWall then SetChannelWall(False);
  FSettings.WinMaximized := FMaxed;
  if FMaxed and not FSystemFrame then
  begin
    FSettings.WinLeft := FNormalBounds.Left;
    FSettings.WinTop := FNormalBounds.Top;
    FSettings.WinWidth := FNormalBounds.Right - FNormalBounds.Left;
    FSettings.WinHeight := FNormalBounds.Bottom - FNormalBounds.Top;
  end
  else if WindowState = wsNormal then
  begin
    FSettings.WinLeft := Left;
    FSettings.WinTop := Top;
    FSettings.WinWidth := Width;
    FSettings.WinHeight := Height;
  end;
  if (pnlSide.Width >= 250) and (pnlSide.Width <= 1200) then
    FSettings.SideWidth := pnlSide.Width;
  if (pnlBottom.Height - 50 >= 60) and (pnlBottom.Height - 50 <= 700) then
    FSettings.InfoHeight := pnlBottom.Height - 50;
  if (FSettings.WinWidth < 760) or (FSettings.WinWidth > Screen.DesktopWidth) or
     (FSettings.WinHeight < 460) or (FSettings.WinHeight > Screen.DesktopHeight) then
  begin
    FSettings.WinWidth := 1180;
    FSettings.WinHeight := 720;
    FSettings.WinLeft := -1;
    FSettings.WinTop := -1;
  end;
  FSettings.LastTab := segTabs.ItemIndex;
  FSettings.ViewMode := Ord(chView.Mode);
  if not FPlaying then FSettings.LastUrl := '';
  FSettings.Save;
  tmrStatus.Enabled := False;
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  InEdit: Boolean;
begin
  InEdit := ActiveControl = edSearch;
  if FSettingsOpen and (Key <> VK_ESCAPE) then Exit;
  if ssCtrl in Shift then
  begin
    case Key of
      VK_F:
        begin
          if FFullscreen then SetFullscreen(False);
          if edSearch.CanFocus then edSearch.SetFocus;
          Key := 0;
        end;
      VK_R:
        begin
          RecClick(nil);
          Key := 0;
        end;
    end;
    Exit;
  end;
  case Key of
    VK_F11:
      begin
        SetFullscreen(not FFullscreen);
        Key := 0;
      end;
    VK_F5:
      begin
        ReloadClick(nil);
        Key := 0;
      end;
    VK_ESCAPE:
      if FSettingsOpen then
      begin
        pgSettings.SaveValues;
        CloseSettings;
        Key := 0;
      end
      else if FFullscreen then
      begin
        SetFullscreen(False);
        Key := 0;
      end
      else if FGuideOpen then
      begin
        CloseGuide;
        Key := 0;
      end
      else if FWall then
      begin
        SetChannelWall(False);
        Key := 0;
      end
      else if InEdit and (edSearch.Text <> '') then
      begin
        edSearch.Text := '';
        Key := 0;
      end;
    VK_G:
      if (not InEdit) and (Shift = []) then
      begin
        SetChannelWall(not FWall);
        Key := 0;
      end;
    VK_E:
      if (not InEdit) and (Shift = []) then
      begin
        if FGuideOpen then CloseGuide
        else
        begin
          if FFullscreen then SetFullscreen(False);
          OpenGuide(TargetChannel);
        end;
        Key := 0;
      end;
    VK_BACK:
      if (not InEdit) and FGuideOpen then
      begin
        CloseGuide;
        Key := 0;
      end
      else if (not InEdit) and FInCategory then
      begin
        BackClick(nil);
        Key := 0;
      end;
    VK_PRIOR:
      begin
        StepChannel(-1);
        Key := 0;
      end;
    VK_NEXT:
      begin
        StepChannel(1);
        Key := 0;
      end;
    VK_UP, VK_DOWN:
      if FFullscreen then
      begin
        if Key = VK_UP then StepChannel(-1) else StepChannel(1);
        Key := 0;
      end;
    VK_F:
      if (not InEdit) and (Shift = []) then
      begin
        SetFullscreen(not FFullscreen);
        Key := 0;
      end;
    VK_M:
      if (not InEdit) and (Shift = []) then
      begin
        ToggleMute;
        Key := 0;
      end;
    VK_SPACE:
      if not InEdit then
      begin
        StopClick(nil);
        Key := 0;
      end;
  end;
end;

procedure TMainForm.TabsChange(Sender: TObject);
begin
  CloseGuide;
  FInCategory := False;
  FSettings.LastTab := segTabs.ItemIndex;
  ApplyFilter;
  chView.ScrollToTop;
  if FCurrent <> nil then chView.EnsureVisible(chView.IndexOfChannel(FCurrent));
end;

procedure TMainForm.BackClick(Sender: TObject);
begin
  FInCategory := False;
  ApplyFilter;
end;

procedure TMainForm.ViewModeClick(Sender: TObject);
begin
  chView.Mode := TViewMode(TFlatButton(Sender).Tag);
  FSettings.ViewMode := TFlatButton(Sender).Tag;
  UpdateViewButtons;
end;

procedure TMainForm.AddClick(Sender: TObject);
var
  N, S, E: string;
  Idx: Integer;
begin
  N := '';
  S := '';
  E := '';
  if not EditPlaylist(Self, 'Новый плейлист', N, S, E) then Exit;
  Idx := FSettings.AddPlaylist(N, S, E);
  FSettings.LastPlaylist := Idx;
  FSettings.Save;
  RefreshPlaylistCombo;
  LoadPlaylist(Idx, False);
end;

procedure TMainForm.EditClick(Sender: TObject);
var
  Idx: Integer;
  P: TPlaylistEntry;
  N, S, E: string;
begin
  Idx := cbPlaylists.ItemIndex;
  if Idx < 0 then Exit;
  P := FSettings.Playlist(Idx);
  N := P.Name;
  S := P.Source;
  E := P.Epg;
  if not EditPlaylist(Self, 'Изменить плейлист', N, S, E) then Exit;
  P.Name := N;
  P.Source := S;
  P.Epg := E;
  FSettings.Save;
  RefreshPlaylistCombo;
  LoadPlaylist(Idx, False);
end;

procedure TMainForm.RemoveClick(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := cbPlaylists.ItemIndex;
  if Idx < 0 then Exit;
  if MessageDlg('Удалить плейлист «' + FSettings.Playlist(Idx).Name + '» из списка?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  FSettings.DeletePlaylist(Idx);
  FSettings.LastPlaylist := 0;
  FSettings.Save;
  RefreshPlaylistCombo;
  if FSettings.PlaylistCount > 0 then
    LoadPlaylist(cbPlaylists.ItemIndex, False)
  else
  begin
    Inc(FPlGen);
    Inc(FEpgGen);
    FView.Clear;
    chView.SetChannels(nil);
    chView.Current := nil;
    FCurrent := nil;
    FreeAndNil(FPlaylist);
    ApplyFilter;
    SetInfo('');
  end;
end;

procedure TMainForm.ReloadClick(Sender: TObject);
begin
  if cbPlaylists.ItemIndex >= 0 then
    LoadPlaylist(cbPlaylists.ItemIndex, True);
end;

procedure TMainForm.PrevClick(Sender: TObject);
begin
  StepChannel(-1);
end;

procedure TMainForm.NextClick(Sender: TObject);
begin
  StepChannel(1);
end;

procedure TMainForm.StopClick(Sender: TObject);
var
  Ch: TChannel;
begin
  if FPlaying then
    StopPlayback
  else
  begin
    Ch := chView.SelectedChannel;
    if Ch = nil then Ch := FCurrent;
    PlayChannel(Ch);
  end;
end;

procedure TMainForm.FavClick(Sender: TObject);
begin
  ToggleFavorite(TargetChannel);
end;

procedure TMainForm.RecClick(Sender: TObject);
begin
  if FRecPlayer <> nil then
    StopRecording('')
  else
    StartRecording(TargetChannel);
end;

procedure TMainForm.ExtClick(Sender: TObject);
begin
  OpenExternal(TargetChannel);
end;

procedure TMainForm.MuteClick(Sender: TObject);
begin
  ToggleMute;
end;

procedure TMainForm.FullClick(Sender: TObject);
begin
  SetFullscreen(not FFullscreen);
end;

procedure TMainForm.SettingsClick(Sender: TObject);
begin
  OpenSettings(0);
end;

procedure TMainForm.VolumeChange(Sender: TObject);
begin
  FSettings.Volume := sldVolume.Position;
  if FSettings.Muted and (FSettings.Volume > 0) then
  begin
    FSettings.Muted := False;
    btnMute.Kind := ikVolume;
  end;
  ApplyVolume;
end;

procedure TMainForm.PlaylistChange(Sender: TObject);
begin
  if FUpdating then Exit;
  LoadPlaylist(cbPlaylists.ItemIndex, False);
end;

procedure TMainForm.SearchChange(Sender: TObject);
begin
  if FUpdating then Exit;
  tmrSearch.Enabled := False;
  tmrSearch.Enabled := True;
end;

procedure TMainForm.SearchTimer(Sender: TObject);
begin
  tmrSearch.Enabled := False;
  ApplyFilter;
  chView.ScrollToTop;
end;

procedure TMainForm.ViewItemClick(Sender: TObject; Index: Integer);
var
  Ch: TChannel;
begin
  tmrSelect.Enabled := False;
  if chView.CatMode then
  begin
    OpenCategory(Index);
    Exit;
  end;
  Ch := chView.ChannelAt(Index);
  UpdateTransport;
  if FWall and (Ch <> nil) then
  begin
    SetChannelWall(False);
    PlayChannel(Ch);
    Exit;
  end;
  if (Ch <> nil) and ((Ch <> FCurrent) or (not FPlaying and not FSettings.UseExternalPlayer)) then
    PlayChannel(Ch);
end;

procedure TMainForm.ViewItemActivate(Sender: TObject; Index: Integer);
var
  Ch: TChannel;
begin
  tmrSelect.Enabled := False;
  if chView.CatMode then
  begin
    OpenCategory(Index);
    Exit;
  end;
  Ch := chView.ChannelAt(Index);
  if Ch = nil then Exit;
  if FWall then SetChannelWall(False);
  if (Ch <> FCurrent) or not FPlaying then PlayChannel(Ch);
end;

procedure TMainForm.ViewSelectionMoved(Sender: TObject; Index: Integer);
begin
  UpdateTransport;
  if chView.CatMode or FSettings.UseExternalPlayer or FWall then Exit;
  tmrSelect.Enabled := False;
  tmrSelect.Enabled := True;
end;

procedure TMainForm.SelectTimer(Sender: TObject);
var
  Ch: TChannel;
begin
  tmrSelect.Enabled := False;
  Ch := chView.SelectedChannel;
  if (Ch <> nil) and ((Ch <> FCurrent) or not FPlaying) then
    PlayChannel(Ch);
end;

procedure TMainForm.VideoDblClick(Sender: TObject);
begin
  SetFullscreen(not FFullscreen);
end;

procedure TMainForm.InfoPaint(Sender: TObject);
var
  C: TCanvas;
  W, H, X, Y, LS, LineH, k, BarW, TW: Integer;
  It, Prev: TEpgItem;
  S, T: string;
  Frac: Double;
  B: TBitmap;
  Live, Past, Arch: Boolean;
begin
  C := pbInfo.Canvas;
  W := pbInfo.Width;
  H := pbInfo.Height;
  C.Brush.Style := bsSolid;
  C.Brush.Color := clrBg;
  C.FillRect(Rect(0, 0, W, H));
  C.Font.Assign(Font);
  C.Brush.Style := bsClear;
  X := 16;
  Y := 8;
  SetLength(FInfoItems, 0);

  if FCurrent = nil then
  begin
    C.Font.Size := 10;
    C.Font.Color := clrDim;
    C.TextOut(X, Y + 18, 'Ничего не воспроизводится');
    Exit;
  end;

  { логотип }
  if FSettings.ShowLogos then
  begin
    LS := Math.Min(H - 16, 60);
    if LS >= 16 then
    begin
      B := ChannelLogo(FLogos, FCurrent, LS, clrBg);
      if B <> nil then
      begin
        C.Draw(X, 8, B);
        Inc(X, LS + 14);
      end;
    end;
  end;
  FInfoX := X;

  C.Font.Size := 12;
  C.Font.Style := [fsBold];
  C.Font.Color := clrText;
  S := FCurrent.Name;
  if FSettings.ShowNumbers then S := IntToStr(FCurrent.Number) + '.  ' + S;
  C.TextOut(X, Y, Ellipsize(C, S, W - X - 16));
  Inc(Y, C.TextHeight('Ag') + 4);

  C.Font.Size := 9;
  C.Font.Style := [];
  if FArchive then
  begin
    C.Font.Color := clrAccent;
    S := 'АРХИВ   ' + FormatDateTime('dd.mm  hh:nn', UtcToLocal(FArchiveStart)) + ' - ' +
      FormatDateTime('hh:nn', UtcToLocal(FArchiveStop)) + '   ' + FArchiveTitle;
    C.TextOut(X, Y, Ellipsize(C, S, W - X - 16));
    Inc(Y, C.TextHeight('Ag') + 2);
    C.Font.Color := clrDim;
    C.TextOut(X, Y, 'Кнопка «В эфир» внизу вернёт к прямой трансляции');
    Exit;
  end;

  if FCurrent.Epg = nil then
  begin
    C.Font.Color := clrDim;
    if FEpg = nil then
      C.TextOut(X, Y, 'Телепрограмма не загружена')
    else
      C.TextOut(X, Y, 'Нет телепрограммы для этого канала');
    Exit;
  end;

  { список передач: сколько помещается по высоте панели }
  LineH := C.TextHeight('Ag') + 6;
  FInfoLinesTop := Y;
  FInfoLineH := LineH;
  BarW := 150;
  Prev := nil;
  k := 0;
  while (Y + LineH <= H + 4) or (k = 0) do
  begin
    It := InfoItem(FInfoOffset + k);
    if (It = nil) or (It = Prev) then Break;
    Live := (It.Start <= FNowUtc) and (FNowUtc < It.Stop);
    Past := It.Stop <= FNowUtc;
    Arch := Past and ItemInArchive(FCurrent, It);

    T := FormatDateTime('hh:nn', UtcToLocal(It.Start));
    if Trunc(UtcToLocal(It.Start)) <> Trunc(Now) then
      T := FormatDateTime('dd.mm', UtcToLocal(It.Start)) + '  ' + T;
    S := It.Title;
    if Arch then S := S + '   · смотреть в записи';

    if Live then
    begin
      C.Font.Style := [fsBold];
      C.Font.Color := clrText;
    end
    else if Arch then
    begin
      C.Font.Style := [];
      C.Font.Color := clrAccent;
    end
    else if Past then
    begin
      C.Font.Style := [];
      C.Font.Color := clrDim;
    end
    else
    begin
      C.Font.Style := [];
      C.Font.Color := clrText;
    end;
    C.TextOut(X, Y, T);
    TW := C.TextWidth('00.00  00:00') + 12;
    if Live then
    begin
      C.TextOut(X + TW, Y, Ellipsize(C, S, W - X - TW - BarW - 32));
      Frac := (FNowUtc - It.Start) / Math.Max(1e-9, It.Stop - It.Start);
      if Frac < 0 then Frac := 0;
      if Frac > 1 then Frac := 1;
      C.Brush.Style := bsSolid;
      C.Brush.Color := clrTrack;
      C.FillRect(Rect(W - BarW - 16, Y + 7, W - 16, Y + 11));
      C.Brush.Color := clrAccent;
      C.FillRect(Rect(W - BarW - 16, Y + 7, W - BarW - 16 + Round(BarW * Frac), Y + 11));
      C.Brush.Style := bsClear;
    end
    else
      C.TextOut(X + TW, Y, Ellipsize(C, S, W - X - TW - 16));

    SetLength(FInfoItems, k + 1);
    FInfoItems[k] := It;
    Prev := It;
    Inc(Y, LineH);
    Inc(k);
  end;
  C.Font.Style := [];
end;

procedure TMainForm.StatusTimer(Sender: TObject);
var
  St: Integer;
  S: string;
begin
  FNowUtc := NowUtc;
  chView.NowUtc := FNowUtc;
  guide.NowUtc := FNowUtc;
  if FLogos.TakeChanged then
  begin
    chView.Invalidate;
    pbInfo.Invalidate;
  end;
  if (FPlayer <> nil) and FPlaying then
  begin
    St := libvlc_media_player_get_state(FPlayer);
    if St <> FLastState then
    begin
      FLastState := St;
      case St of
        VLC_STATE_OPENING:   S := 'Подключение...';
        VLC_STATE_BUFFERING: S := 'Буферизация...';
        VLC_STATE_PLAYING:
          begin
            if FArchive then S := 'Запись из архива' else S := '';
            ApplyVolume;
          end;
        VLC_STATE_PAUSED:    S := 'Пауза';
        VLC_STATE_ENDED:     S := 'Трансляция завершилась';
        VLC_STATE_ERROR:     S := 'Не удалось открыть поток. Канал недоступен или ссылка устарела.';
      else
        S := '';
      end;
      FPlayerStatus := S;
      UpdateStatusLabel;
    end;
  end;

  if FRecPlayer <> nil then
  begin
    St := libvlc_media_player_get_state(FRecPlayer);
    if St = VLC_STATE_ERROR then
      StopRecording('Запись остановлена: не удалось получить поток канала «' + FRecName + '».')
    else if St = VLC_STATE_ENDED then
      StopRecording('Трансляция канала «' + FRecName + '» завершилась, запись сохранена:' +
        LineEnding + FRecFile)
    else
      lblRec.Caption := 'ЗАПИСЬ ' + FormatDateTime('hh:nn:ss', Now - FRecStart);
  end;

  if FInfoOffset <> 0 then
  begin
    Inc(FInfoIdle);
    if FInfoIdle > 40 then   { через 20 секунд возвращаемся к текущей передаче }
    begin
      FInfoOffset := 0;
      pbInfo.Invalidate;
    end;
  end;
  Inc(FTick);
  if FTick mod 30 = 0 then
  begin
    chView.Invalidate;
    pbInfo.Invalidate;
    if FGuideOpen then guide.Invalidate;
  end;
end;

{ ---------- расписание под видео: листание ---------- }

function TMainForm.InfoItem(Offset: Integer): TEpgItem;
var
  Ec: TEpgChannel;
  i, Base: Integer;
begin
  Result := nil;
  if (FCurrent = nil) or (FCurrent.Epg = nil) then Exit;
  Ec := TEpgChannel(FCurrent.Epg);
  if Ec.Items.Count = 0 then Exit;
  Base := Ec.Items.Count - 1;
  for i := 0 to Ec.Items.Count - 1 do
    if TEpgItem(Ec.Items[i]).Stop > FNowUtc then
    begin
      Base := i;
      Break;
    end;
  i := Base + Offset;
  if i < 0 then i := 0;
  if i >= Ec.Items.Count then i := Ec.Items.Count - 1;
  Result := TEpgItem(Ec.Items[i]);
end;

function TMainForm.ItemInArchive(Ch: TChannel; It: TEpgItem): Boolean;
begin
  Result := (Ch <> nil) and (It <> nil) and (It.Stop <= FNowUtc) and
    HasArchive(Ch, FSettings.DefaultCatchup) and
    (It.Start >= FNowUtc - ArchiveDays(Ch));
end;

procedure TMainForm.InfoUpClick(Sender: TObject);
begin
  if (FCurrent = nil) or (FCurrent.Epg = nil) then Exit;
  if InfoItem(FInfoOffset - 1) <> InfoItem(FInfoOffset) then Dec(FInfoOffset);
  FInfoIdle := 0;
  pbInfo.Invalidate;
end;

procedure TMainForm.InfoDownClick(Sender: TObject);
begin
  if (FCurrent = nil) or (FCurrent.Epg = nil) then Exit;
  if InfoItem(FInfoOffset + 1) <> InfoItem(FInfoOffset) then Inc(FInfoOffset);
  FInfoIdle := 0;
  pbInfo.Invalidate;
end;

procedure TMainForm.InfoWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint; var Handled: Boolean);
begin
  if FArchive then Exit;
  if WheelDelta > 0 then InfoUpClick(nil) else InfoDownClick(nil);
  Handled := True;
end;

procedure TMainForm.InfoClick(Sender: TObject);
var
  P: TPoint;
  Idx: Integer;
  It: TEpgItem;
begin
  if (FCurrent = nil) or (FInfoLineH <= 0) or (Length(FInfoItems) = 0) then Exit;
  P := pbInfo.ScreenToClient(Mouse.CursorPos);
  if P.Y < FInfoLinesTop then Exit;
  Idx := (P.Y - FInfoLinesTop) div FInfoLineH;
  if (Idx < 0) or (Idx > High(FInfoItems)) then Exit;
  It := FInfoItems[Idx];
  if ItemInArchive(FCurrent, It) then
    PlayArchive(FCurrent, It)
  else if (It.Start <= FNowUtc) and (FNowUtc < It.Stop) and FArchive then
    PlayChannel(FCurrent, True);
end;

procedure TMainForm.InfoDblClick(Sender: TObject);
begin
  OpenGuide(FCurrent);
end;

{ ---------- все каналы на весь экран ---------- }

procedure TMainForm.SetChannelWall(Value: Boolean);
begin
  if Value = FWall then Exit;
  if Value and FFullscreen then SetFullscreen(False);
  FWall := Value;
  btnWall.Checked := Value;
  if Value then
  begin
    if FPlaying then StopPlayback;
    FWallPrevMode := chView.Mode;
    FWallSideWidth := pnlSide.Width;
    if chView.Mode in [vmList, vmCompact] then chView.Mode := vmGrid;
    chView.Large := True;
    pnlSide.Constraints.MaxWidth := 0;
    pnlMain.Visible := False;
    splSide.Visible := False;
    pnlSide.Align := alClient;
    btnWall.Hint := 'Вернуться к плееру (G или Esc)';
  end
  else
  begin
    pnlSide.Align := alLeft;
    pnlSide.Width := FWallSideWidth;
    pnlMain.Visible := True;
    splSide.Visible := True;
    splSide.Left := pnlSide.Left + pnlSide.Width + 1;
    chView.Large := False;
    chView.Mode := FWallPrevMode;
    btnWall.Hint := 'Все каналы на весь экран (G)';
    UpdateSideMax;
  end;
  UpdateViewButtons;
  if FCurrent <> nil then chView.EnsureVisible(chView.IndexOfChannel(FCurrent));
end;

procedure TMainForm.WallClick(Sender: TObject);
begin
  SetChannelWall(not FWall);
end;

procedure TMainForm.UpdateSideMax;
var
  M: Integer;
begin
  if FWall or FFullscreen or (pnlRoot = nil) or (pnlSide = nil) then Exit;
  M := pnlRoot.ClientWidth - 380;
  if M < 260 then M := 260;
  if pnlSide.Constraints.MaxWidth <> M then
    pnlSide.Constraints.MaxWidth := M;
end;

procedure TMainForm.FormResize(Sender: TObject);
var
  M: Integer;
begin
  if WindowState = wsMinimized then Exit;
  UpdateSideMax;
  if FSettingsOpen then PlaceSettings;
  if (pnlBottom <> nil) and (pnlMain <> nil) and pnlBottom.Visible then
  begin
    M := pnlMain.ClientHeight - 140;
    if M < 120 then M := 120;
    if pnlBottom.Constraints.MaxHeight <> M then
      pnlBottom.Constraints.MaxHeight := M;
  end;
end;

procedure TMainForm.FormWindowStateChange(Sender: TObject);
begin
  { пока окно свёрнуто, не пересчитываем раскладку панелей }
  if WindowState = wsMinimized then
  begin
    if not FAlignOff then
    begin
      pnlRoot.DisableAlign;
      FAlignOff := True;
    end;
  end
  else if FAlignOff then
  begin
    FAlignOff := False;
    pnlRoot.EnableAlign;
    UpdateSideMax;
  end;
end;

procedure TMainForm.MenuPopup(Sender: TObject);
var
  Ch: TChannel;
begin
  Ch := chView.SelectedChannel;
  miPlay.Enabled := Ch <> nil;
  miGuide.Enabled := Ch <> nil;
  miExternal.Enabled := Ch <> nil;
  miRecord.Enabled := Ch <> nil;
  miFav.Enabled := Ch <> nil;
  miCopy.Enabled := Ch <> nil;
  if IsFav(Ch) then miFav.Caption := 'Убрать из избранного' else miFav.Caption := 'В избранное';
end;

procedure TMainForm.MenuPlayClick(Sender: TObject);
begin
  PlayChannel(chView.SelectedChannel, True);
end;

procedure TMainForm.MenuExternalClick(Sender: TObject);
begin
  OpenExternal(chView.SelectedChannel);
end;

procedure TMainForm.MenuRecordClick(Sender: TObject);
begin
  StartRecording(chView.SelectedChannel);
end;

procedure TMainForm.MenuFavClick(Sender: TObject);
begin
  ToggleFavorite(chView.SelectedChannel);
end;

procedure TMainForm.MenuCopyClick(Sender: TObject);
begin
  if chView.SelectedChannel <> nil then
    Clipboard.AsText := chView.SelectedChannel.URL;
end;

end.
