{ Загрузка файлов (плейлисты, телепрограмма).
  Windows: системный WinINet (есть в любой Windows, начиная с XP).
  Linux: системная утилита curl (или wget). }
unit netload;

{$mode objfpc}{$H+}

interface

function IsRemoteUrl(const S: string): Boolean;
{ Скачивает Source (ссылка или путь к файлу) в DestFile. }
function FetchToFile(const Source, DestFile: string; out ErrorMsg: string): Boolean;
{ То же, но со своим заголовком User-Agent (например, «как браузер» для картинок). }
function FetchToFileUA(const Source, DestFile, UA: string; out ErrorMsg: string): Boolean;

{ True — система не умеет современный HTTPS (Windows XP): ссылки https:// заменяются на http://. }
function HttpsUnsupported: Boolean;
{ На Windows XP превращает https:// в http://; на остальных системах ссылку не меняет. }
function FixUrlForSystem(const Url: string): string;

const
  BROWSER_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36';

implementation

uses
  SysUtils, Classes{$IFDEF WINDOWS}, Windows, Registry{$ELSE}, Process{$ENDIF};

const
  USER_AGENT = 'IPTV-Aristocrat/1.0';

function HttpsUnsupported: Boolean;
begin
{$IFDEF WINDOWS}
  Result := Win32MajorVersion < 6;   { 5.x — Windows 2000 / XP / Server 2003 }
{$ELSE}
  Result := False;
{$ENDIF}
end;

function FixUrlForSystem(const Url: string): string;
var
  T: string;
begin
  T := Trim(Url);
  if HttpsUnsupported and (LowerCase(Copy(T, 1, 8)) = 'https://') then
    Result := 'http://' + Copy(T, 9, MaxInt)
  else
    Result := T;
end;

function IsRemoteUrl(const S: string): Boolean;
var
  L: string;
begin
  L := LowerCase(Copy(Trim(S), 1, 8));
  Result := (Pos('http://', L) = 1) or (Pos('https://', L) = 1) or (Pos('ftp://', L) = 1);
end;

function LocalPath(const S: string): string;
begin
  Result := Trim(S);
  if LowerCase(Copy(Result, 1, 7)) = 'file://' then
  begin
    Delete(Result, 1, 7);
{$IFDEF WINDOWS}
    if (Length(Result) > 2) and (Result[1] = '/') and (Result[3] = ':') then
      Delete(Result, 1, 1);
    Result := StringReplace(Result, '/', '\', [rfReplaceAll]);
{$ENDIF}
  end;
end;

function CopyLocal(const Src, Dest: string; out ErrorMsg: string): Boolean;
var
  A, B: TFileStream;
begin
  Result := False;
  ErrorMsg := '';
  if not FileExists(Src) then
  begin
    ErrorMsg := 'Файл не найден: ' + Src;
    Exit;
  end;
  try
    A := TFileStream.Create(Src, fmOpenRead or fmShareDenyNone);
    try
      B := TFileStream.Create(Dest, fmCreate);
      try
        B.CopyFrom(A, 0);
      finally
        B.Free;
      end;
    finally
      A.Free;
    end;
    Result := True;
  except
    on E: Exception do
      ErrorMsg := E.Message;
  end;
end;

{$IFDEF WINDOWS}
type
  HINTERNET = Pointer;

const
  INTERNET_OPEN_TYPE_PRECONFIG    = 0;
  INTERNET_FLAG_RELOAD            = DWORD($80000000);
  INTERNET_FLAG_NO_CACHE_WRITE    = DWORD($04000000);
  INTERNET_FLAG_PRAGMA_NOCACHE    = DWORD($00000100);
  INTERNET_OPTION_CONNECT_TIMEOUT = 2;
  INTERNET_OPTION_RECEIVE_TIMEOUT = 6;
  HTTP_QUERY_STATUS_CODE          = 19;
  HTTP_QUERY_FLAG_NUMBER          = DWORD($20000000);

function InternetOpenW(lpszAgent: PWideChar; dwAccessType: DWORD; lpszProxy,
  lpszProxyBypass: PWideChar; dwFlags: DWORD): HINTERNET; stdcall; external 'wininet.dll';
function InternetOpenUrlW(hInet: HINTERNET; lpszUrl, lpszHeaders: PWideChar;
  dwHeadersLength, dwFlags: DWORD; dwContext: PtrUInt): HINTERNET; stdcall; external 'wininet.dll';
function InternetReadFile(hFile: HINTERNET; lpBuffer: Pointer; dwToRead: DWORD;
  var dwRead: DWORD): BOOL; stdcall; external 'wininet.dll';
function InternetCloseHandle(hInet: HINTERNET): BOOL; stdcall; external 'wininet.dll';
function InternetSetOptionW(hInet: HINTERNET; dwOption: DWORD; lpBuffer: Pointer;
  dwBufferLength: DWORD): BOOL; stdcall; external 'wininet.dll';
function HttpQueryInfoW(hRequest: HINTERNET; dwInfoLevel: DWORD; lpBuffer: Pointer;
  var lpdwBufferLength: DWORD; var lpdwIndex: DWORD): BOOL; stdcall; external 'wininet.dll';

function HttpDownload(const URL, Dest, UA: string; out ErrorMsg: string): Boolean;
var
  hNet, hUrl: HINTERNET;
  Buf: array[0..32767] of Byte;
  N, Code, Len, Idx, T: DWORD;
  F: TFileStream;
  WUrl: UnicodeString;
begin
  Result := False;
  ErrorMsg := '';
  hNet := InternetOpenW(PWideChar(UnicodeString(UA)), INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if hNet = nil then
  begin
    ErrorMsg := 'WinINet недоступен (код ' + IntToStr(GetLastError) + ')';
    Exit;
  end;
  try
    T := 20000;
    InternetSetOptionW(hNet, INTERNET_OPTION_CONNECT_TIMEOUT, @T, SizeOf(T));
    T := 60000;
    InternetSetOptionW(hNet, INTERNET_OPTION_RECEIVE_TIMEOUT, @T, SizeOf(T));
    WUrl := UTF8Decode(URL);
    hUrl := InternetOpenUrlW(hNet, PWideChar(WUrl), nil, 0,
      INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE or INTERNET_FLAG_PRAGMA_NOCACHE, 0);
    if hUrl = nil then
    begin
      ErrorMsg := 'нет соединения с сервером (код ' + IntToStr(GetLastError) + ')';
      if LowerCase(Copy(URL, 1, 6)) = 'https:' then
        ErrorMsg := ErrorMsg + '. Старые Windows (XP/Vista) могут не поддерживать ' +
          'современное HTTPS-шифрование — попробуйте ссылку http://';
      Exit;
    end;
    try
      Code := 0;
      Len := SizeOf(Code);
      Idx := 0;
      if HttpQueryInfoW(hUrl, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @Code, Len, Idx)
        and (Code >= 400) then
      begin
        ErrorMsg := 'сервер ответил ошибкой HTTP ' + IntToStr(Code);
        Exit;
      end;
      F := TFileStream.Create(Dest, fmCreate);
      try
        repeat
          N := 0;
          if not InternetReadFile(hUrl, @Buf[0], SizeOf(Buf), N) then
          begin
            ErrorMsg := 'загрузка прервалась';
            Exit;
          end;
          if N > 0 then
            F.WriteBuffer(Buf[0], N);
        until N = 0;
      finally
        F.Free;
      end;
      Result := True;
    finally
      InternetCloseHandle(hUrl);
    end;
  finally
    InternetCloseHandle(hNet);
  end;
end;
{$ELSE}
function HttpDownload(const URL, Dest, UA: string; out ErrorMsg: string): Boolean;
var
  Outp: string;
begin
  Result := False;
  ErrorMsg := '';
  try
    Result := RunCommand('curl', ['-fsSL', '--compressed', '--connect-timeout', '20',
      '--max-time', '900', '-A', UA, '-o', Dest, URL], Outp);
  except
    Result := False;
  end;
  if not Result then
  try
    Result := RunCommand('wget', ['-q', '-T', '60', '-U', UA, '-O', Dest, URL], Outp);
  except
    Result := False;
  end;
  if not Result then
    ErrorMsg := 'не удалось скачать ' + URL + ' (проверьте интернет и ссылку; нужен curl или wget)';
end;
{$ENDIF}

function FetchToFile(const Source, DestFile: string; out ErrorMsg: string): Boolean;
begin
  Result := FetchToFileUA(Source, DestFile, USER_AGENT, ErrorMsg);
end;

function FetchToFileUA(const Source, DestFile, UA: string; out ErrorMsg: string): Boolean;
begin
  if IsRemoteUrl(Source) then
    Result := HttpDownload(FixUrlForSystem(Source), DestFile, UA, ErrorMsg)
  else
    Result := CopyLocal(LocalPath(Source), DestFile, ErrorMsg);
  if Result and FileExists(DestFile) then
  begin
    { Пустой ответ считаем ошибкой. }
    with TFileStream.Create(DestFile, fmOpenRead or fmShareDenyNone) do
    try
      if Size = 0 then
      begin
        Result := False;
        ErrorMsg := 'получен пустой файл';
      end;
    finally
      Free;
    end;
  end;
end;

{$IFDEF WINDOWS}
{ Windows 7 умеет TLS 1.2, но по умолчанию WinINet его не включает —
  без этого многие сайты с https:// не открываются. Включаем для текущего
  пользователя (то же, что галочка «Использовать TLS 1.2» в свойствах браузера). }
procedure EnableModernTls;
var
  R: TRegistry;
  V: Integer;
begin
  if not ((Win32MajorVersion = 6) and (Win32MinorVersion <= 1)) then Exit;
  R := TRegistry.Create;
  try
    try
      R.RootKey := HKEY_CURRENT_USER;
      if R.OpenKey('Software\Microsoft\Windows\CurrentVersion\Internet Settings', True) then
      begin
        V := $A0;   { SSL 3.0 + TLS 1.0 — значение Windows 7 по умолчанию }
        if R.ValueExists('SecureProtocols') then V := R.ReadInteger('SecureProtocols');
        if (V and $800) = 0 then
          R.WriteInteger('SecureProtocols', V or $200 or $800);   { + TLS 1.1 и TLS 1.2 }
      end;
    except
    end;
  finally
    R.Free;
  end;
end;

initialization
  EnableModernTls;
{$ENDIF}

end.
