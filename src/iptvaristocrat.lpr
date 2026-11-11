program iptvaristocrat;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  xthreadsinit,   { должен идти раньше Interfaces }
  Interfaces,
  SysUtils,
  Forms,
  applog,
  mainform;

{$R *.res}

{$IFDEF WINDOWS}
{ Не показывать системные окна «Точка входа не найдена» при загрузке модулей VLC:
  модуль, несовместимый с этой версией Windows, просто пропускается. }
function SetErrorMode(uMode: LongWord): LongWord; stdcall; external 'kernel32.dll';
{$ENDIF}

begin
  {$IFDEF WINDOWS}
  SetErrorMode($0001 or $0002 or $8000);  { FAILCRITICALERRORS, NOGPFAULTERRORBOX, NOOPENFILEERRORBOX }
  {$ENDIF}
  MaskFloatExceptions;
  Log('---- запуск ' + ParamStr(0));
  try
    RequireDerivedFormResource := False;
    Application.Title := 'IPTV Aristocrat';
    Application.Scaled := True;
    Application.Initialize;
    InstallErrorHandler;
    Log('создание окна');
    Application.CreateForm(TMainForm, AppMainForm);
    Log('окно создано, запуск');
    Application.Run;
    Log('нормальное завершение');
  except
    on E: Exception do
      ReportFatal(E, 'При запуске');
  end;
end.
