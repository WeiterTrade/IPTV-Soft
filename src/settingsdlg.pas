{ Окно настроек IPTV Aristocrat. }
unit settingsdlg;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Spin, Dialogs,
  appsettings;

type
  TSettingsResult = (srCancel, srSaved, srImported);

function ShowSettings(AOwner: TComponent; S: TAppSettings; StartPage: Integer = 0): TSettingsResult;

implementation

uses
  widgets;

type
  TSettingsForm = class(TForm)
  public
    S: TAppSettings;
    Imported: Boolean;
    Pages: TPageControl;
    { вид }
    cbAccent: TComboBox;
    rgView: TRadioGroup;
    chkNumbers, chkLogos, chkMaximized, chkSystemFrame, chkAutoPlay: TCheckBox;
    { плеер }
    rgPlayer: TRadioGroup;
    edExtPath, edExtArgs: TEdit;
    seCaching: TSpinEdit;
    { запись }
    edRecDir: TEdit;
    { телепрограмма }
    chkPlaylistEpg: TCheckBox;
    lbSources: TListBox;
    procedure BrowsePlayer(Sender: TObject);
    procedure BrowseRecDir(Sender: TObject);
    procedure AddSource(Sender: TObject);
    procedure EditSource(Sender: TObject);
    procedure RemoveSource(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure ImportClick(Sender: TObject);
    procedure OkClick(Sender: TObject);
  end;

function AddPage(F: TSettingsForm; const ACaption: string): TTabSheet;
begin
  Result := TTabSheet.Create(F);
  Result.PageControl := F.Pages;
  Result.Caption := ACaption;
end;

function AddLabel(AParent: TWinControl; const S: string; X, Y: Integer; W: Integer = 0): TLabel;
begin
  Result := TLabel.Create(AParent);
  Result.Parent := AParent;
  Result.Left := X;
  Result.Top := Y;
  Result.Caption := S;
  if W > 0 then
  begin
    Result.AutoSize := False;
    Result.WordWrap := True;
    Result.Width := W;
    Result.Height := 48;
  end;
end;

function AddCheck(AParent: TWinControl; const S: string; X, Y: Integer; V: Boolean): TCheckBox;
begin
  Result := TCheckBox.Create(AParent);
  Result.Parent := AParent;
  Result.Left := X;
  Result.Top := Y;
  Result.Caption := S;
  Result.Checked := V;
end;

function AddButton(AParent: TWinControl; const S: string; X, Y, W: Integer; H: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AParent);
  Result.Parent := AParent;
  Result.Left := X;
  Result.Top := Y;
  Result.Width := W;
  Result.Caption := S;
  Result.OnClick := H;
end;

function AddEdit(AParent: TWinControl; const S: string; X, Y, W: Integer): TEdit;
begin
  Result := TEdit.Create(AParent);
  Result.Parent := AParent;
  Result.Left := X;
  Result.Top := Y;
  Result.Width := W;
  Result.Text := S;
end;

{ TSettingsForm }

procedure TSettingsForm.BrowsePlayer(Sender: TObject);
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

procedure TSettingsForm.BrowseRecDir(Sender: TObject);
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

procedure TSettingsForm.AddSource(Sender: TObject);
var
  V: string;
begin
  V := '';
  if InputQuery('Источник телепрограммы',
    'Ссылка на телепрограмму в формате XMLTV (.xml или .xml.gz):', V) then
  begin
    V := Trim(V);
    if (V <> '') and (lbSources.Items.IndexOf(V) < 0) then
      lbSources.Items.Add(V);
  end;
end;

procedure TSettingsForm.EditSource(Sender: TObject);
var
  V: string;
  I: Integer;
begin
  I := lbSources.ItemIndex;
  if I < 0 then Exit;
  V := lbSources.Items[I];
  if InputQuery('Источник телепрограммы', 'Ссылка на телепрограмму (XMLTV):', V) then
  begin
    V := Trim(V);
    if V <> '' then lbSources.Items[I] := V;
  end;
end;

procedure TSettingsForm.RemoveSource(Sender: TObject);
begin
  if lbSources.ItemIndex >= 0 then
    lbSources.Items.Delete(lbSources.ItemIndex);
end;

procedure TSettingsForm.ExportClick(Sender: TObject);
var
  D: TSaveDialog;
  Err: string;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Title := 'Экспорт конфигурации';
    D.Filter := 'Конфигурация IPTV Aristocrat (*.aristocrat)|*.aristocrat|Все файлы|*';
    D.DefaultExt := 'aristocrat';
    D.FileName := 'iptv-aristocrat-' + FormatDateTime('yyyy-mm-dd', Now) + '.aristocrat';
    D.Options := D.Options + [ofOverwritePrompt];
    if not D.Execute then Exit;
    if S.ExportTo(D.FileName, Err) then
      MessageDlg('Конфигурация сохранена:' + LineEnding + D.FileName + LineEnding + LineEnding +
        'В файл попали плейлисты, источники телепрограмм, избранное и настройки.',
        mtInformation, [mbOK], 0)
    else
      MessageDlg('Не удалось сохранить файл: ' + Err, mtError, [mbOK], 0);
  finally
    D.Free;
  end;
end;

procedure TSettingsForm.ImportClick(Sender: TObject);
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
    if S.ImportFrom(D.FileName, Err) then
    begin
      Imported := True;
      MessageDlg('Конфигурация загружена.', mtInformation, [mbOK], 0);
      ModalResult := mrOK;
    end
    else
      MessageDlg('Не удалось загрузить конфигурацию: ' + Err, mtError, [mbOK], 0);
  finally
    D.Free;
  end;
end;

procedure TSettingsForm.OkClick(Sender: TObject);
begin
  S.Accent := cbAccent.ItemIndex;
  S.ViewMode := rgView.ItemIndex;
  S.ShowNumbers := chkNumbers.Checked;
  S.ShowLogos := chkLogos.Checked;
  S.OpenMaximized := chkMaximized.Checked;
  S.SystemFrame := chkSystemFrame.Checked;
  S.AutoPlayLast := chkAutoPlay.Checked;
  S.UseExternalPlayer := rgPlayer.ItemIndex = 1;
  S.ExternalPlayer := Trim(edExtPath.Text);
  S.ExternalArgs := Trim(edExtArgs.Text);
  S.NetworkCaching := seCaching.Value;
  S.RecordDir := Trim(edRecDir.Text);
  if S.RecordDir = '' then S.RecordDir := DefaultRecordDir;
  S.UsePlaylistEpg := chkPlaylistEpg.Checked;
  S.EpgSources.Assign(lbSources.Items);
  S.Save;
  ModalResult := mrOK;
end;

function ShowSettings(AOwner: TComponent; S: TAppSettings; StartPage: Integer): TSettingsResult;
var
  F: TSettingsForm;
  P: TTabSheet;
  i, Y: Integer;
  B: TButton;
begin
  F := TSettingsForm.CreateNew(AOwner);
  try
    F.S := S;
    F.Caption := 'Настройки — IPTV Aristocrat';
    F.BorderStyle := bsDialog;
    F.Position := poOwnerFormCenter;
    F.ClientWidth := 620;
    F.ClientHeight := 470;

    F.Pages := TPageControl.Create(F);
    F.Pages.Parent := F;
    F.Pages.SetBounds(8, 8, 604, 408);

    { ---------- Вид ---------- }
    P := AddPage(F, 'Вид');
    AddLabel(P, 'Цвет оформления:', 16, 18);
    F.cbAccent := TComboBox.Create(F);
    F.cbAccent.Parent := P;
    F.cbAccent.Style := csDropDownList;
    F.cbAccent.SetBounds(200, 14, 200, 24);
    for i := Low(ACCENT_NAMES) to High(ACCENT_NAMES) do
      F.cbAccent.Items.Add(ACCENT_NAMES[i]);
    F.cbAccent.ItemIndex := S.Accent;

    F.rgView := TRadioGroup.Create(F);
    F.rgView.Parent := P;
    F.rgView.Caption := 'Отображение каналов';
    F.rgView.SetBounds(16, 54, 260, 140);
    F.rgView.Items.Add('Список');
    F.rgView.Items.Add('Компактный список');
    F.rgView.Items.Add('Сетка');
    F.rgView.Items.Add('Плитка');
    F.rgView.ItemIndex := S.ViewMode;

    Y := 58;
    F.chkNumbers := AddCheck(P, 'Отображать номера каналов', 300, Y, S.ShowNumbers);
    Inc(Y, 30);
    F.chkLogos := AddCheck(P, 'Показывать логотипы каналов', 300, Y, S.ShowLogos);
    Inc(Y, 30);
    F.chkAutoPlay := AddCheck(P, 'Включать последний канал при запуске', 300, Y, S.AutoPlayLast);
    Inc(Y, 30);
    F.chkMaximized := AddCheck(P, 'Открывать окно на весь экран', 300, Y, S.OpenMaximized);

    F.chkSystemFrame := AddCheck(P, 'Использовать стандартную рамку окна системы', 16, 214, S.SystemFrame);
    AddLabel(P, 'По умолчанию у программы своя тёмная рамка в общем стиле. ' +
      'Стандартная рамка может пригодиться на старых системах. ' +
      'Изменение применится после перезапуска программы.', 36, 240, 540);

    { ---------- Плеер ---------- }
    P := AddPage(F, 'Плеер');
    F.rgPlayer := TRadioGroup.Create(F);
    F.rgPlayer.Parent := P;
    F.rgPlayer.Caption := 'Чем воспроизводить каналы';
    F.rgPlayer.SetBounds(16, 12, 560, 78);
    F.rgPlayer.Items.Add('Встроенный плеер (внутри окна программы)');
    F.rgPlayer.Items.Add('Внешний плеер (указанная ниже программа)');
    if S.UseExternalPlayer then F.rgPlayer.ItemIndex := 1 else F.rgPlayer.ItemIndex := 0;

    AddLabel(P, 'Программа внешнего плеера (например, VLC, MPC-HC, mpv):', 16, 104);
    F.edExtPath := AddEdit(P, S.ExternalPlayer, 16, 126, 450);
    AddButton(P, 'Обзор...', 476, 125, 100, @F.BrowsePlayer);
    AddLabel(P, 'Дополнительные параметры запуска (необязательно, %u — ссылка на канал):', 16, 162);
    F.edExtArgs := AddEdit(P, S.ExternalArgs, 16, 184, 450);
    AddLabel(P, 'Если программа не указана, используется найденный VLC или mpv. ' +
      'Открыть канал во внешнем плеере можно и разово — через правую кнопку мыши на канале.',
      16, 218, 560);

    AddLabel(P, 'Буфер сети, мс (больше — меньше рывков на медленном интернете):', 16, 286);
    F.seCaching := TSpinEdit.Create(F);
    F.seCaching.Parent := P;
    F.seCaching.SetBounds(16, 308, 120, 24);
    F.seCaching.MinValue := 100;
    F.seCaching.MaxValue := 60000;
    F.seCaching.Increment := 500;
    F.seCaching.Value := S.NetworkCaching;

    { ---------- Запись ---------- }
    P := AddPage(F, 'Запись');
    AddLabel(P, 'Папка для сохранения записей эфира:', 16, 18);
    F.edRecDir := AddEdit(P, S.RecordDir, 16, 40, 450);
    AddButton(P, 'Выбрать...', 476, 39, 100, @F.BrowseRecDir);
    AddLabel(P, 'Запись включается красной кнопкой на панели управления. ' +
      'Записывается канал, который смотрите в момент нажатия; ' +
      'можно переключиться на другой канал — запись продолжится. ' +
      'Файлы сохраняются в формате .ts (открываются любым плеером). ' +
      'Во время записи поток скачивается дважды, нужен запас по скорости интернета.',
      16, 80, 560).Height := 100;

    { ---------- Источники телепрограмм ---------- }
    P := AddPage(F, 'Источники телепрограмм');
    F.chkPlaylistEpg := AddCheck(P, 'Брать телепрограмму, указанную в плейлисте (url-tvg)', 16, 14,
      S.UsePlaylistEpg);
    AddLabel(P, 'Свои источники (XMLTV, .xml или .xml.gz). Используются все сразу:', 16, 46);
    F.lbSources := TListBox.Create(F);
    F.lbSources.Parent := P;
    F.lbSources.SetBounds(16, 68, 450, 250);
    F.lbSources.Items.Assign(S.EpgSources);
    F.lbSources.OnDblClick := @F.EditSource;
    AddButton(P, 'Добавить...', 476, 68, 100, @F.AddSource);
    AddButton(P, 'Изменить...', 476, 102, 100, @F.EditSource);
    AddButton(P, 'Удалить', 476, 136, 100, @F.RemoveSource);
    AddLabel(P, 'Телепрограмма обновляется раз в 12 часов или кнопкой «Обновить» (F5).', 16, 330);

    { ---------- Резервная копия ---------- }
    P := AddPage(F, 'Экспорт и импорт');
    AddLabel(P, 'Сохраните все плейлисты, источники телепрограмм, избранное и настройки в один ' +
      'файл, чтобы перенести их на другой компьютер или восстановить после переустановки.',
      16, 16, 560);
    AddButton(P, 'Экспорт конфигурации...', 16, 76, 240, @F.ExportClick);
    AddLabel(P, 'Загрузить конфигурацию из файла .aristocrat (текущие настройки будут заменены):',
      16, 130, 560);
    AddButton(P, 'Импорт конфигурации...', 16, 178, 240, @F.ImportClick);

    if (StartPage >= 0) and (StartPage < F.Pages.PageCount) then
      F.Pages.ActivePageIndex := StartPage;

    { ---------- кнопки ---------- }
    B := AddButton(F, 'Сохранить', 386, 428, 110, @F.OkClick);
    B.Default := True;
    B := AddButton(F, 'Отмена', 502, 428, 110, nil);
    B.Cancel := True;
    B.ModalResult := mrCancel;

    if F.ShowModal = mrOK then
    begin
      if F.Imported then Result := srImported else Result := srSaved;
    end
    else if F.Imported then
      Result := srImported
    else
      Result := srCancel;
  finally
    F.Free;
  end;
end;

end.
