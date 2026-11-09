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

begin
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
