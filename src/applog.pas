{ Журнал запуска и перехват ошибок.
  Файл журнала: %TEMP%\iptv-aristocrat.log (Windows) или /tmp/iptv-aristocrat.log (Linux). }
unit applog;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

procedure Log(const S: string);
function LogFileName: string;
{ Отключает «ловушки» вычислений с плавающей точкой. Без этого видеодвижок
  VLC и драйверы видео могут обрушить программу прямо при запуске. }
procedure MaskFloatExceptions;
procedure InstallErrorHandler;
procedure ReportFatal(E: Exception; const Where: string);

implementation

uses
  Classes, Math, Forms, Dialogs;

type
  TErrorSink = class
    procedure HandleException(Sender: TObject; E: Exception);
  end;

var
  Sink: TErrorSink = nil;
  LogPath: string = '';

function LogFileName: string;
begin
  if LogPath = '' then
    LogPath := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'iptv-aristocrat.log';
  Result := LogPath;
end;

procedure Log(const S: string);
var
  F: TFileStream;
  Line: string;
begin
  try
    if FileExists(LogFileName) then
    begin
      F := TFileStream.Create(LogFileName, fmOpenWrite or fmShareDenyNone);
      F.Seek(0, soEnd);
    end
    else
      F := TFileStream.Create(LogFileName, fmCreate);
    try
      Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + '  ' + S + LineEnding;
      F.WriteBuffer(Line[1], Length(Line));
    finally
      F.Free;
    end;
  except
    { журнал не обязателен }
  end;
end;

procedure MaskFloatExceptions;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision]);
end;

procedure ReportFatal(E: Exception; const Where: string);
var
  Msg: string;
begin
  Msg := Where + ': ' + E.ClassName + ': ' + E.Message;
  Log('ОШИБКА ' + Msg);
  try
    MessageDlg('IPTV Aristocrat — ошибка',
      'Произошла ошибка:' + LineEnding + LineEnding + Msg + LineEnding + LineEnding +
      'Подробности записаны в файл:' + LineEnding + LogFileName,
      mtError, [mbOK], 0);
  except
  end;
end;

procedure TErrorSink.HandleException(Sender: TObject; E: Exception);
begin
  ReportFatal(E, 'Во время работы');
end;

procedure InstallErrorHandler;
begin
  if Sink = nil then Sink := TErrorSink.Create;
  Application.OnException := @Sink.HandleException;
end;

finalization
  Sink.Free;
end.
