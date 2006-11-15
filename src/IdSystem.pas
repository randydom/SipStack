{
  (c) 2004 Directorate of New Technologies, Royal National Institute for Deaf people (RNID)

  The RNID licence covers this unit. Read the licence at:
      http://www.ictrnid.org.uk/docs/gw/rnid_license.txt

  This unit contains code written by:
    * Frank Shearar
    * Guido Gybels
}
unit IdSystem;

interface

uses
  Classes;

{ This unit contains all platform-specific (i.e., OS calls) that you might need
  to call. Currently only the Windows (2000 and more recent) platform is
  implemented.
}

function  ConstructUUID: String;
function  GetCurrentProcessId: Cardinal;
function  GetFullUserName: WideString;
function  GetHostName: String;
function  GetTickCount: Cardinal;
function  GetTickDiff(const OldTickCount, NewTickCount : Cardinal): Cardinal;
function  GetUserName: WideString;
function  LocalAddress: String;
procedure LocalAddresses(IPs: TStrings);
function  RoutableIP: String;
procedure DefineLocalAddress(AAddress: String); {Allows you to use a specified IP address}

implementation

uses
  IdSimpleParser, IdGlobal, IdStack, IdUDPServer, SysUtils, Windows, Winsock;

{See commentary for LocalAddress for an explanation of this variable}
var
  idLocalAddress: String;

function ConstructUUID: String;
var
  NewGuid: TGUID;
begin
  CreateGUID(NewGuid);
  Result := Lowercase(WithoutFirstAndLastChars(GUIDToString(NewGuid)));
end;

function GetCurrentProcessId: Cardinal;
begin
  Result := Windows.GetCurrentProcessId;
end;

function GetFullUserName: WideString;
begin
  // Really, we want to get something like "John Random" rather than "JohnR" or
  // "JRandom".
  Result := GetUserName;
end;

function GetHostName: String;
var
  Buf:       PAnsiChar;
  ErrorCode: Integer;
  Len:       Integer;
  RC:        Integer;
  Unused:    TWSAData;
begin
  // Return the full name of this machine.

  Len := 1000;
  GetMem(Buf, Len*Sizeof(AnsiChar));
  try
    RC := Winsock.gethostname(Buf, Len);

    if (RC = 0) then
      Result := Buf
    else begin
      ErrorCode := WSAGetLastError;
      raise Exception.Create('GetHostName: ' + IntToStr(ErrorCode) + '(' + SysErrorMessage(ErrorCode) + ')');
    end;
  finally
    FreeMem(Buf);
  end;
end;

function GetTickCount: Cardinal;
var
  Count, Frequency: Int64;
  Temp:             Int64;
begin
  if QueryPerformanceFrequency(Frequency) then
    if QueryPerformanceCounter(Count) then begin
       Temp := Trunc((Count * 1000)/ Frequency);

       if (Temp > High(Cardinal)) then
         Result := Temp - High(Cardinal)
       else
         Result := Temp
    end
    else
       Result:= Windows.GetTickCount
  else
    Result:= Windows.GetTickCount;
end;

function GetTickDiff(const OldTickCount, NewTickCount : Cardinal): Cardinal;
begin
  // Remember: tick counts can roll over

  if (NewTickCount >= OldTickCount) then begin
    Result := NewTickCount - OldTickCount
  end
  else
    Result := High(Cardinal) - OldTickCount + NewTickCount;
end;

function GetUserName: WideString;
var
  Buf: PWideChar;
  Len: Cardinal;
begin
  Len := 1000;
  GetMem(Buf, Len);
  try
    if not GetUserNameW(Buf, Len) then
      raise Exception.Create(SysErrorMessage(GetLastError));

    Result := Buf;
  finally
    FreeMem(Buf);
  end;
end;

{Normally, the local machine address is automatically discovered when using the "LocalAddress" function.
 In certain scenarios, however, you might want to preselect which local address to use. This applies
 for instance to multihomed scenarios as well as cases where you wish to signal a public IP address
 in stead of the local address.
 If you want to override the automatic address discovery, call "DefineLocalAddress" with the address
 you wish to use. Subsequent calls to LocalAddress will then always return this address. To restore
 automatic discovery, call DefineLocalAddress with a zero length string or with "0.0.0.0" as the
 address.}
function LocalAddress: String;
var
  UnusedServer: TIdUDPServer;
begin
  if (Length(idLocalAddress)=0) or (idLocalAddress='0.0.0.0') then
  begin
    if not Assigned(GStack) then begin
      UnusedServer := TIdUDPServer.Create(nil);
      try
        Result := GStack.LocalAddress;
      finally
        UnusedServer.Free;
      end;
    end
    else
      Result := GStack.LocalAddress;
  end else
    Result:=idLocalAddress;
end;

procedure LocalAddresses(IPs: TStrings);
var
  UnusedServer: TIdUDPServer;
begin
  IPs.Clear;

  if not Assigned(GStack) then begin
    UnusedServer := TIdUDPServer.Create(nil);
    try
      IPs.AddStrings(GStack.LocalAddresses);
    finally
      UnusedServer.Free;
    end;
  end
  else
    IPs.AddStrings(GStack.LocalAddresses);
end;

function RoutableIP: String;
begin
  // If you have a machine sitting behind a Network Address Translator (NAT),
  // your LocalAddress will probably return an IP in one of the private address
  // ranges (e.g., in the 192.168.0.0/24 subnet). These addresses are by
  // definition not reachable by machines on the public Internet. This function
  // returns an address that other people can use to make calls to you.

  Result := '41.241.49.94';
end;

{See commentary for LocalAddress for an explanation of this function}
procedure DefineLocalAddress(AAddress: String);
begin
  idLocalAddress:=AAddress;
end;

initialization
  idLocalAddress:='0.0.0.0';

end.

