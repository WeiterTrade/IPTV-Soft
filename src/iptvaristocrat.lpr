program iptvaristocrat;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  xthreadsinit,   { должен идти раньше Interfaces }
  Interfaces,
  Forms,
  mainform;

{$R *.res}

begin
  RequireDerivedFormResource := False;
  Application.Title := 'IPTV Aristocrat';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
