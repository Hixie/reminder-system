{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit tokeniser;

interface

//{$DEFINE VERBOSE}

type
   TTokenKind = (tkNone, tkIdentifier, tkOpenBrace, tkCloseBrace, tkOpenParen, tkCloseParen, tkString, tkNumber, tkSemicolon, tkColon, tkHyphen, tkEnd, tkError);
   TReminderRulesTokeniser = class
    strict private
     type
      TToken = record
         case Kind: TTokenKind of
            tkNone: ();
            tkIdentifier: (Identifier: ShortString);
            tkOpenBrace, tkCloseBrace, tkOpenParen, tkCloseParen: ();
            tkString: (StringValue: ShortString);
            tkNumber: (NumberValue: Cardinal);
            tkSemicolon, tkColon, tkHyphen: ();
            tkEnd: ();
            tkError: ();
      end;
      TTokenKinds = set of TTokenKind;
     var
      FData: Pointer;
      FFileName: AnsiString;
      FIndex, FLength: Cardinal;
      FToken: TToken;
      function GetToken(): TToken;
      procedure ConsumeToken();
      function DescribeToken(const TokenKind: TTokenKind): AnsiString;
    public
      procedure ReadFrom(const Filename: AnsiString);
      destructor Destroy(); override;
      function GetLocation(): AnsiString;
      procedure ExpectToken(const WantedKinds: TTokenKinds);
      function GetNextTokenKind(): TTokenKind;
      procedure ConsumePunctuation(const WantedKind: TTokenKind);
      function MaybeConsumePunctuation(const WantedKind: TTokenKind): Boolean;
      procedure ConsumeKeyword(const WantedString: ShortString);
      function MaybeConsumeKeyword(const WantedString: ShortString): Boolean;
      function ConsumeIdentifier(): ShortString;
      function ConsumeString(): ShortString;
      function ConsumeNumber(const Min: Cardinal = 0; const Max: Cardinal = High(Integer)): Cardinal;
      procedure RaiseError(Message: AnsiString);
   end;

implementation

uses
   sysutils, exceptions;

type
   PCharacter = ^Char;

function TReminderRulesTokeniser.DescribeToken(const TokenKind: TTokenKind): AnsiString;
begin
   case (TokenKind) of
       tkIdentifier: Result := 'identifier';
       tkOpenBrace: Result := '"{"';
       tkCloseBrace: Result := '"}"';
       tkOpenParen: Result := '"("';
       tkCloseParen: Result := '")"';
       tkString: Result := 'string';
       tkNumber: Result := 'number';
       tkSemicolon: Result := '";"';
       tkColon: Result := '":"';
       tkHyphen: Result := '"-"';
       tkEnd: Result := 'end of file';
      else
         Result := 'unknown token';
   end;
end;

procedure TReminderRulesTokeniser.ReadFrom(const FileName: AnsiString);
var
   InputFile: File;
   Size: Int64;
begin
   if (Assigned(FData)) then
      FreeMem(FData);
   FIndex := 0;
   Assign(InputFile, FileName);
   Reset(InputFile, 1);
   Size := FileSize(InputFile);
   if (Size > 4 * 1024 * 1024) then
      raise ESyntaxError.Create('File is larger than arbitrary sanity limit');
   Assert(Size < High(FLength));
   FLength := Size; {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
   FData := GetMem(FLength);
   BlockRead(InputFile, FData^, FLength);
   Close(InputFile);
   FFileName := FileName;
end;

destructor TReminderRulesTokeniser.Destroy();
begin
   if (Assigned(FData)) then
      FreeMem(FData);
   inherited;
end;

function TReminderRulesTokeniser.GetLocation(): AnsiString;
var
   Line, Col, Spaces, Index: Cardinal;
   C: Char;
begin
   Line := 1;
   Col := 1;
   Spaces := 0;
   for Index := 0 to FIndex do
   begin
      C := PCharacter(FData + Index)^;
      if (C = #$0A) then
      begin
         if (Index < FIndex) then
         begin
            Inc(Line);
            Col := 1;
         end;
      end
      else
      if (C = #$20) then
      begin
         Inc(Spaces);
      end
      else
      begin
         Inc(Col, Spaces+1);
         Spaces := 0;
      end;
   end;
   Result := FFileName + ':' + IntToStr(Line) + ':' + IntToStr(Col);
end;

function TReminderRulesTokeniser.GetToken(): TToken;

   function GetSubString(const Index, Start, CurrentLength: Cardinal): ShortString;
   begin
      if (Index - Start > High(Result)-CurrentLength) then
         RaiseError('String or identifier too long');
      SetLength(Result, Index - Start);
      Move((FData + Start)^, Result[1], Index - Start);
   end;

type
   TState = (tsBetween, tsIdentifier, tsString, tsNumber, tsSlash, tsComment);
var
   C: Char;
   Buffer: ShortString;
   Start: Cardinal;
   State: TState;
begin
   if (FToken.Kind <> tkNone) then
   begin
      Result := FToken;
      Exit;
   end;
   Result.Kind := tkNone;
   State := tsBetween;
   repeat
      if (FIndex >= FLength) then
      begin // EOF
         case (State) of
            tsIdentifier:
               begin
                  Result.Kind := tkIdentifier;
                  Result.Identifier := GetSubString(FIndex, Start, 0); {BOGUS Warning: Local variable "Start" does not seem to be initialized}
               end;
            tsNumber:
               begin
                  Result.Kind := tkNumber;
                  Result.NumberValue := StrToInt(GetSubString(FIndex, Start, 0)); {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
               end;
            tsString, tsSlash: Result.Kind := tkError;
            else
               Assert(State in [tsBetween, tsComment]);
               Result.Kind := tkEnd;
         end;
      end
      else
      begin
         C := PCharacter(FData + FIndex)^;
         {$IFDEF VERBOSE} Writeln('Reading: ', C, ' in state ', State); {$ENDIF}
         case (State) of
            tsIdentifier:
               begin
                  case (C) of
                     'a'..'z', 'A'..'Z', '0'..'9', '_', '-': ;
                     else
                        Result.Kind := tkIdentifier;
                        Result.Identifier := GetSubString(FIndex, Start, 0);
                        Dec(FIndex);
                     end;
               end;
            tsString:
               begin
                  case (C) of
                     #$0A: Result.Kind := tkError;
                     '\':
                        begin
                           Buffer := Buffer + GetSubString(FIndex, Start, Length(Buffer)); {BOGUS Warning: Local variable "Buffer" does not seem to be initialized}
                           Inc(FIndex);
                           Start := FIndex;
                        end;
                     '''':
                        begin
                           Result.Kind := tkString;
                           Result.StringValue := Buffer + GetSubString(FIndex, Start, Length(Buffer));
                        end;
                  end;
               end;
            tsNumber:
               begin
                  case (C) of
                     '0'..'9': ;
                     'a'..'z', 'A'..'Z', '_', '''': Result.Kind := tkError;
                     else
                        Result.Kind := tkNumber;
                        try
                           Result.NumberValue := StrToInt(GetSubString(FIndex, Start, 0)); {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
                        except
                           on EConvertError do
                              Result.Kind := tkError;
                        end;
                        Dec(FIndex);
                  end;
               end;
            tsSlash:
               begin
                  case (C) of
                     '/': State := tsComment;
                     else
                        Result.Kind := tkError;
                  end;
               end;
            tsComment:
               begin
                  case (C) of
                     #$0A: State := tsBetween;
                  end;
               end;
            else
               Assert(State = tsBetween);
               case (C) of
                  'a'..'z', 'A'..'Z', '_':
                     begin
                        Start := FIndex;
                        State := tsIdentifier;
                     end;
                  '''':
                     begin
                        Inc(FIndex);
                        Start := FIndex;
                        Buffer := '';
                        State := tsString;
                     end;
                  '0'..'9':
                     begin
                        Start := FIndex;
                        State := tsNumber;
                     end;
                  '{': Result.Kind := tkOpenBrace;
                  '}': Result.Kind := tkCloseBrace;
                  '(': Result.Kind := tkOpenParen;
                  ')': Result.Kind := tkCloseParen;
                  ';': Result.Kind := tkSemicolon;
                  ':': Result.Kind := tkColon;
                  '-': Result.Kind := tkHyphen;
                  '/': State := tsSlash;
                  ' ', #$0A, #$09: ;
                  else
                     Result.Kind := tkError;
               end;
         end;
      end;
      Inc(FIndex);
   until Result.Kind <> tkNone;
   FToken := Result;
   {$IFDEF VERBOSE} Writeln('Token => ', FToken.Kind); {$ENDIF}
end;

procedure TReminderRulesTokeniser.ConsumeToken();
begin
   Assert(FToken.Kind <> tkNone);
   FToken.Kind := tkNone;
end;

procedure TReminderRulesTokeniser.ExpectToken(const WantedKinds: TTokenKinds);
var
   Token: TToken;
   S: AnsiString;
   Kind: TTokenKind;
begin
   Token := GetToken();
   if (not (Token.Kind in WantedKinds)) then
   begin
      S := '';
      for Kind in WantedKinds do
      begin
         if (S <> '') then
            S := S + ' or ';
         S := S + DescribeToken(Kind);
      end;
      RaiseError('Expected ' + S + ' but found ' + DescribeToken(Token.Kind));
   end;
end;

function TReminderRulesTokeniser.GetNextTokenKind(): TTokenKind;
begin
   Result := GetToken().Kind;
end;

procedure TReminderRulesTokeniser.ConsumePunctuation(const WantedKind: TTokenKind);
begin
   ExpectToken([WantedKind]);
   ConsumeToken();
end;

function TReminderRulesTokeniser.MaybeConsumePunctuation(const WantedKind: TTokenKind): Boolean;
var
   Token: TToken;
begin
   Token := GetToken();
   Result := (Token.Kind = WantedKind);
   if (Result) then
      ConsumeToken();
end;

procedure TReminderRulesTokeniser.ConsumeKeyword(const WantedString: ShortString);
var
   Token: TToken;
begin
   ExpectToken([tkIdentifier]);
   Token := GetToken();
   Assert(Token.Kind = tkIdentifier);
   if (Token.Identifier <> WantedString) then
      RaiseError('Expected keyword "' + WantedString + '"');
   ConsumeToken();
end;

function TReminderRulesTokeniser.MaybeConsumeKeyword(const WantedString: ShortString): Boolean;
var
   Token: TToken;
begin
   Token := GetToken();
   Result := (Token.Kind = tkIdentifier) and (Token.Identifier = WantedString);
   if (Result) then
      ConsumeToken();
end;

function TReminderRulesTokeniser.ConsumeIdentifier(): ShortString;
var
   Token: TToken;
begin
   ExpectToken([tkIdentifier]);
   Token := GetToken();
   Assert(Token.Kind = tkIdentifier);
   Result := Token.Identifier;
   ConsumeToken();
end;

function TReminderRulesTokeniser.ConsumeString(): ShortString;
var
   Token: TToken;
begin
   ExpectToken([tkString]);
   Token := GetToken();
   Assert(Token.Kind = tkString);
   Result := Token.StringValue;
   ConsumeToken();
end;

function TReminderRulesTokeniser.ConsumeNumber(const Min: Cardinal = 0; const Max: Cardinal = High(Integer)): Cardinal;
var
   Token: TToken;
begin
   ExpectToken([tkNumber]);
   Token := GetToken();
   Assert(Token.Kind = tkNumber);
   if ((Token.NumberValue < Min) or (Token.NumberValue > Max)) then
      RaiseError('Number out of range');
   Result := Token.NumberValue;
   ConsumeToken();
end;

procedure TReminderRulesTokeniser.RaiseError(Message: AnsiString);
begin
   {$IFDEF DEBUG}
     Writeln(GetLocation() + ': ' + Message);
     Writeln(GetStackTrace());
   {$ENDIF}
   raise ESyntaxError.Create(GetLocation() + ': ' + Message);
end;

end.
