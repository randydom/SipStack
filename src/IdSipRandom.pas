unit IdSipRandom;

interface

type
  TIdSipRandomNumber = class(TObject)
  public
    class function Next: Cardinal; overload; virtual;
    class function Next(Max: Cardinal): Cardinal; overload;
  end;

implementation

class function TIdSipRandomNumber.Next: Cardinal;
begin
  // TODO: This is CRAP. When we have time we shall implement Schneier's
  // Fortuna PRNG, as described in "Practical Cryptography".
  Result := Random(MaxInt);
end;

class function TIdSipRandomNumber.Next(Max: Cardinal): Cardinal;
begin
  repeat
    Result := Self.Next;
  until Result <= Max;

  Assert(Result <= Max, 'Result > Max');
end;

initialization
  Randomize;
end.
