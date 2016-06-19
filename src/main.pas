{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
program reminder;

// XXX rename "src/" to "server/"

// {$DEFINE DEBUG_ESCALATIONS}
//{$DEFINE DEBUG_TIMING}
//{$DEFINE VERBOSE}

uses
   parser, primitives, rulelogic, statestore,
   corenetwork, network, hashtable, hashfunctions, stringutils,
   dateutils, unixutils, unixtype, sysutils, exceptions;

(* Clipboard: FormatDateTime('dddd yyyy-mm-dd hh:nn:ss', Now) *)

type
   TButtonHashTable = specialize THashTable <UTF8String, TPressableRule, UTF8StringUtils>;

const
   kWebSocketPort = 12548;
   kTCPPort = 12549;
   InternalToDoEntry = ':todo';

var
   Password: UTF8String;

procedure LoadPassword();
var
   T: Text;
begin
   Assign(T, '.password');
   Reset(T);
   Readln(T, Password);
   Close(T);
end;

var
   RulesList: TRuleList;
   Buttons: TButtonHashTable;
   Server: TServer;
   StateRecalculationIsPending: Boolean;
   LastUI: UTF8String;

procedure Log(S: UTF8String);
begin
   Writeln(Output, FormatDateTime('YYYY-MM-DD hh:nn:ss', Now), ': ', S);
   Flush(Output);
end;

procedure HandleNewUIConnection(const Client: IClient);
begin
   Client.WriteFrame('update' + LastUI);
   {$IFDEF DEBUG} Log('A new UI client has connected.'); {$ENDIF}
end;

procedure HandleMessage(const S: UTF8String; const Client: IClient);
var
   GivenUsername, GivenPassword, GivenButton: UTF8String;
   Index, Count: Cardinal;
   Button: TPressableRule;
begin
   // Message format:
   //   <username>#0<password>#0<button>
   // Empty <button> means "ping" and receives a personal "pong".
   if (Length(S) > 0) then
   begin
      Count := 0;
      Assert(Low(S) = 1);
      for Index := Low(S) to Length(S) do // $R-
      begin
         if (S[Index] = #0) then
         begin
            Count := Index-1; // $R-
            Break;
         end;
      end;
      if (Count = 0) then
      begin
         Log('Received message without username, ignoring: ' + S);
         Exit;
      end;
      GivenUsername := Copy(S, 1, Count);
      Count := 0;
      for Index := Length(GivenUsername)+2 to Length(S) do // $R-
      begin
         if (S[Index] = #0) then
         begin
            Count := Index - (Length(GivenUsername) + 2); // $R-
            Break;
         end;
      end;
      if (Count = 0) then
      begin
         Log('Received message without password, ignoring: ' + S);
         Exit;
      end;
      GivenPassword := Copy(S, Length(GivenUsername)+2, Count);
      if (GivenPassword <> Password) then
      begin
         Log('Received message with invalid password, ignoring: ' + S);
         Exit;
      end;
      GivenButton := Copy(S, Length(GivenUsername)+Length(GivenPassword)+3, Length(S) - (Length(GivenUsername)+Length(GivenPassword)+2));
      if (GivenButton = '') then
      begin
         Client.Pong();
      end
      else
      begin
         Button := Buttons[GivenButton];
         if (not Assigned(Button)) then
         begin
            Log('Received message with unknown button "' + GivenButton + '" from user ' + GivenUsername + ', ignoring.');
            Exit;
         end;
         if (not Button.Visible) then
         begin
            Log('Received message with invisible button "' + GivenButton + '" from user ' + GivenUsername + ', ignoring.');
            Exit;
         end;
         Log('User ' + GivenUsername + ' pressed button: ' + Button.Name);
         Button.Press(Now());
         StateRecalculationIsPending := True;
      end;
   end;
end;

type
   PToDoListEntry = ^TToDoListEntry;
   TToDoListEntry = record
      Value: TToDo;
      Previous, Next: PToDoListEntry;
   end;

var
   Index, Subindex, ButtonCount: Cardinal;
   Count: THashTableSizeInt;
   Store: TStateStore;
   LastSelectedEntryStoreValue: TStateData;
   CandidateToDo: TPressableRule;
   ToDoList, PreviousEntry, NextEntry, NewEntry, SelectedEntry: PToDoListEntry;
   S: UTF8String;
   CurrentTime, NextTime, SelectedTime, TargetTime: TDateTime;
   Timeout: cint;
   CandidateTimeout: Int64;
   Button: TButton;
   ClassLabel: UTF8String;
begin
   Randomize();
   try
      HookSignalHandlers();
      LoadPassword();
      try
         RulesList := GetRulesFromDisk();
         Assert(High(RulesList) >= Low(RulesList));
      except
         on E: ESyntaxError do
         begin
            Log(E.Message);
            raise ECaughtException.Create();
         end;
      end;
      Store := TStateStore.Create('state.dat');
      Store.Restore(); // might throw
      try
         ToDoList := nil;
         for Index := High(RulesList) downto Low(RulesList) do // $R-
         begin
            // first, make sure we've read in the state
            RulesList[Index].ReadState(Store);
            // next, build the todo list
            // we do this backwards so that we add the most recent unchanged to the head of the list
            // ones that are already done just get thrown out, we don't care about those
            // (in fact we could drop them from the RulesList entirely, really)
            // XXX actually because we drop these, restarting Remy after the selected ToDo has been done will
            // XXX cause it to select a new one prematurely - see XXX-SELECT below
            if ((RulesList[Index] is TToDo) and (not (RulesList[Index] as TToDo).Done)) then
            begin
               New(NewEntry);
               NewEntry^.Value := (RulesList[Index] as TToDo);
               // put in the list in the right position based on LastChange order
               // since we've just got a linked list, we're going to walk the list. Not very efficient, but only has to happen at load.
               PreviousEntry := nil;
               NextEntry := ToDoList;
               while (Assigned(NextEntry) and (NextEntry^.Value.LastChange < NewEntry^.Value.LastChange)) do
               begin
                  PreviousEntry := NextEntry;
                  NextEntry := NextEntry^.Next;
               end;
               NewEntry^.Next := NextEntry;
               if (Assigned(NextEntry)) then
                  NextEntry^.Previous := NewEntry;
               NewEntry^.Previous := PreviousEntry;
               if (Assigned(PreviousEntry)) then
                  PreviousEntry^.Next := NewEntry
               else
                  ToDoList := NewEntry;
            end;
         end;
{$IFDEF VERBOSE}
         Writeln('TODOs:');
         NextEntry := ToDoList;
         while (Assigned(NextEntry)) do
         begin
            Write(' ');
            if (NextEntry^.Value.Visible) then
               Write('VIS ')
            else
               Write('    ');
            if (NextEntry^.Value.Selectable) then
               Write('SEL ')
            else
               Write('    ');
            Writeln(FormatDateTime('YYYY-MM-DD hh:nn:ss', NextEntry^.Value.LastChange), ': ', NextEntry^.Value.Name);
            NextEntry := NextEntry^.Next;
         end;
{$ENDIF}
         Count := 0;
         for Index := Low(RulesList) to High(RulesList) do // $R-
            if (RulesList[Index] is TPressableRule) then
               Inc(Count);
         Buttons := TButtonHashTable.Create(@UTF8StringHash32, Count);
         for Index := Low(RulesList) to High(RulesList) do // $R-
            if (RulesList[Index] is TPressableRule) then
               Buttons[RulesList[Index].Name] := (RulesList[Index] as TPressableRule);
         SelectedEntry := nil;
         SelectedTime := 0.0;
         if (Store.Has(InternalToDoEntry)) then
         begin
            LastSelectedEntryStoreValue := Store[InternalToDoEntry];
            if (Buttons.Has(LastSelectedEntryStoreValue.Value)) then
            begin
               CandidateToDo := Buttons[LastSelectedEntryStoreValue.Value];
               if (Assigned(CandidateToDo) and (CandidateToDo is TToDo)) then
               begin
                  SelectedEntry := ToDoList;
                  while (Assigned(SelectedEntry) and (SelectedEntry^.Value <> CandidateToDo)) do
                     SelectedEntry := SelectedEntry^.Next;
                  // XXX-SELECT if we fix the problem where a done todo gets thrown out prematurely,
                  // XXX then we should change this if() to an Assert(). See XXX-SELECT above
                  if (Assigned(SelectedEntry)) then
                     SelectedTime := LastSelectedEntryStoreValue.LastChange;
               end;
            end;
         end;
         if (Assigned(SelectedEntry)) then
            Log('Selected todo at startup: ' + SelectedEntry^.Value.Name)
         else
            Log('No selected todo at startup.');
         Log('Starting network server...');
         Server := TServer.Create(kWebSocketPort, kTCPPort, @HandleMessage, @HandleNewUIConnection);
         try
            Log('Running...');
            LastUI := '';
            repeat
               CurrentTime := Now();
               {$IFDEF DEBUG_ESCALATIONS} Writeln(FormatDateTime('YYYY-MM-DD hh:nn:ss', CurrentTime), ': Evaluating rules...'); {$ENDIF}
               Assert(High(RulesList) > 0);
               for Index := Low(RulesList) to High(RulesList) do // $R-
                  RulesList[Index].Update(CurrentTime);
               if (Assigned(SelectedEntry)) then
               begin
                  if (SelectedEntry^.Value.SelectionDuration.AddedTo(SelectedTime) <= CurrentTime) then
                  begin
                     SelectedEntry^.Value.Escalate(CurrentTime);
                     NextEntry := SelectedEntry^.Next;
                     if (Assigned(NextEntry)) then
                     begin
                        // splice this entry out from where it is now...
                        PreviousEntry := SelectedEntry^.Previous;
                        if (Assigned(PreviousEntry)) then
                           PreviousEntry^.Next := NextEntry
                        else
                           ToDoList := NextEntry;
                        if (Assigned(NextEntry)) then
                           NextEntry^.Previous := PreviousEntry;
                        // ...and move it to end of the linked list of those things
                        while (Assigned(NextEntry^.Next)) do
                           NextEntry := NextEntry^.Next;
                        NextEntry^.Next := SelectedEntry;
                        SelectedEntry^.Previous := NextEntry;
                        SelectedEntry^.Next := nil;
                     end; // else, already at end of list
                     SelectedEntry := nil;
                  end;
               end;
               if (not Assigned(SelectedEntry)) then
               begin
                  // need another entry to select!
                  SelectedEntry := ToDoList;
                  while (Assigned(SelectedEntry) and ((not SelectedEntry^.Value.Selectable) or (Random >= 0.5))) do
                  begin
{$IFDEF VERBOSE}     Writeln('skipping ', SelectedEntry^.Value.Name, '; Selectable=', SelectedEntry^.Value.Selectable); {$ENDIF}
                     SelectedEntry := SelectedEntry^.Next;
                  end;
                  if (not Assigned(SelectedEntry)) then
                  begin
                     // pick first available one as a last resort
{$IFDEF VERBOSE}     Writeln('bummo, didn''t find one. trying again'); {$ENDIF}
                     SelectedEntry := ToDoList;
                     while (Assigned(SelectedEntry) and (not SelectedEntry^.Value.Selectable)) do
                     begin
{$IFDEF VERBOSE}        Writeln('skipping ', SelectedEntry^.Value.Name, '; Selectable=', SelectedEntry^.Value.Selectable); {$ENDIF}
                        SelectedEntry := SelectedEntry^.Next;
                     end;
                  end;
                  if (Assigned(SelectedEntry)) then
                  begin
                     SelectedTime := CurrentTime;
                     Log('New selected todo: ' + SelectedEntry^.Value.Name);
                  end
                  else
                  begin
                     Log('No selected todo.');
                  end;
               end;
               if (Assigned(SelectedEntry)) then
               begin
                  CandidateTimeout := MillisecondsBetween(CurrentTime, SelectedEntry^.Value.SelectionDuration.AddedTo(SelectedTime));
                  if (CandidateTimeout > High(Timeout)) then
                     Timeout := High(Timeout)
                  else
                     Timeout := CandidateTimeout; // $R-
               end
               else
                  Timeout := timeoutForever;
               for Index := Low(RulesList) to High(RulesList) do // $R-
               begin
                  NextTime := RulesList[Index].GetNextEvent();
                  if (NextTime <> kNever) then
                  begin
                     CandidateTimeout := MillisecondsBetween(CurrentTime, NextTime);
                     {$IFDEF DEBUG_TIMING} Writeln(FormatDateTime('YYYY-MM-DD hh:nn:ss', CurrentTime), ':    Rule ', RulesList[Index].Name, ' has next event at: ', FormatDateTime('YYYY-MM-DD hh:nn:ss', NextTime), ' (', CandidateTimeout, 'ms)'); {$ENDIF}
                     {$IFDEF DEBUG_ESCALATIONS} if (RulesList[Index].Name = 'alarm') then Writeln(FormatDateTime('YYYY-MM-DD hh:nn:ss', CurrentTime), ': Rule ', RulesList[Index].Name, ' has next event at: ', FormatDateTime('YYYY-MM-DD hh:nn:ss', NextTime), ' (', CandidateTimeout, 'ms)'); {$ENDIF}
                     if ((Timeout = timeoutForever) or (CandidateTimeout < Timeout)) then
                     begin
                        {$IFDEF DEBUG_TIMING} Writeln(FormatDateTime('YYYY-MM-DD hh:nn:ss', CurrentTime), ':    + better than existing timeout!'); {$ENDIF}
                        Assert(CandidateTimeout >= 0);
                        if (CandidateTimeout > High(Timeout)) then
                        begin
                           {$IFDEF DEBUG_TIMING} Writeln(FormatDateTime('YYYY-MM-DD hh:nn:ss', CurrentTime), ':    + (clamped)'); {$ENDIF}
                           Assert(Timeout = timeoutForever);
                           Timeout := High(Timeout);
                        end
                        else
                           Timeout := CandidateTimeout; // $R-
                     end;
                  end
                  else
                  begin
                     //{$IFDEF DEBUG_TIMING} Writeln(FormatDateTime('YYYY-MM-DD hh:nn:ss', CurrentTime), ':    Rule ', RulesList[Index].Name, ' has no scheduled next event'); {$ENDIF}
                     {$IFDEF DEBUG_ESCALATIONS} if (RulesList[Index].Name = 'alarm') then Writeln(FormatDateTime('YYYY-MM-DD hh:nn:ss', CurrentTime), ': Rule ', RulesList[Index].Name, ' has no scheduled next event'); {$ENDIF}
                  end;
               end;
               {$IFDEF DEBUG_TIMING} Writeln(FormatDateTime('YYYY-MM-DD hh:nn:ss', CurrentTime), ':    Conclusion: timeout should be: ', IntToStr(Timeout), 'ms'); {$ENDIF}
               S := '';
               Assert(High(RulesList) > 0);
               for Index := Low(RulesList) to High(RulesList) do // $R-
               begin
                  if (RulesList[Index] is TButton) then
                  begin
                     if ((RulesList[Index] as TButton).Visible) then
                     begin
                        S := S + #0#0 + 'button' + #0 +
                                 (RulesList[Index] as TButton).Name + #0;
                        if ((RulesList[Index] as TButton).Highlighted) then
                           S := S + 'highlighted' + #0
                        else
                           S := S + 'normal' + #0;
                        S := S + (RulesList[Index] as TButton).ButtonLabel;
                     end;
                  end
                  else
                  if (RulesList[Index] is TBehaviour) then
                  begin
                     {$IFDEF VERBOSE}
                     if ((RulesList[Index] as TBehaviour).Active) then
                     begin
                        if ((RulesList[Index] as TBehaviour).GetNextEvent() <> timeoutForever) then
                        begin
                           Log('Behaviour ' + RulesList[Index].Name + ' active at escalation level ' + IntToStr((RulesList[Index] as TBehaviour).EscalationLevel) + ' (last reported ' + IntToStr((RulesList[Index] as TBehaviour).LastEscalatedLevel) + '); next change: ' + FormatDateTime('YYYY-MM-DD hh:nn:ss', (RulesList[Index] as TBehaviour).GetNextEvent()));
                        end
                        else
                        begin
                           Log('Behaviour ' + RulesList[Index].Name + ' active at escalation level ' + IntToStr((RulesList[Index] as TBehaviour).EscalationLevel) + ' (last reported ' + IntToStr((RulesList[Index] as TBehaviour).LastEscalatedLevel) + '); no change scheduled');
                        end;
                     end
                     else
                     begin
                        if ((RulesList[Index] as TBehaviour).GetNextEvent() <> timeoutForever) then
                        begin
                           Log('Behaviour ' + RulesList[Index].Name + ' inactive; next change: ' + FormatDateTime('YYYY-MM-DD hh:nn:ss', (RulesList[Index] as TBehaviour).GetNextEvent()));
                        end
                        else
                        begin
                           Log('Behaviour ' + RulesList[Index].Name + ' inactive; no change scheduled');
                        end;
                     end;
                     {$ENDIF}
                     if ((RulesList[Index] as TBehaviour).Active) then
                     begin 
                        if ((RulesList[Index] as TBehaviour).Message <> '') then
                        begin
                           ClassLabel := (RulesList[Index] as TBehaviour).ClassLabel;
                           if (ClassLabel = '') then
                              ClassLabel := 'normal';
                           Assert(ClassLabel <> '');
                           S := S + #0#0 + 'message' + #0 +
                                (RulesList[Index] as TBehaviour).Message + #0 +
                                ClassLabel + #0 +
                                IntToStr((RulesList[Index] as TBehaviour).EscalationLevel);
                           ButtonCount := (RulesList[Index] as TBehaviour).ButtonCount;
                           if (ButtonCount > 0) then
                              for Subindex := 0 to ButtonCount-1 do // $R-
                              begin
                                 Button := (RulesList[Index] as TBehaviour).Buttons[Subindex];
                                 if (Button.Visible) then
                                    S := S + #0 + Button.Name;
                              end;
                           Assert((RulesList[Index] as TBehaviour).LastEscalatedLevel < High(Subindex));
                           if ((RulesList[Index] as TBehaviour).LastEscalatedLevel < (RulesList[Index] as TBehaviour).EscalationLevel) then
                           begin
                              Subindex := (RulesList[Index] as TBehaviour).EscalationLevel;
                              Server.BroadcastNotification(IntToStr(Subindex) + #0 + (RulesList[Index] as TBehaviour).Message + #0 + ClassLabel);
                              if ((RulesList[Index] as TBehaviour).LastEscalatedLevel > 0) then
                                 Log('Escalating ' + RulesList[Index].Name + ' to level ' + IntToStr(Subindex))
                              else
                                 Log('Activating ' + RulesList[Index].Name + ' (escalation level ' + IntToStr(Subindex) + ')');
                           end;
                        end;
                        (RulesList[Index] as TBehaviour).MarkEscalated();
                     end;
                  end
                  else
                  if (RulesList[Index] is TToDo) then
                  begin
                     if ((RulesList[Index] as TToDo).Visible) then
                     begin 
                        ClassLabel := (RulesList[Index] as TToDo).ClassLabel;
                        if (ClassLabel = '') then
                           ClassLabel := 'normal';
                        if (Assigned(SelectedEntry) and (SelectedEntry^.Value = RulesList[Index])) then
                           ClassLabel := ClassLabel + ' selected';
                        Assert(ClassLabel <> '');
                        S := S + #0#0 + 'todo' + #0 +
                           (RulesList[Index] as TToDo).Name + #0 +
                           (RulesList[Index] as TToDo).ToDoLabel + #0 +
                           ClassLabel + #0 +
                           IntToStr((RulesList[Index] as TToDo).EscalationLevel);
                     end;
                  end
                  {$IFDEF VERBOSE}
                  else
                  if (RulesList[Index] is TState) then
                  begin
                     Log('State ' + RulesList[Index].Name + ' = ' + (RulesList[Index] as TState).CurrentValue.Name);
                  end;
                  {$ENDIF}
               end;
               if (S <> LastUI) then
               begin
                  {$IFDEF DEBUG} Log('Broadcasting UI update...'); {$ENDIF}
                  Server.BroadcastUI('update' + S);
                  LastUI := S;
               end;
               Store.Empty();
               for Index := Low(RulesList) to High(RulesList) do // $R-
                  RulesList[Index].SaveState(Store);
               if (Assigned(SelectedEntry)) then
               begin
                  LastSelectedEntryStoreValue.Value := SelectedEntry^.Value.Name;
                  LastSelectedEntryStoreValue.LastChange := SelectedTime;
                  Store[InternalToDoEntry] := LastSelectedEntryStoreValue;
               end;
               Store.Save();
               {$IFDEF DEBUG_TIMING} Writeln(FormatDateTime('YYYY-MM-DD hh:nn:ss', CurrentTime), ': next scheduled event at ', FormatDateTime('YYYY-MM-DD hh:nn:ss', IncMillisecond(CurrentTime, Timeout)), ' (', Timeout, 'ms)'); {$ENDIF}
               StateRecalculationIsPending := False;
               TargetTime := IncMillisecond(CurrentTime, Timeout); // XXX we really should just keep the NextTime up to here instead of converting to a timeout then back again
               repeat
                  {$IFDEF DEBUG_TIMING} Writeln(FormatDateTime('YYYY-MM-DD hh:nn:ss', Now), ': next scheduled event at ', FormatDateTime('YYYY-MM-DD hh:nn:ss', IncMillisecond(TargetTime)), ' (', Timeout, 'ms)'); {$ENDIF}
                  Server.Select(Timeout);
                  Timeout := MillisecondsBetween(Now, TargetTime); // $R-
               until StateRecalculationIsPending or (Now >= TargetTime);
            until Aborted;
            Store.Save();
         finally
            Buttons.Free();
            Server.Free();
         end;
      finally
         if (Length(RulesList) > 0) then
            for Index := High(RulesList) downto Low(RulesList) do
               RulesList[Index].Free();
         while (Assigned(ToDoList)) do
         begin
            NextEntry := ToDoList^.Next;
            Dispose(ToDoList);
            ToDoList := NextEntry;
         end;
         Store.Free();
      end;
      Log('Aborted.');
   except
      on E: ECaughtException do ;
   end;
end.
