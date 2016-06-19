{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit primitives;

interface

const
   kNever: TDateTime = 0.0;

type
   TDayTime = record
     type
      THour = 0..23;
      TMinute = 0..59;
     var
      Hour: THour;
      Minute: TMinute;
      class function Create(const NewHour: THour; NewMinute: TMinute): TDayTime; inline; static; // i really should just make this a constructor
   end;

   operator + (const A: TDateTime; const B: TDayTime): TDateTime;

type
   TDuration = class abstract
    protected
      FDuration: Cardinal;
    public
      constructor Create(const NewDuration: Cardinal);
      function AddedTo(const Anchor: TDateTime): TDateTime; virtual; abstract;
      function SubtractedFrom(const Anchor: TDateTime): TDateTime; virtual; abstract;
   end;

   TMonthDuration = class(TDuration)
    strict private
      function InternalAdd(const Anchor: TDateTime; const Delta: Integer): TDateTime;
    public
      function AddedTo(const Anchor: TDateTime): TDateTime; override;
      function SubtractedFrom(const Anchor: TDateTime): TDateTime; override;
   end;

   TSecondDuration = class(TDuration)
    protected
     const
      kScaleFactor: TDateTime = 1 / (24.0 * 60.0 * 60.0); // one second as a TDateTime
    public
      function AddedTo(const Anchor: TDateTime): TDateTime; override;
      function SubtractedFrom(const Anchor: TDateTime): TDateTime; override;
      function AsDateTime(): TDateTime;
   end;


   TWeekday = (wdMonday = 0, wdTuesday = 1, wdWednesday = 2, wdThursday = 3, wdFriday = 4, wdSaturday = 5, wdSunday = 6);
   TPeriod = 1..High(Cardinal);
   TWeekOrdinal = 1..5;

   TTimeAnchor = (taBefore, taAfter); // taBefore is really taBeforeOrEquals

   TTime = class abstract
    protected
      function GetTime(): TDateTime; virtual; abstract;
    public
      procedure Update(const Anchor: TDateTime; const AnchorKind: TTimeAnchor); virtual; abstract;
      property Time: TDateTime read GetTime;
   end;

   TMasterTime = class abstract (TTime)
   end;

   TCachedTime = class abstract (TMasterTime)
    protected
      FTime: TDateTime;
      function GetTime(): TDateTime; override;
   end;

   TRepeatingTime = class(TCachedTime)
    strict private
      FZero,
      FPeriod: TDateTime; // 7 = every week, 14 = every other week, etc
    public
      constructor Create(const NewZero, NewPeriod: TDateTime);
      procedure Update(const Anchor: TDateTime; const AnchorKind: TTimeAnchor); override;
   end;

   TMonthRelativeWeekdaysTime = class(TCachedTime)
    strict private
      FWeek: TWeekOrdinal; // 1 = first, 2 = second, etc
      FWeekday: TWeekday;
      FDayTime: TDayTime;
    public
      constructor Create(const NewWeek: TWeekOrdinal; const NewWeekday: TWeekday; const NewDayTime: TDayTime);
      procedure Update(const Anchor: TDateTime; const AnchorKind: TTimeAnchor); override;
   end;

   TMonthTime = class(TCachedTime)
    strict private
      FMonth, FDay: Word;
      FDayTime: TDayTime;
    public
      constructor Create(const NewMonth, NewDay: Word; const NewDayTime: TDayTime);
      procedure Update(const Anchor: TDateTime; const AnchorKind: TTimeAnchor); override;
   end;

   TDeltaTime = class abstract (TMasterTime)
    protected
      FAnchor: TMasterTime;
    public
      constructor Create(const NewAnchor: TMasterTime);
      destructor Destroy(); override;
   end;

   TDeltaDuration = class abstract (TDeltaTime)
    protected
      FDuration: TDuration;
    public
      constructor Create(const NewAnchor: TMasterTime; const NewDuration: TDuration);
      destructor Destroy(); override;
   end;

   // pretend CurrentTime is CurrentTime+Duration, then get the new time, then subtract Duration from the time
   TDeltaBeforeDuration = class(TDeltaDuration)
    public
      procedure Update(const Anchor: TDateTime; const AnchorKind: TTimeAnchor); override;
      function GetTime(): TDateTime; override;
   end;

   // pretend CurrentTime is CurrentTime-Duration, then get the new time, then add Duration to the time
   TDeltaAfterDuration = class(TDeltaDuration)
    public
      procedure Update(const Anchor: TDateTime; const AnchorKind: TTimeAnchor); override;
      function GetTime(): TDateTime; override;
   end;

   TSlaveTime = class (TTime)
    strict private
      FAnchor: TMasterTime;
    protected
      function GetTime(): TDateTime; override;
    public
      constructor Create(const NewAnchorOwner: TDeltaTime);
      procedure Update(const Anchor: TDateTime; const AnchorKind: TTimeAnchor); override;
   end;

implementation

uses
   exceptions, sysutils, dateutils;

class function TDayTime.Create(const NewHour: THour; NewMinute: TMinute): TDayTime;
begin
   Result.Hour := NewHour;
   Result.Minute := NewMinute;
end;

operator + (const A: TDateTime; const B: TDayTime): TDateTime;
begin
   Result := A + (B.Hour * 60 * 60 + B.Minute * 60) * OneSecond;
end;



constructor TDuration.Create(const NewDuration: Cardinal);
begin
   FDuration := NewDuration;
end;


function TMonthDuration.InternalAdd(const Anchor: TDateTime; const Delta: Integer): TDateTime;
var
   Year, Month, Day, MaxDays: Integer;
   DayFrac: Double;
begin
   Year := YearOf(Anchor);
   Month := MonthOf(Anchor);
   Day := DayOf(Anchor);
   DayFrac := Day / DaysInAMonth(Year, Month); {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
   Inc(Month, Delta);
   Assert(Year >= 1899, 'Year is too low! ' + IntToStr(Year));
   Assert(Year < 9999); // arbitrary limit below High(Word)
   if (Month <= 0) then
   begin
      Year := Year - (1+(-Month div MonthsPerYear)); {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
      Month := 12+(Month mod MonthsPerYear); {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
   end
   else
   begin
      Year := Year + ((Month-1) div MonthsPerYear); {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
      Month := ((Month-1) mod MonthsPerYear)+1; {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
   end;
   MaxDays := DaysInAMonth(Year, Month); {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
   if (Day > MaxDays) then
      Day := Trunc(DayFrac * MaxDays); {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
   Result := RecodeDateTime(Anchor, Year, Month, Day, {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
                            RecodeLeaveFieldAsIs, RecodeLeaveFieldAsIs, RecodeLeaveFieldAsIs, RecodeLeaveFieldAsIs);
end;

function TMonthDuration.AddedTo(const Anchor: TDateTime): TDateTime;
begin
   Assert(FDuration < High(Integer));
   Result := InternalAdd(Anchor, +FDuration); {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
end;

function TMonthDuration.SubtractedFrom(const Anchor: TDateTime): TDateTime;
begin
   Assert(FDuration < High(Integer));
   Result := InternalAdd(Anchor, -FDuration); {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
end;


function TSecondDuration.AddedTo(const Anchor: TDateTime): TDateTime;
begin
   Result := Anchor + (FDuration * kScaleFactor);
end;

function TSecondDuration.SubtractedFrom(const Anchor: TDateTime): TDateTime;
begin
   Result := Anchor - (FDuration * kScaleFactor);
end;

function TSecondDuration.AsDateTime(): TDateTime;
begin
   Result := FDuration * kScaleFactor;
end;


function TCachedTime.GetTime(): TDateTime;
begin
   Result := FTime;
end;


constructor TRepeatingTime.Create(const NewZero, NewPeriod: TDateTime);
begin
   inherited Create();
   FZero := NewZero;
   FPeriod := NewPeriod;
end;

procedure TRepeatingTime.Update(const Anchor: TDateTime; const AnchorKind: TTimeAnchor);
var
   ZeroedAnchor, Delta: TDateTime;
begin
   ZeroedAnchor := Anchor - FZero;
   Assert(FPeriod > 0.0);
   Delta := ZeroedAnchor - FPeriod * Trunc(ZeroedAnchor / FPeriod);
   FTime := ZeroedAnchor - Delta;
   if (AnchorKind = taAfter) then
      FTime := FTime + FPeriod;
   FTime := FTime + FZero;
end;


constructor TMonthRelativeWeekdaysTime.Create(const NewWeek: TWeekOrdinal; const NewWeekday: TWeekday; const NewDayTime: TDayTime);
begin
   inherited Create();
   FWeek := NewWeek;
   FWeekday := NewWeekday;
   FDayTime := NewDayTime;
end;

procedure TMonthRelativeWeekdaysTime.Update(const Anchor: TDateTime; const AnchorKind: TTimeAnchor);

   function GetNthDayOfMonth(const Year, Month: Word; const N: TWeekOrdinal; const Weekday: TWeekday; const DayTime: TDayTime): TDateTime;
   var
      StartOfMonth: TDateTime;
      FirstWeekdayOfMonth: TWeekday;
      Day: Integer;
   begin
      Assert(Ord(wdMonday) = DayMonday-1);
      Assert(TWeekday(DayMonday-1) = wdMonday);
      Day := (N-1) * DaysPerWeek + Ord(Weekday) + 1; {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
      StartOfMonth := EncodeDateTime(Year, Month, 1, 0, 0, 0, 0);
      FirstWeekdayOfMonth := TWeekday(DayOfTheWeek(StartOfMonth)-1);
      if (Weekday < FirstWeekdayOfMonth) then
         Inc(Day, DaysPerWeek);
      Dec(Day, Ord(FirstWeekdayOfMonth));
      Assert(Day >= 1);
      if (Day > DaysInAMonth(Year, Month)) then
         Result := kNever
      else
         Result := EncodeDateTime(Year, Month, Day, DayTime.Hour, DayTime.Minute, 0, 0); {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
   end;

var
   Year, Month: Word;
begin
   Year := YearOf(Anchor);
   Month := MonthOf(Anchor);
   FTime := GetNthDayOfMonth(Year, Month, FWeek, FWeekday, FDayTime);
   if (AnchorKind = taBefore) then
   begin
      if ((FTime = kNever) or (FTime > Anchor)) then
      begin
         repeat
            Dec(Month);
            if (Month < 1) then
            begin
               Month := MonthsPerYear;
               Dec(Year);
            end;
            FTime := GetNthDayOfMonth(Year, Month, FWeek, FWeekday, FDayTime);
         until FTime <> kNever;
      end;
   end
   else
   begin
      if ((FTime = kNever) or (FTime <= Anchor)) then
      begin
         repeat
            Inc(Month);
            if (Month > MonthsPerYear) then
            begin
               Month := 1;
               Inc(Year);
            end;
            FTime := GetNthDayOfMonth(Year, Month, FWeek, FWeekday, FDayTime);
         until FTime <> kNever;
      end;
   end;
end;


constructor TMonthTime.Create(const NewMonth, NewDay: Word; const NewDayTime: TDayTime);
begin
   inherited Create();
   Assert(NewMonth >= 1);
   Assert(NewMonth <= 12);
   Assert(NewDay >= 1);
   Assert(NewDay <= DaysInAMonth(1970, NewMonth)); // 1970 is not a leap year
   FMonth := NewMonth;
   FDay := NewDay;
   FDayTime := NewDayTime;
end;

procedure TMonthTime.Update(const Anchor: TDateTime; const AnchorKind: TTimeAnchor);

   function TryForYear(Year: Word): TDateTime;
   begin
      Result := EncodeDateTime(Year, FMonth, FDay, FDayTime.Hour, FDayTime.Minute, 0, 0); // $R-
   end;

var
   Year: Word;
begin
   Year := YearOf(Anchor);
   FTime := TryForYear(Year);
   if (AnchorKind = taBefore) then
   begin
      while (FTime > Anchor) do
      begin
         Dec(Year);
         FTime := EncodeDateTime(Year, FMonth, FDay, FDayTime.Hour, FDayTime.Minute, 0, 0); // $R-
      end;
   end
   else
   begin
      while (FTime <= Anchor) do
      begin
         Inc(Year);
         FTime := EncodeDateTime(Year, FMonth, FDay, FDayTime.Hour, FDayTime.Minute, 0, 0); // $R-
      end;
   end;
end;


constructor TDeltaTime.Create(const NewAnchor: TMasterTime);
begin
   inherited Create();
   FAnchor := NewAnchor;
end;

destructor TDeltaTime.Destroy();
begin
   FAnchor.Free();
   inherited;
end;


constructor TDeltaDuration.Create(const NewAnchor: TMasterTime; const NewDuration: TDuration);
begin
   inherited Create(NewAnchor);
   FDuration := NewDuration;
end;

destructor TDeltaDuration.Destroy();
begin
   FDuration.Free();
   inherited;
end;


procedure TDeltaBeforeDuration.Update(const Anchor: TDateTime; const AnchorKind: TTimeAnchor);
begin
   FAnchor.Update(FDuration.AddedTo(Anchor), AnchorKind);
end;

function TDeltaBeforeDuration.GetTime(): TDateTime;
begin
   Result := FDuration.SubtractedFrom(FAnchor.Time);
end;


procedure TDeltaAfterDuration.Update(const Anchor: TDateTime; const AnchorKind: TTimeAnchor);
begin
   FAnchor.Update(FDuration.SubtractedFrom(Anchor), AnchorKind);
end;

function TDeltaAfterDuration.GetTime(): TDateTime;
begin
   Result := FDuration.AddedTo(FAnchor.Time);
end;


constructor TSlaveTime.Create(const NewAnchorOwner: TDeltaTime);
begin
   inherited Create();
   FAnchor := NewAnchorOwner.FAnchor;
end;

function TSlaveTime.GetTime(): TDateTime;
begin
   Result := FAnchor.GetTime();
end;

procedure TSlaveTime.Update(const Anchor: TDateTime; const AnchorKind: TTimeAnchor);
begin
   // do nothing, the master will be updated by its owner
end;

{$IFDEF DEBUG}
procedure RunMonthDurationTests();
var
   D: TMonthDuration;
begin
   D := TMonthDuration.Create(1);
   Assert(D.AddedTo(EncodeDateTime(2000, 1, 1, 0, 0, 0, 0)) = EncodeDateTime(2000, 2, 1, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 2, 1, 0, 0, 0, 0)) = EncodeDateTime(2000, 3, 1, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 3, 1, 0, 0, 0, 0)) = EncodeDateTime(2000, 4, 1, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 4, 1, 0, 0, 0, 0)) = EncodeDateTime(2000, 5, 1, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 1, 31, 0, 0, 0, 0)) = EncodeDateTime(2000, 2, 29, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 2, 29, 0, 0, 0, 0)) = EncodeDateTime(2000, 3, 29, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 3, 30, 0, 0, 0, 0)) = EncodeDateTime(2000, 4, 30, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 4, 30, 0, 0, 0, 0)) = EncodeDateTime(2000, 5, 30, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2013, 12, 31, 23, 59, 59, 999)) = EncodeDateTime(2014, 1, 31, 23, 59, 59, 999));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 1, 1, 0, 0, 0, 0)) = EncodeDateTime(1999, 12, 1, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 2, 1, 0, 0, 0, 0)) = EncodeDateTime(2000, 1, 1, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 3, 1, 0, 0, 0, 0)) = EncodeDateTime(2000, 2, 1, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 4, 1, 0, 0, 0, 0)) = EncodeDateTime(2000, 3, 1, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 1, 31, 0, 0, 0, 0)) = EncodeDateTime(1999, 12, 31, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 2, 29, 0, 0, 0, 0)) = EncodeDateTime(2000, 1, 29, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 3, 30, 0, 0, 0, 0)) = EncodeDateTime(2000, 2, 28, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 4, 30, 0, 0, 0, 0)) = EncodeDateTime(2000, 3, 30, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2013, 12, 31, 23, 59, 59, 999)) = EncodeDateTime(2013, 11, 30, 23, 59, 59, 999));
   D.Free();
   D := TMonthDuration.Create(6);
   Assert(D.AddedTo(EncodeDateTime(2000, 1, 1, 0, 0, 0, 0)) = EncodeDateTime(2000, 7, 1, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 2, 1, 0, 0, 0, 0)) = EncodeDateTime(2000, 8, 1, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 3, 1, 0, 0, 0, 0)) = EncodeDateTime(2000, 9, 1, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 4, 1, 0, 0, 0, 0)) = EncodeDateTime(2000, 10, 1, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 1, 31, 0, 0, 0, 0)) = EncodeDateTime(2000, 7, 31, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 2, 29, 0, 0, 0, 0)) = EncodeDateTime(2000, 8, 29, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 3, 30, 0, 0, 0, 0)) = EncodeDateTime(2000, 9, 30, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 4, 30, 0, 0, 0, 0)) = EncodeDateTime(2000, 10, 30, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2013, 12, 31, 23, 59, 59, 999)) = EncodeDateTime(2014, 6, 30, 23, 59, 59, 999));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 1, 1, 0, 0, 0, 0)) = EncodeDateTime(1999, 7, 1, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 2, 1, 0, 0, 0, 0)) = EncodeDateTime(1999, 8, 1, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 3, 1, 0, 0, 0, 0)) = EncodeDateTime(1999, 9, 1, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 4, 1, 0, 0, 0, 0)) = EncodeDateTime(1999, 10, 1, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 1, 31, 0, 0, 0, 0)) = EncodeDateTime(1999, 7, 31, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 2, 29, 0, 0, 0, 0)) = EncodeDateTime(1999, 8, 29, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 3, 30, 0, 0, 0, 0)) = EncodeDateTime(1999, 9, 30, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 4, 30, 0, 0, 0, 0)) = EncodeDateTime(1999, 10, 30, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2013, 12, 31, 23, 59, 59, 999)) = EncodeDateTime(2013, 6, 30, 23, 59, 59, 999));
   D.Free();
   D := TMonthDuration.Create(13);
   Assert(D.AddedTo(EncodeDateTime(2000, 1, 1, 0, 0, 0, 0)) = EncodeDateTime(2001, 2, 1, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 2, 1, 0, 0, 0, 0)) = EncodeDateTime(2001, 3, 1, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 3, 1, 0, 0, 0, 0)) = EncodeDateTime(2001, 4, 1, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 4, 1, 0, 0, 0, 0)) = EncodeDateTime(2001, 5, 1, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 1, 31, 0, 0, 0, 0)) = EncodeDateTime(2001, 2, 28, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 2, 29, 0, 0, 0, 0)) = EncodeDateTime(2001, 3, 29, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 3, 30, 0, 0, 0, 0)) = EncodeDateTime(2001, 4, 30, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2000, 4, 30, 0, 0, 0, 0)) = EncodeDateTime(2001, 5, 30, 0, 0, 0, 0));
   Assert(D.AddedTo(EncodeDateTime(2013, 12, 31, 23, 59, 59, 999)) = EncodeDateTime(2015, 1, 31, 23, 59, 59, 999));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 1, 1, 0, 0, 0, 0)) = EncodeDateTime(1998, 12, 1, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 2, 1, 0, 0, 0, 0)) = EncodeDateTime(1999, 1, 1, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 3, 1, 0, 0, 0, 0)) = EncodeDateTime(1999, 2, 1, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 4, 1, 0, 0, 0, 0)) = EncodeDateTime(1999, 3, 1, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 1, 31, 0, 0, 0, 0)) = EncodeDateTime(1998, 12, 31, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 2, 29, 0, 0, 0, 0)) = EncodeDateTime(1999, 1, 29, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 3, 30, 0, 0, 0, 0)) = EncodeDateTime(1999, 2, 27, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2000, 4, 30, 0, 0, 0, 0)) = EncodeDateTime(1999, 3, 30, 0, 0, 0, 0));
   Assert(D.SubtractedFrom(EncodeDateTime(2013, 12, 31, 23, 59, 59, 999)) = EncodeDateTime(2012, 11, 30, 23, 59, 59, 999));
   D.Free();
end;

procedure RunWeekdaysTimeTests();
var
   T: TRepeatingTime;
begin
   // T := TWeekdaysTime.Create(1, wdThursday, EncodeDayTime(13, 28));
   T := TRepeatingTime.Create(EncodeDateTime(2011, 1, 6, 13, 28, 0, 0), 7);
   T.Update(EncodeDateTime(2013, 8, 1, 13, 28, 0, 0), taBefore);
   Assert(T.Time = EncodeDateTime(2013, 8, 1, 13, 28, 0, 0)); // this tests that taBefore means taBeforeOrEquals
   T.Update(EncodeDateTime(2013, 8, 1, 13, 28, 0, 0), taAfter);
   Assert(T.Time = EncodeDateTime(2013, 8, 8, 13, 28, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 7, 18, 36, 12, 0), taBefore);
   Assert(T.Time = EncodeDateTime(2013, 8, 1, 13, 28, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 7, 18, 36, 12, 0), taAfter);
   Assert(T.Time = EncodeDateTime(2013, 8, 8, 13, 28, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 8, 18, 36, 12, 0), taBefore);
   Assert(T.Time = EncodeDateTime(2013, 8, 8, 13, 28, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 8, 18, 36, 12, 0), taAfter);
   Assert(T.Time = EncodeDateTime(2013, 8, 15, 13, 28, 0, 0));
   T.Update(EncodeDateTime(2013, 1, 2, 3, 4, 5, 0), taBefore);
   Assert(T.Time = EncodeDateTime(2012, 12, 27, 13, 28, 0, 0));
   T.Update(EncodeDateTime(2013, 1, 2, 3, 4, 5, 0), taAfter);
   Assert(T.Time = EncodeDateTime(2013, 1, 3, 13, 28, 0, 0));
   T.Free();
   // T := TWeekdaysTime.Create(2, wdSunday, EncodeDayTime(0, 0));
   T := TRepeatingTime.Create(EncodeDateTime(2011, 1, 9, 0, 0, 0, 0), 14);
   T.Update(EncodeDateTime(2013, 8, 7, 1, 36, 12, 0), taBefore);
   Assert(T.Time = EncodeDateTime(2013, 8, 4, 0, 0, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 7, 1, 36, 12, 0), taAfter);
   Assert(T.Time = EncodeDateTime(2013, 8, 18, 0, 0, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 8, 1, 36, 12, 0), taBefore);
   Assert(T.Time = EncodeDateTime(2013, 8, 4, 0, 0, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 8, 1, 36, 12, 0), taAfter);
   Assert(T.Time = EncodeDateTime(2013, 8, 18, 0, 0, 0, 0));
   T.Update(EncodeDateTime(2013, 1, 2, 3, 4, 5, 0), taBefore);
   Assert(T.Time = EncodeDateTime(2012, 12, 23, 0, 0, 0, 0));
   T.Update(EncodeDateTime(2013, 1, 2, 3, 4, 5, 0), taAfter);
   Assert(T.Time = EncodeDateTime(2013, 1, 6, 0, 0, 0, 0));
   T.Free();
end;

procedure RunMonthRelativeWeekdaysTimeTests();
var
   T: TMonthRelativeWeekdaysTime;
begin
   T := TMonthRelativeWeekdaysTime.Create(1, wdMonday, TDayTime.Create(0, 0));
   T.Update(EncodeDateTime(2007, 1, 1, 0, 0, 0, 0), taBefore);
   Assert(T.Time = EncodeDateTime(2007, 1, 1, 0, 0, 0, 0));
   T.Update(EncodeDateTime(2007, 1, 1, 0, 0, 0, 0), taAfter);
   Assert(T.Time = EncodeDateTime(2007, 2, 5, 0, 0, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 7, 0, 0, 0, 0), taBefore);
   Assert(T.Time = EncodeDateTime(2013, 8, 5, 0, 0, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 7, 0, 0, 0, 0), taAfter);
   Assert(T.Time = EncodeDateTime(2013, 9, 2, 0, 0, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 17, 0, 0, 0, 0), taBefore);
   Assert(T.Time = EncodeDateTime(2013, 8, 5, 0, 0, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 17, 0, 0, 0, 0), taAfter);
   Assert(T.Time = EncodeDateTime(2013, 9, 2, 0, 0, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 2, 0, 0, 0, 0), taBefore);
   Assert(T.Time = EncodeDateTime(2013, 7, 1, 0, 0, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 2, 0, 0, 0, 0), taAfter);
   Assert(T.Time = EncodeDateTime(2013, 8, 5, 0, 0, 0, 0));
   T.Free();
   T := TMonthRelativeWeekdaysTime.Create(3, wdSaturday, TDayTime.Create(12, 0));
   T.Update(EncodeDateTime(2007, 1, 1, 0, 0, 0, 0), taBefore);
   Assert(T.Time = EncodeDateTime(2006, 12, 16, 12, 0, 0, 0));
   T.Update(EncodeDateTime(2007, 1, 1, 0, 0, 0, 0), taAfter);
   Assert(T.Time = EncodeDateTime(2007, 1, 20, 12, 0, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 7, 0, 0, 0, 0), taBefore);
   Assert(T.Time = EncodeDateTime(2013, 7, 20, 12, 0, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 7, 0, 0, 0, 0), taAfter);
   Assert(T.Time = EncodeDateTime(2013, 8, 17, 12, 0, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 17, 0, 0, 0, 0), taBefore);
   Assert(T.Time = EncodeDateTime(2013, 7, 20, 12, 0, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 17, 0, 0, 0, 0), taAfter);
   Assert(T.Time = EncodeDateTime(2013, 8, 17, 12, 0, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 2, 0, 0, 0, 0), taBefore);
   Assert(T.Time = EncodeDateTime(2013, 7, 20, 12, 0, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 2, 0, 0, 0, 0), taAfter);
   Assert(T.Time = EncodeDateTime(2013, 8, 17, 12, 0, 0, 0));
   T.Free();
   T := TMonthRelativeWeekdaysTime.Create(5, wdWednesday, TDayTime.Create(8, 9));
   T.Update(EncodeDateTime(2013, 8, 7, 9, 8, 7, 6), taBefore);
   Assert(T.Time = EncodeDateTime(2013, 7, 31, 8, 9, 0, 0));
   T.Update(EncodeDateTime(2013, 8, 7, 9, 8, 7, 6), taAfter);
   Assert(T.Time = EncodeDateTime(2013, 10, 30, 8, 9, 0, 0));
   T.Update(EncodeDateTime(2013, 9, 30, 9, 8, 7, 6), taBefore);
   Assert(T.Time = EncodeDateTime(2013, 7, 31, 8, 9, 0, 0));
   T.Update(EncodeDateTime(2013, 9, 30, 9, 8, 7, 6), taAfter);
   Assert(T.Time = EncodeDateTime(2013, 10, 30, 8, 9, 0, 0));
   T.Update(EncodeDateTime(2013, 10, 31, 9, 8, 7, 6), taBefore);
   Assert(T.Time = EncodeDateTime(2013, 10, 30, 8, 9, 0, 0));
   T.Update(EncodeDateTime(2013, 10, 31, 9, 8, 7, 6), taAfter);
   Assert(T.Time = EncodeDateTime(2014, 1, 29, 8, 9, 0, 0));
   T.Update(EncodeDateTime(2013, 12, 28, 9, 8, 7, 6), taBefore);
   Assert(T.Time = EncodeDateTime(2013, 10, 30, 8, 9, 0, 0));
   T.Update(EncodeDateTime(2013, 12, 28, 9, 8, 7, 6), taAfter);
   Assert(T.Time = EncodeDateTime(2014, 1, 29, 8, 9, 0, 0));
   T.Free();
end;

procedure RunTests();
begin
   RunMonthDurationTests();
   RunWeekdaysTimeTests();
   RunMonthRelativeWeekdaysTimeTests();
end;
{$ENDIF}

initialization
   {$IFDEF DEBUG} RunTests(); {$ENDIF}
end.
