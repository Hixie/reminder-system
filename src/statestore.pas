{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit statestore;

interface

uses
   hashtable, stringutils, sysutils;

type
   TStateData = record
      Value: UTF8String;
      LastChange: TDateTime;
   end;

   // Names and Values must not have newlines, spaces, punctuation like "=", "@"
   TStateStore = class(specialize THashTable <UTF8String, TStateData, UTF8StringUtils>)
    strict private
     FFileName: UTF8String;
    public
     constructor Create(const NewFileName: UTF8String);
     procedure Save();
     procedure Restore();
   end;

implementation

uses
   exceptions, primitives, hashfunctions;

var
   SaveFormat: TFormatSettings;

constructor TStateStore.Create(const NewFileName: UTF8String);
begin
   inherited Create(@UTF8StringHash32, 8);
   FFileName := NewFileName;
end;

procedure TStateStore.Save();
var
   Name, BackupFilename: UTF8String;
   F, OldF: Text;
   Data: TStateData;
begin
   Assign(F, FFileName + '.$$$');
   Rewrite(F);
   for Name in Self do
   begin
      Data := Self[Name];
      Assert(Pos('=', Name) = 0);
      Assert(Pos('@', Name) = 0);
      Assert(Pos(#$0A, Name) = 0);
      Assert(Pos('@', Data.Value) = 0);
      Assert(Pos(#$0A, Data.Value) = 0);
      if (Data.LastChange = kNever) then
         Writeln(F, Name, '=', Data.Value, '@never')
      else
         Writeln(F, Name, '=', Data.Value, '@', DateTimeToStr(Data.LastChange, SaveFormat));
   end;
   Writeln(F, 'END'); // so we can tell if the file got truncated
   Close(F);
   if (FileExists(FFileName)) then
   begin
      BackupFilename := FFileName + '.' + FormatDateTime('YYYY-MM-DD-HH', Now);
      if (FileExists(BackupFilename)) then
      begin
         Assign(OldF, BackupFilename);
         Erase(OldF);
      end;
      Assign(OldF, FFilename);
      Rename(OldF, BackupFileName);
   end;
   Rename(F, FFileName);
end;

procedure TStateStore.Restore();
var
   S, DateTimeS: UTF8String;
   F: Text;
   I, J: SizeInt;
   Name: UTF8String;
   Data: TStateData;
begin
   Empty();
   if (FileExists(FFileName)) then
   begin
      Assign(F, FFileName);
      Reset(F);
      while not EOF(F) do
      begin
         Readln(F, S);
         I := Pos('=', S);
         if (I = 0) then
         begin
            if (S = 'END') then
            begin
               break;
            end;
            raise Exception.Create('Failed to parse state store; syntax error (missing "=").');
         end;
         Name := Copy(S, 1, I-1);
         J := Pos('@', S);
         if (J = 0) then
         begin
            raise Exception.Create('Failed to parse state store; syntax error (missing "@").');
         end;
         Data.Value := Copy(S, I+1, J-(I+1));
         DateTimeS := Copy(S, J+1, Length(S)-J);
         if (DateTimeS = 'never') then
         begin
            Data.LastChange := kNever;
         end
         else
         begin
            try
               Data.LastChange := StrToDateTime(DateTimeS, SaveFormat);
            except
               on EConvertError do
               begin
                  Writeln('Failed to parse ', Name, '''s last change time: ', DateTimeS);
                  raise;
               end;
            end;
         end;
         Self[Name] := Data;
      end;
      if (S <> 'END') then
         raise Exception.Create('Failed to parse state store; syntax error (missing "END" marker).');
      Close(F);
   end;
end;

initialization
   SaveFormat := DefaultFormatSettings;
   SaveFormat.DateSeparator := '-';
   SaveFormat.ShortDateFormat := 'YYYY-MM-DD';
end.