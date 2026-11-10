(* Архив передач (catchup): построение ссылки на прошедшую передачу.
  Поддерживаются распространённые схемы IPTV-провайдеров:
    shift     — к ссылке добавляется ?utc=НАЧАЛО&lutc=СЕЙЧАС
    append    — к ссылке добавляется catchup-source с подстановками
    default   — catchup-source целиком заменяет ссылку
    flussonic — сервер Flussonic (index-НАЧАЛО-ДЛИТЕЛЬНОСТЬ.m3u8 / timeshift_abs-НАЧАЛО.ts)
    xc        — Xtream Codes (/timeshift/логин/пароль/минуты/дата/id.ts)
  Подстановки в catchup-source: {utc} {start} ${start} {utcend} {end} ${end}
  {lutc} {now} {timestamp} ${timestamp} {duration} ${duration} {offset} ${offset}
  {Y} {m} {d} {H} {M} {S} а также {utc:YmdHMS}-подобные форматы. *)
unit catchup;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, m3u;

const
  CATCHUP_NAMES: array[0..4] of string = ('', 'shift', 'flussonic', 'xc', 'append');
  CATCHUP_TITLES: array[0..4] of string =
    ('Нет (только если указано в плейлисте)', 'shift (?utc=…&lutc=…)', 'Flussonic', 'Xtream Codes', 'append');

{ Тип архива канала с учётом значения по умолчанию из настроек ('' — архива нет). }
function ArchiveType(Ch: TChannel; DefaultIndex: Integer): string;
function HasArchive(Ch: TChannel; DefaultIndex: Integer): Boolean;
function ArchiveDays(Ch: TChannel): Integer;
{ Ссылка на передачу StartUtc..StopUtc. Пустая строка — архив недоступен. }
function BuildArchiveUrl(Ch: TChannel; DefaultIndex: Integer;
  StartUtc, StopUtc, NowUtc: TDateTime): string;

implementation

uses
  epg;

function UnixOf(T: TDateTime): Int64;
begin
  Result := Round((T - 25569.0) * 86400);
end;

function Pad2(V: Integer): string;
begin
  Result := Format('%.2d', [V]);
end;

function NormType(const T: string): string;
begin
  Result := LowerCase(Trim(T));
  if (Result = 'fs') or (Result = 'flussonic-hls') or (Result = 'flussonic-ts') then
    Result := 'flussonic'
  else if (Result = 'xtream') or (Result = 'xtream-codes') then
    Result := 'xc'
  else if (Result = 'archive') or (Result = 'timeshift') then
    Result := 'shift'
  else if (Result = 'vod') or (Result = 'none') or (Result = 'disabled') then
    Result := '';
end;

function ArchiveType(Ch: TChannel; DefaultIndex: Integer): string;
begin
  Result := NormType(Ch.CatchupType);
  if Result = '' then
  begin
    if (DefaultIndex > 0) and (DefaultIndex <= High(CATCHUP_NAMES)) then
      Result := CATCHUP_NAMES[DefaultIndex]
    else if Ch.CatchupDays > 0 then
      Result := 'shift'
    else if Ch.CatchupSource <> '' then
      Result := 'default';
  end;
  if (Result = 'append') and (Ch.CatchupSource = '') then Result := 'shift';
  if (Result = 'default') and (Ch.CatchupSource = '') then Result := 'shift';
end;

function HasArchive(Ch: TChannel; DefaultIndex: Integer): Boolean;
begin
  Result := (Ch <> nil) and (ArchiveType(Ch, DefaultIndex) <> '');
end;

function ArchiveDays(Ch: TChannel): Integer;
begin
  Result := Ch.CatchupDays;
  if Result <= 0 then Result := 7;
end;

{ Формат вида YmdHMS → строка по времени T }
function FormatSpec(const Spec: string; T: TDateTime): string;
var
  i: Integer;
  Y, Mo, D, H, Mi, S, Ms: Word;
begin
  DecodeDate(T, Y, Mo, D);
  DecodeTime(T, H, Mi, S, Ms);
  Result := '';
  for i := 1 to Length(Spec) do
    case Spec[i] of
      'Y': Result := Result + IntToStr(Y);
      'y': Result := Result + Pad2(Y mod 100);
      'm': Result := Result + Pad2(Mo);
      'd': Result := Result + Pad2(D);
      'H': Result := Result + Pad2(H);
      'M': Result := Result + Pad2(Mi);
      'S': Result := Result + Pad2(S);
    else
      Result := Result + Spec[i];
    end;
end;

function Max1(V: Integer): Integer;
begin
  if V < 1 then Result := 1 else Result := V;
end;

function Fill(const Tpl: string; StartUtc, StopUtc, NowUtc: TDateTime): string;
var
  StartU, StopU, NowU, Dur: Int64;
  LocalStart: TDateTime;
  i, p, q: Integer;
  Name, Spec, Rep, Out: string;
begin
  StartU := UnixOf(StartUtc);
  StopU := UnixOf(StopUtc);
  NowU := UnixOf(NowUtc);
  Dur := StopU - StartU;
  LocalStart := UtcToLocal(StartUtc);
  Result := Tpl;

  // форматы вида имя:спецификация в фигурных скобках, например utc:YmdHMS или duration:60
  Out := '';
  i := 1;
  while i <= Length(Tpl) do
  begin
    Rep := #0;
    q := 0;
    if Tpl[i] = '{' then
    begin
      q := i + 1;
      while (q <= Length(Tpl)) and (Tpl[q] <> '}') and (Tpl[q] <> '{') do Inc(q);
      if (q <= Length(Tpl)) and (Tpl[q] = '}') then
      begin
        Name := Copy(Tpl, i + 1, q - i - 1);
        p := Pos(':', Name);
        if p > 0 then
        begin
          Spec := Copy(Name, p + 1, MaxInt);
          Name := LowerCase(Copy(Name, 1, p - 1));
          if (Name = 'utc') or (Name = 'start') then Rep := FormatSpec(Spec, StartUtc)
          else if (Name = 'utcend') or (Name = 'end') then Rep := FormatSpec(Spec, StopUtc)
          else if (Name = 'lutc') or (Name = 'now') or (Name = 'timestamp') then Rep := FormatSpec(Spec, NowUtc)
          else if Name = 'duration' then Rep := IntToStr(Dur div Int64(Max1(StrToIntDef(Spec, 1))))
          else if Name = 'offset' then Rep := IntToStr((NowU - StartU) div Int64(Max1(StrToIntDef(Spec, 1))));
        end;
      end;
    end;
    if Rep <> #0 then
    begin
      Out := Out + Rep;
      i := q + 1;
    end
    else
    begin
      Out := Out + Tpl[i];
      Inc(i);
    end;
  end;
  Result := Out;

  Result := StringReplace(Result, '${start}', IntToStr(StartU), [rfReplaceAll]);
  Result := StringReplace(Result, '${end}', IntToStr(StopU), [rfReplaceAll]);
  Result := StringReplace(Result, '${timestamp}', IntToStr(NowU), [rfReplaceAll]);
  Result := StringReplace(Result, '${duration}', IntToStr(Dur), [rfReplaceAll]);
  Result := StringReplace(Result, '${offset}', IntToStr(NowU - StartU), [rfReplaceAll]);
  Result := StringReplace(Result, '{utcend}', IntToStr(StopU), [rfReplaceAll]);
  Result := StringReplace(Result, '{utc}', IntToStr(StartU), [rfReplaceAll]);
  Result := StringReplace(Result, '{start}', IntToStr(StartU), [rfReplaceAll]);
  Result := StringReplace(Result, '{end}', IntToStr(StopU), [rfReplaceAll]);
  Result := StringReplace(Result, '{lutc}', IntToStr(NowU), [rfReplaceAll]);
  Result := StringReplace(Result, '{now}', IntToStr(NowU), [rfReplaceAll]);
  Result := StringReplace(Result, '{timestamp}', IntToStr(NowU), [rfReplaceAll]);
  Result := StringReplace(Result, '{duration}', IntToStr(Dur), [rfReplaceAll]);
  Result := StringReplace(Result, '{offset}', IntToStr(NowU - StartU), [rfReplaceAll]);
  Result := StringReplace(Result, '{Y}', FormatSpec('Y', LocalStart), [rfReplaceAll]);
  Result := StringReplace(Result, '{m}', FormatSpec('m', LocalStart), [rfReplaceAll]);
  Result := StringReplace(Result, '{d}', FormatSpec('d', LocalStart), [rfReplaceAll]);
  Result := StringReplace(Result, '{H}', FormatSpec('H', LocalStart), [rfReplaceAll]);
  Result := StringReplace(Result, '{M}', FormatSpec('M', LocalStart), [rfReplaceAll]);
  Result := StringReplace(Result, '{S}', FormatSpec('S', LocalStart), [rfReplaceAll]);
end;

procedure SplitQuery(const Url: string; out Base, Query: string);
var
  p: Integer;
begin
  p := Pos('?', Url);
  if p > 0 then
  begin
    Base := Copy(Url, 1, p - 1);
    Query := Copy(Url, p, MaxInt);
  end
  else
  begin
    Base := Url;
    Query := '';
  end;
end;

function FlussonicUrl(const Url: string; StartU, Dur: Int64): string;
var
  Base, Query, Dir, Last: string;
  p: Integer;
begin
  SplitQuery(Url, Base, Query);
  p := Length(Base);
  while (p > 0) and (Base[p] <> '/') do Dec(p);
  Dir := Copy(Base, 1, p);
  Last := Copy(Base, p + 1, MaxInt);
  if (LowerCase(Last) = 'mpegts') or (LowerCase(ExtractFileExt(Last)) = '.ts') then
    Result := Dir + 'timeshift_abs-' + IntToStr(StartU) + '.ts' + Query
  else if LowerCase(ExtractFileExt(Last)) = '.m3u8' then
    Result := Dir + ChangeFileExt(Last, '') + '-' + IntToStr(StartU) + '-' + IntToStr(Dur) + '.m3u8' + Query
  else
    Result := Base + '/index-' + IntToStr(StartU) + '-' + IntToStr(Dur) + '.m3u8' + Query;
end;

function XtreamUrl(const Url: string; StartUtc: TDateTime; Dur: Int64): string;
var
  Base, Query, Rest, Host, User, Pass, Id: string;
  Parts: array of string;
  p, n, i: Integer;
  LocalStart: TDateTime;
begin
  Result := '';
  SplitQuery(Url, Base, Query);
  p := Pos('://', Base);
  if p = 0 then Exit;
  Rest := Copy(Base, p + 3, MaxInt);
  n := 0;
  SetLength(Parts, 0);
  while Rest <> '' do
  begin
    p := Pos('/', Rest);
    SetLength(Parts, n + 1);
    if p = 0 then
    begin
      Parts[n] := Rest;
      Rest := '';
    end
    else
    begin
      Parts[n] := Copy(Rest, 1, p - 1);
      Rest := Copy(Rest, p + 1, MaxInt);
    end;
    Inc(n);
  end;
  { host/[live/]user/pass/id }
  if n < 4 then Exit;
  Host := Copy(Base, 1, Pos('://', Base) + 2) + Parts[0];
  i := 1;
  if LowerCase(Parts[1]) = 'live' then i := 2;
  if n - i < 3 then Exit;
  User := Parts[i];
  Pass := Parts[i + 1];
  Id := ChangeFileExt(Parts[n - 1], '');
  LocalStart := UtcToLocal(StartUtc);
  Result := Host + '/timeshift/' + User + '/' + Pass + '/' + IntToStr((Dur + 59) div 60) + '/' +
    FormatSpec('Y-m-d:H-M', LocalStart) + '/' + Id + '.ts' + Query;
end;

function BuildArchiveUrl(Ch: TChannel; DefaultIndex: Integer;
  StartUtc, StopUtc, NowUtc: TDateTime): string;
var
  T, Sep: string;
  StartU, Dur: Int64;
begin
  Result := '';
  if Ch = nil then Exit;
  T := ArchiveType(Ch, DefaultIndex);
  StartU := UnixOf(StartUtc);
  Dur := UnixOf(StopUtc) - StartU;
  if Pos('?', Ch.URL) > 0 then Sep := '&' else Sep := '?';
  if T = 'shift' then
    Result := Ch.URL + Sep + 'utc=' + IntToStr(StartU) + '&lutc=' + IntToStr(UnixOf(NowUtc))
  else if T = 'append' then
    Result := Ch.URL + Fill(Ch.CatchupSource, StartUtc, StopUtc, NowUtc)
  else if T = 'default' then
    Result := Fill(Ch.CatchupSource, StartUtc, StopUtc, NowUtc)
  else if T = 'flussonic' then
    Result := FlussonicUrl(Ch.URL, StartU, Dur)
  else if T = 'xc' then
    Result := XtreamUrl(Ch.URL, StartUtc, Dur);
end;

end.
