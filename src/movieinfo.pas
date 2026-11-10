{ Описание фильма из открытых источников (без ключей и регистрации):
    Википедия (описание) + Викиданные (режиссёр, актёры, жанр)
    и каталог iTunes (жанр, длительность, режиссёр — если не нашлось выше).
  Результат сохраняется на диске, поэтому работает и без интернета. }
unit movieinfo;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TMovieInfo = record
    Found: Boolean;
    Description, Director, Cast, Genre, Runtime, Country: string;
  end;

  TMovieInfoThread = class(TThread)
  protected
    procedure Execute; override;
  public
    Title, Year, CacheDir: string;
    Generation: Integer;
    Data: Pointer;        { кому принадлежит результат (TMovie) }
    Info: TMovieInfo;
    constructor Create(const ATitle, AYear, ACacheDir: string; AGen: Integer);
  end;

implementation

uses
  fpjson, jsonparser, netload, appsettings, applog;

function UrlEnc(const S: string): string;
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

constructor TMovieInfoThread.Create(const ATitle, AYear, ACacheDir: string; AGen: Integer);
begin
  Title := ATitle;
  Year := AYear;
  CacheDir := IncludeTrailingPathDelimiter(ACacheDir);
  Generation := AGen;
  inherited Create(True);
  FreeOnTerminate := True;
end;

function GetJsonUrl(const Url, Tmp: string): TJSONData;
var
  Err: string;
  F: TFileStream;
begin
  Result := nil;
  if not FetchToFileUA(Url, Tmp, BROWSER_UA, Err) then Exit;
  try
    F := TFileStream.Create(Tmp, fmOpenRead or fmShareDenyNone);
    try
      Result := GetJSON(F);
    finally
      F.Free;
    end;
  except
    Result := nil;
  end;
  DeleteFile(Tmp);
end;

function JStr(D: TJSONData; const Path: string): string;
var
  X: TJSONData;
begin
  Result := '';
  if D = nil then Exit;
  X := D.FindPath(Path);
  if (X <> nil) and (X.JSONType = jtString) then Result := X.AsString;
end;

{ Подписи (названия) сущностей Викиданных по их идентификаторам. }
function WikidataLabels(Ids: TStrings; const Tmp: string; MaxCount: Integer): string;
var
  D, E: TJSONData;
  i: Integer;
  L, S: string;
begin
  Result := '';
  if Ids.Count = 0 then Exit;
  S := '';
  for i := 0 to Ids.Count - 1 do
  begin
    if i >= MaxCount then Break;
    if S <> '' then S := S + '|';
    S := S + Ids[i];
  end;
  D := GetJsonUrl('https://www.wikidata.org/w/api.php?action=wbgetentities&format=json&props=labels' +
    '&languages=ru|en&ids=' + UrlEnc(S), Tmp);
  if D = nil then Exit;
  try
    for i := 0 to Ids.Count - 1 do
    begin
      if i >= MaxCount then Break;
      E := D.FindPath('entities.' + Ids[i]);
      if E = nil then Continue;
      L := JStr(E, 'labels.ru.value');
      if L = '' then L := JStr(E, 'labels.en.value');
      if L = '' then Continue;
      if Result <> '' then Result := Result + ', ';
      Result := Result + L;
    end;
  finally
    D.Free;
  end;
end;

procedure ClaimIds(Ent: TJSONData; const Prop: string; Ids: TStrings; MaxCount: Integer);
var
  A: TJSONData;
  i: Integer;
  Id: string;
begin
  A := Ent.FindPath('claims.' + Prop);
  if (A = nil) or (A.JSONType <> jtArray) then Exit;
  for i := 0 to A.Count - 1 do
  begin
    if Ids.Count >= MaxCount then Break;
    Id := JStr(A.Items[i], 'mainsnak.datavalue.value.id');
    if (Id <> '') and (Ids.IndexOf(Id) < 0) then Ids.Add(Id);
  end;
end;

function LoadCache(const FileName: string; out Info: TMovieInfo): Boolean;
var
  L: TStringList;
begin
  Result := False;
  if not FileExists(FileName) then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    Info.Found := L.Values['found'] = '1';
    Info.Description := StringReplace(L.Values['desc'], '\n', LineEnding, [rfReplaceAll]);
    Info.Director := L.Values['director'];
    Info.Cast := L.Values['cast'];
    Info.Genre := L.Values['genre'];
    Info.Runtime := L.Values['runtime'];
    Info.Country := L.Values['country'];
    Result := True;
  finally
    L.Free;
  end;
end;

procedure SaveCache(const FileName: string; const Info: TMovieInfo);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    if Info.Found then L.Add('found=1') else L.Add('found=0');
    L.Add('desc=' + StringReplace(StringReplace(Info.Description, #13, '', [rfReplaceAll]),
      #10, '\n', [rfReplaceAll]));
    L.Add('director=' + Info.Director);
    L.Add('cast=' + Info.Cast);
    L.Add('genre=' + Info.Genre);
    L.Add('runtime=' + Info.Runtime);
    L.Add('country=' + Info.Country);
    try
      L.SaveToFile(FileName);
    except
    end;
  finally
    L.Free;
  end;
end;

procedure TMovieInfoThread.Execute;
var
  CacheFile, Tmp, WTitle, QId, S: string;
  D, Ent: TJSONData;
  Ids: TStringList;
  i, Ms: Integer;
  R: TJSONData;
  Rel: string;
begin
  MaskFloatExceptions;
  Info.Found := False;
  Info.Description := '';
  Info.Director := '';
  Info.Cast := '';
  Info.Genre := '';
  Info.Runtime := '';
  Info.Country := '';
  CacheFile := CacheDir + 'movie_' + HashStr(LowerCase(Title) + '|' + Year) + '.txt';
  Tmp := CacheDir + 'movie_' + HashStr(Title + Year) + '.tmp';
  if LoadCache(CacheFile, Info) then
    if Info.Found or (Now - FileDateToDateTime(FileAge(CacheFile)) < 3) then Exit;
  Info.Found := False;
  try
    { 1) Википедия: поиск статьи о фильме }
    S := Title;
    if Year <> '' then S := S + ' ' + Year;
    S := S + ' фильм';
    D := GetJsonUrl('https://ru.wikipedia.org/w/api.php?action=query&format=json&list=search&srlimit=1' +
      '&srsearch=' + UrlEnc(S), Tmp);
    WTitle := '';
    if D <> nil then
    try
      WTitle := JStr(D, 'query.search[0].title');
    finally
      D.Free;
    end;
    QId := '';
    if WTitle <> '' then
    begin
      D := GetJsonUrl('https://ru.wikipedia.org/api/rest_v1/page/summary/' +
        UrlEnc(StringReplace(WTitle, ' ', '_', [rfReplaceAll])), Tmp);
      if D <> nil then
      try
        Info.Description := JStr(D, 'extract');
        QId := JStr(D, 'wikibase_item');
      finally
        D.Free;
      end;
    end;

    { 2) Викиданные: режиссёр, актёры, жанр, страна, длительность }
    if QId <> '' then
    begin
      D := GetJsonUrl('https://www.wikidata.org/wiki/Special:EntityData/' + QId + '.json', Tmp);
      if D <> nil then
      try
        Ent := D.FindPath('entities.' + QId);
        if Ent <> nil then
        begin
          Ids := TStringList.Create;
          try
            ClaimIds(Ent, 'P57', Ids, 3);
            Info.Director := WikidataLabels(Ids, Tmp, 3);
            Ids.Clear;
            ClaimIds(Ent, 'P161', Ids, 10);
            Info.Cast := WikidataLabels(Ids, Tmp, 10);
            Ids.Clear;
            ClaimIds(Ent, 'P136', Ids, 3);
            Info.Genre := WikidataLabels(Ids, Tmp, 3);
            Ids.Clear;
            ClaimIds(Ent, 'P495', Ids, 2);
            Info.Country := WikidataLabels(Ids, Tmp, 2);
          finally
            Ids.Free;
          end;
          S := JStr(Ent, 'claims.P2047[0].mainsnak.datavalue.value.amount');
          if S <> '' then
          begin
            S := StringReplace(S, '+', '', []);
            if Pos('.', S) > 0 then S := Copy(S, 1, Pos('.', S) - 1);
            if StrToIntDef(S, 0) > 0 then Info.Runtime := S + ' мин';
          end;
        end;
      finally
        D.Free;
      end;
    end;

    { 3) iTunes — если чего-то не хватает }
    if (Info.Description = '') or (Info.Director = '') or (Info.Genre = '') or (Info.Runtime = '') then
    begin
      D := GetJsonUrl('https://itunes.apple.com/search?media=movie&entity=movie&country=ru&lang=ru_ru&limit=5&term=' +
        UrlEnc(Title), Tmp);
      if D <> nil then
      try
        R := D.FindPath('results');
        if (R <> nil) and (R.JSONType = jtArray) and (R.Count > 0) then
        begin
          Ent := R.Items[0];
          if Year <> '' then
            for i := 0 to R.Count - 1 do
            begin
              Rel := JStr(R.Items[i], 'releaseDate');
              if Copy(Rel, 1, 4) = Year then
              begin
                Ent := R.Items[i];
                Break;
              end;
            end;
          if Info.Description = '' then Info.Description := JStr(Ent, 'longDescription');
          if Info.Director = '' then Info.Director := JStr(Ent, 'artistName');
          if Info.Genre = '' then Info.Genre := JStr(Ent, 'primaryGenreName');
          if (Info.Runtime = '') and (Ent.FindPath('trackTimeMillis') <> nil) then
          begin
            Ms := Ent.FindPath('trackTimeMillis').AsInteger;
            if Ms > 0 then Info.Runtime := IntToStr(Ms div 60000) + ' мин';
          end;
        end;
      finally
        D.Free;
      end;
    end;
    Info.Found := (Info.Description <> '') or (Info.Director <> '') or (Info.Cast <> '');
  except
    on E: Exception do
      Log('описание фильма «' + Title + '»: ' + E.Message);
  end;
  SaveCache(CacheFile, Info);
end;

end.
