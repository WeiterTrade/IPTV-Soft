{ Окна в стиле программы: сообщение, подтверждение, добавление плейлиста.
  Заменяют стандартные окна Windows. }
unit darkdlg;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Dialogs, LCLType,
  widgets;

procedure DarkMessage(const Text: string; IsError: Boolean = False; const Title: string = '');
function DarkConfirm(const Text: string; const YesText: string = 'Да';
  const NoText: string = 'Отмена'; const Title: string = 'Подтверждение'): Boolean;
{ Окно «О программе». }
procedure DarkAbout(const AppName, Version, Platform: string);
{ Запрос PIN-кода. Confirm = True — новый код с повтором (не короче 4 символов). }
function DarkAskPin(const Title, Text: string; Confirm: Boolean; out Pin: string): Boolean;
{ Kind: 0 — плейлист ТВ-каналов, 1 — медиатека (фильмы) }
function DarkEditPlaylist(const Title: string; Kind: Integer;
  var AName, ASource, AEpg: string): Boolean;

implementation

uses
  Math, winframe, logos, applogo;

type
  TDarkForm = class(TForm)
  private
    FInner, FTitleBar, FButtons: TPanel;
    FTitleLbl: TLabel;
    procedure TitleDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure OkClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
  public
    OnValidate: function: Boolean of object;
    constructor CreateDark(const ATitle: string; AWidth: Integer);
    function AddButton(const S: string; Primary: Boolean; Res: TModalResult): TFlatButton;
    function AddText(const S: string; Y, W: Integer; Dim: Boolean = False): TLabel;
    { высота окна — по фактическому содержимому (ничего не прячется под кнопками) }
    procedure FitHeight;
    function ContentTop: Integer;
    property Inner: TPanel read FInner;
  end;

  { окно PIN-кода }
  TPinForm = class(TDarkForm)
  public
    edPin, edPin2: TEdit;
    function Validate: Boolean;
  end;

  { данные окна плейлиста }
  TPlaylistForm = class(TDarkForm)
  public
    edName, edSource, edEpg: TEdit;
    procedure BrowseClick(Sender: TObject);
    function Validate: Boolean;
  end;

function OwnerForm: TCustomForm;
begin
  Result := Screen.ActiveCustomForm;
  if Result = nil then Result := Application.MainForm;
end;

{ Перенос текста по словам под ширину W (по шрифту F). }
function WrapText(const S: string; F: TFont; W: Integer): string;
var
  B: TBitmap;
  Lines, Words: TStringList;
  i, j: Integer;
  Cur: string;
begin
  Result := '';
  B := TBitmap.Create;
  Lines := TStringList.Create;
  Words := TStringList.Create;
  try
    B.SetSize(4, 4);
    B.Canvas.Font.Assign(F);
    Lines.Text := S;
    for i := 0 to Lines.Count - 1 do
    begin
      Words.Delimiter := ' ';
      Words.StrictDelimiter := True;
      Words.DelimitedText := Lines[i];
      Cur := '';
      for j := 0 to Words.Count - 1 do
      begin
        if (Cur <> '') and (B.Canvas.TextWidth(Cur + ' ' + Words[j]) > W) then
        begin
          Result := Result + Cur + LineEnding;
          Cur := Words[j];
        end
        else if Cur = '' then
          Cur := Words[j]
        else
          Cur := Cur + ' ' + Words[j];
      end;
      Result := Result + Cur;
      if i < Lines.Count - 1 then Result := Result + LineEnding;
    end;
  finally
    Words.Free;
    Lines.Free;
    B.Free;
  end;
end;

function LineCount(const S: string): Integer;
var
  i: Integer;
begin
  Result := 1;
  for i := 1 to Length(S) do
    if S[i] = #10 then Inc(Result);
end;

{ TDarkForm }

constructor TDarkForm.CreateDark(const ATitle: string; AWidth: Integer);
begin
  inherited CreateNew(OwnerForm);
  BorderStyle := bsNone;
  Position := poOwnerFormCenter;
  Color := clrFrame;
  Font.Color := clrText;
  KeyPreview := True;
  OnKeyDown := @FormKey;
  ClientWidth := Sc(AWidth);
  ClientHeight := Sc(200);

  FInner := TPanel.Create(Self);
  FInner.Parent := Self;
  FInner.BevelOuter := bvNone;
  FInner.Color := clrBg;
  FInner.ParentColor := False;
  FInner.Align := alClient;
  FInner.BorderSpacing.Around := 1;

  FTitleBar := TPanel.Create(Self);
  FTitleBar.Parent := FInner;
  FTitleBar.BevelOuter := bvNone;
  FTitleBar.Color := clrTitle;
  FTitleBar.ParentColor := False;
  FTitleBar.Height := Sc(44);
  FTitleBar.Align := alTop;
  FTitleBar.OnMouseDown := @TitleDown;

  FTitleLbl := TLabel.Create(Self);
  FTitleLbl.Parent := FTitleBar;
  FTitleLbl.Align := alClient;
  FTitleLbl.AutoSize := False;
  FTitleLbl.Layout := tlCenter;
  FTitleLbl.BorderSpacing.Left := Sc(18);
  FTitleLbl.Font.Size := 11;
  FTitleLbl.Font.Style := [fsBold];
  FTitleLbl.Font.Color := clrText;
  FTitleLbl.Caption := ATitle;
  FTitleLbl.OnMouseDown := @TitleDown;

  FButtons := TPanel.Create(Self);
  FButtons.Parent := FInner;
  FButtons.BevelOuter := bvNone;
  FButtons.Color := clrBg;
  FButtons.ParentColor := False;
  FButtons.Height := Sc(62);
  FButtons.Align := alBottom;
end;

function TDarkForm.ContentTop: Integer;
begin
  Result := FTitleBar.Top + FTitleBar.Height;
end;

procedure TDarkForm.FitHeight;
var
  i, B: Integer;
  C: TControl;
begin
  B := ContentTop;
  for i := 0 to FInner.ControlCount - 1 do
  begin
    C := FInner.Controls[i];
    if (C = FTitleBar) or (C = FButtons) or not C.Visible then Continue;
    if C.Top + C.Height > B then B := C.Top + C.Height;
  end;
  ClientHeight := B + Sc(18) + FButtons.Height + 2;
end;

procedure TDarkForm.TitleDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then BeginWindowMove(Self);
end;

procedure TDarkForm.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    ModalResult := mrCancel;
    Key := 0;
  end
  else if (Key = VK_RETURN) and not (ActiveControl is TCustomMemo) then
  begin
    OkClick(nil);
    Key := 0;
  end;
end;

procedure TDarkForm.OkClick(Sender: TObject);
begin
  if Assigned(OnValidate) and not OnValidate() then Exit;
  ModalResult := mrOK;
end;

procedure TDarkForm.CancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

function TDarkForm.AddButton(const S: string; Primary: Boolean; Res: TModalResult): TFlatButton;
begin
  Result := TFlatButton.Create(Self);
  Result.Parent := FButtons;
  Result.Bordered := True;
  Result.Caption := S;
  Result.Width := Math.Max(Sc(140), MeasureText(Result.Font, S).cx + Sc(36));
  Result.Align := alRight;
  Result.BorderSpacing.Top := Sc(12);
  Result.BorderSpacing.Bottom := Sc(14);
  Result.BorderSpacing.Right := Sc(14);
  if Primary then
  begin
    Result.Left := 2000;
    Result.Checked := True;
    Result.OnClick := @OkClick;
  end
  else
  begin
    Result.Left := 1000;
    Result.OnClick := @CancelClick;
  end;
end;

function TDarkForm.AddText(const S: string; Y, W: Integer; Dim: Boolean): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := FInner;
  Result.Left := Sc(22);
  Result.Top := Y;
  if Dim then
  begin
    Result.Font.Color := clrDim;
    Result.Font.Size := 8;
  end
  else
  begin
    Result.Font.Color := clrText;
    Result.Font.Size := 10;
  end;
  Result.Caption := WrapText(S, Result.Font, Sc(W));
  Result.AutoSize := False;
  Result.WordWrap := False;
  Result.Width := Sc(W) + 8;
  Result.Height := MeasureText(Result.Font, 'Ag').cy * LineCount(Result.Caption) + 4;
end;

{ ---------- сообщение и подтверждение ---------- }

function RunTextDialog(const Title, Text, YesText, NoText: string; IsError: Boolean): Boolean;
var
  F: TDarkForm;
  L: TLabel;
  Bar: TPanel;
begin
  F := TDarkForm.CreateDark(Title, 520);
  try
    if IsError then
    begin
      Bar := TPanel.Create(F);
      Bar.Parent := F.Inner;
      Bar.BevelOuter := bvNone;
      Bar.Color := clrDanger;
      Bar.ParentColor := False;
      Bar.SetBounds(0, Sc(44), Sc(4), Sc(400));
    end;
    L := F.AddText(Text, F.ContentTop + Sc(20), 470);
    if NoText <> '' then F.AddButton(NoText, False, mrCancel);
    F.AddButton(YesText, True, mrOK);
    F.FitHeight;
    Result := F.ShowModal = mrOK;
  finally
    F.Free;
  end;
end;

procedure DarkMessage(const Text: string; IsError: Boolean; const Title: string);
var
  T: string;
begin
  T := Title;
  if T = '' then
    if IsError then T := 'Ошибка' else T := 'IPTV Aristocrat';
  RunTextDialog(T, Text, 'OK', '', IsError);
end;

function DarkConfirm(const Text: string; const YesText: string; const NoText: string;
  const Title: string): Boolean;
begin
  Result := RunTextDialog(Title, Text, YesText, NoText, False);
end;

{ ---------- о программе ---------- }

function MakePic(F: TDarkForm; const Px: array of Byte; W, H, Size, X, Y: Integer): TImage;
var
  B: TBitmap;
begin
  Result := TImage.Create(F);
  Result.Parent := F.Inner;
  Result.SetBounds(X, Y, Size, Size);
  B := BitmapFromRgba(Px, W, H, Size, clrBg);
  try
    if B <> nil then Result.Picture.Assign(B);
  finally
    B.Free;
  end;
end;

function MakeLine(F: TDarkForm; const S: string; X, Y, W, Size: Integer; Bold, Dim: Boolean;
  Center: Boolean = False): TLabel;
begin
  Result := TLabel.Create(F);
  Result.Parent := F.Inner;
  Result.AutoSize := False;
  Result.Font.Size := Size;
  if Bold then Result.Font.Style := [fsBold];
  if Dim then Result.Font.Color := clrDim else Result.Font.Color := clrText;
  if Center then Result.Alignment := taCenter;
  Result.Caption := S;
  Result.SetBounds(X, Y, W, WrappedHeight(Result.Font, S, W));
end;

procedure DarkAbout(const AppName, Version, Platform: string);
var
  F: TDarkForm;
  Y, X, W, PicL, PicT: Integer;
  L: TLabel;
  Sep: TPanel;
begin
  F := TDarkForm.CreateDark('О программе', 560);
  try
    W := F.ClientWidth;
    { значок и название программы }
    PicL := Sc(28);
    Y := F.ContentTop + Sc(24);
    MakePic(F, APPBIG_RGBA, APPBIG_W, APPBIG_H, Sc(80), PicL, Y);
    X := PicL + Sc(80) + Sc(20);
    L := MakeLine(F, AppName, X, Y, W - X - Sc(20), 18, True, False);
    L := MakeLine(F, 'Версия ' + Version + '  ·  ' + Platform, X, L.Top + L.Height,
      W - X - Sc(20), 10, False, True);
    L := MakeLine(F, 'Плеер IPTV-каналов и фильмов с телепрограммой и архивом', X,
      L.Top + L.Height + Sc(2), W - X - Sc(20), 9, False, True);
    Y := Math.Max(Y + Sc(80), L.Top + L.Height) + Sc(20);

    Sep := TPanel.Create(F);
    Sep.Parent := F.Inner;
    Sep.BevelOuter := bvNone;
    Sep.Color := clrFrame;
    Sep.ParentColor := False;
    Sep.SetBounds(Sc(28), Y, W - Sc(56), 1);
    Inc(Y, Sc(20));

    { команда }
    PicT := Y;
    MakePic(F, TEAM_RGBA, TEAM_W, TEAM_H, Sc(96), PicL, PicT);
    X := PicL + Sc(96) + Sc(20);
    L := MakeLine(F, 'Aristocrat TEAM', X, PicT + Sc(10), W - X - Sc(20), 14, True, False);
    L := MakeLine(F, 'Разработчик:', X, L.Top + L.Height + Sc(4), W - X - Sc(20), 9, False, True);
    L := MakeLine(F, 'Олег Поляев', X, L.Top + L.Height, W - X - Sc(20), 11, False, False);
    Y := Math.Max(PicT + Sc(96), L.Top + L.Height) + Sc(18);

    MakeLine(F, '© 2026 Aristocrat TEAM  ✦  Все права защищены', Sc(20), Y, W - Sc(40), 9,
      False, True, True);

    F.AddButton('Закрыть', True, mrOK);
    F.FitHeight;
    F.ShowModal;
  finally
    F.Free;
  end;
end;

{ ---------- плейлист ---------- }

procedure TPlaylistForm.BrowseClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Title := 'Выберите файл плейлиста';
    D.Filter := 'Плейлисты (*.m3u, *.m3u8)|*.m3u;*.m3u8;*.M3U;*.M3U8|Все файлы|*';
    if D.Execute then
    begin
      edSource.Text := D.FileName;
      if Trim(edName.Text) = '' then
        edName.Text := ChangeFileExt(ExtractFileName(D.FileName), '');
    end;
  finally
    D.Free;
  end;
end;

function TPlaylistForm.Validate: Boolean;
begin
  Result := Trim(edSource.Text) <> '';
  if not Result then
  begin
    DarkMessage('Укажите ссылку на плейлист или выберите файл.');
    if edSource.CanFocus then edSource.SetFocus;
  end;
end;

function EditHeight(F: TFont): Integer;
begin
  Result := MeasureText(F, 'Ag').cy + Sc(12);
  if Result < Sc(28) then Result := Sc(28);
end;

function MakeEdit(F: TDarkForm; Y, W: Integer; const Hint: string): TEdit;
begin
  Result := TEdit.Create(F);
  Result.Parent := F.Inner;
  Result.Font.Color := clWindowText;
  Result.AutoSize := False;
  Result.SetBounds(Sc(22), Y, Sc(W), EditHeight(Result.Font));
  Result.TextHint := Hint;
end;

function GuessName(const Src: string): string;
var
  S: string;
  p: Integer;
begin
  S := Trim(Src);
  p := Pos('://', S);
  if p > 0 then
  begin
    S := Copy(S, p + 3, MaxInt);
    p := Pos('/', S);
    if p > 0 then S := Copy(S, 1, p - 1);
    Result := S;
  end
  else
    Result := ChangeFileExt(ExtractFileName(S), '');
  if Result = '' then Result := 'Плейлист';
end;

function DarkEditPlaylist(const Title: string; Kind: Integer;
  var AName, ASource, AEpg: string): Boolean;
var
  F: TPlaylistForm;
  Y: Integer;
  B: TFlatButton;
  L: TLabel;
begin
  F := TPlaylistForm.CreateDark(Title, 600);
  try
    F.OnValidate := @F.Validate;
    Y := F.ContentTop + Sc(18);
    if Kind = 1 then
      L := F.AddText('Медиатека — это плейлист M3U с фильмами и сериалами. Он появится в разделе «Фильмы» ' +
        'с постерами, без повторов и по категориям.', Y, 550, True)
    else
      L := F.AddText('Плейлист M3U с телеканалами. Телепрограмма подтянется сама, если ссылка на неё ' +
        'указана в плейлисте.', Y, 550, True);
    Inc(Y, L.Height + Sc(16));
    L := F.AddText('Название', Y, 550);
    Inc(Y, L.Height + Sc(4));
    F.edName := MakeEdit(F, Y, 554, 'например, Мой провайдер');
    F.edName.Text := AName;
    Inc(Y, F.edName.Height + Sc(16));
    L := F.AddText('Ссылка (http://...) или файл на компьютере', Y, 550);
    Inc(Y, L.Height + Sc(4));
    F.edSource := MakeEdit(F, Y, 420, 'http://provider.tv/playlist.m3u');
    F.edSource.Text := ASource;
    B := TFlatButton.Create(F);
    B.Parent := F.Inner;
    B.Bordered := True;
    B.Caption := 'Файл...';
    { кнопка — точно на одной линии с полем и той же высоты }
    B.SetBounds(F.edSource.Left + F.edSource.Width + Sc(10), F.edSource.Top,
      Sc(22) + Sc(554) - (F.edSource.Left + F.edSource.Width + Sc(10)), F.edSource.Height);
    B.OnClick := @F.BrowseClick;
    Inc(Y, F.edSource.Height + Sc(16));
    if Kind = 0 then
    begin
      L := F.AddText('Телепрограмма XMLTV (необязательно)', Y, 550);
      Inc(Y, L.Height + Sc(4));
      F.edEpg := MakeEdit(F, Y, 554, 'обычно указана в самом плейлисте');
      F.edEpg.Text := AEpg;
      Inc(Y, F.edEpg.Height + Sc(16));
    end;
    F.AddButton('Отмена', False, mrCancel);
    F.AddButton('Сохранить', True, mrOK);
    F.FitHeight;
    F.ActiveControl := F.edSource;

    Result := F.ShowModal = mrOK;
    if Result then
    begin
      ASource := Trim(F.edSource.Text);
      if F.edEpg <> nil then AEpg := Trim(F.edEpg.Text) else AEpg := '';
      AName := Trim(F.edName.Text);
      if AName = '' then AName := GuessName(ASource);
    end;
  finally
    F.Free;
  end;
end;


{ ---------- PIN-код ---------- }

function TPinForm.Validate: Boolean;
begin
  Result := False;
  if edPin2 <> nil then
  begin
    if Length(edPin.Text) < 4 then
    begin
      DarkMessage('PIN-код должен быть не короче 4 символов.');
      Exit;
    end;
    if edPin.Text <> edPin2.Text then
    begin
      DarkMessage('Коды не совпадают. Введите одинаковый код в оба поля.');
      Exit;
    end;
  end
  else if edPin.Text = '' then
    Exit;
  Result := True;
end;

function DarkAskPin(const Title, Text: string; Confirm: Boolean; out Pin: string): Boolean;
var
  F: TPinForm;
  Y: Integer;
  L: TLabel;
begin
  Pin := '';
  F := TPinForm.CreateDark(Title, 420);
  try
    F.OnValidate := @F.Validate;
    Y := F.ContentTop + Sc(18);
    L := F.AddText(Text, Y, 370, True);
    Inc(Y, L.Height + Sc(12));
    if Confirm then
    begin
      L := F.AddText('Новый PIN-код', Y, 370);
      Inc(Y, L.Height + Sc(4));
    end;
    F.edPin := MakeEdit(F, Y, 374, 'PIN-код');
    F.edPin.PasswordChar := '*';
    Inc(Y, F.edPin.Height + Sc(14));
    if Confirm then
    begin
      L := F.AddText('Повторите PIN-код', Y, 370);
      Inc(Y, L.Height + Sc(4));
      F.edPin2 := MakeEdit(F, Y, 374, 'ещё раз');
      F.edPin2.PasswordChar := '*';
    end;
    F.AddButton('Отмена', False, mrCancel);
    F.AddButton('OK', True, mrOK);
    F.FitHeight;
    F.ActiveControl := F.edPin;
    Result := F.ShowModal = mrOK;
    if Result then Pin := F.edPin.Text;
  finally
    F.Free;
  end;
end;

end.
