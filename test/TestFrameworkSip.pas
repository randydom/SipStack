{
  (c) 2004 Directorate of New Technologies, Royal National Institute for Deaf people (RNID)

  The RNID licence covers this unit. Read the licence at:
      http://www.ictrnid.org.uk/docs/gw/rnid_license.txt

  This unit contains code written by:
    * Frank Shearar
}
unit TestFrameworkSip;

interface

uses
  Classes, IdInterfacedObject, IdObservable, IdRTP, IdSdp, IdSipMessage,
  IdSipCore, IdSipTcpClient, IdSipTcpServer, IdSipTransaction, IdSipTransport,
  IdSocketHandle, SysUtils, TestFrameworkEx;

type
  TIdSipTestResources = class(TObject)
  private
    class function CreateCommonRequest: TIdSipRequest;
  public
    class function CreateBasicRequest: TIdSipRequest;
    class function CreateBasicResponse: TIdSipResponse;
    class function CreateLocalLoopRequest: TIdSipRequest;
    class function CreateLocalLoopResponse: TIdSipResponse;
  end;

  TTestCaseSip = class(TThreadingTestCase)
  public
    procedure CheckEquals(Expected, Received: TIdSipURI; Message: String); overload;
  end;

  TIdSipMockListener = class(TIdInterfacedObject)
  private
    fFailWith: ExceptClass;
  public
    constructor Create; virtual;

    property FailWith: ExceptClass read fFailWith write fFailWith;
  end;

  TIdSipTestDataListener = class(TIdSipMockListener,
                                 IIdRtpDataListener)
  private
    fNewData:    Boolean;
    fNewUdpData: Boolean;
  public
    constructor Create; override;

    procedure OnNewData(Data: TIdRTPPayload;
                        Binding: TIdSocketHandle);
    procedure OnNewUdpData(Data: TStream);

    property NewData:    Boolean read fNewData;
    property NewUdpData: Boolean read fNewUdpData;
  end;

  TIdSipTestMessageListener = class(TIdSipMockListener,
                                    IIdSipMessageListener)
  private
    fException:        Boolean;
    fMalformedMessage: Boolean;
    fReceivedRequest:  Boolean;
    fReceivedResponse: Boolean;

    procedure OnException(E: Exception;
                          const Reason: String);
    procedure OnMalformedMessage(const Msg: String;
                                 const Reason: String);
    procedure OnReceiveRequest(Request: TIdSipRequest;
                               ReceivedFrom: TIdSipConnectionBindings);
    procedure OnReceiveResponse(Response: TIdSipResponse;
                                ReceivedFrom: TIdSipConnectionBindings);
  public
    constructor Create; override;

    property Exception:        Boolean read fException;
    property MalformedMessage: Boolean read fMalformedMessage;
    property ReceivedRequest:  Boolean read fReceivedRequest;
    property ReceivedResponse: Boolean read fReceivedResponse;
  end;

  TIdSipTestObserver = class(TIdSipMockListener,
                             IIdObserver)
  private
    fChanged: Boolean;

    procedure OnChanged(Observed: TObject);
  public
    constructor Create; override;

    property Changed: Boolean read fChanged;
  end;

  TIdSipTestOptionsListener = class(TIdSipMockListener,
                                    IIdSipOptionsListener)
  private
  private
    fAuthenticationChallenge: Boolean;
    fFailure:                 Boolean;
    fPassword:                String;
    fSuccess:                 Boolean;

    procedure OnAuthenticationChallenge(Action: TIdSipAction;
                                        Response: TIdSipResponse;
                                        var Password: String);
    procedure OnFailure(OptionsAgent: TIdSipOutboundOptions;
                        Response: TIdSipResponse;
                        const Reason: String);
    procedure OnSuccess(OptionsAgent: TIdSipOutboundOptions;
                        Response: TIdSipResponse);
  public
    constructor Create; override;

    property AuthenticationChallenge: Boolean read fAuthenticationChallenge;
    property Failure:                 Boolean read fFailure;
    property Success:                 Boolean read fSuccess;
    property Password:                String  read fPassword write fPassword;
  end;

  TIdSipTestRegistrationListener = class(TIdSipMockListener,
                                         IIdSipRegistrationListener)
  private
    fAuthenticationChallenge: Boolean;
    fFailure:                 Boolean;
    fPassword:                String;
    fSuccess:                 Boolean;
  public
    constructor Create; override;

    procedure OnAuthenticationChallenge(Action: TIdSipAction;
                                        Response: TIdSipResponse;
                                        var Password: String);
    procedure OnFailure(RegisterAgent: TIdSipOutboundRegistration;
                        CurrentBindings: TIdSipContacts;
                        const Reason: String);
    procedure OnSuccess(RegisterAgent: TIdSipOutboundRegistration;
                        CurrentBindings: TIdSipContacts);

    property AuthenticationChallenge: Boolean read fAuthenticationChallenge;
    property Failure:                 Boolean read fFailure;
    property Success:                 Boolean read fSuccess;
    property Password:                String  read fPassword write fPassword;
  end;

  TIdSipTestSessionListener = class(TIdSipMockListener,
                                    IIdSipSessionListener)
  private
    fAuthenticationChallenge: Boolean;
    fEndedSession:            Boolean;
    fEstablishedSession:      Boolean;
    fModifiedSession:         Boolean;
    fNewSession:              Boolean;
  public
    constructor Create; override;

    procedure OnAuthenticationChallenge(Action: TIdSipAction;
                                        Response: TIdSipResponse;
                                        var Password: String);
    procedure OnEndedSession(Session: TIdSipSession;
                             const Reason: String);
    procedure OnEstablishedSession(Session: TIdSipSession);
    procedure OnModifiedSession(Session: TIdSipSession;
                                Invite: TIdSipRequest);
    procedure OnNewSession(Session: TIdSipSession);

    property AuthenticationChallenge: Boolean read fAuthenticationChallenge;
    property EndedSession:            Boolean read fEndedSession;
    property EstablishedSession:      Boolean read fEstablishedSession;
    property ModifiedSession:         Boolean read fModifiedSession;
    property NewSession:              Boolean read fNewSession;
  end;

  TIdSipTestTransactionListener = class(TIdSipMockListener,
                                        IIdSipTransactionListener)
  private
    fFailReason:       String;
    fReceivedRequest:  Boolean;
    fReceivedResponse: Boolean;
    fTerminated:       Boolean;

    procedure OnFail(Transaction: TIdSipTransaction;
                     const Reason: String);
    procedure OnReceiveRequest(Request: TIdSipRequest;
                               Transaction: TIdSipTransaction;
                               Transport: TIdSipTransport);
    procedure OnReceiveResponse(Response: TIdSipResponse;
                                Transaction: TIdSipTransaction;
                                Transport: TIdSipTransport);
    procedure OnTerminated(Transaction: TIdSipTransaction);
  public
    constructor Create; override;

    property FailReason:       String  read fFailReason;
    property ReceivedRequest:  Boolean read fReceivedRequest;
    property ReceivedResponse: Boolean read fReceivedResponse;
    property Terminated:       Boolean read fTerminated;
  end;

  TIdSipTestTransportListener = class(TIdSipMockListener,
                                      IIdSipTransportListener)
  private
    fException:        Boolean;
    fReceivedRequest:  Boolean;
    fReceivedResponse: Boolean;
    fRejectedMessage:  Boolean;

    procedure OnException(E: Exception;
                          const Reason: String);
    procedure OnReceiveRequest(Request: TIdSipRequest;
                               Transport: TIdSipTransport);
    procedure OnReceiveResponse(Response: TIdSipResponse;
                                Transport: TIdSipTransport);
    procedure OnRejectedMessage(const Msg: String;
                                const Reason: String);
  public
    constructor Create; override;

    property Exception:        Boolean read fException;
    property ReceivedRequest:  Boolean read fReceivedRequest;
    property ReceivedResponse: Boolean read fReceivedResponse;
    property RejectedMessage:  Boolean read fRejectedMessage;
  end;

  TIdSipTestTransportSendingListener = class(TIdSipMockListener,
                                             IIdSipTransportSendingListener)
  private
    fSentRequest:  Boolean;
    fSentResponse: Boolean;

    procedure OnSendRequest(Request: TIdSipRequest;
                            Transport: TIdSipTransport);
    procedure OnSendResponse(Response: TIdSipResponse;
                             Transport: TIdSipTransport);
  public
    constructor Create; override;

    property SentRequest:  Boolean read fSentRequest;
    property SentResponse: Boolean read fSentResponse;
  end;

  TIdSipTestUnhandledMessageListener = class(TIdSipMockListener,
                                             IIdSipUnhandledMessageListener)
  private
    fReceivedRequest:           Boolean;
    fReceivedResponse:          Boolean;
    fReceivedUnhandledRequest:  Boolean;
    fReceivedUnhandledResponse: Boolean;


    procedure OnReceiveRequest(Request: TIdSipRequest;
                               Receiver: TIdSipTransport);
    procedure OnReceiveResponse(Response: TIdSipResponse;
                                Receiver: TIdSipTransport);
    procedure OnReceiveUnhandledRequest(Request: TIdSipRequest;
                                        Receiver: TIdSipTransport);
    procedure OnReceiveUnhandledResponse(Response: TIdSipResponse;
                                         Receiver: TIdSipTransport);
  public
    constructor Create; override;

    property ReceivedRequest:           Boolean read fReceivedRequest;
    property ReceivedResponse:          Boolean read fReceivedResponse;
    property ReceivedUnhandledRequest:  Boolean read fReceivedUnhandledRequest;
    property ReceivedUnhandledResponse: Boolean read fReceivedUnhandledResponse;
  end;

  TIdSipTestUserAgentListener = class(TIdSipMockListener,
                                      IIdSipUserAgentListener)
  private
    fDroppedUnmatchedResponse: Boolean;
    fInboundCall:              Boolean;

    procedure OnDroppedUnmatchedResponse(Response: TIdSipResponse;
                                         Receiver: TIdSipTransport);
    procedure OnInboundCall(Session: TIdSipInboundSession);
  public
    constructor Create; override;

    property DroppedUnmatchedResponse: Boolean read fDroppedUnmatchedResponse write fDroppedUnmatchedResponse;
    property InboundCall:              Boolean read fInboundCall write fInboundCall;
  end;

  // constants used in tests
const
  CertPasswd     = 'test';
  DefaultTimeout = 1000;
  RootCert       = '..\etc\cacert.pem';
  ServerCert     = '..\etc\newcert.pem';
  ServerKey      = '..\etc\newkey.pem';

implementation

uses
  IdSipConsts;

//******************************************************************************
//* TIdSipTestResources                                                        *
//******************************************************************************
//* TIdSipTestResources Public methods *****************************************

class function TIdSipTestResources.CreateBasicRequest: TIdSipRequest;
begin
  Result := Self.CreateCommonRequest;
  Result.RequestUri.Uri := 'sip:wintermute@tessier-ashpool.co.luna';
  Result.AddHeader(ViaHeaderFull).Value := 'SIP/2.0/TCP gw1.leo-ix.org;branch=z9hG4bK776asdhds';
  Result.ToHeader.Value := 'Wintermute <sip:wintermute@tessier-ashpool.co.luna>;tag=1928301775';
  Result.From.Value := 'Case <sip:case@fried.neurons.org>;tag=1928301774';
  Result.AddHeader(ContactHeaderFull).Value := 'sip:wintermute@tessier-ashpool.co.luna';
end;

class function TIdSipTestResources.CreateBasicResponse: TIdSipResponse;
var
  Request: TIdSipRequest;
begin
  Request := Self.CreateBasicRequest;
  try
    Result := TIdSipResponse.InResponseTo(Request, SIPBusyHere);
    Result.AddHeader(ContactHeaderFull).Value := 'Wintermute <sip:wintermute@tessier-ashpool.co.luna>';
  finally
    Request.Free;
  end;
end;

class function TIdSipTestResources.CreateLocalLoopRequest: TIdSipRequest;
begin
  Result := Self.CreateCommonRequest;
  Result.RequestUri.Uri := 'sip:franks@127.0.0.1';
  Result.AddHeader(ViaHeaderFull).Value := 'SIP/2.0/TCP 127.0.0.1;branch=z9hG4bK776asdhds';
  Result.ToHeader.Value := 'Wintermute <sip:franks@127.0.0.1>';
  Result.From.Value := 'Case <sip:franks@127.0.0.1>;tag=1928301774';
  Result.AddHeader(ContactHeaderFull).Value := 'sip:franks@127.0.0.1';
end;

class function TIdSipTestResources.CreateLocalLoopResponse: TIdSipResponse;
var
  Request: TIdSipRequest;
begin
  Request := Self.CreateLocalLoopRequest;
  try
    Result := TIdSipResponse.InResponseTo(Request, SIPBusyHere);
  finally
    Request.Free;
  end;
end;

//* TIdSipTestResources Private methods ****************************************

class function TIdSipTestResources.CreateCommonRequest: TIdSipRequest;
begin
  Result := TIdSipRequest.Create;
  Result.Method := MethodInvite;
  Result.ContentType := 'text/plain';
  Result.Body := 'I am a message. Hear me roar!';
  Result.ContentLength := Length(Result.Body);
  Result.MaxForwards := 70;
  Result.SIPVersion := SipVersion;
  Result.CallID := 'a84b4c76e66710@gw1.leo-ix.org';
  Result.CSeq.Method := Result.Method;
  Result.CSeq.SequenceNo := 314159;
end;

//******************************************************************************
//* TTestCaseSip                                                               *
//******************************************************************************
//* TTestCaseSip Public methods ************************************************

procedure TTestCaseSip.CheckEquals(Expected, Received: TIdSipURI; Message: String);
begin
  CheckEquals(Expected.URI, Received.URI, Message);
end;

//******************************************************************************
//* TIdSipMockListener
//******************************************************************************
//* TIdSipMockListener Public methods ******************************************

constructor TIdSipMockListener.Create;
begin
  Self.FailWith := nil;
end;

//******************************************************************************
//* TIdSipTestDataListener                                                     *
//******************************************************************************
//* TIdSipTestDataListener Public methods **************************************

constructor TIdSipTestDataListener.Create;
begin
  inherited Create;

  Self.fNewData    := false;
  Self.fNewUdpData := false;
end;

procedure TIdSipTestDataListener.OnNewData(Data: TIdRTPPayload;
                                           Binding: TIdSocketHandle);
begin
  Self.fNewData := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestDataListener.OnNewData');
end;

procedure TIdSipTestDataListener.OnNewUdpData(Data: TStream);
begin
  Self.fNewUdpData := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestDataListener.OnNewUdpData');
end;

//******************************************************************************
//* TIdSipTestMessageListener                                                  *
//******************************************************************************
//* TIdSipTestMessageListener Public methods ***********************************

constructor TIdSipTestMessageListener.Create;
begin
  inherited Create;

  Self.fException        := false;
  Self.fMalformedMessage := false;
  Self.fReceivedRequest  := false;
  Self.fReceivedResponse := false;
end;

//* TIdSipTestMessageListener Private methods **********************************

procedure TIdSipTestMessageListener.OnException(E: Exception;
                                                const Reason: String);
begin
  Self.fException := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestMessageListener.OnException');
end;

procedure TIdSipTestMessageListener.OnMalformedMessage(const Msg: String;
                                                       const Reason: String);
begin
  Self.fMalformedMessage := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestMessageListener.OnMalformedMessage');
end;

procedure TIdSipTestMessageListener.OnReceiveRequest(Request: TIdSipRequest;
                                                     ReceivedFrom: TIdSipConnectionBindings);
begin
  Self.fReceivedRequest := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestMessageListener.OnReceiveRequest');
end;

procedure TIdSipTestMessageListener.OnReceiveResponse(Response: TIdSipResponse;
                                                      ReceivedFrom: TIdSipConnectionBindings);
begin
  Self.fReceivedResponse := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestMessageListener.OnReceiveResponse');
end;

//******************************************************************************
//* TIdSipTestObserver                                                         *
//******************************************************************************
//* TIdSipTestObserver Public methods ******************************************

constructor TIdSipTestObserver.Create;
begin
  inherited Create;

  Self.fChanged := false;
end;

//* TIdSipTestObserver Private methods *****************************************

procedure TIdSipTestObserver.OnChanged(Observed: TObject);
begin
  Self.fChanged := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestObserver.OnChanged');
end;

//******************************************************************************
//* TIdSipTestOptionsListener                                                  *
//******************************************************************************
//* TIdSipTestOptionsListener Public methods ***********************************

constructor TIdSipTestOptionsListener.Create;
begin
  inherited Create;

  Self.fAuthenticationChallenge := false;
  Self.fFailure                 := false;
  Self.fSuccess                 := false;
end;

//* TIdSipTestOptionsListener Private methods **********************************

procedure TIdSipTestOptionsListener.OnAuthenticationChallenge(Action: TIdSipAction;
                                                              Response: TIdSipResponse;
                                                              var Password: String);
begin
  Self.fAuthenticationChallenge := true;
  Password := Self.Password;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestOptionsListener.OnAuthenticationChallenge');
end;

procedure TIdSipTestOptionsListener.OnFailure(OptionsAgent: TIdSipOutboundOptions;
                                              Response: TIdSipResponse;
                                              const Reason: String);
begin
  Self.fFailure := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestOptionsListener.OnFailure');
end;

procedure TIdSipTestOptionsListener.OnSuccess(OptionsAgent: TIdSipOutboundOptions;
                                              Response: TIdSipResponse);
begin
  Self.fSuccess := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestOptionsListener.OnSuccess');
end;

//******************************************************************************
//* TIdSipTestRegistrationListener                                             *
//******************************************************************************
//* TIdSipTestRegistrationListener Public methods ******************************

constructor TIdSipTestRegistrationListener.Create;
begin
  inherited Create;

  Self.fAuthenticationChallenge := false;
  Self.fFailure                 := false;
  Self.fSuccess                 := false;
end;

//* TIdSipRegistrationListener Private methods *********************************

procedure TIdSipTestRegistrationListener.OnAuthenticationChallenge(Action: TIdSipAction;
                                                                   Response: TIdSipResponse;
                                                                   var Password: String);
begin
  Self.fAuthenticationChallenge := true;
  Password := Self.Password;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestRegistrationListener.OnAuthenticationChallenge');
end;

procedure TIdSipTestRegistrationListener.OnFailure(RegisterAgent: TIdSipOutboundRegistration;
                                                   CurrentBindings: TIdSipContacts;
                                                   const Reason: String);
begin
  Self.fFailure := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestRegistrationListener.OnFailure');
end;

procedure TIdSipTestRegistrationListener.OnSuccess(RegisterAgent: TIdSipOutboundRegistration;
                                                   CurrentBindings: TIdSipContacts);
begin
  Self.fSuccess := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestRegistrationListener.OnSuccess');
end;

//******************************************************************************
//* TIdSipTestSessionListener                                                  *
//******************************************************************************
//* TIdSipTestSessionListener Public methods ***********************************

constructor TIdSipTestSessionListener.Create;
begin
  inherited Create;

  Self.fAuthenticationChallenge := true;
  Self.fEndedSession            := false;
  Self.fEstablishedSession      := false;
  Self.fModifiedSession         := false;
  Self.fNewSession              := false;
end;

procedure TIdSipTestSessionListener.OnAuthenticationChallenge(Action: TIdSipAction;
                                                              Response: TIdSipResponse;
                                                              var Password: String);
begin
  Self.fAuthenticationChallenge := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestSessionListener.OnAuthenticationChallenge');
end;

procedure TIdSipTestSessionListener.OnEndedSession(Session: TIdSipSession;
                                                   const Reason: String);
begin
  Self.fEndedSession := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestSessionListener.OnEndedSession');
end;

procedure TIdSipTestSessionListener.OnEstablishedSession(Session: TIdSipSession);
begin
  Self.fEstablishedSession := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestSessionListener.OnEstablishedSession');
end;

procedure TIdSipTestSessionListener.OnModifiedSession(Session: TIdSipSession;
                                                      Invite: TIdSipRequest);
begin
  Self.fModifiedSession := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestSessionListener.OnModifiedSession');
end;

procedure TIdSipTestSessionListener.OnNewSession(Session: TIdSipSession);
begin
  Self.fNewSession := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestSessionListener.OnNewSession');
end;

//******************************************************************************
//* TIdSipTestTransactionListener                                              *
//******************************************************************************
//* TIdSipTestTransactionListener Public methods *******************************

constructor TIdSipTestTransactionListener.Create;
begin
  inherited Create;

  Self.fFailReason       := '';
  Self.fReceivedRequest  := false;
  Self.fReceivedResponse := false;
  Self.fTerminated       := false;
end;

//* TIdSipTestTransactionListener Private methods ******************************

procedure TIdSipTestTransactionListener.OnFail(Transaction: TIdSipTransaction;
                                               const Reason: String);
begin
  Self.fFailReason := Reason;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestTransactionListener.OnFail');
end;

procedure TIdSipTestTransactionListener.OnReceiveRequest(Request: TIdSipRequest;
                                                         Transaction: TIdSipTransaction;
                                                         Transport: TIdSipTransport);
begin
  Self.fReceivedRequest := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestTransactionListener.OnReceiveRequest');
end;

procedure TIdSipTestTransactionListener.OnReceiveResponse(Response: TIdSipResponse;
                                                          Transaction: TIdSipTransaction;
                                                          Transport: TIdSipTransport);
begin
  Self.fReceivedResponse := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestTransactionListener.OnReceiveResponse');
end;

procedure TIdSipTestTransactionListener.OnTerminated(Transaction: TIdSipTransaction);
begin
  Self.fTerminated := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestTransactionListener.OnTerminated');
end;

//******************************************************************************
//* TIdSipTestTransportListener                                                *
//******************************************************************************
//* TIdSipTestTransportListener Public methods *********************************

constructor TIdSipTestTransportListener.Create;
begin
  inherited Create;

  Self.fException        := false;
  Self.fReceivedRequest  := false;
  Self.fReceivedResponse := false;
  Self.fRejectedMessage  := false;
end;

//* TIdSipTestTransportListener Private methods ********************************

procedure TIdSipTestTransportListener.OnException(E: Exception;
                                                  const Reason: String);
begin
  Self.fException := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestTransportListener.OnException');
end;

procedure TIdSipTestTransportListener.OnReceiveRequest(Request: TIdSipRequest;
                                                       Transport: TIdSipTransport);
begin
  Self.fReceivedRequest := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestTransportListener.OnReceiveRequest');
end;

procedure TIdSipTestTransportListener.OnReceiveResponse(Response: TIdSipResponse;
                                                        Transport: TIdSipTransport);
begin
  Self.fReceivedResponse := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestTransportListener.OnReceiveResponse');
end;

procedure TIdSipTestTransportListener.OnRejectedMessage(const Msg: String;
                                                        const Reason: String);
begin
  Self.fRejectedMessage := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestTransportListener.OnRejectedMessage');
end;

//******************************************************************************
//* TIdSipTestTransportSendingListener                                         *
//******************************************************************************
//* TIdSipTestTransportSendingListener Public methods **************************

constructor TIdSipTestTransportSendingListener.Create;
begin
  inherited Create;

  Self.fSentRequest      := false;
  Self.fSentResponse     := false;
end;

//* TIdSipTestTransportSendingListener Private methods *************************


procedure TIdSipTestTransportSendingListener.OnSendRequest(Request: TIdSipRequest;
                                                           Transport: TIdSipTransport);
begin
  Self.fSentRequest := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestTransportListener.OnSendRequest');
end;

procedure TIdSipTestTransportSendingListener.OnSendResponse(Response: TIdSipResponse;
                                                            Transport: TIdSipTransport);
begin
  Self.fSentResponse := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestTransportListener.OnSendResponse');
end;

//******************************************************************************
//* TIdSipTestUnhandledMessageListener                                         *
//******************************************************************************
//* TIdSipTestUnhandledMessageListener Public methods **************************

constructor TIdSipTestUnhandledMessageListener.Create;
begin
  inherited Create;

  fReceivedRequest           := false;
  fReceivedResponse          := false;
  fReceivedUnhandledRequest  := false;
  fReceivedUnhandledResponse := false;
end;

//* TIdSipTestUnhandledMessageListener Private methods *************************

procedure TIdSipTestUnhandledMessageListener.OnReceiveRequest(Request: TIdSipRequest;
                                                              Receiver: TIdSipTransport);
begin
  fReceivedRequest := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestUnhandledMessageListener.OnReceiveRequest');
end;

procedure TIdSipTestUnhandledMessageListener.OnReceiveResponse(Response: TIdSipResponse;
                                                               Receiver: TIdSipTransport);
begin
  fReceivedResponse := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestUnhandledMessageListener.OnReceiveResponse');
end;

procedure TIdSipTestUnhandledMessageListener.OnReceiveUnhandledRequest(Request: TIdSipRequest;
                                                                       Receiver: TIdSipTransport);
begin
  fReceivedUnhandledRequest := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestUnhandledMessageListener.OnReceiveUnhandledRequest');
end;

procedure TIdSipTestUnhandledMessageListener.OnReceiveUnhandledResponse(Response: TIdSipResponse;
                                                                        Receiver: TIdSipTransport);
begin
  fReceivedUnhandledResponse := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestUnhandledMessageListener.OnReceiveUnhandledResponse');
end;

//******************************************************************************
//* TIdSipTestUserAgentListener                                                *
//******************************************************************************
//* TIdSipTestUserAgentListener Public methods *********************************

constructor TIdSipTestUserAgentListener.Create;
begin
  inherited Create;

  fDroppedUnmatchedResponse := false;
  fInboundCall              := false;
end;

//* TIdSipTestUserAgentListener Private methods ********************************

procedure TIdSipTestUserAgentListener.OnDroppedUnmatchedResponse(Response: TIdSipResponse;
                                                                 Receiver: TIdSipTransport);
begin
  fDroppedUnmatchedResponse := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestUnhandledMessageListener.OnDroppedUnmatchedResponse');
end;

procedure TIdSipTestUserAgentListener.OnInboundCall(Session: TIdSipInboundSession);
begin
  fInboundCall := true;

  if Assigned(Self.FailWith) then
    raise Self.FailWith.Create('TIdSipTestUnhandledMessageListener.OnInboundCall');
end;

end.
