{ Окно добавления / изменения плейлиста. }
unit playlistdlg;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Dialogs;

function EditPlaylist(AOwner: TComponent; const ATitle: string;
  var AName, ASource, AEpg: string): Boolean;

implementation

type
  TPlaylistDlg = class(TForm)
  public
    edName, edSource, edEpg: TEdit;
    procedure BrowseClick(Sender: TObject);
    procedure OkClick(Sender: TObject);
  end;

procedure TPlaylistDlg.BrowseClick(Sender: TObject);
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

procedure TPlaylistDlg.OkClick(Sender: TObject);
begin
  if Trim(edSource.Text) = '' then
  begin
    MessageDlg('Укажите ссылку на плейлист или выберите файл.', mtInformation, [mbOK], 0);
    edSource.SetFocus;
    Exit;
  end;
  ModalResult := mrOK;
end;

function MakeLabel(F: TForm; const S: string; Y: Integer): TLabel;
begin
  Result := TLabel.Create(F);
  Result.Parent := F;
  Result.Caption := S;
  Result.Left := 14;
  Result.Top := Y;
end;

function MakeEdit(F: TForm; Y, W: Integer): TEdit;
begin
  Result := TEdit.Create(F);
  Result.Parent := F;
  Result.Left := 14;
  Result.Top := Y;
  Result.Width := W;
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

function EditPlaylist(AOwner: TComponent; const ATitle: string;
  var AName, ASource, AEpg: string): Boolean;
var
  D: TPlaylistDlg;
  B: TButton;
  Y: Integer;
begin
  D := TPlaylistDlg.CreateNew(AOwner);
  try
    D.Caption := ATitle;
    D.BorderStyle := bsDialog;
    D.Position := poOwnerFormCenter;
    D.ClientWidth := 540;

    Y := 14;
    MakeLabel(D, 'Название (как будет показан в списке):', Y);
    Inc(Y, 22);
    D.edName := MakeEdit(D, Y, 512);
    D.edName.Text := AName;
    Inc(Y, 40);

    MakeLabel(D, 'Ссылка на плейлист M3U (http://...) или файл на компьютере:', Y);
    Inc(Y, 22);
    D.edSource := MakeEdit(D, Y, 410);
    D.edSource.Text := ASource;
    B := TButton.Create(D);
    B.Parent := D;
    B.Caption := 'Файл...';
    B.Left := 432;
    B.Top := Y - 1;
    B.Width := 94;
    B.OnClick := @D.BrowseClick;
    Inc(Y, 40);

    MakeLabel(D, 'Телепрограмма XMLTV (необязательно, обычно указана в самом плейлисте):', Y);
    Inc(Y, 22);
    D.edEpg := MakeEdit(D, Y, 512);
    D.edEpg.Text := AEpg;
    Inc(Y, 50);

    B := TButton.Create(D);
    B.Parent := D;
    B.Caption := 'Сохранить';
    B.Default := True;
    B.Width := 110;
    B.Left := 300;
    B.Top := Y;
    B.OnClick := @D.OkClick;

    B := TButton.Create(D);
    B.Parent := D;
    B.Caption := 'Отмена';
    B.Cancel := True;
    B.ModalResult := mrCancel;
    B.Width := 110;
    B.Left := 416;
    B.Top := Y;

    D.ClientHeight := Y + 46;
    D.ActiveControl := D.edSource;

    Result := D.ShowModal = mrOK;
    if Result then
    begin
      ASource := Trim(D.edSource.Text);
      AEpg := Trim(D.edEpg.Text);
      AName := Trim(D.edName.Text);
      if AName = '' then AName := GuessName(ASource);
    end;
  finally
    D.Free;
  end;
end;

end.
