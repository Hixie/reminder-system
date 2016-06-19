{$MODE OBJFPC} (*-*- delphi -*-*)
{$MODESWITCH ADVANCEDRECORDS}
program Test;

type
   TRec = record
      class procedure Tester(); static;
   end;

class procedure TRec.Tester();
begin
end;

begin
   TRec.Tester();
end.

// fpc test.pas -dDEBUG -Ci -Co -CO -Cr -CR -Ct -O- -gt -gl -gh -Sa -veiwnhb -FE../bin/ -Fulib -Filib && ../bin/test && rm -f test test.o; exit;