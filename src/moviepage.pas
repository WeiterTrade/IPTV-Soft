{ Страница фильма: постер, название, описание, режиссёр, актёры,
  кнопка «Воспроизвести» — как в онлайн-кинотеатрах. }
unit moviepage;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, StdCtrls, ExtCtrls, Menus, Math, Forms,
  movies, m3u, widgets, logos, darkmenu;

type
  TPlayEvent = procedure(Sender: TObject; M: TMovie; SourceIndex: Integer) of object;

  TMoviePage = class(TPanel)
  private
    FMovie: TMovie;
    FLogos: TLogoCache;
    FSource: Integer;
    FOnPlay: TPlayEvent;
    FOnBack, FOnFav, FOnDownload: TNotifyEvent;
    btnBack, btnPlay, btnSource, btnFav, btnDownload: TFlatButton;
    lblTitle, lblMeta, lblDirector, lblCast, lblDesc, lblGroups: TLabel;
    pbPoster: TPaintBox;
    pmSources: TPopupMenu;
    FBox: TScrollBox;
    procedure PosterPaint(Sender: TObject);
    procedure BackClick(Sender: TObject);
    procedure PlayClick(Sender: TObject);
    procedure FavClick(Sender: TObject);
    procedure DownloadClick(Sender: TObject);
    procedure SourceClick(Sender: TObject);
    procedure SourceItemClick(Sender: TObject);
    function MakeLabel(Size: Integer; Bold, Dim: Boolean): TLabel;
    procedure LayoutControls;
  protected
    procedure Resize; override;
  public
    constructor CreatePage(AOwner: TComponent; ALogos: TLogoCache);
    procedure SetMovie(M: TMovie);
    procedure UpdateInfo;
    procedure SetFavorite(V: Boolean);
    procedure RefreshPoster;
    procedure SetDownloadCaption(const S: string);
    property Source: Integer read FSource;
    property Movie: TMovie read FMovie;
    property OnPlay: TPlayEvent read FOnPlay write FOnPlay;
    property OnBack: TNotifyEvent read FOnBack write FOnBack;
    property OnFav: TNotifyEvent read FOnFav write FOnFav;
    property OnDownload: TNotifyEvent read FOnDownload write FOnDownload;
  end;

implementation

const
  PW = 300;
  PH = 450;

constructor TMoviePage.CreatePage(AOwner: TComponent; ALogos: TLogoCache);
begin
  inherited Create(AOwner);
  SetBounds(0, 0, 1200, 800);
  BevelOuter := bvNone;
  Color := clrBg;
  ParentColor := False;
  FLogos := ALogos;
  { всё содержимое — в прокручиваемой области: длинное описание не обрежется }
  FBox := TScrollBox.Create(Self);
  FBox.Parent := Self;
  FBox.Align := alClient;
  FBox.BorderStyle := bsNone;
  FBox.Color := clrBg;
  FBox.ParentColor := False;
  FBox.HorzScrollBar.Visible := False;
  FBox.VertScrollBar.Tracking := True;
  FBox.VertScrollBar.Increment := 40;

  btnBack := TFlatButton.Create(Self);
  btnBack.Parent := FBox;
  btnBack.Kind := ikBack;
  btnBack.Caption := 'Назад';
  btnBack.Hint := 'Вернуться (Esc)';
  btnBack.OnClick := @BackClick;

  pbPoster := TPaintBox.Create(Self);
  pbPoster.Parent := FBox;
  pbPoster.OnPaint := @PosterPaint;

  lblTitle := MakeLabel(22, True, False);
  lblMeta := MakeLabel(10, False, True);
  lblGroups := MakeLabel(9, False, True);
  lblDirector := MakeLabel(10, False, False);
  lblCast := MakeLabel(10, False, False);
  lblDesc := MakeLabel(10, False, False);

  btnPlay := TFlatButton.Create(Self);
  btnPlay.Parent := FBox;
  btnPlay.Bordered := True;
  btnPlay.Checked := True;
  btnPlay.Kind := ikPlay;
  btnPlay.CheckedColor := clrBg;
  btnPlay.Caption := 'Воспроизвести';
  btnPlay.OnClick := @PlayClick;

  btnSource := TFlatButton.Create(Self);
  btnSource.Parent := FBox;
  btnSource.Bordered := True;
  btnSource.Caption := 'Источник 1';
  btnSource.OnClick := @SourceClick;

  btnFav := TFlatButton.Create(Self);
  btnFav.Parent := FBox;
  btnFav.Bordered := True;
  btnFav.Kind := ikStar;
  btnFav.Caption := 'В избранное';
  btnFav.OnClick := @FavClick;

  btnDownload := TFlatButton.Create(Self);
  btnDownload.Parent := FBox;
  btnDownload.Bordered := True;
  btnDownload.Kind := ikDownload;
  btnDownload.Caption := 'Скачать';
  btnDownload.Hint := 'Скачать фильм на компьютер, чтобы смотреть без интернета';
  btnDownload.OnClick := @DownloadClick;

  pmSources := TPopupMenu.Create(Self);
  LayoutControls;
end;

function TMoviePage.MakeLabel(Size: Integer; Bold, Dim: Boolean): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := FBox;
  Result.AutoSize := False;
  Result.WordWrap := True;
  Result.Font.Size := Size;
  if Bold then Result.Font.Style := [fsBold];
  if Dim then Result.Font.Color := clrDim else Result.Font.Color := clrText;
  Result.Caption := '';
end;

procedure TMoviePage.LayoutControls;
var
  X, Y, W, BH, BW, LH, Top0, SPos: Integer;

  procedure Place(L: TLabel; Gap: Integer);
  var
    H: Integer;
  begin
    H := WrappedHeight(L.Font, L.Caption, W);
    L.Visible := H > 0;
    if H = 0 then Exit;
    L.SetBounds(X, Y, W, H);
    Inc(Y, H + Gap);
  end;

begin
  if FBox = nil then Exit;
  { раскладываем при нулевой прокрутке, потом возвращаем её }
  SPos := FBox.VertScrollBar.Position;
  FBox.VertScrollBar.Position := 0;
  LH := MeasureText(btnBack.Font, 'Ag').cy;
  btnBack.SetBounds(Sc(20), Sc(12), MeasureText(btnBack.Font, 'Назад').cx + LH * 2 + Sc(16), LH + Sc(16));
  Top0 := btnBack.Top + btnBack.Height + Sc(16);
  pbPoster.SetBounds(Sc(36), Top0, PW, PH);
  BH := Math.Max(Sc(44), LH * 2 + Sc(6));
  btnPlay.SetBounds(Sc(36), Top0 + PH + Sc(16), PW, BH);
  { две кнопки под «Воспроизвести»: если не влезают в ширину постера — друг под другом }
  BW := MeasureText(btnSource.Font, btnSource.Caption).cx + Sc(24);
  if BW + MeasureText(btnFav.Font, btnFav.Caption).cx + LH * 2 + Sc(30) <= PW then
  begin
    btnSource.SetBounds(Sc(36), btnPlay.Top + BH + Sc(10), PW div 2 - 4, LH + Sc(18));
    btnFav.SetBounds(Sc(36) + PW div 2 + 4, btnSource.Top, PW div 2 - 4, LH + Sc(18));
  end
  else
  begin
    btnSource.SetBounds(Sc(36), btnPlay.Top + BH + Sc(10), PW, LH + Sc(18));
    btnFav.SetBounds(Sc(36), btnSource.Top + btnSource.Height + Sc(8), PW, LH + Sc(18));
  end;
  btnDownload.SetBounds(Sc(36), btnFav.Top + btnFav.Height + Sc(8), PW, LH + Sc(18));
  X := Sc(36) + PW + Sc(36);
  W := FBox.ClientWidth - X - Sc(36);
  if W < 200 then W := 200;
  Y := Top0 - Sc(6);
  Place(lblTitle, Sc(10));
  Place(lblMeta, Sc(2));
  Place(lblGroups, Sc(14));
  Place(lblDirector, Sc(6));
  Place(lblCast, Sc(16));
  Place(lblDesc, Sc(24));
  FBox.VertScrollBar.Position := SPos;
end;

procedure TMoviePage.SetDownloadCaption(const S: string);
begin
  btnDownload.Caption := S;
  btnDownload.Invalidate;
end;

procedure TMoviePage.DownloadClick(Sender: TObject);
begin
  if Assigned(FOnDownload) then FOnDownload(Self);
end;

procedure TMoviePage.RefreshPoster;
begin
  pbPoster.Invalidate;
end;

procedure TMoviePage.Resize;
begin
  inherited Resize;
  if (pbPoster <> nil) and (FBox <> nil) then LayoutControls;
end;

procedure TMoviePage.SetMovie(M: TMovie);
begin
  FMovie := M;
  FSource := 0;
  FBox.VertScrollBar.Position := 0;
  UpdateInfo;
  pbPoster.Invalidate;
end;

procedure TMoviePage.SetFavorite(V: Boolean);
begin
  if V then btnFav.IconColor := clrStar else btnFav.IconColor := clrText;
  if V then btnFav.Caption := 'В избранном' else btnFav.Caption := 'В избранное';
  btnFav.Invalidate;
  LayoutControls;
end;

procedure TMoviePage.UpdateInfo;
var
  S: string;
  i: Integer;
begin
  if FMovie = nil then Exit;
  lblTitle.Caption := FMovie.Title;
  S := FMovie.Year;
  if FMovie.Info.Genre <> '' then
  begin
    if S <> '' then S := S + '   ·   ';
    S := S + FMovie.Info.Genre;
  end;
  if FMovie.Info.Country <> '' then
  begin
    if S <> '' then S := S + '   ·   ';
    S := S + FMovie.Info.Country;
  end;
  if FMovie.Info.Runtime <> '' then
  begin
    if S <> '' then S := S + '   ·   ';
    S := S + FMovie.Info.Runtime;
  end;
  lblMeta.Caption := S;
  S := '';
  for i := 0 to FMovie.Groups.Count - 1 do
  begin
    if S <> '' then S := S + ', ';
    S := S + FMovie.Groups[i];
  end;
  lblGroups.Caption := S;
  if FMovie.Info.Director <> '' then
    lblDirector.Caption := 'Режиссёр:  ' + FMovie.Info.Director
  else
    lblDirector.Caption := '';
  if FMovie.Info.Cast <> '' then
    lblCast.Caption := 'В ролях:  ' + FMovie.Info.Cast
  else
    lblCast.Caption := '';
  case FMovie.InfoState of
    1: lblDesc.Caption := 'Загружаем описание...';
    2:
      if FMovie.Info.Description <> '' then
        lblDesc.Caption := FMovie.Info.Description
      else
        lblDesc.Caption := 'Описание не найдено.';
  else
    lblDesc.Caption := '';
  end;
  btnSource.Caption := 'Источник ' + IntToStr(FSource + 1) + ' из ' + IntToStr(FMovie.Sources.Count);
  btnSource.Enabled := FMovie.Sources.Count > 1;
  btnSource.Invalidate;
  LayoutControls;
end;

procedure TMoviePage.PosterPaint(Sender: TObject);
var
  C: TCanvas;
  B: TBitmap;
  S: string;
  TW: Integer;
begin
  C := pbPoster.Canvas;
  C.Brush.Style := bsSolid;
  C.Brush.Color := clrCard;
  C.Pen.Color := clrCard;
  C.RoundRect(0, 0, PW, PH, 14, 14);
  if FMovie = nil then Exit;
  B := nil;
  if (FLogos <> nil) and (FMovie.Poster <> '') then
    B := FLogos.GetPoster(FMovie.Poster, PW, PH, clrCard);
  if B <> nil then
    C.Draw(0, 0, B)
  else
  begin
    C.Brush.Style := bsClear;
    C.Font.Assign(Font);
    C.Font.Height := -90;
    C.Font.Style := [fsBold];
    C.Font.Color := clrDim;
    S := Copy(FMovie.Title, 1, 1);
    if (Length(FMovie.Title) > 1) and (Ord(FMovie.Title[1]) >= $C0) then S := Copy(FMovie.Title, 1, 2);
    TW := C.TextWidth(S);
    C.TextOut((PW - TW) div 2, PH div 3, S);
  end;
end;

procedure TMoviePage.BackClick(Sender: TObject);
begin
  if Assigned(FOnBack) then FOnBack(Self);
end;

procedure TMoviePage.PlayClick(Sender: TObject);
begin
  if (FMovie <> nil) and Assigned(FOnPlay) then FOnPlay(Self, FMovie, FSource);
end;

procedure TMoviePage.FavClick(Sender: TObject);
begin
  if Assigned(FOnFav) then FOnFav(Self);
end;

procedure TMoviePage.SourceClick(Sender: TObject);
var
  i: Integer;
  Mi: TMenuItem;
  Src: TChannel;
  P: TPoint;
begin
  if (FMovie = nil) or (FMovie.Sources.Count < 2) then Exit;
  pmSources.Items.Clear;
  for i := 0 to FMovie.Sources.Count - 1 do
  begin
    Src := TChannel(FMovie.Sources[i]);
    Mi := TMenuItem.Create(pmSources);
    Mi.Caption := 'Источник ' + IntToStr(i + 1) + ' — ' + Src.Name;
    if Src.Group <> '' then Mi.Caption := Mi.Caption + '  [' + Src.Group + ']';
    Mi.Tag := i;
    Mi.Checked := i = FSource;
    Mi.OnClick := @SourceItemClick;
    pmSources.Items.Add(Mi);
  end;
  StyleMenu(pmSources);
  P := btnSource.ClientToScreen(Point(0, btnSource.Height));
  pmSources.PopUp(P.X, P.Y);
end;

procedure TMoviePage.SourceItemClick(Sender: TObject);
begin
  FSource := TMenuItem(Sender).Tag;
  UpdateInfo;
end;

end.
