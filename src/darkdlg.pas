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
{ Kind: 0 — плейлист ТВ-каналов, 1 — медиатека (фильмы) }
function DarkEditPlaylist(const Title: string; Kind: Integer;
  var AName, ASource, AEpg: string): Boolean;

implementation

uses
  winframe;

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
    property Inner: TPanel read FInner;
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
  ClientWidth := AWidth;
  ClientHeight := 200;

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
  FTitleBar.Height := 44;
  FTitleBar.Align := alTop;
  FTitleBar.OnMouseDown := @TitleDown;

  FTitleLbl := TLabel.Create(Self);
  FTitleLbl.Parent := FTitleBar;
  FTitleLbl.Align := alClient;
  FTitleLbl.AutoSize := False;
  FTitleLbl.Layout := tlCenter;
  FTitleLbl.BorderSpacing.Left := 18;
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
  FButtons.Height := 62;
  FButtons.Align := alBottom;
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
  Result.Width := 140;
  Result.Align := alRight;
  Result.BorderSpacing.Top := 12;
  Result.BorderSpacing.Bottom := 14;
  Result.BorderSpacing.Right := 14;
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
  Result.Left := 22;
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
  Result.Caption := WrapText(S, Result.Font, W);
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
      Bar.SetBounds(0, 44, 4, 400);
    end;
    L := F.AddText(Text, 64, 470);
    F.ClientHeight := 44 + 20 + L.Height + 24 + 62 + 2;
    if NoText <> '' then F.AddButton(NoText, False, mrCancel);
    F.AddButton(YesText, True, mrOK);
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

function MakeEdit(F: TDarkForm; Y, W: Integer; const Hint: string): TEdit;
begin
  Result := TEdit.Create(F);
  Result.Parent := F.Inner;
  Result.Font.Color := clWindowText;
  Result.SetBounds(22, Y, W, 28);
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
begin
  F := TPlaylistForm.CreateDark(Title, 600);
  try
    F.OnValidate := @F.Validate;
    Y := 62;
    if Kind = 1 then
      F.AddText('Медиатека — это плейлист M3U с фильмами и сериалами. Он появится в разделе «Фильмы» ' +
        'с постерами, без повторов и по категориям.', Y, 550, True)
    else
      F.AddText('Плейлист M3U с телеканалами. Телепрограмма подтянется сама, если ссылка на неё ' +
        'указана в плейлисте.', Y, 550, True);
    Inc(Y, 50);
    F.AddText('Название', Y, 550);
    F.edName := MakeEdit(F, Y + 24, 554, 'например, Мой провайдер');
    F.edName.Text := AName;
    Inc(Y, 66);
    F.AddText('Ссылка (http://...) или файл на компьютере', Y, 550);
    F.edSource := MakeEdit(F, Y + 24, 420, 'http://provider.tv/playlist.m3u');
    F.edSource.Text := ASource;
    B := TFlatButton.Create(F);
    B.Parent := F.Inner;
    B.Bordered := True;
    B.Caption := 'Файл...';
    B.SetBounds(452, Y + 21, 124, 34);
    B.OnClick := @F.BrowseClick;
    Inc(Y, 66);
    if Kind = 0 then
    begin
      F.AddText('Телепрограмма XMLTV (необязательно)', Y, 550);
      F.edEpg := MakeEdit(F, Y + 24, 554, 'обычно указана в самом плейлисте');
      F.edEpg.Text := AEpg;
      Inc(Y, 66);
    end;
    F.ClientHeight := Y + 10 + 62 + 2;
    F.AddButton('Отмена', False, mrCancel);
    F.AddButton('Сохранить', True, mrOK);
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

end.
