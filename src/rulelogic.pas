{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit rulelogic;

//{$DEFINE DEBUG_STATE_TIMING}

interface

uses
   primitives, statestore;

const
   kMaxEscalations = 9;

type
   TRule = class;
   TState = class;
   TStateValue = class;
   TButton = class;
   TBehaviour = class;
   TToDo = class;

   TCondition = class
    public
      procedure Update(const CurrentTime: TDateTime); virtual;
      function GetNextEvent(): TDateTime; virtual;
      function Evaluate(): Boolean; virtual; abstract;
   end;
   TConditionClass = class of TCondition;

   TBinaryOperatorCondition = class abstract (TCondition)
    protected
      FLHS, FRHS: TCondition;
    public
      constructor Create(const LHS, RHS: TCondition);
      destructor Destroy(); override;
      procedure Update(const CurrentTime: TDateTime); override;
      function GetNextEvent(): TDateTime; override;
   end;

   TAndCondition = class(TBinaryOperatorCondition)
      function Evaluate(): Boolean; override;
   end;

   TOrCondition = class(TBinaryOperatorCondition)
      function Evaluate(): Boolean; override;
   end;

   TNotCondition = class(TCondition)
    strict private
      FCondition: TCondition;
    public
      constructor Create(const NewCondition: TCondition);
      destructor Destroy(); override;
      procedure Update(const CurrentTime: TDateTime); override;
      function GetNextEvent(): TDateTime; override;
      function Evaluate(): Boolean; override; 
   end;

   TTimeRangeCondition = class(TCondition)
    strict private
      FStart: TTime;
      FEnd: TMasterTime;
      FCurrent: Boolean;
    public
      constructor Create(const NewStart: TTime; const NewEnd: TMasterTime);
      destructor Destroy(); override;
      procedure Update(const CurrentTime: TDateTime); override;
      function GetNextEvent(): TDateTime; override;
      function Evaluate(): Boolean; override;
   end;

   TStateCondition = class(TCondition)
    strict private
      FState: TState;
      FStateValue: TStateValue;
    public
      constructor Create(const NewState: TState; const NewStateValue: TStateValue);
      // GetNextEvent() returns kNever (the state itself is what gets the event, not us)
      function Evaluate(): Boolean; override;
   end;

   TDurationBasedCondition = class abstract (TCondition)
    strict private
      FDuration: TDuration;
      FMatched: Boolean;
      FNextEvent: TDateTime;
    protected
      function GetAnchorTime(): TDateTime; virtual; abstract;
    public
      constructor Create(const NewDuration: TDuration); // event was _over_ NewDuration ago
      destructor Destroy(); override;
      procedure Update(const CurrentTime: TDateTime); override;
      function GetNextEvent(): TDateTime; override;
      function Evaluate(): Boolean; override;
   end;

   TChangeAgeCondition = class(TDurationBasedCondition)
    strict private
      FRule: TRule;
    protected
      function GetAnchorTime(): TDateTime; override;
    public
      constructor Create(const NewRule: TRule; const NewDuration: TDuration); // event was _over_ NewDuration ago
   end;

   TAgeComparisonCondition = class abstract (TCondition)
    protected
      FLHS, FRHS: TRule;
    public
      constructor Create(const NewLHS, NewRHS: TRule);
      // GetNextEvent() returns kNever (the condition won't change until one of the rules does, and the rules are top-level anyway)
   end;
   TAgeComparisonConditionClass = class of TAgeComparisonCondition;

   TAgeComparisonBeforeCondition = class (TAgeComparisonCondition)
    public
      function Evaluate(): Boolean; override;
   end;

   TAgeComparisonAfterCondition = class (TAgeComparisonCondition)
    public
      function Evaluate(): Boolean; override;
   end;

   TBehaviourCondition = class(TCondition)
    strict private
      FBehaviour: TBehaviour;
    public
      constructor Create(const NewBehaviour: TBehaviour);
      // GetNextEvent() returns kNever (the behaviour itself is what gets the event, not us)
      function Evaluate(): Boolean; override;
   end;

   TToDoAbstractCondition = class(TCondition)
    protected
      FToDo: TToDo;
    public
      constructor Create(const NewToDo: TToDo);
      // GetNextEvent() returns kNever (we don't know when it'll be done)
   end;
   TToDoConditionClass = class of TToDoAbstractCondition;

   TToDoDoneCondition = class(TToDoAbstractCondition)
    public
      function Evaluate(): Boolean; override;
   end;

   TToDoRelevantCondition = class(TToDoAbstractCondition)
    public
      function Evaluate(): Boolean; override;
   end;


   TStateValue = class
    strict private
      FName: AnsiString;
      FCondition: TCondition;
      function GetReadyToAutomaticallyActivate(): Boolean;
    public
      constructor Create(const NewName: AnsiString);
      constructor Create(const NewName: AnsiString; const NewCondition: TCondition);
      destructor Destroy(); override;
      procedure Update(const CurrentTime: TDateTime);
      function GetNextEvent(const CurrentlySet: Boolean): TDateTime;
      property Name: AnsiString read FName;
      property ReadyToAutomaticallyActivate: Boolean read GetReadyToAutomaticallyActivate;
   end;


   TRule = class
    strict private
      FName: AnsiString;
    protected
      FLastChange: TDateTime;
    public
      constructor Create(const NewName: AnsiString);
      procedure ReadState(const StateStore: TStateStore); virtual;
      procedure SaveState(const StateStore: TStateStore); virtual;
      procedure Update(const CurrentTime: TDateTime); virtual; abstract;
      function GetNextEvent(): TDateTime; virtual; abstract;
      property Name: AnsiString read FName;
      property LastChange: TDateTime read FLastChange;
   end;

   TState = class(TRule)
    strict private
      FValues: array of TStateValue;
      FCurrentValue: TStateValue;
    public
      destructor Destroy(); override;
      procedure AddValue(const Value: TStateValue);
      function GetValue(const StateName: AnsiString): TStateValue;
      procedure SetValue(const Value: TStateValue; const CurrentTime: TDateTime);
      procedure ReadState(const StateStore: TStateStore); override;
      procedure SaveState(const StateStore: TStateStore); override;
      procedure Update(const CurrentTime: TDateTime); override;
      function GetNextEvent(): TDateTime; override;
      property CurrentValue: TStateValue read FCurrentValue;
   end;

   TPressableRule = class(TRule)
    protected
      function GetVisible(): Boolean; virtual; abstract;
    public
      procedure Press(const CurrentTime: TDateTime); virtual; abstract;
      property Visible: Boolean read GetVisible;
   end;

   TButton = class(TPressableRule)
    strict private
     type
      TButtonInstructionKind = (biSet, biImply);
      TButtonInstruction = record
       case Kind: TButtonInstructionKind of
        biSet: (State: TState; Value: TStateValue);
        biImply: (Button: TButton);
      end;
      TButtonInstructionArray = array of TButtonInstruction;
     var
      FButtonLabel: AnsiString;
      FInstructions: TButtonInstructionArray;
      FVisibleCondition, FHighlightCondition: TCondition;
      FVisible, FHighlighted: Boolean;
    protected
      function GetVisible(): Boolean; override;
    public
      constructor Create(const NewName, NewButtonLabel: AnsiString; const NewVisibleCondition: TCondition = nil; const NewHighlightCondition: TCondition = nil);
      destructor Destroy(); override;
      procedure AddSet(const NewState: TState; const NewValue: TStateValue);
      procedure AddImply(const OtherButton: TButton);
      procedure Press(const CurrentTime: TDateTime); override;
      procedure ReadState(const StateStore: TStateStore); override;
      procedure Update(const CurrentTime: TDateTime); override;
      function GetNextEvent(): TDateTime; override;
      property Highlighted: Boolean read FHighlighted;
      property ButtonLabel: AnsiString read FButtonLabel;
   end;

   TBehaviour = class(TRule)
    strict private
     type
      TBehaviourInstructionKind = (biClassLabel, biPromoteButton, biEscalateImmediately, biEscalateOnSchedule, biEscalateRepeatedly);
      TBehaviourInstruction = record
       case Kind: TBehaviourInstructionKind of
        biClassLabel: (ClassLabel: ^AnsiString; Condition: TCondition);
        biPromoteButton: (Button: TButton);
        biEscalateImmediately: ();
        biEscalateOnSchedule, biEscalateRepeatedly: (Schedule: TDuration; Anchor: TRule);
      end;
      TBehaviourInstructionArray = array of TBehaviourInstruction;
     var
      FInstructions: TBehaviourInstructionArray;
      FCondition: TCondition;
      FActive: Boolean;
      FNextChangeWhenActive: TDateTime;
      FMessage, FClassLabel: AnsiString;
      FEscalationLevel, FLastEscalationLevel: Cardinal;
      function GetButtonCount(): Cardinal;
      function GetButton(ButtonNumber: Cardinal): TButton;
    public
      constructor Create(const NewName: AnsiString; const NewCondition: TCondition); overload;
      destructor Destroy(); override;
      procedure SetMessage(const NewMessage: AnsiString);
      procedure AddClassLabel(const NewClassLabel: AnsiString; const NewCondition: TCondition);
      procedure AddPromote(const OtherButton: TButton);
      procedure AddEscalateImmediately();
      procedure AddEscalationSchedule(const NewDuration: TDuration; const NewAnchor: TRule);
      procedure AddEscalationRepetition(const NewDuration: TDuration; const NewAnchor: TRule);
      procedure ReadState(const StateStore: TStateStore); override;
      procedure SaveState(const StateStore: TStateStore); override;
      procedure Update(const CurrentTime: TDateTime); override;
      function GetNextEvent(): TDateTime; override;
      property Active: Boolean read FActive;
      property EscalationLevel: Cardinal read FEscalationLevel;
      property LastEscalatedLevel: Cardinal read FLastEscalationLevel;
      procedure MarkEscalated();
      property Message: AnsiString read FMessage;
      property ClassLabel: AnsiString read FClassLabel;
      property ButtonCount: Cardinal read GetButtonCount;
      property Buttons[ButtonNumber: Cardinal]: TButton read GetButton;
   end;

   TToDo = class(TPressableRule)
    strict private
     type
      TClassEntry = record
         ClassLabel: AnsiString;
         Condition: TCondition;
      end;
     var
      FClasses: array of TClassEntry;
      FLabel, FClassLabel: AnsiString;
      FRelevancyCondition, FSelectableCondition: TCondition;
      FSelectionDuration: TDuration;
      FDone, FRelevant, FSelectable: Boolean;
      FEscalationLevel: Cardinal;
      function GetHasSelectable(): Boolean;
    protected
      function GetVisible(): Boolean; override; // exposes Relevant
    public
      constructor Create(const NewName: AnsiString; const NewLabel: AnsiString; const NewRelevancyCondition: TCondition);
      destructor Destroy(); override;
      procedure AddSelectionDuration(const NewSelectionDuration: TDuration);
      procedure AddSelectableCondition(const NewSelectableCondition: TCondition);
      procedure AddClassLabel(const NewClassLabel: AnsiString; const NewCondition: TCondition);
      procedure ReadState(const StateStore: TStateStore); override;
      procedure SaveState(const StateStore: TStateStore); override;
      procedure Update(const CurrentTime: TDateTime); override;
      function GetNextEvent(): TDateTime; override;
      procedure Escalate(const CurrentTime: TDateTime); // call whenever main unpromotes us as the main todo item (i.e. when it moves on to something else)
      procedure Press(const CurrentTime: TDateTime); override; // called when user presses our button
      property ToDoLabel: AnsiString read FLabel;
      property ClassLabel: AnsiString read FClassLabel;
      property Selectable: Boolean read FSelectable;
      property Done: Boolean read FDone;
      property HasSelectable: Boolean read GetHasSelectable;
      property SelectionDuration: TDuration read FSelectionDuration;
      property EscalationLevel: Cardinal read FEscalationLevel;
   end;

type
   TRuleList = array of TRule;

implementation

uses
   exceptions, sysutils {$IFDEF DEBUG}, dateutils, debug{$ENDIF};

procedure TCondition.Update(const CurrentTime: TDateTime);
begin
end;

function TCondition.GetNextEvent(): TDateTime;
begin
   Result := kNever;
end;


constructor TBinaryOperatorCondition.Create(const LHS, RHS: TCondition);
begin
   FLHS := LHS;
   FRHS := RHS;
end;

destructor TBinaryOperatorCondition.Destroy();
begin
   FLHS.Free();
   FRHS.Free();
   inherited;
end;

procedure TBinaryOperatorCondition.Update(const CurrentTime: TDateTime);
begin
   FLHS.Update(CurrentTime);
   FRHS.Update(CurrentTime);
end;

function TBinaryOperatorCondition.GetNextEvent(): TDateTime;
var
   LHST, RHST: TDateTime;
begin
   LHST := FLHS.GetNextEvent();
   RHST := FRHS.GetNextEvent();
   if (LHST = kNever) then
      Result := RHST
   else
   if (RHST = kNever) then
      Result := LHST
   else
   if (LHST < RHST) then
      Result := LHST
   else
      Result := RHST;
end;


function TAndCondition.Evaluate(): Boolean;
begin
   Result := FLHS.Evaluate() and FRHS.Evaluate();
end;


function TOrCondition.Evaluate(): Boolean;
begin
   Result := FLHS.Evaluate() or FRHS.Evaluate();
end;


constructor TNotCondition.Create(const NewCondition: TCondition);
begin
   FCondition := NewCondition;
end;

destructor TNotCondition.Destroy();
begin
   FCondition.Free();
   inherited;
end;

procedure TNotCondition.Update(const CurrentTime: TDateTime);
begin
   FCondition.Update(CurrentTime);
end;

function TNotCondition.GetNextEvent(): TDateTime;
begin
   Result := FCondition.GetNextEvent();
end;

function TNotCondition.Evaluate(): Boolean;
begin
   Result := not FCondition.Evaluate();
end;


constructor TTimeRangeCondition.Create(const NewStart: TTime; const NewEnd: TMasterTime);
begin
   inherited Create();
   FStart := NewStart;
   FEnd := NewEnd;
end;

destructor TTimeRangeCondition.Destroy();
begin
   FStart.Free();
   FEnd.Free();
   inherited;
end;

procedure TTimeRangeCondition.Update(const CurrentTime: TDateTime);
begin
   FEnd.Update(CurrentTime, taAfter);
   Assert(FEnd.Time > CurrentTime);
   FStart.Update(FEnd.Time, taBefore);
   FCurrent := FStart.Time <= CurrentTime;
end;

function TTimeRangeCondition.GetNextEvent(): TDateTime;
begin
   if (FCurrent) then
      Result := FEnd.Time
   else
      Result := FStart.Time;
end;

function TTimeRangeCondition.Evaluate(): Boolean;
begin
   Result := FCurrent;
end;



constructor TStateCondition.Create(const NewState: TState; const NewStateValue: TStateValue);
begin
   FState := NewState;
   FStateValue := NewStateValue;
end;

function TStateCondition.Evaluate(): Boolean;
begin
   Assert(Assigned(FState.CurrentValue));
   Assert(Assigned(FStateValue));
   Result := FState.CurrentValue = FStateValue;
end;


constructor TDurationBasedCondition.Create(const NewDuration: TDuration);
begin
   FDuration := NewDuration;
end;

destructor TDurationBasedCondition.Destroy();
begin
   FDuration.Free();
   inherited;
end;

procedure TDurationBasedCondition.Update(const CurrentTime: TDateTime);
var
   AnchorTime: TDateTime;
begin
//   {$IFDEF DEBUG_STATE_TIMING} Writeln(ClassName, '.Update()'); Writeln(GetStackTrace()); {$ENDIF}
   AnchorTime := GetAnchorTime();
   if (AnchorTime = kNever) then
   begin
      {$IFDEF DEBUG_STATE_TIMING} Writeln('  anchor time is never'); {$ENDIF}
      FMatched := True;
      FNextEvent := kNever;
   end
   else
   begin
      {$IFDEF DEBUG_STATE_TIMING} Writeln('  anchor time is ', FormatDateTime('dddd yyyy-mm-dd hh:nn:ss', AnchorTime)); {$ENDIF}
      FNextEvent := FDuration.AddedTo(AnchorTime);
      if (FNextEvent < CurrentTime) then
      begin
         {$IFDEF DEBUG_STATE_TIMING} Writeln('  + currently matching...'); {$ENDIF}
         FMatched := True;
         FNextEvent := kNever;
      end
      else
      begin
         {$IFDEF DEBUG_STATE_TIMING} Writeln('  + not matched, condition will match at ', FormatDateTime('dddd yyyy-mm-dd hh:nn:ss', FNextEvent)); {$ENDIF}
         FMatched := False;
      end;
   end;
end;

function TDurationBasedCondition.GetNextEvent(): TDateTime;
begin
   Result := FNextEvent;
  {$IFDEF DEBUG_STATE_TIMING} Writeln('      ', ClassName, '.GetNextEvent(): ', FormatDateTime('dddd yyyy-mm-dd hh:nn:ss', FNextEvent)); {$ENDIF}
end;

function TDurationBasedCondition.Evaluate(): Boolean;
begin
   Result := FMatched;
end;


constructor TChangeAgeCondition.Create(const NewRule: TRule; const NewDuration: TDuration);
begin
   inherited Create(NewDuration);
   FRule := NewRule;
end;

function TChangeAgeCondition.GetAnchorTime(): TDateTime;
begin
   Result := FRule.LastChange;
end;


constructor TAgeComparisonCondition.Create(const NewLHS, NewRHS: TRule);
begin
   FLHS := NewLHS;
   FRHS := NewRHS;
end;

function TAgeComparisonBeforeCondition.Evaluate(): Boolean;
begin
   Result := FLHS.LastChange < FRHS.LastChange;
end;

function TAgeComparisonAfterCondition.Evaluate(): Boolean;
begin
   Result := FLHS.LastChange > FRHS.LastChange;
end;


constructor TBehaviourCondition.Create(const NewBehaviour: TBehaviour);
begin
   FBehaviour := NewBehaviour;
end;

function TBehaviourCondition.Evaluate(): Boolean;
begin
   Result := FBehaviour.Active;
end;


constructor TToDoAbstractCondition.Create(const NewToDo: TToDo);
begin
   FToDo := NewToDo;
end;

function TToDoDoneCondition.Evaluate(): Boolean;
begin
   Result := FToDo.Done;
end;

function TToDoRelevantCondition.Evaluate(): Boolean;
begin
   Result := FToDo.Visible;
end;


constructor TStateValue.Create(const NewName: AnsiString);
begin
   FName := NewName;
end;

constructor TStateValue.Create(const NewName: AnsiString; const NewCondition: TCondition);
begin
   FName := NewName;
   FCondition := NewCondition;
end;

destructor TStateValue.Destroy();
begin
   if (Assigned(FCondition)) then
      FCondition.Free();
   inherited;
end;

procedure TStateValue.Update(const CurrentTime: TDateTime);
begin
   if (Assigned(FCondition)) then
   begin
      {$IFDEF DEBUG_STATE_TIMING} Writeln(ClassName, '.Update() for ', Name); {$ENDIF}
      FCondition.Update(CurrentTime);
      {$IFDEF DEBUG_STATE_TIMING} Writeln(ClassName, '.Update() for ', Name, ' done, matching=', FCondition.Evaluate()); {$ENDIF}
   end;
end;

function TStateValue.GetNextEvent(const CurrentlySet: Boolean): TDateTime;
begin
   {$IFDEF DEBUG_STATE_TIMING} Writeln('    ', Name, '''s GetNextEvent(', CurrentlySet, '):'); {$ENDIF}
   {$IFDEF DEBUG_STATE_TIMING}
   if (Assigned(FCondition)) then
      Writeln('    FCondition.Evaluate() = ', FCondition.Evaluate())
   else
      Writeln('    no condition');
   {$ENDIF}
   if (Assigned(FCondition) and (FCondition.Evaluate() = CurrentlySet)) then
   begin
      {$IFDEF DEBUG_STATE_TIMING} Writeln('    so calling ', FCondition.ClassName, '.GetNextEvent()'); {$ENDIF}
      Result := FCondition.GetNextEvent()
   end
   else
      Result := kNever;
   {$IFDEF DEBUG_STATE_TIMING} Writeln('    result = ', FormatDateTime('YYYY-MM-DD hh:nn:ss', Result)); {$ENDIF}
end;

function TStateValue.GetReadyToAutomaticallyActivate(): Boolean;
begin
   Result := Assigned(FCondition) and FCondition.Evaluate();
end;


constructor TRule.Create(const NewName: AnsiString);
begin
   FName := NewName;
end;

procedure TRule.ReadState(const StateStore: TStateStore);
begin
   FLastChange := StateStore[Name].LastChange;
end;

procedure TRule.SaveState(const StateStore: TStateStore);
var
   Scratch: TStateData;
begin
   inherited;
   Scratch := StateStore[Name];
   Scratch.LastChange := FLastChange;
   StateStore[Name] := Scratch;
end;


destructor TState.Destroy();
var
   Index: Cardinal;
begin
   if (Length(FValues) > 0) then
      for Index := Low(FValues) to High(FValues) do
         FValues[Index].Free();
   inherited;
end;

procedure TState.AddValue(const Value: TStateValue);
begin
   Assert(Assigned(Value));
   if (not Assigned(FCurrentValue)) then
   begin
      Assert(FLastChange = 0.0);
      FCurrentValue := Value;
   end;
   SetLength(FValues, Length(FValues)+1);
   FValues[High(FValues)] := Value;
end;

function TState.GetValue(const StateName: AnsiString): TStateValue;
var
   Index: Cardinal;
begin
   if (Length(FValues) > 0) then
      for Index := Low(FValues) to High(FValues) do
      begin
         if (FValues[Index].Name = StateName) then
         begin
            Result := FValues[Index];
            Exit;
         end;
      end;
   Result := nil;
end;

procedure TState.SetValue(const Value: TStateValue; const CurrentTime: TDateTime);
begin
   Assert(Assigned(Value));
   FCurrentValue := Value;
   FLastChange := CurrentTime; // even if the value didn't actually change
end;

procedure TState.ReadState(const StateStore: TStateStore);
var
   Scratch: TStateData;
begin
   inherited;
   Scratch := StateStore[Name];
   FCurrentValue := GetValue(Scratch.Value);
   if (not Assigned(FCurrentValue)) then
      FCurrentValue := FValues[0];
   Assert(Assigned(FCurrentValue));
end;

procedure TState.SaveState(const StateStore: TStateStore);
var
   Scratch: TStateData;
begin
   inherited;
   Scratch := StateStore[Name];
   Scratch.Value := FCurrentValue.Name;
   StateStore[Name] := Scratch;
end;

procedure TState.Update(const CurrentTime: TDateTime);
var
   Index: Cardinal;
begin
   if (Length(FValues) > 0) then
      for Index := Low(FValues) to High(FValues) do
      begin
         FValues[Index].Update(CurrentTime);
         if ((FCurrentValue <> FValues[Index]) and (FValues[Index].ReadyToAutomaticallyActivate)) then
         begin
            FCurrentValue := FValues[Index];
            FLastChange := CurrentTime;
         end;
      end;
end;

function TState.GetNextEvent(): TDateTime;
var
   Candidate: TDateTime;
   Index: Cardinal;
   IsCurrentState: Boolean;
begin
   Result := kNever;
   {$IFDEF DEBUG_STATE_TIMING} Writeln('State ', Name); {$ENDIF}
   if (Length(FValues) > 0) then
      for Index := Low(FValues) to High(FValues) do
      begin
         IsCurrentState := FValues[Index] = FCurrentValue;
         if ((not IsCurrentState) or (FValues[Index].ReadyToAutomaticallyActivate)) then
         begin
            {$IFDEF DEBUG_STATE_TIMING} Writeln('  Value ', FValues[Index].Name); {$ENDIF}
            Candidate := FValues[Index].GetNextEvent(IsCurrentState);
            if (IsCurrentState) then
            begin
               {$IFDEF DEBUG_STATE_TIMING}
               if (Candidate <> kNever) then
                  Writeln('    -> will become inactive at ', FormatDateTime('YYYY-MM-DD hh:nn:ss', Candidate))
               else
                  Writeln('    -> is active but not due to a time-based condition');
               {$ENDIF}
               if ((Candidate <> kNever) and (Candidate > Result)) then // Candidate > Result means that this state's condition, which is currently true, will remain true until after all the previous states have changed, so the earlier states' conditions aren't interesting
                  Result := kNever;
            end
            else
            begin
               {$IFDEF DEBUG_STATE_TIMING}
               if (Candidate <> kNever) then
                  Writeln('    -> will become active at ', FormatDateTime('YYYY-MM-DD hh:nn:ss', Candidate))
               else
                  Writeln('    -> will not automatically become active');
               {$ENDIF}
               if ((Result = kNever) or ((Candidate <> kNever) and (Candidate < Result))) then
                  Result := Candidate;
            end;
         end;
      end;
end;


constructor TButton.Create(const NewName, NewButtonLabel: AnsiString; const NewVisibleCondition, NewHighlightCondition: TCondition);
begin
   inherited Create(NewName);
   FButtonLabel := NewButtonLabel;
   FVisibleCondition := NewVisibleCondition;
   FHighlightCondition := NewHighlightCondition;
end;

destructor TButton.Destroy();
begin
   if (Assigned(FVisibleCondition)) then
      FVisibleCondition.Free();
   if (Assigned(FHighlightCondition)) then
      FHighlightCondition.Free();
   inherited;
end;

procedure TButton.AddSet(const NewState: TState; const NewValue: TStateValue);
begin
   SetLength(FInstructions, Length(FInstructions)+1);
   FInstructions[High(FInstructions)].Kind := biSet;
   FInstructions[High(FInstructions)].State := NewState;
   FInstructions[High(FInstructions)].Value := NewValue;
end;

procedure TButton.AddImply(const OtherButton: TButton);
begin
   SetLength(FInstructions, Length(FInstructions)+1);
   FInstructions[High(FInstructions)].Kind := biImply;
   FInstructions[High(FInstructions)].Button := OtherButton;
end;

procedure TButton.Press(const CurrentTime: TDateTime);
var
   Index: Cardinal;
begin
   if (Length(FInstructions) > 0) then
      for Index := Low(FInstructions) to High(FInstructions) do
         begin
            case FInstructions[Index].Kind of
               biSet: FInstructions[Index].State.SetValue(FInstructions[Index].Value, CurrentTime);
               biImply: FInstructions[Index].Button.Press(CurrentTime);
               else Assert(False);
            end;
         end;
   FLastChange := CurrentTime;
end;

procedure TButton.ReadState(const StateStore: TStateStore);
begin
   inherited;
   Assert(StateStore[Name].Value = '');
end;

procedure TButton.Update(const CurrentTime: TDateTime);
begin
   if (Assigned(FVisibleCondition)) then
   begin
      FVisibleCondition.Update(CurrentTime);
      FVisible := FVisibleCondition.Evaluate();
   end
   else
      FVisible := True;
   if (Assigned(FHighlightCondition)) then
   begin
      FHighlightCondition.Update(CurrentTime);
      FHighlighted := FHighlightCondition.Evaluate();
   end
   else
      FHighlighted := False;
end;

function TButton.GetNextEvent(): TDateTime;
var
   Candidate: TDateTime;
begin
   if (Assigned(FVisibleCondition)) then
      Result := FVisibleCondition.GetNextEvent()
   else
      Result := kNever;
   if (Assigned(FHighlightCondition)) then
   begin
      Candidate := FHighlightCondition.GetNextEvent();
      if ((Result = kNever) or (Result > Candidate)) then
         Result := Candidate;
   end;
end;

function TButton.GetVisible(): Boolean;
begin
   Result := FVisible;
end;


constructor TBehaviour.Create(const NewName: AnsiString; const NewCondition: TCondition);
begin
   inherited Create(NewName);
   FCondition := NewCondition;
end;

destructor TBehaviour.Destroy();
var
   Index: Cardinal;
begin
   if (Length(FInstructions) > 0) then
      for Index := Low(FInstructions) to High(FInstructions) do
         case (FInstructions[Index].Kind) of
            biClassLabel:
               begin
                  Dispose(FInstructions[Index].ClassLabel);
                  if (Assigned(FInstructions[Index].Condition)) then
                     FInstructions[Index].Condition.Free();
               end;
            biEscalateOnSchedule, biEscalateRepeatedly: FInstructions[Index].Schedule.Free();
         end;
   if (Assigned(FCondition)) then
      FCondition.Free();
   inherited;
end;

procedure TBehaviour.SetMessage(const NewMessage: AnsiString);
begin
   Assert(FMessage = '');
   FMessage := NewMessage;
end;

procedure TBehaviour.AddClassLabel(const NewClassLabel: AnsiString; const NewCondition: TCondition);
begin
   SetLength(FInstructions, Length(FInstructions)+1);
   FInstructions[High(FInstructions)].Kind := biClassLabel;
   New(FInstructions[High(FInstructions)].ClassLabel);
   FInstructions[High(FInstructions)].ClassLabel^ := NewClassLabel;
   FInstructions[High(FInstructions)].Condition := NewCondition;
end;

procedure TBehaviour.AddPromote(const OtherButton: TButton);
begin
   SetLength(FInstructions, Length(FInstructions)+1);
   FInstructions[High(FInstructions)].Kind := biPromoteButton;
   FInstructions[High(FInstructions)].Button := OtherButton;
end;

procedure TBehaviour.AddEscalateImmediately();
begin
   SetLength(FInstructions, Length(FInstructions)+1);
   FInstructions[High(FInstructions)].Kind := biEscalateImmediately;
end;

procedure TBehaviour.AddEscalationSchedule(const NewDuration: TDuration; const NewAnchor: TRule);
begin
   SetLength(FInstructions, Length(FInstructions)+1);
   FInstructions[High(FInstructions)].Kind := biEscalateOnSchedule;
   FInstructions[High(FInstructions)].Schedule := NewDuration;
   FInstructions[High(FInstructions)].Anchor := NewAnchor;
end;

procedure TBehaviour.AddEscalationRepetition(const NewDuration: TDuration; const NewAnchor: TRule);
begin
   SetLength(FInstructions, Length(FInstructions)+1);
   FInstructions[High(FInstructions)].Kind := biEscalateRepeatedly;
   FInstructions[High(FInstructions)].Schedule := NewDuration;
   FInstructions[High(FInstructions)].Anchor := NewAnchor;
end;

procedure TBehaviour.ReadState(const StateStore: TStateStore);
var
   Scratch: TStateData;
begin
   inherited;
   Assert(not FActive);
   Scratch := StateStore[Name];
   try
      FEscalationLevel := StrToInt(Scratch.Value); // $R-
      FLastEscalationLevel := FEscalationLevel;
   except
      on EConvertError do ;
   end;
   if (FEscalationLevel > 0) then
      FActive := True;
end;

procedure TBehaviour.SaveState(const StateStore: TStateStore);
var
   Scratch: TStateData;
begin
   inherited;
   Assert(FLastEscalationLevel = FEscalationLevel, 'Behaviour ' + Name + ' has FEscalationLevel of ' + IntToStr(FEscalationLevel) + ' but FLastEscalationLevel of ' + IntToStr(FLastEscalationLevel));
   Scratch := StateStore[Name];
   Scratch.Value := IntToStr(FEscalationLevel);
   StateStore[Name] := Scratch;
end;

procedure TBehaviour.Update(const CurrentTime: TDateTime);

   procedure AddClassLabelSegment(const ClassLabel: AnsiString);
   begin
      if (FClassLabel <> '') then
         FClassLabel := FClassLabel + ' ' + ClassLabel
      else
         FClassLabel := ClassLabel;
   end;

var
   Index: Cardinal;
   NewActive: Boolean;
   Candidate, EscalationAnchor: TDateTime;
begin
   if (Assigned(FCondition)) then
      FCondition.Update(CurrentTime);
   NewActive := (not Assigned(FCondition)) or (FCondition.Evaluate());
   // First, do the things that happen just when we go into or out of the behaviour
   if (NewActive <> FActive) then
   begin
      FLastEscalationLevel := 0;
      FLastChange := CurrentTime;
      FActive := NewActive;
   end;
   // Then, do the things that can change while the behaviour is active
   FClassLabel := '';
   FEscalationLevel := 0;
   FNextChangeWhenActive := kNever;
   if (FActive) then
   begin
      Inc(FEscalationLevel);
      if (Length(FInstructions) > 0) then
      begin
         for Index := Low(FInstructions) to High(FInstructions) do // $R-
         begin
            Candidate := kNever;
            case (FInstructions[Index].Kind) of
              biClassLabel:
                 begin
                    if (Assigned(FInstructions[Index].Condition)) then
                    begin
                       FInstructions[Index].Condition.Update(CurrentTime);
                       if (FInstructions[Index].Condition.Evaluate()) then
                          AddClassLabelSegment(FInstructions[Index].ClassLabel^);
                       Candidate := FInstructions[Index].Condition.GetNextEvent();
                    end
                    else
                       AddClassLabelSegment(FInstructions[Index].ClassLabel^);
                 end;
              biEscalateImmediately: Inc(FEscalationLevel);
              biEscalateOnSchedule:
                 begin
                    if (Assigned(FInstructions[Index].Anchor)) then
                       EscalationAnchor := FInstructions[Index].Anchor.LastChange
                    else
                       EscalationAnchor := FLastChange;
                    Candidate := FInstructions[Index].Schedule.AddedTo(EscalationAnchor);
                    if (Candidate <= CurrentTime) then
                    begin
                       Inc(FEscalationLevel);
                       Candidate := kNever;
                    end;
                 end;
              biEscalateRepeatedly:
                 begin
                    if (Assigned(FInstructions[Index].Anchor)) then
                       EscalationAnchor := FInstructions[Index].Anchor.LastChange
                    else
                       EscalationAnchor := FLastChange;
                    Candidate := FInstructions[Index].Schedule.AddedTo(EscalationAnchor);
                    while ((Candidate <= CurrentTime) and (FEscalationLevel < kMaxEscalations)) do
                    begin
                       Inc(FEscalationLevel);
                       Candidate := FInstructions[Index].Schedule.AddedTo(Candidate);
                    end;
                 end;
            end;
            if ((FNextChangeWhenActive = kNever) or ((Candidate <> kNever) and (FNextChangeWhenActive > Candidate))) then
               FNextChangeWhenActive := Candidate;
         end;
      end;
      if (FEscalationLevel > kMaxEscalations) then
         FEscalationLevel := kMaxEscalations;
   end;
end;

procedure TBehaviour.MarkEscalated();
begin
   FLastEscalationLevel := FEscalationLevel;
end;

function TBehaviour.GetNextEvent(): TDateTime;
begin
   if (Assigned(FCondition)) then
      Result := FCondition.GetNextEvent()
   else
      Result := kNever;
   if ((Result = kNever) or ((FNextChangeWhenActive <> kNever) and (Result > FNextChangeWhenActive))) then
      Result := FNextChangeWhenActive;
end;

function TBehaviour.GetButtonCount(): Cardinal;
var
   Index: Cardinal;
begin
   Result := 0;
   if ((FActive) and (Length(FInstructions) > 0)) then
      for Index := Low(FInstructions) to High(FInstructions) do // $R-
         if (FInstructions[Index].Kind = biPromoteButton) then
            Inc(Result);
end;

function TBehaviour.GetButton(ButtonNumber: Cardinal): TButton;
var
   Index: Cardinal;
begin
   Result := nil;
   if (FActive and (Length(FInstructions) > 0)) then
   begin
      for Index := Low(FInstructions) to High(FInstructions) do // $R-
         if (FInstructions[Index].Kind = biPromoteButton) then
         begin
            if (ButtonNumber = 0) then
            begin
               Result := FInstructions[Index].Button;
               Exit;
            end;
            Dec(ButtonNumber);
         end;
   end;
end;


constructor TToDo.Create(const NewName: AnsiString; const NewLabel: AnsiString; const NewRelevancyCondition: TCondition);
begin
   inherited Create(NewName);
   FLabel := NewLabel;
   FRelevancyCondition := NewRelevancyCondition;
end;

destructor TToDo.Destroy();
var
   Index: Cardinal;
begin
   if (Length(FClasses) > 0) then
      for Index := Low(FClasses) to High(FClasses) do
         if (Assigned(FClasses[Index].Condition)) then
            FClasses[Index].Condition.Free();
   if (Assigned(FRelevancyCondition)) then
      FRelevancyCondition.Free();
   if (Assigned(FSelectableCondition)) then
      FSelectableCondition.Free();
   if (Assigned(FSelectionDuration)) then
      FSelectionDuration.Free();
   inherited;
end;

procedure TToDo.AddSelectionDuration(const NewSelectionDuration: TDuration);
begin
   Assert(not Assigned(FSelectionDuration));
   FSelectionDuration := NewSelectionDuration;
end;

procedure TToDo.AddSelectableCondition(const NewSelectableCondition: TCondition);
begin
   Assert(not Assigned(FSelectableCondition));
   FSelectableCondition := NewSelectableCondition;
end;

function TToDo.GetHasSelectable(): Boolean;
begin
   Result := Assigned(FSelectableCondition);
end;

procedure TToDo.AddClassLabel(const NewClassLabel: AnsiString; const NewCondition: TCondition);
begin
   SetLength(FClasses, Length(FClasses)+1);
   FClasses[High(FClasses)].ClassLabel := NewClassLabel;
   FClasses[High(FClasses)].Condition := NewCondition;
end;

procedure TToDo.ReadState(const StateStore: TStateStore);
var
   Scratch: TStateData;
begin
   inherited;
   Scratch := StateStore[Name];
   try
      if (Scratch.Value = 'done') then
      begin
         FDone := True;
         FEscalationLevel := 0;
      end
      else
      if (Scratch.Value <> '') then
      begin
         FDone := False;
         // This is such a hack
         Assert(Length(Scratch.Value) > 2);
         FRelevant := (Scratch.Value[1] = 'R');
         Scratch.Value[1] := ' ';
         FSelectable := (Scratch.Value[2] = 'S');
         Scratch.Value[2] := ' ';
         FEscalationLevel := StrToInt(Scratch.Value); // $R-
      end;
   except
      on EConvertError do ;
   end;
end;

procedure TToDo.SaveState(const StateStore: TStateStore);
var
   Scratch: TStateData;
   S1, S2: Char;
begin
   inherited;
   Scratch := StateStore[Name];
   if (FDone) then
   begin
      Scratch.Value := 'done';
      Assert(FEscalationLevel = 0);
   end
   else
   begin
      if (FRelevant) then
         S1 := 'R'
      else
         S1 := ' ';
      if (FSelectable) then
         S2 := 'S'
      else
         S2 := ' ';
      Scratch.Value := S1 + S2 + IntToStr(FEscalationLevel);
   end;
   StateStore[Name] := Scratch;
end;

procedure TToDo.Update(const CurrentTime: TDateTime);

   procedure AddClassLabelSegment(const ClassLabel: AnsiString);
   begin
      if (FClassLabel <> '') then
         FClassLabel := FClassLabel + ' ' + ClassLabel
      else
         FClassLabel := ClassLabel;
   end;

var
   Index: Cardinal;
begin
   FClassLabel := '';
   if (FDone) then
   begin
      FRelevant := False;
      FSelectable := False;
   end
   else
   begin
      if (Assigned(FRelevancyCondition)) then
      begin
         FRelevancyCondition.Update(CurrentTime);
         FRelevant := FRelevancyCondition.Evaluate();
      end
      else
         FRelevant := True;
      if (FRelevant) then
         if (Length(FClasses) > 0) then
            for Index := Low(FClasses) to High(FClasses) do
            begin
               if (Assigned(FClasses[Index].Condition)) then
               begin
                  FClasses[Index].Condition.Update(CurrentTime);
                  if (FClasses[Index].Condition.Evaluate()) then
                     AddClassLabelSegment(FClasses[Index].ClassLabel);
               end
               else
                  AddClassLabelSegment(FClasses[Index].ClassLabel);
            end;
      if (Assigned(FSelectableCondition)) then
      begin
         Assert(Assigned(FSelectionDuration));
         FSelectableCondition.Update(CurrentTime);
         FSelectable := FSelectableCondition.Evaluate(); // must happen after FRelevant is updated
      end
      else
         FSelectable := Assigned(FSelectionDuration);
      if (FSelectable) then
         AddClassLabelSegment('selectable');
   end;
end;

function TToDo.GetNextEvent(): TDateTime;
var
   Candidate: TDateTime;
   Index: Cardinal;
begin
   if (FDone) then
   begin
      Result := kNever;
      Exit;
   end;
   if (Assigned(FRelevancyCondition)) then
      Result := FRelevancyCondition.GetNextEvent()
   else
      Result := kNever;
   if (Assigned(FSelectableCondition)) then
   begin
      // Generally this is a waste of time, but consider a time where there's only one ToDo left, and it's
      // only available in winter, or something
      Candidate := FSelectableCondition.GetNextEvent();
      if ((Result = kNever) or (Result > Candidate)) then
         Result := Candidate;
   end;
   if (FRelevant) then
   begin
      if (Length(FClasses) > 0) then
         for Index := Low(FClasses) to High(FClasses) do
            if (Assigned(FClasses[Index].Condition)) then
            begin
               Candidate := FClasses[Index].Condition.GetNextEvent();
               if ((Result = kNever) or (Result > Candidate)) then
                  Result := Candidate;
            end;
   end;
end;

function TToDo.GetVisible(): Boolean;
begin
   Result := FRelevant;
end;

procedure TToDo.Escalate(const CurrentTime: TDateTime);
begin
   if (not FDone) then
   begin
      Inc(FEscalationLevel);
      FLastChange := CurrentTime;
   end;
end;

procedure TToDo.Press(const CurrentTime: TDateTime);
begin
   FDone := True;
   FEscalationLevel := 0;
   FLastChange := CurrentTime;
end;


{$IFDEF DEBUG}
procedure RunTimeRangeConditionTests();
var
   C: TTimeRangeCondition;
begin
   // between alternating sundays at 21:00 and alternating mondays at 10:00
   // note that this is 9 days' worth of time, not 2!
   C := TTimeRangeCondition.Create(TRepeatingTime.Create(EncodeDateTime(2011, 1, 9, 21, 0, 0, 0), 14),
                                   TRepeatingTime.Create(EncodeDateTime(2011, 1, 17, 10, 0, 0, 0), 14));
   C.Update(EncodeDateTime(2013, 7, 31, 12, 53, 0, 0)); Assert(not C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 4, 21, 0, 0, 0));
   C.Update(EncodeDateTime(2013, 8,  1, 12, 53, 0, 0)); Assert(not C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 4, 21, 0, 0, 0));
   C.Update(EncodeDateTime(2013, 8,  2, 12, 53, 0, 0)); Assert(not C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 4, 21, 0, 0, 0));
   C.Update(EncodeDateTime(2013, 8,  3, 12, 53, 0, 0)); Assert(not C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 4, 21, 0, 0, 0));
   C.Update(EncodeDateTime(2013, 8,  4, 12, 53, 0, 0)); Assert(not C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 4, 21, 0, 0, 0));
   //            starts at 2013  8   4  21   0  0  0
   C.Update(EncodeDateTime(2013, 8,  4, 22, 53, 0, 0)); Assert(C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 12, 10, 0, 0, 0));
   C.Update(EncodeDateTime(2013, 8,  5, 12, 53, 0, 0)); Assert(C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 12, 10, 0, 0, 0));
   C.Update(EncodeDateTime(2013, 8,  6, 12, 53, 0, 0)); Assert(C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 12, 10, 0, 0, 0));
   C.Update(EncodeDateTime(2013, 8,  7, 12, 53, 0, 0)); Assert(C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 12, 10, 0, 0, 0));
   C.Update(EncodeDateTime(2013, 8,  8, 12, 53, 0, 0)); Assert(C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 12, 10, 0, 0, 0));
   C.Update(EncodeDateTime(2013, 8,  9, 12, 53, 0, 0)); Assert(C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 12, 10, 0, 0, 0));
   C.Update(EncodeDateTime(2013, 8, 10, 12, 53, 0, 0)); Assert(C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 12, 10, 0, 0, 0));
   C.Update(EncodeDateTime(2013, 8, 11, 12, 53, 0, 0)); Assert(C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 12, 10, 0, 0, 0));
   C.Update(EncodeDateTime(2013, 8, 12,  8, 53, 0, 0)); Assert(C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 12, 10, 0, 0, 0));
   C.Update(EncodeDateTime(2013, 8, 12,  9, 53, 0, 0)); Assert(C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 12, 10, 0, 0, 0));
   C.Update(EncodeDateTime(2013, 8, 12,  9, 59, 0, 0)); Assert(C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 12, 10, 0, 0, 0));
   //              ends at 2013  8  12  10   0  0  0
   C.Update(EncodeDateTime(2013, 8, 12, 10,  1, 0, 0)); Assert(not C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 18, 21, 0, 0, 0));
   C.Update(EncodeDateTime(2013, 8, 12, 12, 53, 0, 0)); Assert(not C.Evaluate());
   C.Update(EncodeDateTime(2013, 8, 13, 12, 53, 0, 0)); Assert(not C.Evaluate());
   C.Update(EncodeDateTime(2013, 8, 14, 12, 53, 0, 0)); Assert(not C.Evaluate());
   C.Update(EncodeDateTime(2013, 8, 15, 12, 53, 0, 0)); Assert(not C.Evaluate());
   C.Update(EncodeDateTime(2013, 8, 16, 12, 53, 0, 0)); Assert(not C.Evaluate());
   C.Update(EncodeDateTime(2013, 8, 17, 12, 53, 0, 0)); Assert(not C.Evaluate());
   C.Update(EncodeDateTime(2013, 8, 18, 12, 53, 0, 0)); Assert(not C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 18, 21, 0, 0, 0));
   // starts again...
   C.Update(EncodeDateTime(2013, 8, 19, 12, 53, 0, 0)); Assert(C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 26, 10, 0, 0, 0));
   C.Update(EncodeDateTime(2013, 8, 20, 12, 53, 0, 0)); Assert(C.Evaluate());
   C.Update(EncodeDateTime(2013, 8, 21, 12, 53, 0, 0)); Assert(C.Evaluate());
   C.Update(EncodeDateTime(2013, 8, 22, 12, 53, 0, 0)); Assert(C.Evaluate());
   C.Update(EncodeDateTime(2013, 8, 23, 12, 53, 0, 0)); Assert(C.Evaluate());
   C.Update(EncodeDateTime(2013, 8, 24, 12, 53, 0, 0)); Assert(C.Evaluate());
   C.Update(EncodeDateTime(2013, 8, 25, 12, 53, 0, 0)); Assert(C.Evaluate());
   Assert(C.GetNextEvent() = EncodeDateTime(2013, 8, 26, 10, 0, 0, 0));
   // ends again...
   C.Update(EncodeDateTime(2013, 8, 26, 12, 53, 0, 0)); Assert(not C.Evaluate());
   C.Update(EncodeDateTime(2013, 8, 27, 12, 53, 0, 0)); Assert(not C.Evaluate());
   C.Update(EncodeDateTime(2013, 8, 28, 12, 53, 0, 0)); Assert(not C.Evaluate());
   C.Update(EncodeDateTime(2013, 8, 29, 12, 53, 0, 0)); Assert(not C.Evaluate());
   C.Update(EncodeDateTime(2013, 8, 30, 12, 53, 0, 0)); Assert(not C.Evaluate());
   C.Update(EncodeDateTime(2013, 8, 31, 12, 53, 0, 0)); Assert(not C.Evaluate());
   C.Update(EncodeDateTime(2013, 9, 1, 12, 53, 0, 0)); Assert(not C.Evaluate());
   C.Free();
end;

procedure RunChangeAgeConditionTests();
var
   C: TChangeAgeCondition;
   Rule: TRule;
begin
   Rule := TButton.Create('Test', 'Test Label', nil, nil);
   C := TChangeAgeCondition.Create(Rule, TSecondDuration.Create(10)); // changed over 10 seconds ago?
   (Rule as TButton).Press(10.0); // pressed at midnight on day ten
   Rule.Update(20.0); // updating at midnight on day twenty
   C.Update(20.0);
   Assert(C.Evaluate());
   (Rule as TButton).Press(20.5); // pressed at noon on day twenty
   Rule.Update(20.5); // updating at same time
   C.Update(20.5);
   Assert(not C.Evaluate());
   Rule.Update(20.5 + 6 * OneSecond); // six seconds later
   C.Update(20.5 + 6 * OneSecond);
   Assert(not C.Evaluate());
   Rule.Update(20.5 + 12 * OneSecond); // six seconds later again
   C.Update(20.5 + 12 * OneSecond);
   Assert(C.Evaluate());
   C.Free();
   Rule.Free();
end;

procedure RunTests();
begin
   RunTimeRangeConditionTests();
   RunChangeAgeConditionTests();
end;
{$ENDIF}

initialization
   {$IFDEF DEBUG} RunTests(); {$ENDIF}
end.
