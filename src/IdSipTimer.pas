unit IdSipTimer;

interface

uses
  Classes, IdThread;

type
  TIdSipTimer = class(TIdThread)
  private
    CoarseTiming: Boolean;
    fInterval:    Cardinal;
    fOnTimer:     TNotifyEvent;
    fStart:       TDateTime;
    Resolution:   Cardinal;
  protected
    procedure Run; override;
  public
    constructor Create(CreateSuspended: Boolean = True;
                       CoarseTiming: Boolean = True); reintroduce;

    function  ElapsedTime: TDateTime;
    procedure Reset;

    property Interval: Cardinal     read fInterval write fInterval;
    property OnTimer:  TNotifyEvent read fOnTimer write fOnTimer;
  end;

implementation

uses
  DateUtils, SysUtils;

//******************************************************************************
//* TIdSipTimer                                                                *
//******************************************************************************
//* TIdSipTimer Public methods *************************************************

constructor TIdSipTimer.Create(CreateSuspended: Boolean = True;
                               CoarseTiming: Boolean = True);
begin
  Self.CoarseTiming := CoarseTiming;
  if Self.CoarseTiming then
    Self.Resolution := 50;

  inherited Create(CreateSuspended);
end;

function TIdSipTimer.ElapsedTime: TDateTime;
begin
  Result := Now - Self.fStart
end;

procedure TIdSipTimer.Reset;
begin
  Self.fStart := Now;
end;

//* TIdSipTimer Protected methods **********************************************

procedure TIdSipTimer.Run;
begin
  Self.Reset;
  while not Self.Terminated do begin
    if Self.CoarseTiming then begin
      Sleep(Self.Resolution);

      if (Self.ElapsedTime > (OneMillisecond * Self.Interval)) then begin
        Self.Reset;
        Self.OnTimer(Self);
      end;
    end
    else begin
      Sleep(Self.Interval);
      Self.OnTimer(Self);
    end;
  end;
end;

end.
