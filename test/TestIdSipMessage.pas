unit TestIdSipMessage;

interface

uses
  IdSipHeaders, IdSipMessage, TestFramework, TestFrameworkEx;

type
  TestTIdSipMessage = class(TExtendedTestCase)
  protected
    Message: TIdSipMessage;
  public
    procedure TearDown; override;
  published
    procedure TestLastHop;
    procedure TestReadBody;
    procedure TestSetCallID;
    procedure TestSetContentLength;
    procedure TestSetContentType;
    procedure TestSetCSeq;
    procedure TestSetFrom;
    procedure TestSetMaxForwards;
    procedure TestSetSipVersion;
    procedure TestSetTo;
  end;

  TestTIdSipRequest = class(TestTIdSipMessage)
  private
    Request: TIdSipRequest;
  public
    procedure SetUp; override;
  published
    procedure TestAssign;
    procedure TestAssignBad;
    procedure TestAsString;
    procedure TestHasSipsUri;
    procedure TestIsAck;
    procedure TestIsInvite;
    procedure TestIsRequest;
    procedure TestSetPath;
  end;

  TestTIdSipResponse = class(TestTIdSipMessage)
  private
    Response: TIdSipResponse;
  public
    procedure SetUp; override;
  published
    procedure TestAssign;
    procedure TestAssignBad;
    procedure TestAsString;
    procedure TestIsFinal;
    procedure TestIsProvisional;
    procedure TestIsRequest;
  end;

implementation

uses
  Classes, IdSipConsts, SysUtils, TestMessages;

function Suite: ITestSuite;
begin
  Result := TTestSuite.Create('IdSipMessage tests (Messages)');

  Result.AddTest(TestTIdSipRequest.Suite);
  Result.AddTest(TestTIdSipResponse.Suite);
end;

//******************************************************************************
//* TestTIdSipMessage                                                          *
//******************************************************************************
//* TestTIdSipMessage Public methods *******************************************

procedure TestTIdSipMessage.TearDown;
begin
  Self.Message.Free;

  inherited TearDown;
end;

//* TestTIdSipMessage Published methods ****************************************

procedure TestTIdSipMessage.TestLastHop;
begin
  CheckNull(Self.Message.LastHop, 'Unexpected return for empty path');

  Self.Message.Headers.Add(ViaHeaderFull);
  Check(Self.Message.LastHop = Self.Message.Path.LastHop, 'Unexpected return');
end;

procedure TestTIdSipMessage.TestReadBody;
var
  Len: Integer;
  S:   String;
  Str: TStringStream;
begin
  Self.Message.ContentLength := 8;

  Str := TStringStream.Create('Negotium perambuians in tenebris');
  try
    Self.Message.ReadBody(Str);
    CheckEquals('Negotium', Self.Message.Body, 'Body');

    Len := Length(' perambuians in tenebris');
    SetLength(S, Len);
    Str.Read(S[1], Len);
    CheckEquals(' perambuians in tenebris', S, 'Unread bits of the stream');
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipMessage.TestSetCallID;
begin
  Self.Message.CallID := '999';

  Self.Message.CallID := '42';
  CheckEquals('42', Self.Message.CallID, 'Call-ID not set');
end;

procedure TestTIdSipMessage.TestSetContentLength;
begin
  Self.Message.ContentLength := 999;

  Self.Message.ContentLength := 42;
  CheckEquals(42, Self.Message.ContentLength, 'Content-Length not set');
end;

procedure TestTIdSipMessage.TestSetContentType;
begin
  Self.Message.ContentType := 'text/plain';

  Self.Message.ContentType := 'text/t140';
  CheckEquals('text/t140', Self.Message.ContentType, 'Content-Type not set');
end;

procedure TestTIdSipMessage.TestSetCSeq;
var
  C: TIdSipCSeqHeader;
begin
  C := TIdSipCSeqHeader.Create;
  try
    C.Value := '314159 INVITE';

    Self.Message.CSeq := C;

    Check(Self.Message.CSeq.IsEqualTo(C), 'CSeq not set');
  finally
    C.Free;
  end;
end;

procedure TestTIdSipMessage.TestSetFrom;
var
  From: TIdSipFromHeader;
begin
  Self.Message.From.Value := 'Wintermute <sip:wintermute@tessier-ashpool.co.lu>';

  From := TIdSipFromHeader.Create;
  try
    From.Value := 'Case <sip:case@fried.neurons.org>';

    Self.Message.From := From;

    CheckEquals(From.Value, Self.Message.From.Value, 'From value not set');
  finally
    From.Free;
  end;
end;

procedure TestTIdSipMessage.TestSetMaxForwards;
var
  OrigMaxForwards: Byte;
begin
  OrigMaxForwards := Self.Message.MaxForwards;

  Self.Message.MaxForwards := Self.Message.MaxForwards + 1;

  CheckEquals(OrigMaxForwards + 1, Self.Message.MaxForwards, 'Max-Forwards not set');
end;

procedure TestTIdSipMessage.TestSetSipVersion;
begin
  Self.Message.SIPVersion := 'SIP/2.0';

  Self.Message.SIPVersion := 'SIP/7.7';
  CheckEquals('SIP/7.7', Self.Message.SipVersion, 'SipVersion not set');
end;

procedure TestTIdSipMessage.TestSetTo;
var
  ToHeader: TIdSipToHeader;
begin
  Self.Message.ToHeader.Value := 'Wintermute <sip:wintermute@tessier-ashpool.co.lu>';

  ToHeader := TIdSipToHeader.Create;
  try
    ToHeader.Value := 'Case <sip:case@fried.neurons.org>';

    Self.Message.ToHeader := ToHeader;

    CheckEquals(ToHeader.Value, Self.Message.ToHeader.Value, 'To value not set');
  finally
    ToHeader.Free;
  end;
end;

//******************************************************************************
//* TestTIdSipRequest                                                          *
//******************************************************************************
//* TestTIdSipRequest Public methods *******************************************

procedure TestTIdSipRequest.SetUp;
begin
  inherited SetUp;

  Self.Message := TIdSipRequest.Create;
  Self.Request := Self.Message as TIdSipRequest;
end;

//* TestTIdSipRequest Published methods ****************************************

procedure TestTIdSipRequest.TestAssign;
var
  R: TIdSipRequest;
  I: Integer;
begin
  R := TIdSipRequest.Create;
  try
    R.SIPVersion := 'SIP/1.5';
    R.Method := 'NewMethod';
    R.RequestUri := 'sip:wintermute@tessier-ashpool.co.lu';
    R.Headers.Add(ViaHeaderFull).Value := 'SIP/2.0/TCP gw1.leo-ix.org;branch=z9hG4bK776asdhds';
    R.ContentLength := 5;
    R.Body := 'hello';

    Self.Request.Assign(R);
    CheckEquals(R.SIPVersion,    Self.Request.SipVersion,    'SIP-Version');
    CheckEquals(R.Method,        Self.Request.Method,        'Method');
    CheckEquals(R.RequestUri,    Self.Request.RequestUri,    'Request-URI');
    CheckEquals(R.Headers.Count, Self.Request.Headers.Count, 'Header count');

    for I := 0 to R.Headers.Count - 1 do
      CheckEquals(R.Headers.Items[0].Value,
                  Self.Request.Headers.Items[0].Value,
                  'Header ' + IntToStr(I));
  finally
    R.Free;
  end;
end;

procedure TestTIdSipRequest.TestAssignBad;
var
  P: TPersistent;
begin
  P := TPersistent.Create;
  try
    try
      Request.Assign(P);
      Fail('Failed to bail out assigning a TPersistent to a TIdSipRequest');
    except
      on EConvertError do;
    end;
  finally
    P.Free;
  end;
end;

procedure TestTIdSipRequest.TestAsString;
var
  Expected: TStrings;
  Received: TStrings;
  Parser:   TIdSipParser;
  Str:      TStringStream;
  Hop:      TIdSipViaHeader;
begin
  Request.Method                       := 'INVITE';
  Request.RequestUri                   := 'sip:wintermute@tessier-ashpool.co.lu';
  Request.SIPVersion                   := SIPVersion;
  Hop := Request.Headers.Add(ViaHeaderFull) as TIdSipViaHeader;
  Hop.Value                            := 'SIP/2.0/TCP gw1.leo-ix.org;branch=z9hG4bK776asdhds';
  Request.MaxForwards                  := 70;

  Request.Headers.Add('To').Value           := 'Wintermute <sip:wintermute@tessier-ashpool.co.lu>;tag=1928301775';
  Request.Headers.Add('From').Value         := 'Case <sip:case@fried.neurons.org>;tag=1928301774';
  Request.CallID                            := 'a84b4c76e66710@gw1.leo-ix.org';
  Request.Headers.Add('CSeq').Value         := '314159 INVITE';
  Request.Headers.Add('Contact').Value      := '<sip:wintermute@tessier-ashpool.co.lu>';
  Request.Headers.Add('Content-Type').Value := 'text/plain';

  Request.ContentLength                := 29;
  Request.Body                         := 'I am a message. Hear me roar!';

  Expected := TStringList.Create;
  try
    Expected.Text := BasicRequest;

    Received := TStringList.Create;
    try
      Received.Text := Request.AsString;

      CheckEquals(Expected, Received, '');

      Parser := TIdSipParser.Create;
      try
        Str := TStringStream.Create(Received.Text);
        try
          Parser.Source := Str;

          Parser.ParseRequest(Request);
        finally
          Str.Free;
        end;
      finally
        Parser.Free;
      end;
    finally
      Received.Free;
    end;
  finally
    Expected.Free;
  end;
end;

procedure TestTIdSipRequest.TestHasSipsUri;
begin
  Self.Request.RequestUri := 'tel://999';
  Check(not Self.Request.HasSipsUri, 'tel URI');

  Self.Request.RequestUri := 'sip:wintermute@tessier-ashpool.co.lu';
  Check(not Self.Request.HasSipsUri, 'sip URI');

  Self.Request.RequestUri := 'sips:wintermute@tessier-ashpool.co.lu';
  Check(Self.Request.HasSipsUri, 'sips URI');
end;

procedure TestTIdSipRequest.TestIsAck;
begin
  Self.Request.Method := MethodAck;
  Check(Self.Request.IsAck, MethodAck);

  Self.Request.Method := MethodBye;
  Check(not Self.Request.IsAck, MethodBye);

  Self.Request.Method := MethodCancel;
  Check(not Self.Request.IsAck, MethodCancel);

  Self.Request.Method := MethodInvite;
  Check(not Self.Request.IsAck, MethodInvite);

  Self.Request.Method := MethodOptions;
  Check(not Self.Request.IsAck, MethodOptions);

  Self.Request.Method := MethodRegister;
  Check(not Self.Request.IsAck, MethodRegister);

  Self.Request.Method := 'XXX';
  Check(not Self.Request.IsAck, 'XXX');
end;

procedure TestTIdSipRequest.TestIsInvite;
begin
  Self.Request.Method := MethodAck;
  Check(not Self.Request.IsInvite, MethodAck);

  Self.Request.Method := MethodBye;
  Check(not Self.Request.IsInvite, MethodBye);

  Self.Request.Method := MethodCancel;
  Check(not Self.Request.IsInvite, MethodCancel);

  Self.Request.Method := MethodInvite;
  Check(Self.Request.IsInvite, MethodInvite);

  Self.Request.Method := MethodOptions;
  Check(not Self.Request.IsInvite, MethodOptions);

  Self.Request.Method := MethodRegister;
  Check(not Self.Request.IsInvite, MethodRegister);

  Self.Request.Method := 'XXX';
  Check(not Self.Request.IsInvite, 'XXX');
end;

procedure TestTIdSipRequest.TestIsRequest;
begin
  Check(Self.Request.IsRequest, 'IsRequest');
end;

procedure TestTIdSipRequest.TestSetPath;
var
  H: TIdSipHeaders;
  P: TIdSipViaPath;
begin
  Self.Request.Headers.Add(ViaHeaderFull).Value := 'SIP/2.0/TCP gw1.leo-ix.org;branch=z9hG4bK776asdhds';

  H := TIdSipHeaders.Create;
  try
    H.Add(ViaHeaderFull).Value := 'SIP/2.0/TCP gw2.leo-ix.org;branch=z9hG4bK776asdhds';
    H.Add(ViaHeaderFull).Value := 'SIP/2.0/TCP gw3.leo-ix.org;branch=z9hG4bK776asdhds';
    P := TIdSipViaPath.Create(H);
    try
      Self.Request.Path := P;

      Check(Self.Request.Path.IsEqualTo(P), 'Path not correctly set');
    finally
      P.Free;
    end;
  finally
    H.Free;
  end;
end;

//******************************************************************************
//* TestTIdSipResponse                                                         *
//******************************************************************************
//* TestTIdSipResponse Public methods ******************************************

procedure TestTIdSipResponse.SetUp;
begin
  inherited SetUp;

  Self.Message := TIdSipResponse.Create;
  Self.Response := Self.Message as TIdSipResponse;
end;

//* TestTIdSipResponse Published methods ***************************************

procedure TestTIdSipResponse.TestAssign;
var
  R: TIdSipResponse;
  I: Integer;
begin
  R := TIdSipResponse.Create;
  try
    R.SIPVersion := 'SIP/1.5';
    R.StatusCode := 101;
    R.StatusText := 'Hehaeha I''ll get back to you';
    R.Headers.Add(ViaHeaderFull).Value := 'SIP/2.0/TCP gw1.leo-ix.org;branch=z9hG4bK776asdhds';
    R.ContentLength := 5;
    R.Body := 'hello';

    Self.Response.Assign(R);
    CheckEquals(R.SIPVersion,    Self.Response.SipVersion,    'SIP-Version');
    CheckEquals(R.StatusCode,    Self.Response.StatusCode,    'Status-Code');
    CheckEquals(R.StatusText,    Self.Response.StatusText,    'Status-Text');
    CheckEquals(R.Headers.Count, Self.Response.Headers.Count, 'Header count');

    for I := 0 to R.Headers.Count - 1 do
      CheckEquals(R.Headers.Items[0].Value,
                  Self.Response.Headers.Items[0].Value,
                  'Header ' + IntToStr(I));
  finally
    R.Free;
  end;
end;

procedure TestTIdSipResponse.TestAssignBad;
var
  P: TPersistent;
begin
  P := TPersistent.Create;
  try
    try
      Response.Assign(P);
      Fail('Failed to bail out assigning a TObject to a TIdSipResponse');
    except
      on EConvertError do;
    end;
  finally
    P.Free;
  end;
end;

procedure TestTIdSipResponse.TestAsString;
var
  Expected: TStrings;
  Received: TStrings;
  Parser:   TIdSipParser;
  Str:      TStringStream;
begin
  Response.StatusCode                        := 486;
  Response.StatusText                        := 'Busy Here';
  Response.SIPVersion                        := SIPVersion;
  Response.Headers.Add('Via').Value          := 'SIP/2.0/TCP gw1.leo-ix.org;branch=z9hG4bK776asdhds';
  Response.MaxForwards                       := 70;
  Response.Headers.Add('To').Value           := 'Wintermute <sip:wintermute@tessier-ashpool.co.lu>;tag=1928301775';
  Response.Headers.Add('From').Value         := 'Case <sip:case@fried.neurons.org>;tag=1928301774';
  Response.CallID                            := 'a84b4c76e66710@gw1.leo-ix.org';
  Response.Headers.Add('CSeq').Value         := '314159 INVITE';
  Response.Headers.Add('Contact').Value      := '<sip:wintermute@tessier-ashpool.co.lu>';
  Response.Headers.Add('Content-Type').Value := 'text/plain';
  Response.ContentLength                     := 29;
  Response.Body                              := 'I am a message. Hear me roar!';

  Expected := TStringList.Create;
  try
    Expected.Text := BasicResponse;

    Received := TStringList.Create;
    try
      Received.Text := Response.AsString;

      CheckEquals(Expected, Received, '');

      Parser := TIdSipParser.Create;
      try
        Str := TStringStream.Create(Received.Text);
        try
          Parser.Source := Str;

          Parser.ParseResponse(Response);
        finally
          Str.Free;
        end;
      finally
        Parser.Free;
      end;
    finally
      Received.Free;
    end;
  finally
    Expected.Free;
  end;
end;

procedure TestTIdSipResponse.TestIsFinal;
begin
  Self.Response.StatusCode := SIPTrying;
  Check(not Self.Response.IsFinal, IntToStr(Self.Response.StatusCode));

  Self.Response.StatusCode := SIPOK;
  Check(Self.Response.IsFinal, IntToStr(Self.Response.StatusCode));

  Self.Response.StatusCode := SIPMultipleChoices;
  Check(Self.Response.IsFinal, IntToStr(Self.Response.StatusCode));

  Self.Response.StatusCode := SIPBadRequest;
  Check(Self.Response.IsFinal, IntToStr(Self.Response.StatusCode));

  Self.Response.StatusCode := SIPInternalServerError;
  Check(Self.Response.IsFinal, IntToStr(Self.Response.StatusCode));

  Self.Response.StatusCode := SIPBusyEverywhere;
  Check(Self.Response.IsFinal, IntToStr(Self.Response.StatusCode));
end;

procedure TestTIdSipResponse.TestIsProvisional;
begin
  Self.Response.StatusCode := SIPTrying;
  Check(Self.Response.IsProvisional, IntToStr(Self.Response.StatusCode));

  Self.Response.StatusCode := SIPOK;
  Check(not Self.Response.IsProvisional, IntToStr(Self.Response.StatusCode));

  Self.Response.StatusCode := SIPMultipleChoices;
  Check(not Self.Response.IsProvisional, IntToStr(Self.Response.StatusCode));

  Self.Response.StatusCode := SIPBadRequest;
  Check(not Self.Response.IsProvisional, IntToStr(Self.Response.StatusCode));

  Self.Response.StatusCode := SIPInternalServerError;
  Check(not Self.Response.IsProvisional, IntToStr(Self.Response.StatusCode));

  Self.Response.StatusCode := SIPBusyEverywhere;
  Check(not Self.Response.IsProvisional, IntToStr(Self.Response.StatusCode));
end;

procedure TestTIdSipResponse.TestIsRequest;
begin
  Check(not Self.Response.IsRequest, 'IsRequest');
end;

initialization
  RegisterTest('SIP Messages', Suite);
end.
