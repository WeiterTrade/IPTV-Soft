{ На Linux libVLC рисует видео из своих потоков, поэтому Xlib нужно
  перевести в многопоточный режим ДО инициализации интерфейса.
  Модуль должен стоять в uses программы раньше модуля Interfaces. }
unit xthreadsinit;

{$mode objfpc}{$H+}

interface

implementation

{$IFDEF LINUX}
function XInitThreads: LongInt; cdecl; external 'X11';

initialization
  XInitThreads;
{$ENDIF}
end.
