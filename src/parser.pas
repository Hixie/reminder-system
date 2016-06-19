{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit parser;

interface

uses
   rulelogic;

function GetRulesFromDisk(): TRuleList;

implementation

uses
   tokeniser, primitives, hashtable, hashfunctions, exceptions, stringutils, dateutils, sysutils;

function GetRulesFromDisk(): TRuleList;
type
   TRuleTable = specialize THashTable <UTF8String, TRule, UTF8StringUtils>;
   TTimeUnit = (tuYear, tuMonth, tuWeek, tuDay, tuHour, tuMinute, tuSecond, tuNone);
var
   RulesByName: TRuleTable;
   Tokeniser: TReminderRulesTokeniser;

   function MaybeParseTimeUnit(): TTimeUnit;
   begin
      if (Tokeniser.MaybeConsumeKeyword('year') or Tokeniser.MaybeConsumeKeyword('years')) then
         Result := tuYear
      else
      if (Tokeniser.MaybeConsumeKeyword('month') or Tokeniser.MaybeConsumeKeyword('months')) then
         Result := tuMonth
      else
      if (Tokeniser.MaybeConsumeKeyword('week') or Tokeniser.MaybeConsumeKeyword('weeks')) then
         Result := tuWeek
      else
      if (Tokeniser.MaybeConsumeKeyword('day') or Tokeniser.MaybeConsumeKeyword('days')) then
         Result := tuDay
      else
      if (Tokeniser.MaybeConsumeKeyword('hour') or Tokeniser.MaybeConsumeKeyword('hours')) then
         Result := tuHour
      else
      if (Tokeniser.MaybeConsumeKeyword('minute') or Tokeniser.MaybeConsumeKeyword('minutes')) then
         Result := tuMinute
      else
      if (Tokeniser.MaybeConsumeKeyword('second') or Tokeniser.MaybeConsumeKeyword('seconds')) then
         Result := tuSecond
      else
         Result := tuNone;
   end;

   function ParseDuration(): TDuration;
   var
      Value: Cardinal;
      TimeUnit: TTimeUnit;
   begin
      Value := Tokeniser.ConsumeNumber(Low(Value), High(Value) div (7 * 24 * 60 * 60));
      Tokeniser.ExpectToken([tkIdentifier]);
      TimeUnit := MaybeParseTimeUnit();
      if (TimeUnit in [tuMonth, tuYear]) then
      begin
         if (TimeUnit = tuYear) then
            Value := Value * 12 // $R-
         else
            Assert(TimeUnit = tuMonth);
         Result := TMonthDuration.Create(Value);
      end
      else
      begin
         if (TimeUnit = tuWeek) then
            Value := Value * 7 * 24 * 60 * 60 {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
         else
         if (TimeUnit = tuDay) then
            Value := Value *     24 * 60 * 60 {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
         else
         if (TimeUnit = tuHour) then
            Value := Value *          60 * 60 {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
         else
         if (TimeUnit = tuMinute) then
            Value := Value *               60 {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
         else
         if (TimeUnit = tuSecond) then
         begin end
         else
            Tokeniser.RaiseError('Unrecognised duration time unit keyword');
         Result := TSecondDuration.Create(Value);
      end;
   end;

   function ParseTimeUnitOrDuration(): TDuration;
   begin {BOGUS Warning: Function result variable does not seem to initialized}
      case (MaybeParseTimeUnit()) of
        tuNone: Result := ParseDuration();
        tuYear: Result := TMonthDuration.Create(12);
        tuMonth: Result := TMonthDuration.Create(1);
        tuWeek: Result := TSecondDuration.Create(60*60*24*7);
        tuDay: Result := TSecondDuration.Create(60*60*24);
        tuHour: Result := TSecondDuration.Create(60*60);
        tuMinute: Result := TSecondDuration.Create(60);
        tuSecond: Result := TSecondDuration.Create(1);
        else
           Assert(False);
      end;
   end;

   type
      TCharString = String[1]; // zero one one character

   function MaybeParseWeekday(out Weekday: TWeekday; const Suffix: TCharString = ''): Boolean;
   begin
      Result := True;
      if (Tokeniser.MaybeConsumeKeyword('monday' + Suffix)) then
         Weekday := wdMonday
      else
      if (Tokeniser.MaybeConsumeKeyword('tuesday' + Suffix)) then
         Weekday := wdTuesday
      else
      if (Tokeniser.MaybeConsumeKeyword('wednesday' + Suffix)) then
         Weekday := wdWednesday
      else
      if (Tokeniser.MaybeConsumeKeyword('thursday' + Suffix)) then
         Weekday := wdThursday
      else
      if (Tokeniser.MaybeConsumeKeyword('friday' + Suffix)) then
         Weekday := wdFriday
      else
      if (Tokeniser.MaybeConsumeKeyword('saturday' + Suffix)) then
         Weekday := wdSaturday
      else
      if (Tokeniser.MaybeConsumeKeyword('sunday' + Suffix)) then
         Weekday := wdSunday
      else
         Result := False;
   end;

   function MaybeParseMonth(out Month: Word): Boolean;
   begin
      Result := True;
      if (Tokeniser.MaybeConsumeKeyword('january')) then
         Month := 1
      else
      if (Tokeniser.MaybeConsumeKeyword('february')) then
         Month := 2
      else
      if (Tokeniser.MaybeConsumeKeyword('march')) then
         Month := 3
      else
      if (Tokeniser.MaybeConsumeKeyword('april')) then
         Month := 4
      else
      if (Tokeniser.MaybeConsumeKeyword('may')) then
         Month := 5
      else
      if (Tokeniser.MaybeConsumeKeyword('june')) then
         Month := 6
      else
      if (Tokeniser.MaybeConsumeKeyword('july')) then
         Month := 7
      else
      if (Tokeniser.MaybeConsumeKeyword('august')) then
         Month := 8
      else
      if (Tokeniser.MaybeConsumeKeyword('september')) then
         Month := 9
      else
      if (Tokeniser.MaybeConsumeKeyword('october')) then
         Month := 10
      else
      if (Tokeniser.MaybeConsumeKeyword('november')) then
         Month := 11
      else
      if (Tokeniser.MaybeConsumeKeyword('december')) then
         Month := 12
      else
         Result := False;
   end;

   function ParseWeekday(const Suffix: TCharString = ''): TWeekday;
   begin
      Tokeniser.ExpectToken([tkIdentifier]);
      if (not MaybeParseWeekday(Result, Suffix)) then
         Tokeniser.RaiseError('Unknown weekday' + Suffix);
   end;

   function ParseDayTime(): TDayTime;
   begin
      Result.Hour := Tokeniser.ConsumeNumber(0, 23); {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
      Tokeniser.ConsumePunctuation(tkColon);
      Result.Minute := Tokeniser.ConsumeNumber(0, 59); {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
   end;

   function ParseOptionalDayTime(): TDayTime;
   begin
      if (Tokeniser.MaybeConsumeKeyword('at')) then
      begin
         Result := ParseDayTime();
      end
      else
      begin
         Result.Hour := 0;
         Result.Minute := 0;
      end;
   end;

   function ParseMonthRelativeWeekdaysTime(const WeekOrdinal: TWeekOrdinal): TMonthRelativeWeekdaysTime;
   var
      Weekday: TWeekday;
      DayTime: TDayTime;
   begin
      Weekday := ParseWeekday();
      DayTime := ParseOptionalDayTime();
      Result := TMonthRelativeWeekdaysTime.Create(WeekOrdinal, Weekday, DayTime);
   end;

   function ParseDate(): TDateTime;
   var
      Year, Month, Day: Word;
   begin
      Year := Tokeniser.ConsumeNumber(0, High(Word)); {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
      Tokeniser.ConsumePunctuation(tkHyphen);
      Month := Tokeniser.ConsumeNumber(1, 12); {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
      Tokeniser.ConsumePunctuation(tkHyphen);
      Day := Tokeniser.ConsumeNumber(1, 31); {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
      if (not TryEncodeDateTime(Year, Month, Day, 0, 0, 0, 0, Result)) then
         Tokeniser.RaiseError('Invalid date');
   end;

   function ParseMasterTime(): TMasterTime;
   var
      CheckWeekday: Boolean;
      Weekday: TWeekday;
      DayTime: TDayTime;
      Duration: TDuration;
      Anchor: TDateTime;
      Month, Day: Word;
   begin
      if (Tokeniser.GetNextTokenKind() = tkIdentifier) then
      begin
         if (Tokeniser.MaybeConsumeKeyword('first')) then
            Result := ParseMonthRelativeWeekdaysTime(1)
         else
         if (Tokeniser.MaybeConsumeKeyword('second')) then
            Result := ParseMonthRelativeWeekdaysTime(2)
         else
         if (Tokeniser.MaybeConsumeKeyword('third')) then
            Result := ParseMonthRelativeWeekdaysTime(3)
         else
         if (Tokeniser.MaybeConsumeKeyword('fourth')) then
            Result := ParseMonthRelativeWeekdaysTime(4)
         else
         if (Tokeniser.MaybeConsumeKeyword('fifth')) then
            Result := ParseMonthRelativeWeekdaysTime(5)
         else
         if (Tokeniser.MaybeConsumeKeyword('alternating')) then
         begin
            Weekday := ParseWeekday('s');
            Tokeniser.ConsumePunctuation(tkOpenParen);
            Tokeniser.ConsumeKeyword('starting');
            Anchor := ParseDate();
            if (Anchor >= Now) then
               Tokeniser.RaiseError('Anchor dates must be in the past');
            Tokeniser.ConsumePunctuation(tkCloseParen);
            DayTime := ParseOptionalDayTime();
            Result := TRepeatingTime.Create(Anchor + DayTime, 14);
         end
         else
         if (Tokeniser.MaybeConsumeKeyword('every')) then
         begin
            Duration := ParseTimeUnitOrDuration();
            try
               if (not (Duration is TSecondDuration)) then
                  Tokeniser.RaiseError('Only fixed durations (seconds, minutes, hours, days, and weeks) are supported here');
               Tokeniser.ConsumeKeyword('starting');
               CheckWeekday := MaybeParseWeekday(Weekday);
               Anchor := ParseDate();
               if (CheckWeekday) then
               begin
                  Assert(((DayMonday+2) mod 7) = Ord(wdMonday));
                  Assert(((DayWednesday+2) mod 7) = Ord(wdWednesday));
                  Assert(((DaySunday+2) mod 7) = Ord(wdSunday));
                  if (((DayOfTheWeek(Anchor)+2) mod 7) <> Ord(Weekday)) then
                     Tokeniser.RaiseError('Date provided does not match weekday provided');
               end;
               DayTime := ParseOptionalDayTime();
               Result := TRepeatingTime.Create(Anchor + DayTime, (Duration as TSecondDuration).AsDateTime());
            finally
               Duration.Free();
            end;
         end
         else
         if (Tokeniser.MaybeConsumeKeyword('at')) then
         begin
            DayTime := ParseDayTime();
            Result := TRepeatingTime.Create(0.0 + DayTime, 1.0);
         end
         else
         if (MaybeParseMonth(Month)) then
         begin
            if (Tokeniser.GetNextTokenKind() = tkNumber) then // feb 29 is not supportedm
               Day := Tokeniser.ConsumeNumber(1, DaysInAMonth(1970, Month)) // $R-
            else
               Day := 1;
            DayTime := ParseOptionalDayTime();
            Result := TMonthTime.Create(Month, Day, DayTime);
         end
         else
         if (MaybeParseWeekday(Weekday, 's')) then
         begin
            DayTime := ParseOptionalDayTime();
            Result := TRepeatingTime.Create(TDateTime(2.0 + Ord(Weekday)) + DayTime, 7.0);
         end
         else
            Tokeniser.RaiseError('Unrecognised time expression');
      end
      else
      begin
         Duration := ParseDuration();
         try
            Tokeniser.ConsumeKeyword('before');
            Result := TDeltaBeforeDuration.Create(ParseMasterTime(), Duration);
         except
            Duration.Free();
            raise;
         end;
      end;
   end;

   function ParseBetweenTimeRangeCondition(): TTimeRangeCondition;
   var
      StartTime: TTime;
      EndTime: TMasterTime;
   begin
      StartTime := ParseMasterTime();
      try
         Tokeniser.ConsumeKeyword('and');
         EndTime := ParseMasterTime();
      except
         StartTime.Free();
         raise;
      end;
      Result := TTimeRangeCondition.Create(StartTime, EndTime);
   end;

   function ParseForTimeRangeCondition(): TTimeRangeCondition;
   var
      Duration: TDuration;
      StartTime: TMasterTime;
      DeltaTime: TDeltaTime;
   begin
      Duration := ParseDuration();
      try
         Tokeniser.ConsumeKeyword('after');
         StartTime := ParseMasterTime();
      except
         Duration.Free();
         raise;
      end;
      DeltaTime := TDeltaAfterDuration.Create(StartTime, Duration);
      Result := TTimeRangeCondition.Create(TSlaveTime.Create(DeltaTime), DeltaTime);
   end;

   function MaybeParseTimeRangeCondition(): TTimeRangeCondition;
   begin
      if (Tokeniser.MaybeConsumeKeyword('between')) then
      begin
         Result := ParseBetweenTimeRangeCondition();
      end
      else
      if (Tokeniser.MaybeConsumeKeyword('for')) then
      begin
         Result := ParseForTimeRangeCondition();
      end
      else
         Result := nil;
   end;

   function ParseRuleReference(): TRule;
   begin
      Result := RulesByName[Tokeniser.ConsumeIdentifier()];
      if (not Assigned(Result)) then
         Tokeniser.RaiseError('Reference to undeclared rule');
   end;

   function ParseStateReference(): TState;
   var
      Rule: TRule;
   begin
      Rule := ParseRuleReference();
      if (not (Rule is TState)) then
         Tokeniser.RaiseError('Identifier does not identify a state');
      Result := Rule as TState;
   end;

   function ParseStateValueReference(const State: TState): TStateValue;
   begin
      Result := State.GetValue(Tokeniser.ConsumeIdentifier());
      if (not Assigned(Result)) then
         Tokeniser.RaiseError('Unknown state value');
   end;

   function ParseButtonReference(): TButton;
   var
      Rule: TRule;
   begin
      Rule := ParseRuleReference();
      if (not (Rule is TButton)) then
         Tokeniser.RaiseError('Identifier does not identify a button');
      Result := Rule as TButton;
   end;

   function ParseBehaviourReference(): TBehaviour;
   var
      Rule: TRule;
   begin
      Rule := ParseRuleReference();
      if (not (Rule is TBehaviour)) then
         Tokeniser.RaiseError('Identifier does not identify a behaviour');
      Result := Rule as TBehaviour;
   end;

   function MaybeParseTimeReference(Rule: TRule): Boolean;
   begin
      Result := ((Rule is TButton) and Tokeniser.MaybeConsumeKeyword('pressed')) or
                ((Rule is TState) and Tokeniser.MaybeConsumeKeyword('changed')) or
                ((Rule is TBehaviour) and Tokeniser.MaybeConsumeKeyword('triggered'));
   end;

   function ParseCondition(): TCondition; forward;

   function ParseConditionInParens(): TCondition;
   begin
      Result := MaybeParseTimeRangeCondition();
      if (not Assigned(Result)) then
         Result := ParseCondition();
      Assert(Assigned(Result));
      try
         Tokeniser.ConsumePunctuation(tkCloseParen);
      except
         Result.Free();
         raise;
      end;
   end;

   function ParseConditionElement(): TCondition;
   var
      Rule, OtherRule: TRule;
      State: TState;
      StateValue: TStateValue;
      Behaviour: TBehaviour;
      Duration: TDuration;
      Negated: Boolean;
      ConditionClass: TConditionClass;
      AgeComparisonConditionClass: TAgeComparisonConditionClass;
   begin
      if (Tokeniser.MaybeConsumePunctuation(tkOpenParen)) then
      begin
         Result := ParseConditionInParens();
      end
      else
      if (Tokeniser.MaybeConsumeKeyword('not')) then
      begin
         if (Tokeniser.MaybeConsumePunctuation(tkOpenParen)) then
            Result := TNotCondition.Create(ParseConditionInParens())
         else
            Result := TNotCondition.Create(TBehaviourCondition.Create(ParseBehaviourReference()));
      end
      else
      if (Tokeniser.GetNextTokenKind() = tkIdentifier) then
      begin
         Rule := ParseRuleReference();
         if (Tokeniser.MaybeConsumeKeyword('is')) then
         begin
            Negated := Tokeniser.MaybeConsumeKeyword('not');
            if (Rule is TToDo) then
            begin
               if (Tokeniser.MaybeConsumeKeyword('done')) then
               begin
                  ConditionClass := TToDoDoneCondition;
               end
               else
               if (Tokeniser.MaybeConsumeKeyword('relevant')) then
               begin
                  ConditionClass := TToDoRelevantCondition;
               end
               else
                  Tokeniser.RaiseError('Unrecognised duration or age comparison keyword');
               Assert(Assigned(ConditionClass));
               Assert(ConditionClass.InheritsFrom(TToDoAbstractCondition));
               Result := TToDoConditionClass(ConditionClass).Create(Rule as TToDo);
            end
            else
            if (Rule is TState) then
            begin
               State := Rule as TState;
               StateValue := ParseStateValueReference(State);
               Result := TStateCondition.Create(State, StateValue);
            end
            else
               Tokeniser.RaiseError('Identifier does not identify a state');
            if (Negated) then
               Result := TNotCondition.Create(Result);
         end
         else
         if (MaybeParseTimeReference(Rule)) then
         begin
            Tokeniser.ExpectToken([tkIdentifier]);
            if (Tokeniser.MaybeConsumeKeyword('before')) then
            begin
               ConditionClass := TAgeComparisonBeforeCondition;
            end
            else
            if (Tokeniser.MaybeConsumeKeyword('after')) then
            begin
               ConditionClass := TAgeComparisonAfterCondition;
            end
            else
            if (Tokeniser.MaybeConsumeKeyword('over')) then
            begin
               Negated := False;
               ConditionClass := TChangeAgeCondition;
            end
            else
            if (Tokeniser.MaybeConsumeKeyword('under')) then
            begin
               Negated := True;
               ConditionClass := TChangeAgeCondition;
            end
            else
               Tokeniser.RaiseError('Unrecognised duration or age comparison keyword');
            Assert(Assigned(ConditionClass));
            if (ConditionClass.InheritsFrom(TAgeComparisonCondition)) then
            begin
               AgeComparisonConditionClass := TAgeComparisonConditionClass(ConditionClass);
               OtherRule := ParseRuleReference();
               if (not MaybeParseTimeReference(OtherRule)) then
                  Tokeniser.RaiseError('Age comparison syntax unrecognised');
               Result := AgeComparisonConditionClass.Create(Rule, OtherRule);
            end
            else
            begin
               Assert(ConditionClass = TChangeAgeCondition);
               Duration := ParseDuration();
               try
                  Tokeniser.ConsumeKeyword('ago');
                  Result := TChangeAgeCondition.Create(Rule, Duration);
                  if (Negated) then
                     Result := TNotCondition.Create(Result);
               except
                  Duration.Free();
                  raise;
               end;
            end;
         end
         else
         begin
            if (not (Rule is TBehaviour)) then
               Tokeniser.RaiseError('Condition syntax unrecognised');
            Behaviour := Rule as TBehaviour;
            Result := TBehaviourCondition.Create(Behaviour);
         end;
      end
      else
         Tokeniser.RaiseError('Expected condition element');
   end;

   function ParseCondition(): TCondition;
   var
      TimeRangeCondition: TTimeRangeCondition;
   begin
      Result := ParseConditionElement();
      try
         if (Tokeniser.MaybeConsumeKeyword('and')) then
         begin
            repeat
               Result := TAndCondition.Create(Result, ParseConditionElement());
            until not Tokeniser.MaybeConsumeKeyword('and');
         end
         else
         if (Tokeniser.MaybeConsumeKeyword('or')) then
         begin
            repeat
               Result := TOrCondition.Create(Result, ParseConditionElement());
            until not Tokeniser.MaybeConsumeKeyword('or');
         end;
         TimeRangeCondition := MaybeParseTimeRangeCondition();
         if (Assigned(TimeRangeCondition)) then
            Result := TAndCondition.Create(Result, TimeRangeCondition);
      except
         Result.Free();
         raise;
      end;
   end;

   function MaybeParseConditionOrTimeRange(): TCondition;
   begin
      if (Tokeniser.MaybeConsumeKeyword('when')) then
         Result := ParseCondition()
      else
         Result := MaybeParseTimeRangeCondition();
   end;

   procedure AppendRule(const Rule: TRule);
   begin
      RulesByName[Rule.Name] := Rule;
      SetLength(Result, Length(Result)+1);
      Result[High(Result)] := Rule;
   end;

   procedure ParseState(const Name: UTF8String);
   var
      StateName: UTF8String;
      State: TState;
   begin
      Tokeniser.ConsumePunctuation(tkOpenBrace);
      State := TState.Create(Name);
      AppendRule(State);
      repeat
         StateName := Tokeniser.ConsumeIdentifier();
         if (Assigned(State.GetValue(StateName))) then
            Tokeniser.RaiseError('Duplicate state name');
         State.AddValue(TStateValue.Create(StateName, MaybeParseConditionOrTimeRange()));
         Tokeniser.ConsumePunctuation(tkSemicolon);
      until Tokeniser.MaybeConsumePunctuation(tkCloseBrace);
   end;

   procedure ParseButton(const Name: UTF8String);
   var
      BlockLabel: UTF8String;
      State: TState;
      StateValue: TStateValue;
      Button: TButton;
      VisibleCondition, HighlightCondition: TCondition;
   begin
      BlockLabel := Tokeniser.ConsumeString();
      VisibleCondition := MaybeParseConditionOrTimeRange();
      try
         if (Tokeniser.MaybeConsumeKeyword('highlight')) then
         begin
            HighlightCondition := MaybeParseConditionOrTimeRange();
            if (not Assigned(HighlightCondition)) then
               Tokeniser.RaiseError('Missing condition after "highlight"');
         end
         else
            HighlightCondition := nil;
      except
         if (Assigned(VisibleCondition)) then
            VisibleCondition.Free();
         raise;
      end;
      Button := TButton.Create(Name, BlockLabel, VisibleCondition, HighlightCondition);
      AppendRule(Button);
      Tokeniser.ConsumePunctuation(tkOpenBrace);
      while (not Tokeniser.MaybeConsumePunctuation(tkCloseBrace)) do
      begin
         if (Tokeniser.MaybeConsumeKeyword('set')) then
         begin
            State := ParseStateReference();
            Tokeniser.ConsumeKeyword('to');
            StateValue := ParseStateValueReference(State);
            Button.AddSet(State, StateValue);
         end
         else
         if (Tokeniser.MaybeConsumeKeyword('imply')) then
         begin
            Button.AddImply(ParseButtonReference());
         end
         else
            Tokeniser.RaiseError('Unknown button statement');
         Tokeniser.ConsumePunctuation(tkSemicolon);
      end;
   end;

   function MaybeParseEscalationAnchor(): TRule;
   begin
      if (Tokeniser.MaybeConsumeKeyword('after')) then
      begin
         Result := ParseRuleReference();
         if (not MaybeParseTimeReference(Result)) then
            Tokeniser.RaiseError('Escalation anchor syntax unrecognised');
      end
      else
         Result := nil;
   end;

   procedure ParseBehaviour(const Name: UTF8String);
   var
      Behaviour: TBehaviour;
      Message, ClassLabel: UTF8String;
      Escalations: Boolean;
      Duration: TDuration;
      Rule: TRule;
   begin
      Behaviour := TBehaviour.Create(Name, MaybeParseConditionOrTimeRange());
      AppendRule(Behaviour);
      Tokeniser.ConsumePunctuation(tkOpenBrace);
      Escalations := False;
      while (not Tokeniser.MaybeConsumePunctuation(tkCloseBrace)) do
      begin
         if (Tokeniser.MaybeConsumeKeyword('message')) then
         begin
            if (Behaviour.Message <> '') then
               Tokeniser.RaiseError('A behaviour can only have one message');
            Message := Tokeniser.ConsumeString();
            if (Message = '') then
               Tokeniser.RaiseError('A behaviour''s message cannot be empty');
            Behaviour.SetMessage(Message);
         end
         else
         if (Tokeniser.MaybeConsumeKeyword('class')) then
         begin
            ClassLabel := Tokeniser.ConsumeString();
            Behaviour.AddClassLabel(ClassLabel, MaybeParseConditionOrTimeRange());
         end
         else
         if (Tokeniser.MaybeConsumeKeyword('promote')) then
         begin
            // XXX should catch duplicate promotions (client doesn't handle that)
            Behaviour.AddPromote(ParseButtonReference());
         end
         else
         if (Tokeniser.MaybeConsumeKeyword('escalate')) then
         begin
            Escalations := True;
            if (Tokeniser.MaybeConsumeKeyword('immediately')) then
            begin
               Behaviour.AddEscalateImmediately();
            end
            else
            if (Tokeniser.MaybeConsumeKeyword('after')) then
            begin
               Duration := ParseDuration();
               Rule := MaybeParseEscalationAnchor();
               Behaviour.AddEscalationSchedule(Duration, Rule);
            end
            else
            if (Tokeniser.MaybeConsumeKeyword('every')) then
            begin
               Duration := ParseTimeUnitOrDuration();
               Rule := MaybeParseEscalationAnchor();
               Behaviour.AddEscalationRepetition(Duration, Rule);
            end
            else
               Tokeniser.RaiseError('Unknown escalation schedule');
         end
         else
            Tokeniser.RaiseError('Unknown behaviour statement');
         Tokeniser.ConsumePunctuation(tkSemicolon);
      end;
      if (Escalations and (Behaviour.Message = '')) then
         Tokeniser.RaiseError('A behaviour with escalations must have a message');
   end;

   procedure ParseToDo(const Name: UTF8String);
   var
      ToDo: TToDo;
      ToDoLabel, ClassLabel: UTF8String;
      Condition: TCondition;
   begin
      ToDoLabel := Tokeniser.ConsumeString();
      ToDo := TToDo.Create(Name, ToDoLabel, MaybeParseConditionOrTimeRange());
      AppendRule(ToDo);
      Tokeniser.ConsumePunctuation(tkOpenBrace);
      while (not Tokeniser.MaybeConsumePunctuation(tkCloseBrace)) do
      begin
         if (Tokeniser.MaybeConsumeKeyword('select')) then
         begin
            if (ToDo.HasSelectable) then
               Tokeniser.RaiseError('A todo with can only have one "select" condition');
            Condition := MaybeParseConditionOrTimeRange();
            if (not Assigned(Condition)) then
               Tokeniser.RaiseError('Missing condition after "select"');
            ToDo.AddSelectableCondition(Condition);
         end
         else
         if (Tokeniser.MaybeConsumeKeyword('lasts')) then
         begin
            if (Assigned(ToDo.SelectionDuration)) then
               Tokeniser.RaiseError('A todo with can only have one "lasts" duration');
            ToDo.AddSelectionDuration(ParseDuration());
         end
         else
         if (Tokeniser.MaybeConsumeKeyword('class')) then
         begin
            ClassLabel := Tokeniser.ConsumeString();
            ToDo.AddClassLabel(ClassLabel, MaybeParseConditionOrTimeRange());
         end
         else
            Tokeniser.RaiseError('Unknown todo statement');
         Tokeniser.ConsumePunctuation(tkSemicolon);
      end;
      if (ToDo.HasSelectable and not Assigned(ToDo.SelectionDuration)) then
         Tokeniser.RaiseError('Behaviour must have a "lasts" duration if it has a "select" condition');
   end;

   procedure ParseRoot();
   var
      Name: UTF8String;
   begin
      repeat
         Name := Tokeniser.ConsumeIdentifier();
         if (RulesByName.Has(Name)) then
            Tokeniser.RaiseError('Duplicate block name');
         Tokeniser.ConsumePunctuation(tkColon);
         Tokeniser.ExpectToken([tkIdentifier]);
         if (Tokeniser.MaybeConsumeKeyword('state')) then
            ParseState(Name)
         else
         if (Tokeniser.MaybeConsumeKeyword('button')) then
            ParseButton(Name)
         else
         if (Tokeniser.MaybeConsumeKeyword('behaviour')) then
            ParseBehaviour(Name)
         else
         if (Tokeniser.MaybeConsumeKeyword('todo')) then
            ParseToDo(Name)
         else
            Tokeniser.RaiseError('Unknown block type keyword');
         Tokeniser.ExpectToken([tkIdentifier, tkEnd]);
      until Tokeniser.MaybeConsumePunctuation(tkEnd);
   end;

   procedure ParseFile(FileName: UTF8String);
   begin
      Tokeniser.ReadFrom(FileName);
      ParseRoot();
   end;

var
   Index: Cardinal;
begin
   try
      RulesByName := TRuleTable.Create(@UTF8StringHash32);
      Tokeniser := TReminderRulesTokeniser.Create();
      try
         ParseFile('rules');
      finally
         RulesByName.Free();
         Tokeniser.Free();
      end;
   except
      if (Length(Result) > 0) then
         for Index := High(Result) downto Low(Result) do
            Result[Index].Free();
      raise;
   end;
end;

end.
