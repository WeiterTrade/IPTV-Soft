{ Страница фильма: постер, название, описание, режиссёр, актёры,
  кнопка «Воспроизвести» — как в онлайн-кинотеатрах. }
unit moviepage;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, StdCtrls, ExtCtrls, Menus, Math,
  movies, m3u, widgets, logos;

type
  TPlayEvent = procedure(Sender: TObject; M: TMovie; SourceIndex: Integer) of object;

  TMoviePage = class(TPanel)
  private
    FMovie: TMovie;
    FLogos: TLogoCache;
    FSource: Integer;
    FOnPlay: TPlayEvent;
    FOnBack, FOnFav: TNotifyEvent;
    btnBack, btnPlay, btnSource, btnFav: TFlatButton;
    lblTitle, lblMeta, lblDirector, lblCast, lblDesc, lblGroups: TLabel;
    pbPoster: TPaintBox;
    pmSources: TPopupMenu;
    procedure PosterPaint(Sender: TObject);
    procedure BackClick(Sender: TObject);
    procedure PlayClick(Sender: TObject);
    procedure FavClick(Sender: TObject);
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
    property Movie: TMovie read FMovie;
    property OnPlay: TPlayEvent read FOnPlay write FOnPlay;
    property OnBack: TNotifyEvent read FOnBack write FOnBack;
    property OnFav: TNotifyEvent read FOnFav write FOnFav;
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

  btnBack := TFlatButton.Create(Self);
  btnBack.Parent := Self;
  btnBack.Kind := ikBack;
  btnBack.Caption := 'Назад';
  btnBack.Hint := 'Вернуться (Esc)';
  btnBack.OnClick := @BackClick;

  pbPoster := TPaintBox.Create(Self);
  pbPoster.Parent := Self;
  pbPoster.OnPaint := @PosterPaint;

  lblTitle := MakeLabel(22, True, False);
  lblMeta := MakeLabel(10, False, True);
  lblGroups := MakeLabel(9, False, True);
  lblDirector := MakeLabel(10, False, False);
  lblCast := MakeLabel(10, False, False);
  lblDesc := MakeLabel(10, False, False);

  btnPlay := TFlatButton.Create(Self);
  btnPlay.Parent := Self;
  btnPlay.Bordered := True;
  btnPlay.Checked := True;
  btnPlay.Kind := ikPlay;
  btnPlay.CheckedColor := clrBg;
  btnPlay.Caption := 'Воспроизвести';
  btnPlay.OnClick := @PlayClick;

  btnSource := TFlatButton.Create(Self);
  btnSource.Parent := Self;
  btnSource.Bordered := True;
  btnSource.Caption := 'Источник 1';
  btnSource.OnClick := @SourceClick;

  btnFav := TFlatButton.Create(Self);
  btnFav.Parent := Self;
  btnFav.Bordered := True;
  btnFav.Kind := ikStar;
  btnFav.Caption := 'В избранное';
  btnFav.OnClick := @FavClick;

  pmSources := TPopupMenu.Create(Self);
  LayoutControls;
end;

function TMoviePage.MakeLabel(Size: Integer; Bold, Dim: Boolean): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.AutoSize := False;
  Result.WordWrap := True;
  Result.Font.Size := Size;
  if Bold then Result.Font.Style := [fsBold];
  if Dim then Result.Font.Color := clrDim else Result.Font.Color := clrText;
  Result.Caption := '';
end;

procedure TMoviePage.LayoutControls;
var
  X, Y, W: Integer;
begin
  btnBack.SetBounds(24, 16, 110, 36);
  pbPoster.SetBounds(40, 70, PW, PH);
  btnPlay.SetBounds(40, 70 + PH + 18, PW, 48);
  btnSource.SetBounds(40, 70 + PH + 74, PW div 2 - 4, 38);
  btnFav.SetBounds(40 + PW div 2 + 4, 70 + PH + 74, PW div 2 - 4, 38);
  X := 40 + PW + 40;
  W := Math.Max(200, ClientWidth - X - 40);
  Y := 64;
  lblTitle.SetBounds(X, Y, W, 80);
  Inc(Y, 84);
  lblMeta.SetBounds(X, Y, W, 24);
  Inc(Y, 28);
  lblGroups.SetBounds(X, Y, W, 22);
  Inc(Y, 34);
  lblDirector.SetBounds(X, Y, W, 24);
  Inc(Y, 30);
  lblCast.SetBounds(X, Y, W, 48);
  Inc(Y, 60);
  lblDesc.SetBounds(X, Y, W, Math.Max(100, ClientHeight - Y - 30));
end;

procedure TMoviePage.Resize;
begin
  inherited Resize;
  if pbPoster <> nil then LayoutControls;
end;

procedure TMoviePage.SetMovie(M: TMovie);
begin
  FMovie := M;
  FSource := 0;
  UpdateInfo;
  pbPoster.Invalidate;
end;

procedure TMoviePage.SetFavorite(V: Boolean);
begin
  if V then btnFav.IconColor := clrStar else btnFav.IconColor := clrText;
  if V then btnFav.Caption := 'В избранном' else btnFav.Caption := 'В избранное';
  btnFav.Invalidate;
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
  P := btnSource.ClientToScreen(Point(0, btnSource.Height));
  pmSources.PopUp(P.X, P.Y);
end;

procedure TMoviePage.SourceItemClick(Sender: TObject);
begin
  FSource := TMenuItem(Sender).Tag;
  UpdateInfo;
end;

end.
