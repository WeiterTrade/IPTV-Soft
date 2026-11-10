{ Фильмы из M3U-плейлиста: распознавание, объединение повторов, категории.
  Один и тот же фильм часто записан в плейлисте много раз (в разных
  категориях, в разном качестве). Здесь все такие записи собираются
  в одну карточку с несколькими источниками. }
unit movies;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, contnrs, m3u, movieinfo;

type
  TMovie = class
  public
    Title: string;        { очищенное название }
    Year: string;
    Poster: string;
    TitleLower: string;
    Sources: TFPList;     { TChannel — все записи плейлиста с этим фильмом }
    Groups: TStringList;  { категории, в которых встречается фильм }
    Info: TMovieInfo;     { описание, режиссёр, актёры (загружается по запросу) }
    InfoState: Integer;   { 0 — не загружали, 1 — загружается, 2 — готово }
    constructor Create;
    destructor Destroy; override;
    function MainSource: TChannel;
    function Url: string;   { ключ для избранного }
  end;

  TMovieLib = class
  private
    FMovies: TFPObjectList;
    FByKey: TStringList;      { ключ -> TMovie }
    FCategories: TStringList; { категория (Objects = число фильмов), в порядке плейлиста }
  public
    constructor Create;
    destructor Destroy; override;
    procedure Build(P: TPlaylistData);
    function Count: Integer;
    function Get(Index: Integer): TMovie;
    function FindByUrl(const AUrl: string): TMovie;
    property Categories: TStringList read FCategories;
  end;

{ True — запись плейлиста похожа на фильм/сериал, а не на телеканал. }
function IsVodEntry(Ch: TChannel): Boolean;
procedure MarkVod(P: TPlaylistData);
function CleanMovieTitle(const S: string; out Year: string): string;

implementation

uses
  LazUTF8;

const
  VOD_EXT: array[0..9] of string =
    ('.mp4', '.mkv', '.avi', '.mov', '.m4v', '.wmv', '.flv', '.mpg', '.mpeg', '.webm');
  VOD_GROUP_WORDS: array[0..13] of string =
    ('фильм', 'кино', 'сериал', 'мульт', 'movie', 'film', 'vod', 'series', 'cinema',
     'кинозал', 'фільм', 'серіал', 'аниме', 'anime');
  QUALITY_WORDS: array[0..33] of string =
    ('hd', 'fhd', 'uhd', 'sd', '4k', '8k', '1080p', '720p', '2160p', '480p', '1080', '720',
     'bdrip', 'webrip', 'web-dl', 'webdl', 'hdrip', 'dvdrip', 'camrip', 'hdtv', 'bluray',
     'x264', 'x265', 'h264', 'h265', 'hevc', 'avc', 'дубляж', 'дб', 'mvo', 'avo', 'rus', 'eng', '3d');

function UrlPathLower(const Url: string): string;
var
  p: Integer;
begin
  Result := LowerCase(Url);
  p := Pos('?', Result);
  if p > 0 then Result := Copy(Result, 1, p - 1);
end;

function IsVodEntry(Ch: TChannel): Boolean;
var
  U, G: string;
  i: Integer;
  LiveUrl: Boolean;
begin
  Result := False;
  U := UrlPathLower(Ch.URL);
  for i := 0 to High(VOD_EXT) do
    if (Length(U) > Length(VOD_EXT[i])) and
       (Copy(U, Length(U) - Length(VOD_EXT[i]) + 1, MaxInt) = VOD_EXT[i]) then
      Exit(True);
  if (Pos('/movie/', U) > 0) or (Pos('/movies/', U) > 0) or (Pos('/series/', U) > 0) or
     (Pos('/vod/', U) > 0) then
    Exit(True);
  { по названию категории — только если ссылка не похожа на живой поток }
  LiveUrl := (Pos('.m3u8', U) > 0) or (Pos('/live/', U) > 0) or (Pos('udp://', U) = 1) or
    (Pos('rtp://', U) = 1) or (Pos('/udp/', U) > 0) or (Pos('/rtp/', U) > 0) or
    (Pos('/mpegts', U) > 0) or (Pos('rtmp://', U) = 1);
  if LiveUrl then Exit;
  G := UTF8LowerCase(Ch.Group);
  for i := 0 to High(VOD_GROUP_WORDS) do
    if Pos(VOD_GROUP_WORDS[i], G) > 0 then
      Exit(True);
end;

procedure MarkVod(P: TPlaylistData);
var
  i: Integer;
begin
  for i := 0 to P.Count - 1 do
    P.Get(i).IsVod := IsVodEntry(P.Get(i));
end;

function IsYear(const W: string): Boolean;
var
  Y: Integer;
begin
  Result := (Length(W) = 4) and TryStrToInt(W, Y) and (Y >= 1900) and (Y <= 2100);
end;

function CleanMovieTitle(const S: string; out Year: string): string;
var
  T, Inner, W, Lw: string;
  p, q, i, k: Integer;
  Words: TStringList;
  Skip: Boolean;
begin
  Year := '';
  T := Trim(S);
  { содержимое скобок: год сохраняем, остальное убираем }
  repeat
    p := 0;
    for i := 1 to Length(T) do
      if T[i] in ['(', '['] then
      begin
        p := i;
        Break;
      end;
    if p = 0 then Break;
    q := p + 1;
    while (q <= Length(T)) and not (T[q] in [')', ']']) do Inc(q);
    Inner := Trim(Copy(T, p + 1, q - p - 1));
    if (Year = '') and IsYear(Inner) then Year := Inner;
    Delete(T, p, q - p + 1);
  until False;
  for i := 1 to Length(T) do
    if T[i] in ['|', '_', '/', '\'] then T[i] := ' ';

  Words := TStringList.Create;
  try
    Words.Delimiter := ' ';
    Words.StrictDelimiter := True;
    Words.DelimitedText := T;
    Result := '';
    for i := 0 to Words.Count - 1 do
    begin
      W := Trim(Words[i]);
      if W = '' then Continue;
      Lw := UTF8LowerCase(W);
      while (Lw <> '') and (Lw[Length(Lw)] in ['.', ',', '-', ':']) do Delete(Lw, Length(Lw), 1);
      if (Year = '') and IsYear(Lw) and (i > 0) then
      begin
        Year := Lw;
        Continue;
      end;
      Skip := False;
      for k := 0 to High(QUALITY_WORDS) do
        if Lw = QUALITY_WORDS[k] then
        begin
          Skip := True;
          Break;
        end;
      if Skip then Continue;
      if Result <> '' then Result := Result + ' ';
      Result := Result + W;
    end;
  finally
    Words.Free;
  end;
  Result := Trim(Result);
  while (Result <> '') and (Result[Length(Result)] in ['-', ',', '.', ':']) do
    Result := Trim(Copy(Result, 1, Length(Result) - 1));
  if Result = '' then Result := Trim(S);
end;

{ Ключ для сравнения: буквы и цифры в нижнем регистре, ё = е }
function MovieKey(const Title: string): string;
var
  L: string;
  i: Integer;
begin
  L := UTF8LowerCase(Title);
  L := StringReplace(L, 'ё', 'е', [rfReplaceAll]);
  Result := '';
  for i := 1 to Length(L) do
    if (L[i] in ['a'..'z', '0'..'9']) or (Ord(L[i]) >= $80) then
      Result := Result + L[i];
end;

{ TMovie }

constructor TMovie.Create;
begin
  inherited Create;
  Sources := TFPList.Create;
  Groups := TStringList.Create;
end;

destructor TMovie.Destroy;
begin
  Groups.Free;
  Sources.Free;
  inherited Destroy;
end;

function TMovie.MainSource: TChannel;
begin
  if Sources.Count > 0 then Result := TChannel(Sources[0]) else Result := nil;
end;

function TMovie.Url: string;
begin
  if Sources.Count > 0 then Result := TChannel(Sources[0]).URL else Result := '';
end;

{ TMovieLib }

constructor TMovieLib.Create;
begin
  inherited Create;
  FMovies := TFPObjectList.Create(True);
  FByKey := TStringList.Create;
  FByKey.Sorted := True;
  FByKey.CaseSensitive := True;
  FByKey.Duplicates := dupIgnore;
  FCategories := TStringList.Create;
end;

destructor TMovieLib.Destroy;
begin
  FCategories.Free;
  FByKey.Free;
  FMovies.Free;
  inherited Destroy;
end;

procedure TMovieLib.Build(P: TPlaylistData);
var
  i, k, j: Integer;
  Ch: TChannel;
  M: TMovie;
  Title, Year, Key: string;
  CatIdx: TStringList;   { категория -> индекс в FCategories (для быстрого поиска) }
begin
  FMovies.Clear;
  FByKey.Clear;
  FCategories.Clear;
  if P = nil then Exit;
  CatIdx := TStringList.Create;
  try
    CatIdx.Sorted := True;
    CatIdx.CaseSensitive := True;
    for i := 0 to P.Count - 1 do
    begin
      Ch := P.Get(i);
      if not Ch.IsVod then Continue;
      Title := CleanMovieTitle(Ch.Name, Year);
      Key := MovieKey(Title);
      if Key = '' then Key := Ch.URL;
      M := nil;
      { сначала точное совпадение «название + год», затем только название }
      if (Year <> '') and FByKey.Find(Key + '|' + Year, k) then
        M := TMovie(FByKey.Objects[k])
      else if FByKey.Find(Key, k) then
      begin
        M := TMovie(FByKey.Objects[k]);
        if (Year <> '') and (M.Year <> '') and (M.Year <> Year) then M := nil;
      end;
      if M = nil then
      begin
        M := TMovie.Create;
        M.Title := Title;
        M.Year := Year;
        M.TitleLower := UTF8LowerCase(Title);
        FMovies.Add(M);
        if not FByKey.Find(Key, k) then FByKey.AddObject(Key, M);
        if Year <> '' then FByKey.AddObject(Key + '|' + Year, M);
      end
      else if (M.Year = '') and (Year <> '') then
      begin
        M.Year := Year;
        if not FByKey.Find(Key + '|' + Year, k) then FByKey.AddObject(Key + '|' + Year, M);
      end;
      if M.Sources.IndexOf(Ch) < 0 then
      begin
        { одинаковые ссылки не дублируем }
        k := -1;
        for j := 0 to M.Sources.Count - 1 do
          if TChannel(M.Sources[j]).URL = Ch.URL then k := j;
        if k < 0 then M.Sources.Add(Ch);
      end;
      if (M.Poster = '') and (Ch.Logo <> '') then M.Poster := Ch.Logo;
      if (Ch.Group <> '') and (M.Groups.IndexOf(Ch.Group) < 0) then
      begin
        M.Groups.Add(Ch.Group);
        if CatIdx.Find(Ch.Group, k) then
        begin
          j := PtrInt(CatIdx.Objects[k]);
          FCategories.Objects[j] := TObject(PtrInt(FCategories.Objects[j]) + 1);
        end
        else
        begin
          j := FCategories.AddObject(Ch.Group, TObject(PtrInt(1)));
          CatIdx.AddObject(Ch.Group, TObject(PtrInt(j)));
        end;
      end;
    end;
  finally
    CatIdx.Free;
  end;
end;

function TMovieLib.Count: Integer;
begin
  Result := FMovies.Count;
end;

function TMovieLib.Get(Index: Integer): TMovie;
begin
  Result := TMovie(FMovies[Index]);
end;

function TMovieLib.FindByUrl(const AUrl: string): TMovie;
var
  i, j: Integer;
begin
  Result := nil;
  for i := 0 to FMovies.Count - 1 do
    for j := 0 to Get(i).Sources.Count - 1 do
      if TChannel(Get(i).Sources[j]).URL = AUrl then
        Exit(Get(i));
end;

end.
