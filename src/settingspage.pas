{ Страница настроек внутри окна программы: слева разделы, справа содержимое. }
unit settingspage;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Spin, Dialogs,
  appsettings, widgets;

const
  SEC_VIEW = 0;
  SEC_PLAYER = 1;
  SEC_RECORD = 2;
  SEC_EPG = 3;
  SEC_LOGOS = 4;
  SEC_BACKUP = 5;
  SEC_COUNT = 6;

type
  TSettingsPage = class(TPanel)
  private
    FS: TAppSettings;
    FOnClose, FOnImported, FOnClearLogos: TNotifyEvent;
    FNav, FHeader, FContent: TPanel;
    lblHeader: TLabel;
    btnDone: TFlatButton;
    FNavButtons: array[0..SEC_COUNT - 1] of TFlatButton;
    FPages: array[0..SEC_COUNT - 1] of TPanel;
    FSection: Integer;
    { вид }
    segAccent, segView: TSegmentBar;
    tgNumbers, tgLogos, tgMaximized, tgSystemFrame, tgAutoPlay: TToggle;
    { плеер }
    segPlayer: TSegmentBar;
    edExtPath, edExtArgs: TEdit;
    seCaching: TSpinEdit;
    { запись }
    edRecDir: TEdit;
    { телепрограмма }
    tgPlaylistEpg: TToggle;
    lbSources: TListBox;
    edNewSource: TEdit;
    sePastDays: TSpinEdit;
    cbCatchup: TComboBox;
    { логотипы }
    tgLogoDb: TToggle;
    edLogoTpl: TEdit;

    function NewPage(Index: Integer; const ATitle: string; AKind: TIconKind): TPanel;
    function AddLabel(P: TWinControl; const S: string; X, Y: Integer; W: Integer = 0;
      Dim: Boolean = False; Bold: Boolean = False): TLabel;
    function AddButton(P: TWinControl; const S: string; X, Y, W: Integer; H: TNotifyEvent): TFlatButton;
    function AddToggle(P: TWinControl; const S: string; X, Y: Integer): TToggle;
    function AddEdit(P: TWinControl; X, Y, W: Integer): TEdit;
    function AddSegments(P: TWinControl; X, Y, W: Integer; const Items: array of string): TSegmentBar;
    function AddSpin(P: TWinControl; X, Y, AMin, AMax, AStep: Integer): TSpinEdit;
    procedure BuildPages;
    procedure NavClick(Sender: TObject);
    procedure DoneClick(Sender: TObject);
    procedure BrowsePlayer(Sender: TObject);
    procedure BrowseRecDir(Sender: TObject);
    procedure OpenRecDir(Sender: TObject);
    procedure AddSource(Sender: TObject);
    procedure RemoveSource(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure ImportClick(Sender: TObject);
    procedure ClearLogosClick(Sender: TObject);
  public
    constructor CreatePage(AOwner: TComponent; S: TAppSettings);
    procedure LoadValues;
    procedure SaveValues;
    procedure ShowSection(Index: Integer);
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
    property OnImported: TNotifyEvent read FOnImported write FOnImported;
    property OnClearLogos: TNotifyEvent read FOnClearLogos write FOnClearLogos;
  end;

implementation

uses
  LCLIntf, catchup;

const
  X0 = 40;        { левый отступ содержимого }
  COL_W = 620;    { ширина колонки настроек }

constructor TSettingsPage.CreatePage(AOwner: TComponent; S: TAppSettings);
var
  T: TLabel;
  i: Integer;
const
  Titles: array[0..SEC_COUNT - 1] of string =
    ('Внешний вид', 'Воспроизведение', 'Запись эфира', 'Телепрограмма и архив', 'Логотипы', 'Резервная копия');
  Kinds: array[0..SEC_COUNT - 1] of TIconKind =
    (ikViewGrid, ikPlay, ikRecord, ikViewList, ikStar, ikRefresh);
begin
  inherited Create(AOwner);
  FS := S;
  BevelOuter := bvNone;
  Color := clrBg;
  ParentColor := False;

  { разделы слева }
  FNav := TPanel.Create(Self);
  FNav.Parent := Self;
  FNav.BevelOuter := bvNone;
  FNav.Color := clrSide;
  FNav.ParentColor := False;
  FNav.Width := 260;
  FNav.Align := alLeft;

  T := TLabel.Create(Self);
  T.Parent := FNav;
  T.Caption := 'Настройки';
  T.Font.Size := 15;
  T.Font.Style := [fsBold];
  T.Font.Color := clrText;
  T.Align := alTop;
  T.BorderSpacing.Left := 22;
  T.BorderSpacing.Top := 20;
  T.BorderSpacing.Bottom := 16;

  for i := 0 to SEC_COUNT - 1 do
  begin
    FNavButtons[i] := TFlatButton.Create(Self);
    FNavButtons[i].Parent := FNav;
    FNavButtons[i].NavStyle := True;
    FNavButtons[i].Kind := Kinds[i];
    FNavButtons[i].Caption := Titles[i];
    FNavButtons[i].Height := 42;
    FNavButtons[i].Top := 100 + i * 50;
    FNavButtons[i].Align := alTop;
    FNavButtons[i].BorderSpacing.Left := 10;
    FNavButtons[i].BorderSpacing.Right := 10;
    FNavButtons[i].BorderSpacing.Top := 2;
    FNavButtons[i].Tag := i;
    FNavButtons[i].OnClick := @NavClick;
    if i = SEC_RECORD then FNavButtons[i].IconColor := BlendColor(clrDanger, clrText, 0.35);
    if i = SEC_LOGOS then FNavButtons[i].IconColor := clrStar;
  end;

  { заголовок раздела и кнопка «Готово» }
  FHeader := TPanel.Create(Self);
  FHeader.Parent := Self;
  FHeader.BevelOuter := bvNone;
  FHeader.Color := clrBg;
  FHeader.ParentColor := False;
  FHeader.Height := 70;
  FHeader.Align := alTop;

  btnDone := TFlatButton.Create(Self);
  btnDone.Parent := FHeader;
  btnDone.Bordered := True;
  btnDone.Caption := 'Готово';
  btnDone.Hint := 'Сохранить и вернуться к просмотру (Esc)';
  btnDone.Width := 130;
  btnDone.Align := alRight;
  btnDone.BorderSpacing.Top := 16;
  btnDone.BorderSpacing.Bottom := 16;
  btnDone.BorderSpacing.Right := 24;
  btnDone.OnClick := @DoneClick;

  lblHeader := TLabel.Create(Self);
  lblHeader.Parent := FHeader;
  lblHeader.Align := alClient;
  lblHeader.AutoSize := False;
  lblHeader.Layout := tlCenter;
  lblHeader.Font.Size := 16;
  lblHeader.Font.Style := [fsBold];
  lblHeader.Font.Color := clrText;
  lblHeader.BorderSpacing.Left := X0;

  FContent := TPanel.Create(Self);
  FContent.Parent := Self;
  FContent.BevelOuter := bvNone;
  FContent.Color := clrBg;
  FContent.ParentColor := False;
  FContent.Align := alClient;

  BuildPages;
  ShowSection(SEC_VIEW);
end;

function TSettingsPage.NewPage(Index: Integer; const ATitle: string; AKind: TIconKind): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := FContent;
  Result.BevelOuter := bvNone;
  Result.Color := clrBg;
  Result.ParentColor := False;
  Result.Align := alClient;
  Result.Visible := False;
  Result.Caption := '';
  FPages[Index] := Result;
end;

function TSettingsPage.AddLabel(P: TWinControl; const S: string; X, Y: Integer; W: Integer;
  Dim: Boolean; Bold: Boolean): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := P;
  Result.Left := X;
  Result.Top := Y;
  Result.Caption := S;
  if Dim then
  begin
    Result.Font.Color := clrDim;
    Result.Font.Size := 8;
  end
  else
    Result.Font.Color := clrText;
  if Bold then
  begin
    Result.Font.Style := [fsBold];
    Result.Font.Size := 10;
  end;
  if W > 0 then
  begin
    Result.AutoSize := False;
    Result.WordWrap := True;
    Result.Width := W;
    Result.Height := 40;
  end;
end;

function TSettingsPage.AddButton(P: TWinControl; const S: string; X, Y, W: Integer;
  H: TNotifyEvent): TFlatButton;
begin
  Result := TFlatButton.Create(Self);
  Result.Parent := P;
  Result.Bordered := True;
  Result.Caption := S;
  Result.SetBounds(X, Y, W, 34);
  Result.OnClick := H;
end;

function TSettingsPage.AddToggle(P: TWinControl; const S: string; X, Y: Integer): TToggle;
begin
  Result := TToggle.Create(Self);
  Result.Parent := P;
  Result.Caption := S;
  Result.SetBounds(X, Y, COL_W, 30);
end;

function TSettingsPage.AddEdit(P: TWinControl; X, Y, W: Integer): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := P;
  Result.Font.Color := clWindowText;
  Result.SetBounds(X, Y, W, 28);
end;

function TSettingsPage.AddSegments(P: TWinControl; X, Y, W: Integer;
  const Items: array of string): TSegmentBar;
var
  i: Integer;
begin
  Result := TSegmentBar.Create(Self);
  Result.Parent := P;
  for i := 0 to High(Items) do Result.Items.Add(Items[i]);
  Result.SetBounds(X, Y, W, 36);
end;

function TSettingsPage.AddSpin(P: TWinControl; X, Y, AMin, AMax, AStep: Integer): TSpinEdit;
begin
  Result := TSpinEdit.Create(Self);
  Result.Parent := P;
  Result.Font.Color := clWindowText;
  Result.MinValue := AMin;
  Result.MaxValue := AMax;
  Result.Increment := AStep;
  Result.SetBounds(X, Y, 110, 28);
end;

procedure TSettingsPage.BuildPages;
var
  P: TPanel;
  Y, i: Integer;
  Names: array of string;
begin
  { ---------- Внешний вид ---------- }
  P := NewPage(SEC_VIEW, 'Внешний вид', ikViewGrid);
  Y := 10;
  AddLabel(P, 'Цвет оформления', X0, Y, 0, False, True);
  SetLength(Names, Length(ACCENT_NAMES));
  for i := 0 to High(ACCENT_NAMES) do Names[i] := ACCENT_NAMES[i];
  segAccent := AddSegments(P, X0, Y + 28, COL_W, Names);
  Inc(Y, 84);
  AddLabel(P, 'Вид списка каналов', X0, Y, 0, False, True);
  segView := AddSegments(P, X0, Y + 28, COL_W, ['Список', 'Компактный', 'Сетка', 'Плитка']);
  Inc(Y, 90);
  tgNumbers := AddToggle(P, 'Отображать номера каналов', X0, Y);
  Inc(Y, 40);
  tgLogos := AddToggle(P, 'Показывать логотипы каналов', X0, Y);
  Inc(Y, 40);
  tgMaximized := AddToggle(P, 'Открывать окно на весь экран', X0, Y);
  Inc(Y, 40);
  tgSystemFrame := AddToggle(P, 'Стандартная рамка окна системы (после перезапуска)', X0, Y);
  AddLabel(P, 'По умолчанию у программы своя тёмная рамка. Стандартная может пригодиться на старых системах.',
    X0 + 50, Y + 30, COL_W - 50, True);

  { ---------- Воспроизведение ---------- }
  P := NewPage(SEC_PLAYER, 'Воспроизведение', ikPlay);
  Y := 10;
  AddLabel(P, 'Чем воспроизводить каналы', X0, Y, 0, False, True);
  segPlayer := AddSegments(P, X0, Y + 28, COL_W, ['Встроенный плеер', 'Внешний плеер']);
  Inc(Y, 90);
  AddLabel(P, 'Программа внешнего плеера (VLC, MPC-HC, mpv...). Пусто — найти автоматически:', X0, Y);
  edExtPath := AddEdit(P, X0, Y + 24, COL_W - 130);
  AddButton(P, 'Обзор...', X0 + COL_W - 120, Y + 21, 120, @BrowsePlayer);
  Inc(Y, 70);
  AddLabel(P, 'Дополнительные параметры запуска (%u — ссылка на канал):', X0, Y);
  edExtArgs := AddEdit(P, X0, Y + 24, COL_W);
  Inc(Y, 76);
  tgAutoPlay := AddToggle(P, 'Включать последний канал при запуске программы', X0, Y);
  Inc(Y, 50);
  AddLabel(P, 'Буфер сети, мс', X0, Y, 0, False, True);
  seCaching := AddSpin(P, X0, Y + 28, 100, 60000, 250);
  AddLabel(P, 'Меньше — каналы включаются быстрее. Больше — меньше рывков на медленном интернете. ' +
    'Рекомендуется 1000.', X0 + 130, Y + 26, COL_W - 130, True);

  { ---------- Запись ---------- }
  P := NewPage(SEC_RECORD, 'Запись эфира', ikRecord);
  Y := 10;
  AddLabel(P, 'Папка для сохранения записей', X0, Y, 0, False, True);
  edRecDir := AddEdit(P, X0, Y + 30, COL_W - 260);
  AddButton(P, 'Выбрать...', X0 + COL_W - 250, Y + 27, 120, @BrowseRecDir);
  AddButton(P, 'Открыть', X0 + COL_W - 120, Y + 27, 120, @OpenRecDir);
  Inc(Y, 80);
  AddLabel(P, 'Запись включается красной кнопкой под видео или клавишами Ctrl+R. Записывается канал, ' +
    'который вы смотрите в момент нажатия; можно переключиться на другой — запись продолжится. ' +
    'Файлы сохраняются в формате .ts и открываются любым плеером.', X0, Y, COL_W, True).Height := 70;

  { ---------- Телепрограмма ---------- }
  P := NewPage(SEC_EPG, 'Телепрограмма и архив', ikViewList);
  Y := 10;
  tgPlaylistEpg := AddToggle(P, 'Автоматически брать телепрограмму из плейлиста (url-tvg)', X0, Y);
  Inc(Y, 46);
  AddLabel(P, 'Свои источники телепрограммы (XMLTV, .xml или .xml.gz) — используются все сразу', X0, Y, 0, False, True);
  lbSources := TListBox.Create(Self);
  lbSources.Parent := P;
  lbSources.Color := clrSide;
  lbSources.Font.Color := clrText;
  lbSources.BorderStyle := bsNone;
  lbSources.SetBounds(X0, Y + 28, COL_W, 110);
  Inc(Y, 146);
  edNewSource := AddEdit(P, X0, Y, COL_W - 260);
  edNewSource.TextHint := 'https://.../epg.xml.gz';
  AddButton(P, 'Добавить', X0 + COL_W - 250, Y - 3, 120, @AddSource);
  AddButton(P, 'Удалить', X0 + COL_W - 120, Y - 3, 120, @RemoveSource);
  Inc(Y, 54);
  AddLabel(P, 'Хранить прошедшую программу (для архива), дней', X0, Y, 0, False, True);
  sePastDays := AddSpin(P, X0 + COL_W - 110, Y - 4, 0, 14, 1);
  Inc(Y, 42);
  AddLabel(P, 'Тип архива, если провайдер не указал его в плейлисте', X0, Y, 0, False, True);
  cbCatchup := TComboBox.Create(Self);
  cbCatchup.Parent := P;
  cbCatchup.Style := csDropDownList;
  cbCatchup.Font.Color := clWindowText;
  cbCatchup.SetBounds(X0, Y + 28, COL_W, 28);
  for i := Low(CATCHUP_TITLES) to High(CATCHUP_TITLES) do cbCatchup.Items.Add(CATCHUP_TITLES[i]);
  Inc(Y, 70);
  AddLabel(P, 'Телепрограмма обновляется раз в 12 часов или кнопкой «Обновить» (F5). ' +
    'Открыть телепрограмму канала: стрелка справа от канала, правая кнопка мыши или клавиша E.',
    X0, Y, COL_W, True);

  { ---------- Логотипы ---------- }
  P := NewPage(SEC_LOGOS, 'Логотипы', ikStar);
  Y := 10;
  tgLogoDb := AddToggle(P, 'Подбирать недостающие логотипы по названию канала', X0, Y);
  AddLabel(P, 'Если в плейлисте логотипа нет или он не открывается (SVG, WebP), программа ищет его ' +
    'по названию в открытой базе iptv-org. База обновляется раз в неделю.', X0 + 50, Y + 30, COL_W - 50, True);
  Inc(Y, 90);
  AddLabel(P, 'Свой источник логотипов (необязательно)', X0, Y, 0, False, True);
  edLogoTpl := AddEdit(P, X0, Y + 28, COL_W);
  edLogoTpl.TextHint := 'https://example.com/logos/{name}.png';
  AddLabel(P, 'Ссылка-шаблон: {name} — название канала, {key} — название без пробелов и HD, ' +
    '{id} — tvg-id из плейлиста.', X0, Y + 62, COL_W, True);
  Inc(Y, 120);
  AddLabel(P, 'Работа без интернета', X0, Y, 0, False, True);
  AddLabel(P, 'Логотипы, плейлисты и телепрограмма сохраняются на диске. Без интернета программа ' +
    'покажет сохранённые копии.', X0, Y + 26, COL_W, True);
  AddButton(P, 'Очистить кэш логотипов', X0, Y + 72, 240, @ClearLogosClick);

  { ---------- Резервная копия ---------- }
  P := NewPage(SEC_BACKUP, 'Резервная копия', ikRefresh);
  Y := 10;
  AddLabel(P, 'Сохраните плейлисты, источники телепрограмм, избранное и все настройки в один файл, ' +
    'чтобы перенести их на другой компьютер или восстановить после переустановки.', X0, Y, COL_W, True);
  AddButton(P, 'Экспорт конфигурации...', X0, Y + 54, 260, @ExportClick);
  Inc(Y, 120);
  AddLabel(P, 'Загрузить конфигурацию из файла .aristocrat. Текущие настройки будут заменены.',
    X0, Y, COL_W, True);
  AddButton(P, 'Импорт конфигурации...', X0, Y + 40, 260, @ImportClick);
end;

procedure TSettingsPage.ShowSection(Index: Integer);
var
  i: Integer;
begin
  if (Index < 0) or (Index >= SEC_COUNT) then Index := 0;
  FSection := Index;
  for i := 0 to SEC_COUNT - 1 do
  begin
    FNavButtons[i].Checked := i = Index;
    FNavButtons[i].Invalidate;
    FPages[i].Visible := i = Index;
  end;
  lblHeader.Caption := FNavButtons[Index].Caption;
end;

procedure TSettingsPage.LoadValues;
begin
  segAccent.ItemIndex := FS.Accent;
  segView.ItemIndex := FS.ViewMode;
  tgNumbers.Checked := FS.ShowNumbers;
  tgLogos.Checked := FS.ShowLogos;
  tgMaximized.Checked := FS.OpenMaximized;
  tgSystemFrame.Checked := FS.SystemFrame;
  tgAutoPlay.Checked := FS.AutoPlayLast;
  if FS.UseExternalPlayer then segPlayer.ItemIndex := 1 else segPlayer.ItemIndex := 0;
  edExtPath.Text := FS.ExternalPlayer;
  edExtArgs.Text := FS.ExternalArgs;
  seCaching.Value := FS.NetworkCaching;
  edRecDir.Text := FS.RecordDir;
  tgPlaylistEpg.Checked := FS.UsePlaylistEpg;
  lbSources.Items.Assign(FS.EpgSources);
  sePastDays.Value := FS.EpgPastDays;
  cbCatchup.ItemIndex := FS.DefaultCatchup;
  tgLogoDb.Checked := FS.LogoDbEnabled;
  edLogoTpl.Text := FS.LogoTemplate;
end;

procedure TSettingsPage.SaveValues;
begin
  FS.Accent := segAccent.ItemIndex;
  FS.ViewMode := segView.ItemIndex;
  FS.ShowNumbers := tgNumbers.Checked;
  FS.ShowLogos := tgLogos.Checked;
  FS.OpenMaximized := tgMaximized.Checked;
  FS.SystemFrame := tgSystemFrame.Checked;
  FS.AutoPlayLast := tgAutoPlay.Checked;
  FS.UseExternalPlayer := segPlayer.ItemIndex = 1;
  FS.ExternalPlayer := Trim(edExtPath.Text);
  FS.ExternalArgs := Trim(edExtArgs.Text);
  FS.NetworkCaching := seCaching.Value;
  FS.RecordDir := Trim(edRecDir.Text);
  if FS.RecordDir = '' then FS.RecordDir := DefaultRecordDir;
  FS.UsePlaylistEpg := tgPlaylistEpg.Checked;
  FS.EpgSources.Assign(lbSources.Items);
  FS.EpgPastDays := sePastDays.Value;
  if cbCatchup.ItemIndex >= 0 then FS.DefaultCatchup := cbCatchup.ItemIndex;
  FS.LogoDbEnabled := tgLogoDb.Checked;
  FS.LogoTemplate := Trim(edLogoTpl.Text);
  FS.Save;
end;

procedure TSettingsPage.NavClick(Sender: TObject);
begin
  ShowSection(TFlatButton(Sender).Tag);
end;

procedure TSettingsPage.DoneClick(Sender: TObject);
begin
  SaveValues;
  if Assigned(FOnClose) then FOnClose(Self);
end;

procedure TSettingsPage.BrowsePlayer(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Title := 'Выберите программу-плеер';
{$IFDEF WINDOWS}
    D.Filter := 'Программы (*.exe)|*.exe|Все файлы|*.*';
{$ENDIF}
    if D.Execute then edExtPath.Text := D.FileName;
  finally
    D.Free;
  end;
end;

procedure TSettingsPage.BrowseRecDir(Sender: TObject);
var
  D: TSelectDirectoryDialog;
begin
  D := TSelectDirectoryDialog.Create(Self);
  try
    D.Title := 'Папка для сохранения записей';
    if DirectoryExists(edRecDir.Text) then D.InitialDir := edRecDir.Text;
    if D.Execute then edRecDir.Text := D.FileName;
  finally
    D.Free;
  end;
end;

procedure TSettingsPage.OpenRecDir(Sender: TObject);
var
  Dir: string;
begin
  Dir := Trim(edRecDir.Text);
  if Dir = '' then Exit;
  ForceDirectories(Dir);
  OpenDocument(Dir);
end;

procedure TSettingsPage.AddSource(Sender: TObject);
var
  V: string;
begin
  V := Trim(edNewSource.Text);
  if V = '' then
  begin
    if edNewSource.CanFocus then edNewSource.SetFocus;
    Exit;
  end;
  if lbSources.Items.IndexOf(V) < 0 then lbSources.Items.Add(V);
  edNewSource.Text := '';
end;

procedure TSettingsPage.RemoveSource(Sender: TObject);
begin
  if lbSources.ItemIndex >= 0 then
    lbSources.Items.Delete(lbSources.ItemIndex);
end;

procedure TSettingsPage.ExportClick(Sender: TObject);
var
  D: TSaveDialog;
  Err: string;
begin
  SaveValues;
  D := TSaveDialog.Create(Self);
  try
    D.Title := 'Экспорт конфигурации';
    D.Filter := 'Конфигурация IPTV Aristocrat (*.aristocrat)|*.aristocrat|Все файлы|*';
    D.DefaultExt := 'aristocrat';
    D.FileName := 'iptv-aristocrat-' + FormatDateTime('yyyy-mm-dd', Now) + '.aristocrat';
    D.Options := D.Options + [ofOverwritePrompt];
    if not D.Execute then Exit;
    if FS.ExportTo(D.FileName, Err) then
      MessageDlg('Конфигурация сохранена:' + LineEnding + D.FileName, mtInformation, [mbOK], 0)
    else
      MessageDlg('Не удалось сохранить файл: ' + Err, mtError, [mbOK], 0);
  finally
    D.Free;
  end;
end;

procedure TSettingsPage.ImportClick(Sender: TObject);
var
  D: TOpenDialog;
  Err: string;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Title := 'Импорт конфигурации';
    D.Filter := 'Конфигурация IPTV Aristocrat (*.aristocrat)|*.aristocrat|Все файлы|*';
    if not D.Execute then Exit;
    if MessageDlg('Текущие плейлисты, избранное и настройки будут заменены данными из файла. Продолжить?',
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
    if FS.ImportFrom(D.FileName, Err) then
    begin
      LoadValues;
      if Assigned(FOnImported) then FOnImported(Self);
      MessageDlg('Конфигурация загружена.', mtInformation, [mbOK], 0);
    end
    else
      MessageDlg('Не удалось загрузить конфигурацию: ' + Err, mtError, [mbOK], 0);
  finally
    D.Free;
  end;
end;

procedure TSettingsPage.ClearLogosClick(Sender: TObject);
begin
  if MessageDlg('Удалить сохранённые логотипы? Они будут скачаны заново.',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  if Assigned(FOnClearLogos) then FOnClearLogos(Self);
end;

end.
