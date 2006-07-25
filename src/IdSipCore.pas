{
  (c) 2004 Directorate of New Technologies, Royal National Institute for Deaf people (RNID)

  The RNID licence covers this unit. Read the licence at:
      http://www.ictrnid.org.uk/docs/gw/rnid_license.txt

  This unit contains code written by:
    * Frank Shearar
}
unit IdSipCore;

// Some overarching principles followed in this implementation of a SIP/2.0
// (RFC 3261) stack:
// * We rely on short-circuited evaluation of Boolean expressions.
// * We manually manage the lifetime of all objects. We do NOT use reference
//   counting for objects that implement interfaces.
// * We use Value Objects when possible.
// * If an object A receives some object B that it expects to store as data
//   then A must store a COPY of B. Typical objects are: TIdSipURI,
//   TIdSipDialogID, TIdSipMessage.
// * Each layer has references to the layers beneath it. We try to make each
//   layer aware of ONLY the layer immediately below it, but we can't always do
//   that. We NEVER let a lower layer know about layers above it. Thus, the
//   transport layer DOES NOT know about transactions, etc.
// * We propogate messages up the stack using Events or Listeners, and method
//   calls to propogate messages down the stack. We give preference to the more
//   flexible Listeners.
// * We avoid typecasting as much as possible by using polymorphism and, in
//   certain situations where (type-based) polymorphism can't cut it, the
//   Visitor pattern.
// * TObjectLists almost always manage the lifetime of the objects they contain.
// * One single thread forms the core of the stack: a TIdTimerQueue. Each
//   transport has its own thread that does nothing but receive messages and
//   add them to the timer queue for processing, and sending messages to the
//   network.
// * Threads belong to the process in which they run. It doesn't really make
//   sense for us to refer to a class that instantiates a thread as the thread's
//   owner, so
//   (a) all threads should FreeOnTerminate, and
//   (b) all classes that instantiate threads should not free the threads, but
//      just Terminate (and possibly nil any references to the threads).

{
CODE FROM THE TRANSACTION LAYER TO ASSIMILATE

procedure TestTIdSipTransactionDispatcher.TestSendVeryBigMessageWithTcpFailure;
var
  TcpResponseCount: Cardinal;
  UdpResponseCount: Cardinal;
begin
  Self.MockTransport.TransportType := TcpTransport;
  Self.MockTransport.FailWith      := EIdConnectTimeout;

  TcpResponseCount := Self.MockTcpTransport.SentResponseCount;
  UdpResponseCount := Self.MockUdpTransport.SentResponseCount;

  while (Length(Self.Response200.AsString) < MaximumUDPMessageSize) do
    Self.Response200.AddHeader(SubjectHeaderFull).Value := 'In R''lyeh dead Cthulhu lies dreaming';

  Self.Response200.LastHop.Transport := Self.MockUdpTransport.TransportType;
  Self.D.SendToTransport(Self.Response200);

  Check(UdpResponseCount < Self.MockUdpTransport.SentResponseCount,
        'No response sent down UDP');
  CheckEquals(TcpResponseCount, Self.MockTcpTransport.SentResponseCount,
              'TCP response was sent');
end;
}
interface

uses
  Classes, Contnrs, IdBaseThread, IdSipDialog, IdSipDialogID, IdException,
  IdInterfacedObject, IdNotification, IdObservable, IdSipAuthentication,
  IdSipLocator, IdSipMessage, IdSipTransaction, IdSipTransport, IdTimerQueue,
  SysUtils;

const
  SipStackVersion = '0.5.2';

type
  TIdSipAction = class;
  TIdSipActionClass = class of TIdSipAction;

  // I provide a protocol for generic Actions.
  // OnAuthenticationChallenge right now isn't used: it's here in anticipation
  // of a rewrite of the stack's authentication mechanism.
  IIdSipActionListener = interface
    ['{C3255325-A52E-46FF-9C21-478880FB350A}']
    procedure OnAuthenticationChallenge(Action: TIdSipAction;
                                        Challenge: TIdSipResponse);
    procedure OnNetworkFailure(Action: TIdSipAction;
                               ErrorCode: Cardinal;
                               const Reason: String);
  end;

  // In OnSuccess we use a TIdSipMessage because, for instance,
  // TIdSipInboundInvite succeeds when it receives an ACK.
  IIdSipOwnedActionListener = interface(IIdSipActionListener)
    ['{801E7678-473F-4904-8BEE-C1B7D603D2CA}']
    procedure OnFailure(Action: TIdSipAction;
                        Response: TIdSipResponse;
                        const Reason: String);
    procedure OnRedirect(Action: TIdSipAction;
                         Redirect: TIdSipResponse);
    procedure OnSuccess(Action: TIdSipAction;
                        Msg: TIdSipMessage);
  end;

  // Some Actions will fail because the remote party took too long to respond.
  // In these cases the Response parameter will be nil.
  // Some Actions (currently only INVITEs) will succeed upon receipt of a
  // request (an ACK); hence, OnSuccess contains a TIdSipMessage parameter
  // instead of the expected TIdSipResponse parameter.
  IIdSipOutboundActionListener = interface(IIdSipOwnedActionListener)
    ['{7A285B4A-FC96-467C-A1C9-B95DCCD61101}']
    procedure OnFailure(Action: TIdSipAction;
                        Response: TIdSipResponse);
    procedure OnSuccess(Action: TIdSipAction;
                        Msg: TIdSipMessage);
  end;

  TIdSipOutboundOptions = class;

  IIdSipOptionsListener = interface(IIdSipActionListener)
    ['{3F2ED4DF-4854-4255-B156-F4581AEAEDA3}']
    procedure OnResponse(OptionsAgent: TIdSipOutboundOptions;
                         Response: TIdSipResponse);
  end;

  TIdSipAbstractCore = class;

  IIdSipTransactionUserListener = interface
    ['{0AE275B0-4C4D-470B-821B-7F88719E822D}']
    procedure OnDroppedUnmatchedMessage(UserAgent: TIdSipAbstractCore;
                                        Message: TIdSipMessage;
                                        Receiver: TIdSipTransport);
  end;

  // I represent a closure that contains some block of code involving an Action.
  // I also represent the null action closure.
  TIdSipActionClosure = class(TObject)
  public
    procedure Execute(Action: TIdSipAction); virtual;
  end;

  TIdSipActionClosureClass = class of TIdSipActionClosure;

  // I maintain a list of Actions. You may query me for various statistics, as
  // well as do things to particular actions.
  // The FindFooAndPerform methods require some explanation. The Event
  // parameter Data property must point to a copy of a TIdSipRequest.
  // FindFooAndPerform will destroy the Request.
  TIdSipActions = class(TObject)
  private
    Actions:  TObjectList;
    Observed: TIdObservable;

    function  ActionAt(Index: Integer): TIdSipAction;
    function  FindAction(Msg: TIdSipMessage; ClientAction: Boolean): TIdSipAction; overload;
    function  FindAction(const ActionID: String): TIdSipAction; overload;
  public
    constructor Create;
    destructor  Destroy; override;

    function  Add(Action: TIdSipAction): TIdSipAction;
    procedure AddObserver(const Listener: IIdObserver);
    function  AddOutboundAction(UserAgent: TIdSipAbstractCore;
                                ActionType: TIdSipActionClass): TIdSipAction;
    procedure CleanOutTerminatedActions;
    function  Count: Integer;
    function  CountOf(const MethodName: String): Integer;
    procedure FindActionAndPerform(const ID: String;
                                   Block: TIdSipActionClosure);
    procedure FindActionAndPerformOr(const ID: String;
                                     FoundBlock: TIdSipActionClosure;
                                     NotFoundBlock: TIdSipActionClosure);
    function  FindActionForGruu(const LocalGruu: String): TIdSipAction;
    function  InviteCount: Integer;
    function  OptionsCount: Integer;
    procedure Perform(Msg: TIdSipMessage; Block: TIdSipActionClosure; ClientAction: Boolean);
    function  RegistrationCount: Integer;
    procedure RemoveObserver(const Listener: IIdObserver);
    function  SessionCount: Integer;
    procedure TerminateAllActions;
  end;

  // I represent an event that will execute a block (BlockType) on an action in
  // a list of actions.
  TIdSipActionsWait = class(TIdSipMessageWait)
  private
    fActionID:  String;
    fActions:   TIdSipActions;
    fBlockType: TIdSipActionClosureClass;
  public
    procedure Trigger; override;

    property Actions:   TIdSipActions            read fActions write fActions;
    property BlockType: TIdSipActionClosureClass read fBlockType write fBlockType;
    property ActionID: String read fActionID write fActionID;
  end;

  TIdActionWait = class(TIdWait)
  private
    fAction: TIdSipAction;
  public
    property Action: TIdSipAction read fAction write fAction;
  end;

  // I represent the (possibly deferred) execution of something my Action needs
  // done. That is, when you invoke my Trigger, I call Action.Send.
  TIdSipActionSendWait = class(TIdActionWait)
  public
    procedure Trigger; override;
  end;

  TIdSipActionTerminateWait = class(TIdActionWait)
  public
    procedure Trigger; override;
  end;

  TIdSipActionsWaitClass = class of TIdSipActionsWait;

  // I represent a closure that takes a message that we couldn't send, and
  // matches it to the Action that sent it. That Action can then try resend
  // the message, if appropriate.
  TIdSipActionNetworkFailure = class(TIdSipActionClosure)
  private
    fError:         Exception;
    fFailedMessage: TIdSipMessage;
    fReason:        String;
  public
    procedure Execute(Action: TIdSipAction); override;

    property FailedMessage: TIdSipMessage read fFailedMessage write fFailedMessage;
    property Error:         Exception     read fError write fError;
    property Reason:        String        read fReason write fReason;
  end;

  // I represent a closure that a UserAgent uses to, for instance, process a
  // request or response.
  TIdUserAgentClosure = class(TIdSipActionClosure)
  private
    fReceiver:  TIdSipTransport;
    fRequest:   TIdSipRequest;
    fUserAgent: TIdSipAbstractCore;
  public
    property Receiver:  TIdSipTransport    read fReceiver write fReceiver;
    property Request:   TIdSipRequest      read fRequest write fRequest;
    property UserAgent: TIdSipAbstractCore read fUserAgent write fUserAgent;
  end;

  // I give my Request to the Action or create a new Action to which I give the
  // Request. I also drop an unmatched ACK, and respond with 481 Call Leg/
  // Transaction Does Not Exist as the case may be.
  TIdSipUserAgentActOnRequest = class(TIdUserAgentClosure)
  public
    procedure Execute(Action: TIdSipAction); override;
  end;

  // I give the affected Action my Response, or drop the (unmatched) response.
  TIdSipUserAgentActOnResponse = class(TIdUserAgentClosure)
  private
    fResponse: TIdSipResponse;
  public
    procedure Execute(Action: TIdSipAction); override;

    property Response: TIdSipResponse read fResponse write fResponse;
  end;

  TIdSipMessageModule = class;
  TIdSipMessageModuleClass = class of TIdSipMessageModule;

  TIdSipUserAgentReaction = Cardinal;

  // I (usually) represent a human being in the SIP network. I:
  // * inform any listeners when new sessions become established, modified or
  //   terminated;
  // * allow my users to make outgoing "calls";
  // * clean up established Sessions
  //
  // I provide the canonical place to reject messages that have correct syntax
  // but that we don't or can't accept. This includes unsupported SIP versions,
  // unrecognised methods, etc.
  //
  // TODO: there's redundance with this Hostname, and the Hostnames of the
  // transports attached to this core. It's not clear how to set up the
  // hostnames and bindings of the stack.
  TIdSipAbstractCore = class(TIdInterfacedObject,
                             IIdObserver,
                             IIdSipTransactionDispatcherListener)
  private
    fActions:                TIdSipActions;
    fAllowedContentTypeList: TStrings;
    fAllowedLanguageList:    TStrings;
    fAllowedSchemeList:      TStrings;
    fAuthenticator:          TIdSipAbstractAuthenticator;
    fContact:                TIdSipContactHeader;
    fDispatcher:             TIdSipTransactionDispatcher;
    fFrom:                   TIdSipFromHeader;
    fGruu:                   TIdSipContactHeader;
    fHostName:               String;
    fInstanceID:             String;
    fKeyring:                TIdKeyRing;
    fLocator:                TIdSipAbstractLocator;
    fRealm:                  String;
    fRequireAuthentication:  Boolean;
    fTimer:                  TIdTimerQueue;
    fUseGruu:                Boolean;
    fUserAgentName:          String;
    Modules:                 TObjectList;
    NullModule:              TIdSipMessageModule;
    Observed:                TIdObservable;

    procedure AddModuleSpecificHeaders(OutboundMessage: TIdSipMessage);
    procedure CollectAllowedExtensions(ExtensionList: TStrings);
    function  ConvertToHeader(ValueList: TStrings): String;
    function  CreateRequestHandler(Request: TIdSipRequest;
                                   Receiver: TIdSipTransport): TIdSipUserAgentActOnRequest;
    function  CreateResponseHandler(Response: TIdSipResponse;
                                    Receiver: TIdSipTransport): TIdSipUserAgentActOnResponse;
    function  DefaultFrom: String;
    function  DefaultHostName: String;
    function  DefaultUserAgent: String;
    procedure MaybeChangeTransport(Msg: TIdSipMessage);
    function  ModuleAt(Index: Integer): TIdSipMessageModule;
    procedure NotifyModulesOfFree;
    procedure OnChanged(Observed: TObject);
    procedure OnReceiveRequest(Request: TIdSipRequest;
                               Receiver: TIdSipTransport); virtual;
    procedure OnReceiveResponse(Response: TIdSipResponse;
                                Receiver: TIdSipTransport); virtual;
    procedure OnTransportException(FailedMessage: TIdSipMessage;
                                   Error: Exception;
                                   const Reason: String); virtual;
    procedure RejectBadAuthorization(Request: TIdSipRequest);
    procedure RejectMethodNotAllowed(Request: TIdSipRequest);
    procedure RejectRequestBadExtension(Request: TIdSipRequest);
    procedure RejectRequestMethodNotSupported(Request: TIdSipRequest);
    procedure RejectUnsupportedSipVersion(Request: TIdSipRequest);
    procedure SetContact(Value: TIdSipContactHeader);
    procedure SetDispatcher(Value: TIdSipTransactionDispatcher);
    procedure SetFrom(Value: TIdSipFromHeader);
    procedure SetGruu(Value: TIdSipContactHeader);
    procedure SetInstanceID(Value: String);
    procedure SetRealm(const Value: String);
  protected
    procedure ActOnRequest(Request: TIdSipRequest;
                           Receiver: TIdSipTransport); virtual;
    procedure ActOnResponse(Response: TIdSipResponse;
                            Receiver: TIdSipTransport); virtual;
    function  CreateActionsClosure(ClosureType: TIdSipActionsWaitClass;
                                   Msg: TIdSipMessage): TIdSipActionsWait;
    function  GetUseGruu: Boolean; virtual;
    function  ListHasUnknownValue(Request: TIdSipRequest;
                                  ValueList: TStrings;
                                  const HeaderName: String): Boolean;
    procedure NotifyOfChange;
    procedure NotifyOfDroppedMessage(Message: TIdSipMessage;
                                     Receiver: TIdSipTransport); virtual;
    procedure PrepareResponse(Response: TIdSipResponse;
                              Request: TIdSipRequest);
    procedure RejectRequest(Reaction: TIdSipUserAgentReaction;
                            Request: TIdSipRequest);
    procedure RejectRequestUnauthorized(Request: TIdSipRequest);
    procedure SetAuthenticator(Value: TIdSipAbstractAuthenticator); virtual;
    procedure SetUseGruu(Value: Boolean); virtual;
    function  WillAcceptRequest(Request: TIdSipRequest): TIdSipUserAgentReaction; virtual;
    function  WillAcceptResponse(Response: TIdSipResponse): TIdSipUserAgentReaction; virtual;

    property AllowedContentTypeList: TStrings read fAllowedContentTypeList;
    property AllowedLanguageList:    TStrings read fAllowedLanguageList;
    property AllowedSchemeList:      TStrings read fAllowedSchemeList;
  public
    constructor Create; virtual;
    destructor  Destroy; override;

    function  AddAction(Action: TIdSipAction): TIdSipAction;
    procedure AddAllowedLanguage(const LanguageID: String);
    procedure AddAllowedScheme(const Scheme: String);
    function  AddInboundAction(Request: TIdSipRequest;
                               UsingSecureTransport: Boolean): TIdSipAction;
    procedure AddLocalHeaders(OutboundRequest: TIdSipRequest); virtual;
    function  AddModule(ModuleType: TIdSipMessageModuleClass): TIdSipMessageModule;
    procedure AddObserver(const Listener: IIdObserver);
    function  AddOutboundAction(ActionType: TIdSipActionClass): TIdSipAction;
    function  AllowedContentTypes: String;
    function  AllowedEncodings: String;
    function  AllowedExtensions: String;
    function  AllowedLanguages: String;
    function  AllowedMethods(RequestUri: TIdSipUri): String;
    function  AllowedSchemes: String;
    function  Authenticate(Request: TIdSipRequest): Boolean;
    function  CountOf(const MethodName: String): Integer;
    function  CreateChallengeResponse(Request: TIdSipRequest): TIdSipResponse;
    function  CreateChallengeResponseAsUserAgent(Request: TIdSipRequest): TIdSipResponse;
    function  CreateRedirectedRequest(OriginalRequest: TIdSipRequest;
                                      Contact: TIdSipAddressHeader): TIdSipRequest;
    function  CreateRequest(const Method: String;
                            Dest: TIdSipAddressHeader): TIdSipRequest; overload;
    function  CreateRequest(const Method: String;
                            Dialog: TIdSipDialog): TIdSipRequest; overload;
    function  CreateResponse(Request: TIdSipRequest;
                             ResponseCode: Cardinal): TIdSipResponse;
    function  FindActionForGruu(const LocalGruu: String): TIdSipAction;
    procedure FindServersFor(Request: TIdSipRequest;
                             Result: TIdSipLocations); overload;
    procedure FindServersFor(Response: TIdSipResponse;
                             Result: TIdSipLocations); overload;
    function  HasUnknownContentEncoding(Request: TIdSipRequest): Boolean;
    function  HasUnknownContentLanguage(Request: TIdSipRequest): Boolean;
    function  HasUnsupportedExtension(Msg: TIdSipMessage): Boolean;
    function  IsExtensionAllowed(const Extension: String): Boolean;
    function  IsMethodAllowed(RequestUri: TIdSipUri;
                              const Method: String): Boolean;
    function  IsMethodSupported(const Method: String): Boolean;
    function  IsSchemeAllowed(const Scheme: String): Boolean;
    function  KnownMethods: String;
    function  ModuleFor(Request: TIdSipRequest): TIdSipMessageModule; overload;
    function  ModuleFor(const Method: String): TIdSipMessageModule; overload;
    function  ModuleFor(ModuleType: TIdSipMessageModuleClass): TIdSipMessageModule; overload;
    function  NextBranch: String;
    function  NextCallID: String;
    function  NextGrid: String;
    function  NextInitialSequenceNo: Cardinal;
    function  NextNonce: String;
    function  NextTag: String;
    function  OptionsCount: Integer;
    function  QueryOptions(Server: TIdSipAddressHeader): TIdSipOutboundOptions;
    procedure RemoveModule(ModuleType: TIdSipMessageModuleClass);
    procedure RemoveObserver(const Listener: IIdObserver);
    function  RequiresUnsupportedExtension(Request: TIdSipRequest): Boolean;
    function  ResponseForInvite: Cardinal; virtual;
    procedure ReturnResponse(Request: TIdSipRequest;
                             Reason: Cardinal);
    procedure ScheduleEvent(BlockType: TIdSipActionClosureClass;
                            WaitTime: Cardinal;
                            Copy: TIdSipMessage;
                            const ActionID: String); overload;
    procedure ScheduleEvent(Event: TNotifyEvent;
                            WaitTime: Cardinal;
                            Msg: TIdSipMessage); overload;
    procedure ScheduleEvent(WaitTime: Cardinal;
                            Wait: TIdWait); overload;
    procedure SendRequest(Request: TIdSipRequest;
                          Dest: TIdSipLocation);
    procedure SendResponse(Response: TIdSipResponse);
    procedure StartAllTransports;
    procedure StopAllTransports;
    function  Username: String;
    function  UsesModule(ModuleType: TIdSipMessageModuleClass): Boolean;

    // Move to UserAgent:
    procedure TerminateAllCalls; // move to InviteModule
    function  UsingDefaultContact: Boolean;
    function  UsingDefaultFrom: Boolean;

    property Actions:               TIdSipActions               read fActions;
    property Authenticator:         TIdSipAbstractAuthenticator read fAuthenticator write SetAuthenticator;
    property Contact:               TIdSipContactHeader         read fContact write SetContact;
    property Dispatcher:            TIdSipTransactionDispatcher read fDispatcher write SetDispatcher;
    property From:                  TIdSipFromHeader            read fFrom write SetFrom;
    property Gruu:                  TIdSipContactHeader         read fGruu write SetGruu;
    property HostName:              String                      read fHostName write fHostName;
    property InstanceID:            String                      read fInstanceID write SetInstanceID;
    property Keyring:               TIdKeyRing                  read fKeyring;
    property Locator:               TIdSipAbstractLocator       read fLocator write fLocator;
    property Realm:                 String                      read fRealm write SetRealm;
    property RequireAuthentication: Boolean                     read fRequireAuthentication write fRequireAuthentication;
    property Timer:                 TIdTimerQueue               read fTimer write fTimer;
    property UseGruu:               Boolean                     read GetUseGruu write SetUseGruu;
    property UserAgentName:         String                      read fUserAgentName write fUserAgentName;
  end;

  IIdSipMessageModuleListener = interface
    ['{4C5192D0-6AE1-4F59-A31A-FDB3D30BC617}']
  end;

  // I and my subclasses represent chunks of Transaction-User Core
  // functionality: the ability to process REGISTERs, say, or OPTIONS, or the
  // requests involved with establishing a call.
  TIdSipMessageModule = class(TObject)
  private
    fUserAgent: TIdSipAbstractCore;

    function  ConvertToHeader(ValueList: TStrings): String;
    procedure RejectRequestUnknownAccept(Request: TIdSipRequest);
    procedure RejectRequestUnknownContentEncoding(Request: TIdSipRequest);
    procedure RejectRequestUnknownContentLanguage(Request: TIdSipRequest);
    procedure RejectRequestUnknownContentType(Request: TIdSipRequest);
  protected
    AcceptsMethodsList:     TStringList;
    AllowedContentTypeList: TStrings;
    Listeners:              TIdNotificationList;

    function  AcceptRequest(Request: TIdSipRequest;
                            UsingSecureTransport: Boolean): TIdSipAction; virtual;
    function  ListHasUnknownValue(Request: TIdSipRequest;
                                  ValueList: TStrings;
                                  const HeaderName: String): Boolean;
    procedure RejectBadRequest(Request: TIdSipRequest;
                               const Reason: String);
    procedure RejectRequest(Reaction: TIdSipUserAgentReaction;
                            Request: TIdSipRequest); virtual;
    procedure ReturnResponse(Request: TIdSipRequest;
                             Reason: Cardinal);
    function  WillAcceptRequest(Request: TIdSipRequest): TIdSipUserAgentReaction; virtual;
  public
    constructor Create(UA: TIdSipAbstractCore); virtual;
    destructor  Destroy; override;

    function  Accept(Request: TIdSipRequest;
                     UsingSecureTransport: Boolean): TIdSipAction; virtual;
    procedure AddAllowedContentType(const MimeType: String);
    procedure AddAllowedContentTypes(MimeTypes: TStrings);
    procedure AddLocalHeaders(OutboundMessage: TIdSipMessage); virtual;
    function  AcceptsMethods: String; virtual;
    function  AllowedContentTypes: TStrings; overload;
    function  AllowedExtensions: String; virtual;
    procedure CleanUp; virtual;
    function  HasKnownAccept(Request: TIdSipRequest): Boolean;
    function  HasUnknownContentType(Request: TIdSipRequest): Boolean;
    function  IsNull: Boolean; virtual;
    function  SupportsMimeType(const MimeType: String): Boolean;
    function  WillAccept(Request: TIdSipRequest): Boolean; virtual;

    property UserAgent: TIdSipAbstractCore read fUserAgent;
  end;

  // I represent the module selected when a request doesn't match any other
  // module.
  TIdSipNullModule = class(TIdSipMessageModule)
  protected
    function  WillAcceptRequest(Request: TIdSipRequest): TIdSipUserAgentReaction; override;
  public
    function IsNull: Boolean; override;
    function WillAccept(Request: TIdSipRequest): Boolean; override;
  end;

  TIdSipOptionsModule = class(TIdSipMessageModule)
  protected
    function  WillAcceptRequest(Request: TIdSipRequest): TIdSipUserAgentReaction; override;
  public
    constructor Create(UA: TIdSipAbstractCore); override;

    function Accept(Request: TIdSipRequest;
                    UsingSecureTransport: Boolean): TIdSipAction; override;
    function AcceptsMethods: String; override;
    function CreateOptions(Dest: TIdSipAddressHeader): TIdSipRequest;
  end;

  // I represent an asynchronous message send between SIP entities - INVITEs,
  // REGISTERs and the like - where we care what the remote end answers.
  // With CANCELs and BYEs, for instance, we don't care how the remote end
  // answers.
  //
  // Owned actions are actions that other actions control. For example, Sessions
  // are Actions. Sessions use Invites (among other things), and Sessions
  // control those Invites. Thus, the Invites are Owned.
  //
  // Note that both in- and out-bound actions subclass Action. Thus this class
  // contains methods that are sometimes inapplicable to a particular action.
  //
  // Proxies and User Agents can challenge an Action, forcing us to re-issue an
  // action with authorisation credentials. We represent this by the following
  // state machine:
  //
  //                                    +------+
  //                                    |      |
  //                                    V      |
  // +-------------+    +------+    +--------+ |  +----------+
  // | Initialised |--->| Sent |--->| Resent |-+->| Finished |
  // +-------------+    +------+    +--------+    +----------+
  //                        |                          ^
  //                        |                          |
  //                        +--------------------------+
  //
  // We can re-enter the Resent state several times because we may need to
  // authenticate to multiple proxies, and possibly the remote User Agent too,
  // resending the request with its collection of authorisation credentials each
  // time.

  TIdSipActionResult = (arUnknown, arSuccess, arFailure, arInterim);
  TIdSipActionState = (asInitialised, asSent, asResent, asFinished);
  TIdSipAction = class(TIdInterfacedObject)
  private
    fID:             String;
    fInitialRequest: TIdSipRequest;
    fIsTerminated:   Boolean;
    fLocalGruu:      TIdSipContactHeader;
    fResult:         TIdSipActionResult;
    fUA:             TIdSipAbstractCore;
    NonceCount:      Cardinal;

    function  CreateResend(AuthorizationCredentials: TIdSipAuthorizationHeader): TIdSipRequest;
    function  GetUsername: String;
    procedure SetLocalGruu(Value: TIdSipContactHeader);
    procedure SetUsername(const Value: String);
    procedure TrySendRequest(Request: TIdSipRequest;
                             Target: TIdSipLocation);
  protected
    ActionListeners: TIdNotificationList;
    fIsOwned:        Boolean;
    State:           TIdSipActionState;
    TargetLocations: TIdSipLocations;

    procedure ActionSucceeded(Response: TIdSipResponse); virtual;
    function  CreateNewAttempt: TIdSipRequest; virtual; abstract;
    procedure Initialise(UA: TIdSipAbstractCore;
                         Request: TIdSipRequest;
                         UsingSecureTransport: Boolean); virtual;
    procedure MarkAsTerminated; virtual;
    procedure NotifyOfAuthenticationChallenge(Challenge: TIdSipResponse);
    procedure NotifyOfFailure(Response: TIdSipResponse); virtual;
    procedure NotifyOfNetworkFailure(ErrorCode: Cardinal;
                                     const Reason: String); virtual;
    function  ReceiveFailureResponse(Response: TIdSipResponse): TIdSipActionResult; virtual;
    function  ReceiveGlobalFailureResponse(Response: TIdSipResponse): TIdSipActionResult; virtual;

    function  ReceiveOKResponse(Response: TIdSipResponse;
                                UsingSecureTransport: Boolean): TIdSipActionResult; virtual;
    procedure ReceiveOtherRequest(Request: TIdSipRequest); virtual;
    function  ReceiveProvisionalResponse(Response: TIdSipResponse;
                                         UsingSecureTransport: Boolean): TIdSipActionResult; virtual;
    function  ReceiveRedirectionResponse(Response: TIdSipResponse;
                                         UsingSecureTransport: Boolean): TIdSipActionResult; virtual;
    function  ReceiveServerFailureResponse(Response: TIdSipResponse): TIdSipActionResult; virtual;
    procedure SendRequest(Request: TIdSipRequest); virtual;
    procedure SendResponse(Response: TIdSipResponse); virtual;
    procedure SetResult(Value: TIdSipActionResult);
  public
    constructor Create(UA: TIdSipAbstractCore); virtual;
    constructor CreateInbound(UA: TIdSipAbstractCore;
                              Request: TIdSipRequest;
                              UsingSecureTransport: Boolean); virtual;
    destructor  Destroy; override;

    procedure AddActionListener(Listener: IIdSipActionListener);
    function  IsInbound: Boolean; virtual;
    function  IsInvite: Boolean; virtual;
    function  IsOptions: Boolean; virtual;
    function  IsRegistration: Boolean; virtual;
    function  IsSession: Boolean; virtual;
    function  Match(Msg: TIdSipMessage): Boolean; virtual;
    function  Method: String; virtual; abstract;
    procedure NetworkFailureSending(Msg: TIdSipMessage); virtual;
    procedure ReceiveRequest(Request: TIdSipRequest); virtual;
    procedure ReceiveResponse(Response: TIdSipResponse;
                              UsingSecureTransport: Boolean); virtual;
    procedure RemoveActionListener(Listener: IIdSipActionListener);
    procedure Resend(AuthorizationCredentials: TIdSipAuthorizationHeader); virtual;
    procedure Send; virtual;
    procedure Terminate; virtual;

    property ID:             String              read fID;
    property InitialRequest: TIdSipRequest       read fInitialRequest;
    property IsOwned:        Boolean             read fIsOwned;
    property IsTerminated:   Boolean             read fIsTerminated;
    property LocalGruu:      TIdSipContactHeader read fLocalGruu write SetLocalGruu;
    property Result:         TIdSipActionResult  read fResult;
    property UA:             TIdSipAbstractCore  read fUA;
    property Username:       String              read GetUsername write SetUsername;
  end;

  // I encapsulate the call flow around a single request send and response.
  TIdSipOwnedAction = class(TIdSipAction)
  private
    OwningActionListeners: TIdNotificationList;
  protected
    procedure ActionSucceeded(Response: TIdSipResponse); override;
    procedure Initialise(UA: TIdSipAbstractCore;
                         Request: TIdSipRequest;
                         UsingSecureTransport: Boolean); override;
    procedure NotifyOfFailure(Response: TIdSipResponse); override;
    procedure NotifyOfRedirect(Response: TIdSipResponse);
    procedure NotifyOfSuccess(Msg: TIdSipMessage); virtual;
    function  ReceiveRedirectionResponse(Response: TIdSipResponse;
                                         UsingSecureTransport: Boolean): TIdSipActionResult; override;
  public
    destructor Destroy; override;

    procedure AddOwnedActionListener(Listener: IIdSipOwnedActionListener);
    procedure Cancel; virtual;
    procedure RemoveOwnedActionListener(Listener: IIdSipOwnedActionListener);
  end;

  TIdSipRedirectedAction = class(TIdSipOwnedAction)
  private
    fContact:         TIdSipAddressHeader;
    fMethod:          String;
    fOriginalRequest: TIdSipRequest;

    procedure SetContact(Value: TIdSipAddressHeader);
    procedure SetOriginalRequest(Value: TIdSipRequest);
  protected
    function  CreateNewAttempt: TIdSipRequest; override;
    procedure Initialise(UA: TIdSipAbstractCore;
                         Request: TIdSipRequest;
                         UsingSecureTransport: Boolean); override;
  public
    destructor Destroy; override;

    function  Method: String; override;
    procedure SetMethod(const Method: String);
    procedure Send; override;

    property Contact:         TIdSipAddressHeader read fContact write SetContact;
    property OriginalRequest: TIdSipRequest       read fOriginalRequest write SetOriginalRequest;
  end;

  // I represent an action that uses owned actions to accomplish something. My
  // subclasses, for instance, use owned actions to handle redirection
  // responses.
  TIdSipOwningAction = class(TIdSipAction)
  public
    function CreateInitialAction: TIdSipOwnedAction; virtual;
    function CreateRedirectedAction(OriginalRequest: TIdSipRequest;
                                    Contact: TIdSipContactHeader): TIdSipOwnedAction; virtual;
  end;

  TIdSipOptions = class(TIdSipAction)
  protected
    Module: TIdSipOptionsModule;

    function  CreateNewAttempt: TIdSipRequest; override;
    procedure Initialise(UA: TIdSipAbstractCore;
                         Request: TIdSipRequest;
                         UsingSecureTransport: Boolean); override;
  public
    function IsOptions: Boolean; override;
    function Method: String; override;
  end;

  TIdSipInboundOptions = class(TIdSipOptions)
  public
    function  IsInbound: Boolean; override;
    procedure ReceiveRequest(Options: TIdSipRequest); override;
  end;

  TIdSipOutboundOptions = class(TIdSipOptions)
  private
    fServer: TIdSipAddressHeader;

    procedure NotifyOfResponse(Response: TIdSipResponse);
    procedure SetServer(Value: TIdSipAddressHeader);
  protected
    procedure ActionSucceeded(Response: TIdSipResponse); override;
    function  CreateNewAttempt: TIdSipRequest; override;
    procedure Initialise(UA: TIdSipAbstractCore;
                         Request: TIdSipRequest;
                         UsingSecureTransport: Boolean); override;
    procedure NotifyOfFailure(Response: TIdSipResponse); override;
  public
    destructor Destroy; override;

    procedure AddListener(const Listener: IIdSipOptionsListener);
    procedure RemoveListener(const Listener: IIdSipOptionsListener);
    procedure Send; override;

    property Server: TIdSipAddressHeader read fServer write SetServer;
  end;

  TIdSipActionRedirector = class;
  // * OnNewAction allows you to manipulate the new attempt to send a message.
  //   For instance, it allows you to listen for OnDialogEstablished
  //   notifications from an OutboundInvite.
  // * OnFailure returns the failure response to the last attempt to send the
  //   message. No more notifications will occur after this.
  // * OnRedirectFailure tells you that, for instance, there were no locations
  //   returned by the redirecting response, or that no locations could be
  //   reached (because of a series of network failures, say). Like OnFailure,
  //   this is a "final" notification.
  // * OnSuccess does just what it says: it returns the first successful action
  //   (and response). 
  IIdSipActionRedirectorListener = interface
    ['{A538DE4D-DC73-44D2-A888-E7B7B5FA2BF0}']
    procedure OnFailure(Redirector: TIdSipActionRedirector;
                        Response: TIdSipResponse);
    procedure OnNewAction(Redirector: TIdSipActionRedirector;
                          NewAction: TIdSipAction);
    procedure OnRedirectFailure(Redirector: TIdSipActionRedirector;
                                ErrorCode: Cardinal;
                                const Reason: String);
    procedure OnSuccess(Redirector: TIdSipActionRedirector;
                        SuccessfulAction: TIdSipAction;
                        Response: TIdSipResponse);
  end;

  // I encapsulate the logic surrounding receiving 3xx class responses to a
  // request and sending out new, redirected, requests. When I complete then
  // either I have received a 2xx class response for one of the (sub)actions,
  // indicating the success of the action, or some failure response (4xx, 5xx,
  // 6xx).
  TIdSipActionRedirector = class(TIdInterfacedObject,
                                 IIdSipActionListener,
                                 IIdSipOwnedActionListener)
  private
    fCancelling:          Boolean;
    fFullyEstablished:    Boolean;
    fInitialAction:       TIdSipOwnedAction;
    Listeners:            TIdNotificationList;
    OwningAction:         TIdSipOwningAction;
    RedirectedActions:    TObjectList;
    TargetUriSet:         TIdSipContacts;
    UA:                   TIdSipAbstractCore;

    procedure AddNewRedirect(OriginalRequest: TIdSipRequest;
                             Contact: TIdSipContactHeader);
    function  HasOutstandingRedirects: Boolean;
    procedure NotifyOfFailure(ErrorCode: Cardinal;
                              const Reason: String);
    procedure NotifyOfNewAction(Action: TIdSipAction);
    procedure NotifyOfSuccess(Action: TIdSipAction;
                              Response: TIdSipResponse);
    procedure OnAuthenticationChallenge(Action: TIdSipAction;
                                        Challenge: TIdSipResponse);
    procedure OnFailure(Action: TIdSipAction;
                        Response: TIdSipResponse;
                        const Reason: String);
    procedure OnNetworkFailure(Action: TIdSipAction;
                               ErrorCode: Cardinal;
                               const Reason: String);
    procedure OnRedirect(Action: TIdSipAction;
                         Redirect: TIdSipResponse);
    procedure OnSuccess(Action: TIdSipAction;
                        Response: TIdSipMessage);
    procedure RemoveFinishedRedirectedInvite(Agent: TIdSipAction);
    procedure TerminateAllRedirects;
  public
    constructor Create(OwningAction: TIdSipOwningAction);
    destructor  Destroy; override;

    procedure AddListener(const Listener: IIdSipActionRedirectorListener);
    procedure Cancel;
    function  Contains(OwnedAction: TIdSipAction): Boolean;
    procedure RemoveListener(const Listener: IIdSipActionRedirectorListener);
    procedure Resend(ChallengedAction: TIdSipAction;
                     AuthorizationCredentials: TIdSipAuthorizationHeader);
    procedure Send;
    procedure Terminate;

    property Cancelling:       Boolean           read fCancelling write fCancelling;
    property FullyEstablished: Boolean           read fFullyEstablished write fFullyEstablished;
    property InitialAction:    TIdSipOwnedAction read fInitialAction;
  end;

  // I provide facilities to unambiguously locate any action resident in
  // memory, and to allow actions to register and unregister from me as
  // they instantiate and free.
  TIdSipActionRegistry = class(TObject)
  private
    class function ActionAt(Index: Integer): TIdSipAction;
    class function ActionRegistry: TStrings;
  public
    class function  RegisterAction(Instance: TIdSipAction): String;
    class function  FindAction(const ActionID: String): TIdSipAction;
    class procedure UnregisterAction(const ActionID: String);
  end;

  TIdSipActionMethod = class(TIdNotification)
  private
    fActionAgent: TIdSipAction;
  public
    property ActionAgent: TIdSipAction read fActionAgent write fActionAgent;
  end;

  TIdSipActionAuthenticationChallengeMethod = class(TIdSipActionMethod)
  private
    fChallenge: TIdSipResponse;
  public
    procedure Run(const Subject: IInterface); override;

    property Challenge: TIdSipResponse read fChallenge write fChallenge;
  end;

  TIdSipActionNetworkFailureMethod = class(TIdSipActionMethod)
  private
    fErrorCode: Cardinal;
    fReason:    String;
  public
    procedure Run(const Subject: IInterface); override;

    property ErrorCode: Cardinal read fErrorCode write fErrorCode;
    property Reason:    String   read fReason write fReason;
  end;

  TIdSipOwnedActionMethod = class(TIdSipActionMethod)
  end;

  TIdSipOwnedActionFailureMethod = class(TIdSipOwnedActionMethod)
  private
    fReason: String;
    fResponse: TIdSipResponse;
  public
    procedure Run(const Subject: IInterface); override;

    property Reason:   String         read fReason write fReason;
    property Response: TIdSipResponse read fResponse write fResponse;
  end;

  TIdSipOwnedActionRedirectMethod = class(TIdSipOwnedActionMethod)
  private
    fResponse: TIdSipResponse;
  public
    procedure Run(const Subject: IInterface); override;

    property Response: TIdSipResponse read fResponse write fResponse;
  end;

  TIdSipOwnedActionSuccessMethod = class(TIdSipOwnedActionMethod)
  private
    fMsg: TIdSipMessage;
  public
    procedure Run(const Subject: IInterface); override;

    property Msg: TIdSipMessage read fMsg write fMsg;
  end;

  TIdSipOptionsResponseMethod = class(TIdNotification)
  private
    fOptions:  TIdSipOutboundOptions;
    fResponse: TIdSipResponse;
  public
    procedure Run(const Subject: IInterface); override;

    property Options:  TIdSipOutboundOptions read fOptions write fOptions;
    property Response: TIdSipResponse        read fResponse write fResponse;
  end;

  TIdSipActionRedirectorMethod = class(TIdNotification)
  private
    fRedirector: TIdSipActionRedirector;
  public
    property Redirector: TIdSipActionRedirector read fRedirector write fRedirector;
  end;

  TIdSipRedirectorNewActionMethod = class(TIdSipActionRedirectorMethod)
  private
    fNewAction: TIdSipAction;
  public
    procedure Run(const Subject: IInterface); override;

    property NewAction: TIdSipAction read fNewAction write fNewAction;
  end;

  TIdSipRedirectorRedirectFailureMethod = class(TIdSipActionRedirectorMethod)
  private
    fErrorCode: Cardinal;
    fReason:    String;
  public
    procedure Run(const Subject: IInterface); override;

    property ErrorCode: Cardinal read fErrorCode write fErrorCode;
    property Reason:    String   read fReason write fReason;
  end;  

  TIdSipRedirectorSuccessMethod = class(TIdSipActionRedirectorMethod)
  private
    fResponse:         TIdSipResponse;
    fSuccessfulAction: TIdSipAction;

  public
    procedure Run(const Subject: IInterface); override;

    property Response:         TIdSipResponse read fResponse write fResponse;
    property SuccessfulAction: TIdSipAction   read fSuccessfulAction write fSuccessfulAction;
  end;

  TIdSipAbstractCoreMethod = class(TIdNotification)
  private
    fUserAgent: TIdSipAbstractCore;
  public
    property UserAgent: TIdSipAbstractCore read fUserAgent write fUserAgent;
  end;

  TIdSipUserAgentDroppedUnmatchedMessageMethod = class(TIdSipAbstractCoreMethod)
  private
    fReceiver: TIdSipTransport;
    fMessage:  TIdSipMessage;
  public
    procedure Run(const Subject: IInterface); override;

    property Receiver: TIdSipTransport read fReceiver write fReceiver;
    property Message:  TIdSipMessage  read fMessage write fMessage;
  end;

  EIdSipBadSyntax = class(EIdException);
  EIdSipTransactionUser = class(EIdException);

// Transaction-User reactions. Don't forget to update ReactionToStr if you add
// a new value here!
const
  uarAccept                     = 0;
  uarBadAuthorization           = 1;
  uarBadRequest                 = 2;
  uarDoNotDisturb               = 3;
  uarDoNothing                  = 4;
  uarExpireTooBrief             = 5;
  uarForbidden                  = 6;
  uarLoopDetected               = 7;
  uarMethodNotAllowed           = 8;
  uarMissingContact             = 9;
  uarNonInviteWithReplaces      = 10;
  uarNoSuchCall                 = 11;
  uarNotFound                   = 12;
  uarUnsupportedExtension       = 13;
  uarTooManyVias                = 14;
  uarUnauthorized               = 15;
  uarUnsupportedAccept          = 16;
  uarUnsupportedContentEncoding = 17;
  uarUnsupportedContentLanguage = 18;
  uarUnsupportedContentType     = 19;
  uarUnsupportedMethod          = 20;
  uarUnsupportedScheme          = 21;
  uarUnsupportedSipVersion      = 22;

// Stack error codes
const
  NoError                        = 0;
  BusyHere                       = NoError;
  CallRedirected                 = NoError;
  LocalHangUp                    = NoError;
  InboundActionFailed            = NoError + 1;
  NoLocationFound                = NoError + 2;
  NoLocationSucceeded            = NoError + 3;
  RedirectWithNoContacts         = NoError + 4;
  RedirectWithNoMoreTargets      = NoError + 5;
  RedirectWithNoSuccess          = NoError + 6;
  RemoteCancel                   = NoError;
  RemoteHangUp                   = NoError;

// Generally useful constants
const
  BadAuthorizationTokens      = 'Bad Authorization tokens';
  MalformedConfigurationLine  = 'Malformed configuration line: %s';
  MaximumUDPMessageSize       = 1300;
  MaxPrematureInviteRetry     = 10;
  MissingContactHeader        = 'Missing Contact Header';
  NonInviteWithReplacesHeader = 'Non-INVITE request with Replaces header';
  OneMinute                   = 60;
  OneHour                     = 60*OneMinute;
  FiveMinutes                 = 5*OneMinute;
  TwentyMinutes               = 20*OneMinute;

const
  RSBusyHere                  = 'Incoming call rejected - busy here';
  RSCallRedirected            = 'Incoming call redirected';
  RSLocalHangUp               = 'Local end hung up';
  RSInboundActionFailed       = 'For an inbound %s, sending a response failed because: %s';
  RSNoLocationFound           = 'No destination addresses found for URI %s';
  RSNoLocationSucceeded       = 'Attempted message sends to all destination addresses failed for URI %s';
  RSNoReason                  = '';
  RSRedirectWithNoContacts    = 'Call redirected to nowhere';
  RSRedirectWithNoMoreTargets = 'Call redirected but no more targets';
  RSRedirectWithNoSuccess     = 'Call redirected but no target answered';
  RSRemoteCancel              = 'Remote end cancelled call';
  RSRemoteHangUp              = 'Remote end hung up';

implementation

uses
  IdHashMessageDigest, IdRandom, IdSdp, IdSimpleParser, IdSipConsts,
  IdSipIndyLocator, IdSipInviteModule, IdSipRegistration, Math;

// Used by the ActionRegistry.
var
  GActions: TStrings;

const
  ItemNotFoundIndex = -1;

// Exception messages
const
  ContradictoryCreateRequestInvocation = 'You tried to create a %s request '
                                       + 'with a URI specifying a %s method';
  MessageSendFailureMalformed          = 'Cannot send malformed message: %s';
  MessageSendFailureUnknownExtension   = 'Cannot send message with unknown '
                                       + 'extension, one of: %s';
  MessageSendFailureUnknownMethod      = 'Cannot send message with unknown '
                                       + 'method %s';
  MethodInProgress                     = 'A(n) %s is already in progress';
  NotAnUUIDURN                         = '"%s" is not a valid UUID URN';
  OutboundActionFailed                 = 'An outbound %s failed because: %s';

//******************************************************************************
//* Unit private functions & procedures                                        *
//******************************************************************************

function ReactionToStr(Reaction: TIdSipUserAgentReaction): String;
begin
  case Reaction of
    uarAccept:                     Result := 'uarAccept';
    uarBadAuthorization:           Result := 'uarBadAuthorization';
    uarBadRequest:                 Result := 'uarBadRequest';
    uarDoNotDisturb:               Result := 'uarDoNotDisturb';
    uarDoNothing:                  Result := 'uarDoNothing';
    uarExpireTooBrief:             Result := 'uarExpireTooBrief';
    uarForbidden:                  Result := 'uarForbidden';
    uarLoopDetected:               Result := 'uarLoopDetected';
    uarMethodNotAllowed:           Result := 'uarMethodNotAllowed';
    uarMissingContact:             Result := 'uarMissingContact';
    uarNonInviteWithReplaces:      Result := 'uarNonInviteWithReplaces';
    uarNoSuchCall:                 Result := 'uarNoSuchCall';
    uarNotFound:                   Result := 'uarNotFound';
    uarUnsupportedExtension:       Result := 'uarUnsupportedExtension';
    uarTooManyVias:                Result := 'uarTooManyVias';
    uarUnauthorized:               Result := 'uarUnauthorized';
    uarUnsupportedAccept:          Result := 'uarUnsupportedAccept';
    uarUnsupportedContentEncoding: Result := 'uarUnsupportedContentEncoding';
    uarUnsupportedContentLanguage: Result := 'uarUnsupportedContentLanguage';
    uarUnsupportedContentType:     Result := 'uarUnsupportedContentType';
    uarUnsupportedMethod:          Result := 'uarUnsupportedMethod';
    uarUnsupportedScheme:          Result := 'uarUnsupportedScheme';
    uarUnsupportedSipVersion:      Result := 'uarUnsupportedSipVersion';
  else
    Result := IntToStr(Reaction);
  end;
end;

//******************************************************************************
//* TIdSipActionClosure                                                        *
//******************************************************************************
//* TIdSipActionClosure Public methods *****************************************

procedure TIdSipActionClosure.Execute(Action: TIdSipAction);
begin
end;

//******************************************************************************
//* TIdSipActions                                                              *
//******************************************************************************
//* TIdSipActions Public methods ***********************************************

constructor TIdSipActions.Create;
begin
  inherited Create;

  Self.Actions  := TObjectList.Create;
  Self.Observed := TIdObservable.Create;
end;

destructor TIdSipActions.Destroy;
begin
  Self.Observed.Free;
  Self.Actions.Free;

  inherited Destroy;
end;

function TIdSipActions.Add(Action: TIdSipAction): TIdSipAction;
begin
  Result := Action;

  try
    Self.Actions.Add(Action);
  except
    if (Self.Actions.IndexOf(Action) <> ItemNotFoundIndex) then
      Self.Actions.Remove(Action)
    else
      FreeAndNil(Result);
    raise;
  end;

  Self.Observed.NotifyListenersOfChange;
end;

procedure TIdSipActions.AddObserver(const Listener: IIdObserver);
begin
  Self.Observed.AddObserver(Listener);
end;

function TIdSipActions.AddOutboundAction(UserAgent: TIdSipAbstractCore;
                                         ActionType: TIdSipActionClass): TIdSipAction;
begin
  Result := Self.Add(ActionType.Create(UserAgent));
end;

procedure TIdSipActions.CleanOutTerminatedActions;
var
  Changed:      Boolean;
  I:            Integer;
  InitialCount: Integer;
begin
  InitialCount := Self.Actions.Count;

  I := 0;
  while (I < Self.Actions.Count) do
    if Self.ActionAt(I).IsTerminated then
      Self.Actions.Delete(I)
    else
      Inc(I);

  Changed := InitialCount <> Self.Actions.Count;

  if Changed then
    Self.Observed.NotifyListenersOfChange;
end;

function TIdSipActions.Count: Integer;
begin
  // Return the number of actions, both terminated and ongoing.
  Result := Self.Actions.Count;
end;

function TIdSipActions.CountOf(const MethodName: String): Integer;
var
  I: Integer;
begin
  // Return the number of ongoing (non-session) actions of type MethodName.
  Result := 0;

  // We don't count Sessions because Sessions contain other Actions - they
  // look and act more like containers of Actions than Actions themselves.
  for I := 0 to Self.Actions.Count - 1 do
    if not Self.ActionAt(I).IsSession
      and (Self.ActionAt(I).Method = MethodName)
      and not Self.ActionAt(I).IsTerminated then Inc(Result);
end;

procedure TIdSipActions.FindActionAndPerform(const ID: String;
                                             Block: TIdSipActionClosure);
var
  NullBlock: TIdSipActionClosure;
begin
  NullBlock := TIdSipActionClosure.Create;
  try
    Self.FindActionAndPerformOr(ID, Block, NullBlock);
  finally
    NullBlock.Free;
  end;
end;

procedure TIdSipActions.FindActionAndPerformOr(const ID: String;
                                               FoundBlock: TIdSipActionClosure;
                                               NotFoundBlock: TIdSipActionClosure);
var
  Action: TIdSipAction;
begin
  Action := Self.FindAction(ID);

  if Assigned(Action) then
    FoundBlock.Execute(Action)
  else
    NotFoundBlock.Execute(nil);

  Self.CleanOutTerminatedActions;
end;

function TIdSipActions.FindActionForGruu(const LocalGruu: String): TIdSipAction;
var
  Action: TIdSipAction;
  Gruu:   TIdSipUri;
  I:      Integer;
begin
  // Return the non-Owned action that uses LocalGruu as its Contact.

  Gruu := TIdSipUri.Create(LocalGruu);
  try
    Result := nil;
    I      := 0;
    while (I < Self.Count) and not Assigned(Result) do begin
      Action := Self.ActionAt(I);
      if not Action.IsOwned and Action.LocalGruu.Address.Equals(Gruu) then
        Result := Action
      else
        Inc(I);
    end;
  finally
    Gruu.Free;
  end;
end;

function TIdSipActions.InviteCount: Integer;
begin
  Result := Self.CountOf(MethodInvite);
end;

function TIdSipActions.OptionsCount: Integer;
begin
  Result := Self.CountOf(MethodOptions);
end;

procedure TIdSipActions.Perform(Msg: TIdSipMessage; Block: TIdSipActionClosure; ClientAction: Boolean);
var
  Action: TIdSipAction;
begin
  // Find the action, and execute Block regardless of whether we found the
  // action. FindAction returns nil in this case.

  Action := Self.FindAction(Msg, ClientAction);

  Block.Execute(Action);

  Self.CleanOutTerminatedActions;
end;

function TIdSipActions.RegistrationCount: Integer;
begin
  Result := Self.CountOf(MethodRegister);
end;

procedure TIdSipActions.RemoveObserver(const Listener: IIdObserver);
begin
  Self.Observed.RemoveObserver(Listener);
end;

function TIdSipActions.SessionCount: Integer;
var
  I: Integer;
begin
  // Return the number of ongoing Sessions
  Result := 0;

  for I := 0 to Self.Actions.Count - 1 do
    if Self.ActionAt(I).IsSession
      and not Self.ActionAt(I).IsTerminated then
      Inc(Result);
end;

procedure TIdSipActions.TerminateAllActions;
var
  I: Integer;
begin
  for I := 0 to Self.Actions.Count - 1 do
    if not Self.ActionAt(I).IsOwned
      and not Self.ActionAt(I).IsTerminated then
      Self.ActionAt(I).Terminate;
end;

//* TIdSipActions Private methods **********************************************

function TIdSipActions.ActionAt(Index: Integer): TIdSipAction;
begin
  // Precondition: you've invoked Self.LockActions
  Result := Self.Actions[Index] as TIdSipAction;
end;

function TIdSipActions.FindAction(Msg: TIdSipMessage; ClientAction: Boolean): TIdSipAction;
var
  Action: TIdSipAction;
  I:      Integer;
begin
  // Precondition: You've locked Self.ActionLock.
  Result := nil;

  I := 0;
  while (I < Self.Actions.Count) and not Assigned(Result) do begin
    Action := Self.Actions[I] as TIdSipAction;

    // First, if an Action's Terminated we're not interested in dispatching to it.
    // Second, the message has to match the Action (as defined per the type of Action).
    // Third, OwningActions don't typically handle messages directly: Sessions use
    // Invites, for instance.
    // Fourth, do we match the message against the UAC actions (actions we
    // initiated) or against the UAS actions?
    if not Action.IsTerminated
      and Action.Match(Msg) then begin

      if Action.IsOwned then begin
        if (Action.IsInbound = not ClientAction) then
          Result := Action;
      end
      else begin
        Result := Action;
      end;
    end;

    if not Assigned(Result) then
      Inc(I);
  end;
end;

function TIdSipActions.FindAction(const ActionID: String): TIdSipAction;
begin
  Result := TIdSipActionRegistry.FindAction(ActionID);
end;

//******************************************************************************
//* TIdSipActionsWait                                                          *
//******************************************************************************
//* TIdSipActionsWait Public methods *******************************************

procedure TIdSipActionsWait.Trigger;
var
  Block: TIdSipActionClosure;
begin
  Block := Self.BlockType.Create;
  try
    Self.Actions.FindActionAndPerform(Self.ActionID, Block);
  finally
    Block.Free;
  end;
end;

//******************************************************************************
//* TIdSipActionSendWait                                                       *
//******************************************************************************
//* TIdSipActionSendWait Public methods ****************************************

procedure TIdSipActionSendWait.Trigger;
begin
  Self.Action.Send;
end;

//******************************************************************************
//* TIdSipActionTerminateWait                                                  *
//******************************************************************************
//* TIdSipActionTerminateWait **************************************************

procedure TIdSipActionTerminateWait.Trigger;
begin
  Self.Action.Terminate;
end;

//******************************************************************************
//* TIdSipUserAgentActOnRequest                                                *
//******************************************************************************
//* TIdSipUserAgentActOnRequest Public methods *********************************

procedure TIdSipUserAgentActOnRequest.Execute(Action: TIdSipAction);
begin
  // Processing the request - cf. RFC 3261, section 8.2.5
  // Action generates the response - cf. RFC 3261, section 8.2.6

  if Assigned(Action) then
    Action.ReceiveRequest(Request);

  if not Assigned(Action) then
    Action := Self.UserAgent.AddInboundAction(Self.Request, Self.Receiver.IsSecure);

  if not Assigned(Action) then begin
    if Request.IsAck then
      Self.UserAgent.NotifyOfDroppedMessage(Self.Request, Self.Receiver);
  end;
end;

//******************************************************************************
//* TIdSipUserAgentActOnResponse                                               *
//******************************************************************************
//* TIdSipUserAgentActOnResponse Public methods ********************************

procedure TIdSipUserAgentActOnResponse.Execute(Action: TIdSipAction);
begin
  // User Agents drop unmatched responses on the floor.
  // Except for 2xx's on a client INVITE. And these no longer belong to
  // a transaction, since the receipt of a 200 terminates a client INVITE
  // immediately.
  if Assigned(Action) then
    Action.ReceiveResponse(Self.Response, Self.Receiver.IsSecure)
  else

  Self.UserAgent.NotifyOfDroppedMessage(Self.Response, Self.Receiver);
end;

//******************************************************************************
//* TIdSipActionNetworkFailure                                                 *
//******************************************************************************
//* TIdSipActionNetworkFailure Public methods **********************************

procedure TIdSipActionNetworkFailure.Execute(Action: TIdSipAction);
begin
  if Assigned(Action) then
    Action.NetworkFailureSending(Self.FailedMessage);
end;

//******************************************************************************
//* TIdSipAbstractCore                                                         *
//******************************************************************************
//* TIdSipAbstractCore Public methods ******************************************

constructor TIdSipAbstractCore.Create;
begin
  inherited Create;

  Self.fAllowedContentTypeList := TStringList.Create;
  Self.fAllowedLanguageList    := TStringList.Create;
  Self.fAllowedSchemeList      := TStringList.Create;

  Self.Modules    := TObjectList.Create(true);
  Self.NullModule := TIdSipNullModule.Create(Self);
  Self.Observed   := TIdObservable.Create;

  Self.fActions                := TIdSipActions.Create;
  Self.fAllowedContentTypeList := TStringList.Create;
  Self.fAllowedLanguageList    := TStringList.Create;
  Self.fContact                := TIdSipContactHeader.Create;
  Self.fFrom                   := TIdSipFromHeader.Create;
  Self.fGruu                   := TIdSipContactHeader.Create;
  Self.fKeyring                := TIdKeyRing.Create;

  Self.Actions.AddObserver(Self);

  Self.AddModule(TIdSipOptionsModule);

  Self.AddAllowedScheme(SipScheme);

  Self.HostName := Self.DefaultHostName;

  // DefaultFrom depends on Self.HostName
  Self.Contact.Value         := Self.DefaultFrom;
  Self.From.Value            := Self.DefaultFrom;
  Self.Realm                 := Self.HostName;
  Self.RequireAuthentication := false;
  Self.UserAgentName         := Self.DefaultUserAgent;
end;

destructor TIdSipAbstractCore.Destroy;
begin
  Self.NotifyModulesOfFree;

  Self.Keyring.Free;
  Self.Gruu.Free;
  Self.From.Free;
  Self.Contact.Free;
  Self.AllowedSchemeList.Free;
  Self.AllowedLanguageList.Free;
  Self.AllowedContentTypeList.Free;
  Self.Actions.Free;


  Self.Observed.Free;
  Self.NullModule.Free;
  Self.Modules.Free;

  inherited Destroy;
end;

function TIdSipAbstractCore.AddAction(Action: TIdSipAction): TIdSipAction;
begin
  Result := Self.Actions.Add(Action);
end;

procedure TIdSipAbstractCore.AddAllowedLanguage(const LanguageID: String);
begin
  if (Trim(LanguageID) = '') then
    raise EIdSipBadSyntax.Create('Not a valid language identifier');

  if (Self.AllowedLanguageList.IndexOf(LanguageID) = ItemNotFoundIndex) then
    Self.AllowedLanguageList.Add(LanguageID);
end;

procedure TIdSipAbstractCore.AddAllowedScheme(const Scheme: String);
begin
  if not TIdSipParser.IsScheme(Scheme) then
    raise EIdSipBadSyntax.Create('Not a valid scheme');

  if (Self.AllowedSchemeList.IndexOf(Scheme) = ItemNotFoundIndex) then
    Self.AllowedSchemeList.Add(Scheme);
end;

function TIdSipAbstractCore.AddInboundAction(Request: TIdSipRequest;
                                             UsingSecureTransport: Boolean): TIdSipAction;
var
  Module: TIdSipMessageModule;
begin
  Module := Self.ModuleFor(Request);

  if Assigned(Module) then begin
    Result := Module.Accept(Request, UsingSecureTransport);

    if Assigned(Result) then begin
      Self.Actions.Add(Result);
    end;
  end
  else
    Result := nil;
end;

procedure TIdSipAbstractCore.AddLocalHeaders(OutboundRequest: TIdSipRequest);
var
  Transport: String;
begin
  // You might think we need to find out the appropriate transport to use before
  // we send the message. Yes, we do. We do so when the Action actually sends
  // the request in Action.Send(Request|Response).

  // cf RFC 3263, section 4.1
  if OutboundRequest.ToHeader.Address.HasParameter(TransportParam) then
    Transport := OutboundRequest.ToHeader.Address.Transport
  else
    Transport := TransportParamUDP;

  if not OutboundRequest.IsAck and OutboundRequest.Path.IsEmpty then begin
    OutboundRequest.AddHeader(ViaHeaderFull);
    OutboundRequest.LastHop.SipVersion := SipVersion;
    OutboundRequest.LastHop.Transport  := ParamToTransport(Transport);
    OutboundRequest.LastHop.SentBy     := Self.HostName;
    OutboundRequest.LastHop.Branch     := Self.NextBranch;
  end;

  if (Self.UserAgentName <> '') then
    OutboundRequest.AddHeader(UserAgentHeader).Value := Self.UserAgentName;

  if Self.UseGruu then 
    // draft-ietf-sip-gruu, section 8.1
    OutboundRequest.AddHeader(Self.Gruu)
  else
    OutboundRequest.AddHeader(Self.Contact);

  if OutboundRequest.HasSipsUri then
    OutboundRequest.FirstContact.Address.Scheme := SipsScheme;

  Self.AddModuleSpecificHeaders(OutboundRequest);
  OutboundRequest.Supported.Value := Self.AllowedExtensions;
end;

function TIdSipAbstractCore.AddModule(ModuleType: TIdSipMessageModuleClass): TIdSipMessageModule;
begin
  if not Self.UsesModule(ModuleType) then begin
    Result := ModuleType.Create(Self);
    Self.Modules.Add(Result);
  end
  else begin
    Result := Self.ModuleFor(ModuleType);
  end;
end;

procedure TIdSipAbstractCore.AddObserver(const Listener: IIdObserver);
begin
  Self.Observed.AddObserver(Listener);
end;

function TIdSipAbstractCore.AddOutboundAction(ActionType: TIdSipActionClass): TIdSipAction;
begin
  Result := Self.Actions.AddOutboundAction(Self, ActionType);
end;

function TIdSipAbstractCore.AllowedContentTypes: String;
var
  CTs:             TStrings;
  CurrentMimeType: String;
  I, J:            Integer;
begin
  CTs := TStringList.Create;
  try
    // Collect a list of all known MIME types from the modules, and ensure
    // there're no duplicates.
    for I := 0 to Self.Modules.Count - 1 do begin
      for J := 0 to Self.ModuleAt(I).AllowedContentTypeList.Count - 1 do begin
        CurrentMimeType := Self.ModuleAt(I).AllowedContentTypeList[J];
        if (CTs.IndexOf(CurrentMimeType) = ItemNotFoundIndex) then
          CTs.Add(CurrentMimeType);
      end;
    end;

    Result := Self.ConvertToHeader(CTs);
  finally
    CTs.Free;
  end;
end;

function TIdSipAbstractCore.AllowedEncodings: String;
begin
  Result := '';
end;

function TIdSipAbstractCore.AllowedExtensions: String;
var
  Extensions: TStringList;
begin
  Extensions := TStringList.Create;
  try
    Extensions.Duplicates := dupIgnore;
    Extensions.Sorted     := true;
    Self.CollectAllowedExtensions(Extensions);

    // Remember, we ignore duplicates!
    if Self.UseGruu then
      Extensions.Add(ExtensionGruu);

    Result := Self.ConvertToHeader(Extensions);
  finally
    Extensions.Free;
  end;
end;

function TIdSipAbstractCore.AllowedLanguages: String;
begin
  Result := Self.ConvertToHeader(Self.AllowedLanguageList);
end;

function TIdSipAbstractCore.AllowedMethods(RequestUri: TIdSipUri): String;
begin
  // TODO: This is fake.
  Result := Self.KnownMethods;
end;

function TIdSipAbstractCore.AllowedSchemes: String;
begin
  Result := Self.ConvertToHeader(Self.AllowedSchemeList);
end;

function TIdSipAbstractCore.Authenticate(Request: TIdSipRequest): Boolean;
begin
  // We should ALWAYS have an authenticator attached: see TIdSipStackConfigurator.
  Result := Assigned(Self.Authenticator) and Self.Authenticator.Authenticate(Request);
end;

function TIdSipAbstractCore.CountOf(const MethodName: String): Integer;
begin
  Result := Self.Actions.CountOf(MethodName);
end;

function TIdSipAbstractCore.CreateChallengeResponse(Request: TIdSipRequest): TIdSipResponse;
begin
  Result := Self.Authenticator.CreateChallengeResponse(Request);
  Self.PrepareResponse(Result, Request);
end;

function TIdSipAbstractCore.CreateChallengeResponseAsUserAgent(Request: TIdSipRequest): TIdSipResponse;
begin
  Result := Self.Authenticator.CreateChallengeResponseAsUserAgent(Request);
  Self.PrepareResponse(Result, Request);
end;

function TIdSipAbstractCore.CreateRedirectedRequest(OriginalRequest: TIdSipRequest;
                                                    Contact: TIdSipAddressHeader): TIdSipRequest;
begin
  Result := TIdSipRequest.Create;
  Result.Assign(OriginalRequest);
  Result.CSeq.SequenceNo := Self.NextInitialSequenceNo;
  Result.LastHop.Branch  := Self.NextBranch;
  Result.RequestUri      := Contact.Address;
end;

function TIdSipAbstractCore.CreateRequest(const Method: String;
                                          Dest: TIdSipAddressHeader): TIdSipRequest;
begin
  if Dest.Address.HasMethod then begin
    if (Method <> Dest.Address.Method) then
      raise EIdSipTransactionUser.Create(Format(ContradictoryCreateRequestInvocation,
                                                [Method, Dest.Address.Method]));
  end;

  Result := Dest.Address.CreateRequest;
  try
    Result.CallID         := Self.NextCallID;
    Result.From           := Self.From;
    Result.From.Tag       := Self.NextTag;
    Result.Method         := Method;
    Result.ToHeader.Value := Dest.FullValue;

    Result.CSeq.Method     := Result.Method;
    Result.CSeq.SequenceNo := Self.NextInitialSequenceNo;

    Self.AddLocalHeaders(Result);
  except
    FreeAndNil(Result);

    raise;
  end;
end;

function TIdSipAbstractCore.CreateRequest(const Method: String;
                                          Dialog: TIdSipDialog): TIdSipRequest;
begin
  Result := Dialog.CreateRequest;
  try
    Result.Method      := Method;
    Result.CSeq.Method := Method;

    Self.AddLocalHeaders(Result);
  except
    FreeAndNil(Result);

    raise;
  end;
end;

function TIdSipAbstractCore.CreateResponse(Request: TIdSipRequest;
                                           ResponseCode: Cardinal): TIdSipResponse;
var
  ActualContact: TIdSipContactHeader;
begin
  if Self.UseGruu then
    ActualContact := Self.Gruu
  else
    ActualContact := Self.Contact;

  Result := TIdSipResponse.InResponseTo(Request,
                                        ResponseCode,
                                        ActualContact);

  Self.PrepareResponse(Result, Request);
end;

function TIdSipAbstractCore.FindActionForGruu(const LocalGruu: String): TIdSipAction;
begin
  Result := Self.Actions.FindActionForGruu(LocalGruu);
end;

procedure TIdSipAbstractCore.FindServersFor(Request: TIdSipRequest;
                                            Result: TIdSipLocations);
begin
  Self.Locator.FindServersFor(Request.DestinationUri, Result);
end;

procedure TIdSipAbstractCore.FindServersFor(Response: TIdSipResponse;
                                            Result: TIdSipLocations);
begin
  Self.Locator.FindServersFor(Response, Result);
end;

function TIdSipAbstractCore.HasUnknownContentEncoding(Request: TIdSipRequest): Boolean;
begin
  Result := Request.HasHeader(ContentEncodingHeaderFull);
end;

function TIdSipAbstractCore.HasUnknownContentLanguage(Request: TIdSipRequest): Boolean;
begin
  Result := Self.ListHasUnknownValue(Request,
                                     Self.AllowedLanguageList,
                                     ContentLanguageHeader);
end;

function TIdSipAbstractCore.HasUnsupportedExtension(Msg: TIdSipMessage): Boolean;
var
  I: Integer;
begin
  if not Msg.HasHeader(SupportedHeaderFull) then begin
    Result := false;
    Exit;
  end;

  Result := true;
  for I := 0 to Msg.Supported.Values.Count - 1 do
    Result := Result and Self.IsExtensionAllowed(Msg.Supported.Values[I]);

  Result := not Result;
end;

function TIdSipAbstractCore.IsExtensionAllowed(const Extension: String): Boolean;
begin
  Result := Pos(Extension, Self.AllowedExtensions) > 0;
end;

function TIdSipAbstractCore.IsMethodAllowed(RequestUri: TIdSipUri;
                                            const Method: String): Boolean;
begin
  // TODO: This is just a stub at the moment. Eventually we want to support
  // controlling rights for multiple URIs so that, for instance, we could allow a
  // non-User Agent to say "yes, you can SUBSCRIBE to A's state, but not to B's".
  Result := Self.IsMethodSupported(Method);
end;

function TIdSipAbstractCore.IsMethodSupported(const Method: String): Boolean;
begin
  Result := not Self.ModuleFor(Method).IsNull;
end;

function TIdSipAbstractCore.IsSchemeAllowed(const Scheme: String): Boolean;
begin
  Result := Self.AllowedSchemeList.IndexOf(Scheme) >= 0;
end;

function TIdSipAbstractCore.KnownMethods: String;
const
  Delimiter = ', ';
var
  I:              Integer;
  ModulesMethods: String;
begin
  Result := '';
  for I := 0 to Self.Modules.Count - 1 do begin
    ModulesMethods := (Self.Modules[I] as TIdSipMessageModule).AcceptsMethods;
    if (ModulesMethods <> '') then
      Result := Result + ModulesMethods + Delimiter;
  end;

  if (Result <> '') then
    Delete(Result, Length(Result) - 1, Length(Delimiter));
end;

function TIdSipAbstractCore.ModuleFor(Request: TIdSipRequest): TIdSipMessageModule;
var
  I: Integer;
begin
  Result := Self.NullModule;

  I := 0;
  while (I < Self.Modules.Count) and Result.IsNull do
    if (Self.Modules[I] as TIdSipMessageModule).WillAccept(Request) then
      Result := Self.Modules[I] as TIdSipMessageModule
    else
      Inc(I);

  if (Result = nil) then
    Result := Self.NullModule;
end;

function TIdSipAbstractCore.ModuleFor(const Method: String): TIdSipMessageModule;
var
  R: TIdSipRequest;
begin
  R := TIdSipRequest.Create;
  try
    R.Method := Method;

    Result := Self.ModuleFor(R);
  finally
    R.Free;
  end;
end;

function TIdSipAbstractCore.ModuleFor(ModuleType: TIdSipMessageModuleClass): TIdSipMessageModule;
var
  I: Integer;
begin
  I := 0;
  Result := Self.NullModule;

  while (I < Self.Modules.Count) and Result.IsNull do begin
    if (Self.Modules[I] is ModuleType) then
      Result := Self.Modules[I] as TIdSipMessageModule
    else Inc(I);
  end;
end;

function TIdSipAbstractCore.NextBranch: String;
begin
  Result := GRandomNumber.NextSipUserAgentBranch;
end;

function TIdSipAbstractCore.NextCallID: String;
begin
  Result := GRandomNumber.NextHexString + '@' + Self.HostName;
end;

function TIdSipAbstractCore.NextGrid: String;
begin
  Result := GRandomNumber.NextHexString;
end;

function TIdSipAbstractCore.NextInitialSequenceNo: Cardinal;
begin
  Result := GRandomNumber.NextCardinal($7FFFFFFF);
end;

function TIdSipAbstractCore.NextNonce: String;
begin
  Result := GRandomNumber.NextHexString;
end;

function TIdSipAbstractCore.NextTag: String;
begin
  Result := GRandomNumber.NextSipUserAgentTag;
end;

function TIdSipAbstractCore.OptionsCount: Integer;
begin
  Result := Self.Actions.OptionsCount;
end;

function TIdSipAbstractCore.QueryOptions(Server: TIdSipAddressHeader): TIdSipOutboundOptions;
begin
  Result := Self.AddOutboundAction(TIdSipOutboundOptions) as TIdSipOutboundOptions;
  Result.Server := Server;
end;

procedure TIdSipAbstractCore.RemoveModule(ModuleType: TIdSipMessageModuleClass);
var
  I: Integer;
begin
  I := 0;
  while (I < Self.Modules.Count) do begin
    if ((Self.Modules[I] as TIdSipMessageModule).ClassType = ModuleType) then begin
      Self.Modules.Delete(I);
      Break;
    end
    else
      Inc(I);
  end;
end;

procedure TIdSipAbstractCore.RemoveObserver(const Listener: IIdObserver);
begin
  Self.Observed.RemoveObserver(Listener);
end;

function TIdSipAbstractCore.RequiresUnsupportedExtension(Request: TIdSipRequest): Boolean;
var
  I: Integer;
begin
  if not Request.HasHeader(RequireHeader) then begin
    Result := false;
    Exit;
  end;

  Result := true;
  for I := 0 to Request.Require.Values.Count - 1 do
    Result := Result and Self.IsExtensionAllowed(Request.Require.Values[I]);

  Result := not Result;
end;

function TIdSipAbstractCore.ResponseForInvite: Cardinal;
begin
  // If we receive an INVITE (or an OPTIONS), what response code
  // would we return? If we don't wish to be disturbed, we return
  // SIPTemporarilyUnavailable; if we have no available lines, we
  // return SIPBusyHere, etc.

  Result := SIPOK;
end;

procedure TIdSipAbstractCore.ReturnResponse(Request: TIdSipRequest;
                                            Reason: Cardinal);
var
  Response: TIdSipResponse;
begin
  Response := Self.CreateResponse(Request, Reason);
  try
    Self.SendResponse(Response);
  finally
    Response.Free;
  end;
end;

procedure TIdSipAbstractCore.TerminateAllCalls;
begin
  // This is WRONG! It will also terminate subscriptions, which are not calls!
  Self.Actions.TerminateAllActions;
end;

function TIdSipAbstractCore.UsingDefaultContact: Boolean;
begin
  Result := Pos(Self.Contact.Address.Uri, Self.DefaultFrom) > 0;
end;

function TIdSipAbstractCore.UsingDefaultFrom: Boolean;
begin
  Result := Pos(Self.From.Address.Uri, Self.DefaultFrom) > 0;
end;

procedure TIdSipAbstractCore.ScheduleEvent(BlockType: TIdSipActionClosureClass;
                                           WaitTime: Cardinal;
                                           Copy: TIdSipMessage;
                                           const ActionID: String);
var
  Event: TIdSipActionsWait;
begin
  if not Assigned(Self.Timer) then
    Exit;

  Event := Self.CreateActionsClosure(TIdSipActionsWait, Copy) as TIdSipActionsWait;
  Event.BlockType := BlockType;
  Event.ActionID  := ActionID;
  Self.ScheduleEvent(WaitTime, Event);
end;

procedure TIdSipAbstractCore.ScheduleEvent(Event: TNotifyEvent;
                                           WaitTime: Cardinal;
                                           Msg: TIdSipMessage);
var
  RequestEvent: TIdSipMessageNotifyEventWait;
begin
  if Assigned(Self.Timer) then begin
    RequestEvent := TIdSipMessageNotifyEventWait.Create;
    RequestEvent.Message := Msg;
    RequestEvent.Event   := Event;
    Self.Timer.AddEvent(WaitTime, RequestEvent);
  end;
end;

procedure TIdSipAbstractCore.ScheduleEvent(WaitTime: Cardinal;
                                           Wait: TIdWait);
begin
  if not Assigned(Self.Timer) then
    Exit;

  Self.Timer.AddEvent(WaitTime, Wait);
end;

procedure TIdSipAbstractCore.SendRequest(Request: TIdSipRequest;
                                         Dest: TIdSipLocation);
begin
  Self.MaybeChangeTransport(Request);
  if Self.RequiresUnsupportedExtension(Request) then
    raise EIdSipTransactionUser.Create(Format(MessageSendFailureUnknownExtension,
                                              [Request.Require.Value]));

  if Self.HasUnsupportedExtension(Request) then
    raise EIdSipTransactionUser.Create(Format(MessageSendFailureUnknownExtension,
                                              [Request.Supported.Value]));

  // If we know how to receive the message, or we're a UA and we're sending a
  // REGISTER, then send the message. Otherwise, raise an exception.
  if    (Self.ModuleFor(Request.Method).IsNull
    and (Self.ModuleFor(TIdSipOutboundRegisterModule).IsNull or not Request.IsRegister)) then
    raise EIdSipTransactionUser.Create(Format(MessageSendFailureUnknownMethod,
                                              [Request.Method]));

  if Request.IsMalformed then
    raise EIdSipTransactionUser.Create(Format(MessageSendFailureMalformed,
                                              [Request.ParseFailReason]));

  Self.Dispatcher.SendRequest(Request, Dest);
end;

procedure TIdSipAbstractCore.SendResponse(Response: TIdSipResponse);
begin
  Self.MaybeChangeTransport(Response);

  if Self.HasUnsupportedExtension(Response) then
    raise EIdSipTransactionUser.Create(Format(MessageSendFailureUnknownExtension,
                                              [Response.Supported.Value]));

  if Response.IsMalformed then
    raise EIdSipTransactionUser.Create(Format(MessageSendFailureMalformed,
                                              [Response.ParseFailReason]));

  Self.Dispatcher.SendResponse(Response);
end;

procedure TIdSipAbstractCore.StartAllTransports;
begin
  Self.Dispatcher.StartAllTransports;
end;

procedure TIdSipAbstractCore.StopAllTransports;
begin
  Self.Dispatcher.StopAllTransports;
end;

function TIdSipAbstractCore.Username: String;
begin
  Result := Self.From.Address.Username;
end;

function TIdSipAbstractCore.UsesModule(ModuleType: TIdSipMessageModuleClass): Boolean;
begin
  Result := not Self.ModuleFor(ModuleType).IsNull;
end;

//* TIdSipAbstractCore Protected methods ***************************************

procedure TIdSipAbstractCore.ActOnRequest(Request: TIdSipRequest;
                                          Receiver: TIdSipTransport);
var
  Actor: TIdSipUserAgentActOnRequest;
begin
  Actor := Self.CreateRequestHandler(Request, Receiver);
  try
    Self.Actions.Perform(Request, Actor, false);
  finally
    Actor.Free;
  end;
end;

procedure TIdSipAbstractCore.ActOnResponse(Response: TIdSipResponse;
                                           Receiver: TIdSipTransport);
var
  Actor: TIdSipUserAgentActOnResponse;
begin
  Actor := Self.CreateResponseHandler(Response, Receiver);
  try
    Self.Actions.Perform(Response, Actor, true);
  finally
    Actor.Free;
  end;
end;

function TIdSipAbstractCore.CreateActionsClosure(ClosureType: TIdSipActionsWaitClass;
                                                 Msg: TIdSipMessage): TIdSipActionsWait;
begin
  Result := ClosureType.Create;
  Result.Actions := Self.Actions;
  Result.Message := Msg.Copy;
end;

function TIdSipAbstractCore.GetUseGruu: Boolean;
begin
  Result := Self.fUseGruu;
end;

function TIdSipAbstractCore.ListHasUnknownValue(Request: TIdSipRequest;
                                                ValueList: TStrings;
                                                const HeaderName: String): Boolean;
begin
  Result := Request.HasHeader(HeaderName)
       and (ValueList.IndexOf(Request.FirstHeader(HeaderName).Value) = ItemNotFoundIndex);
end;

procedure TIdSipAbstractCore.NotifyOfChange;
begin
  Self.Observed.NotifyListenersOfChange(Self);
end;

procedure TIdSipAbstractCore.NotifyOfDroppedMessage(Message: TIdSipMessage;
                                                    Receiver: TIdSipTransport);
begin
  // By default do nothing.
end;
{
procedure TIdSipAbstractCore.OnAuthenticationChallenge(Dispatcher: TIdSipTransactionDispatcher;
                                                            Challenge: TIdSipResponse;
                                                            ChallengeResponse: TIdSipRequest;
                                                            var TryAgain: Boolean);
var
  AuthHeader:      TIdSipAuthorizationHeader;
  ChallengeHeader: TIdSipAuthenticateHeader;
  Password:        String;
  RealmInfo:       TIdRealmInfo;
  Username:        String;
begin
  // We've received a 401 or 407 response. At this level of the stack we know
  // this response matches a request that we sent out since the transaction
  // layer drops unmatched responses.
  //
  // Now we've a few cases:
  // 1. The response matches something like an INVITE, OPTIONS, etc. FindAction
  //    will return a reference to this action;
  // 2. The response matches a BYE, in which case FindAction will return nil.
  //    Since we consider the session terminated as soon as we send the BYE,
  //    we cannot match the response to an action.
  //
  // In case 1, we find the action and update its initial request. In case 2,
  // we just fake things a bit - we re-issue the request with incremented
  // sequence number and an authentication token, and hope for the best. Really,
  // UASs shouldn't challenge BYEs - since the UAC has left the session,
  // there's no real way to defend against a spoofed BYE: if the UAC did send
  // the BYE, it's left the conversation. If it didn't, the UAC will simply
  // drop your challenge.

  // Usually we want to re-issue a challenged request:
  TryAgain := true;

  // But listeners can decide not to:
  Self.NotifyOfAuthenticationChallenge(Challenge, Username, Password, TryAgain);
  try
    if not TryAgain then Exit;

    ChallengeHeader := Challenge.AuthenticateHeader;

    // All challenges MUST have either a Proxy-Authenticate header or a
    // WWW-Authenticate header. If a response without one of these headers makes
    // it all the way here, we simply cannot do anything with it.
    if not Assigned(ChallengeHeader) then
      Exit;

    Self.Keyring.AddKey(ChallengeHeader,
                        ChallengeResponse.RequestUri.AsString,
                        Username);

    // This may look a bit like a time-of-check/time-of-use race condition
    // ("what if something frees the RealmInfo before you use it?") but it's
    // not - you can't remove realms from the Keyring, only add them.
    RealmInfo := Self.Keyring.Find(ChallengeHeader.Realm,
                                   ChallengeResponse.RequestUri.AsString);

    AuthHeader := RealmInfo.CreateAuthorization(Challenge,
                                                ChallengeResponse.Method,
                                                ChallengeResponse.Body,
                                                Password);
    try
      ChallengeResponse.AddHeader(AuthHeader);
    finally
      AuthHeader.Free;
    end;

    Self.UpdateAffectedActionWithRequest(Challenge, ChallengeResponse);
  finally
    // Write over the buffer that held the password.
    FillChar(Password, Length(Password), 0);
  end;
end;
}
procedure TIdSipAbstractCore.PrepareResponse(Response: TIdSipResponse;
                                             Request: TIdSipRequest);
begin
  if not Request.ToHeader.HasTag then
    Response.ToHeader.Tag := Self.NextTag;

  if (Self.UserAgentName <> '') then
    Response.AddHeader(ServerHeader).Value := Self.UserAgentName;

  Response.AddHeader(SupportedHeaderFull).Value := Self.AllowedExtensions;

  // There's a nasty assumption here: that there's only one Contact in the Response.
  if Self.UseGruu and TIdSipMessage.WillEstablishDialog(Request, Response) then
    Response.FirstContact.Grid := Self.NextGrid;

  Self.AddModuleSpecificHeaders(Response);
end;

procedure TIdSipAbstractCore.RejectRequest(Reaction: TIdSipUserAgentReaction;
                                           Request: TIdSipRequest);
begin
  case Reaction of
    uarBadAuthorization:
      Self.RejectBadAuthorization(Request);
    uarLoopDetected:
      Self.ReturnResponse(Request, SIPLoopDetected);
    uarUnauthorized:
      Self.RejectRequestUnauthorized(Request);
    uarUnsupportedExtension:
      Self.RejectRequestBadExtension(Request);
    uarUnsupportedMethod:
      Self.RejectRequestMethodNotSupported(Request);
  else
    // What do we do here? We've rejected the request for a good reason, but have
    // forgotten to implement the bit where we send a reasonable response.
    raise Exception.Create(Self.ClassName
                         + '.RejectRequest: Can''t handle a reaction '
                         + ReactionToStr(Reaction));
  end;
end;

procedure TIdSipAbstractCore.RejectRequestUnauthorized(Request: TIdSipRequest);
var
  Response: TIdSipResponse;
begin
  Response := Self.CreateChallengeResponse(Request);
  try
    Self.SendResponse(Response);
  finally
    Response.Free;
  end;
end;

procedure TIdSipAbstractCore.SetAuthenticator(Value: TIdSipAbstractAuthenticator);
begin
  Self.fAuthenticator := Value;
  Self.fAuthenticator.Realm := Self.Realm;

  Self.fAuthenticator.IsProxy := false;
end;

procedure TIdSipAbstractCore.SetUseGruu(Value: Boolean);
begin
  Self.fUseGruu := Value;
end;

function TIdSipAbstractCore.WillAcceptRequest(Request: TIdSipRequest): TIdSipUserAgentReaction;
begin
  Result := uarAccept;

  // cf RFC 3261 section 8.2
  // But this is a monkey authentication scheme: we really want a much more
  // fine-grained system: "yes, you can INVITE, but you can only SUBSCRIBE if
  // you're foo or bar."
  if Self.RequireAuthentication then begin
    try
      if not Self.Authenticate(Request) then
        Result := uarUnauthorized;
    except
      on EAuthenticate do
        Result := uarBadAuthorization;
    end;
  end
  // inspect the method - 8.2.1
  // This result code means "I have no modules that can accept this method"
  else if not Self.IsMethodSupported(Request.Method) then
    Result := uarUnsupportedMethod
  // Merged requests - 8.2.2.2
  else if not Request.ToHeader.HasTag and Self.Dispatcher.LoopDetected(Request) then
    Result := uarLoopDetected
  // Require - 8.2.2.3
  else if Self.RequiresUnsupportedExtension(Request) then
    Result := uarUnsupportedExtension;
end;

function  TIdSipAbstractCore.WillAcceptResponse(Response: TIdSipResponse): TIdSipUserAgentReaction;
begin
  // cf RFC 3261 section 8.1.3.3
  if (Response.Path.Count > 1) then
    Result := uarTooManyVias
  else
    Result := uarAccept;
end;

//* TIdSipAbstractCore Private methods *****************************************

procedure TIdSipAbstractCore.AddModuleSpecificHeaders(OutboundMessage: TIdSipMessage);
var
  I: Integer;
begin
  for I := 0 to Self.Modules.Count - 1 do
    Self.ModuleAt(I).AddLocalHeaders(OutboundMessage);
end;

procedure TIdSipAbstractCore.CollectAllowedExtensions(ExtensionList: TStrings);
var
  I:                Integer;
  ModuleExtensions: TStrings;
begin
  ExtensionList.Clear;

  ModuleExtensions := TStringList.Create;
  try
    for I := 0 to Self.Modules.Count - 1 do begin
      ModuleExtensions.CommaText := Self.ModuleAt(I).AllowedExtensions;
      ExtensionList.AddStrings(ModuleExtensions);
    end;
  finally
    ModuleExtensions.Free;
  end;
end;

function TIdSipAbstractCore.ConvertToHeader(ValueList: TStrings): String;
begin
  Result := StringReplace(ValueList.CommaText, ',', ', ', [rfReplaceAll]);
end;

function TIdSipAbstractCore.CreateRequestHandler(Request: TIdSipRequest;
                                                 Receiver: TIdSipTransport): TIdSipUserAgentActOnRequest;
begin
  Result := TIdSipUserAgentActOnRequest.Create;

  Result.Receiver  := Receiver;
  Result.Request   := Request;
  Result.UserAgent := Self;
end;

function TIdSipAbstractCore.CreateResponseHandler(Response: TIdSipResponse;
                                                  Receiver: TIdSipTransport): TIdSipUserAgentActOnResponse;
begin
  Result := TIdSipUserAgentActOnResponse.Create;

  Result.Receiver  := Receiver;
  Result.Response  := Response;
  Result.UserAgent := Self;
end;

function TIdSipAbstractCore.DefaultFrom: String;
begin
  Result := 'unknown <sip:unknown@' + Self.HostName + '>';
end;

function TIdSipAbstractCore.DefaultHostName: String;
begin
  Result := 'localhost';
end;

function TIdSipAbstractCore.DefaultUserAgent: String;
begin
  Result := 'RNID SipStack v' + SipStackVersion;
end;

procedure TIdSipAbstractCore.MaybeChangeTransport(Msg: TIdSipMessage);
var
  MsgLen:       Cardinal;
  RewrittenVia: Boolean;
begin
  MsgLen := Length(Msg.AsString);
  RewrittenVia := (MsgLen > MaximumUDPMessageSize)
              and (Msg.LastHop.Transport = UdpTransport);

  if RewrittenVia then
    Msg.LastHop.Transport := TcpTransport;
end;

function TIdSipAbstractCore.ModuleAt(Index: Integer): TIdSipMessageModule;
begin
  Result := Self.Modules[Index] as TIdSipMessageModule;
end;

procedure TIdSipAbstractCore.NotifyModulesOfFree;
var
  I: Integer;
begin
  for I := 0 to Self.Modules.Count - 1 do
    Self.ModuleAt(I).CleanUp;
end;

procedure TIdSipAbstractCore.OnChanged(Observed: TObject);
begin
  Self.NotifyOfChange;
end;

procedure TIdSipAbstractCore.OnReceiveRequest(Request: TIdSipRequest;
                                              Receiver: TIdSipTransport);
var
  Reaction: TIdSipUserAgentReaction;
begin
  Reaction := Self.WillAcceptRequest(Request);
  if (Reaction = uarAccept) then
    Self.ActOnRequest(Request, Receiver)
  else
    Self.RejectRequest(Reaction, Request);
end;

procedure TIdSipAbstractCore.OnReceiveResponse(Response: TIdSipResponse;
                                               Receiver: TIdSipTransport);
begin
  if (Self.WillAcceptResponse(Response) = uarAccept) then
    Self.ActOnResponse(Response, Receiver);
end;

procedure TIdSipAbstractCore.OnTransportException(FailedMessage: TIdSipMessage;
                                                  Error: Exception;
                                                  const Reason: String);
var
  SendFailed: TIdSipActionNetworkFailure;
begin
  SendFailed := TIdSipActionNetworkFailure.Create;
  try
    SendFailed.Error         := Error;
    SendFailed.FailedMessage := FailedMessage;
    SendFailed.Reason        := Reason;

    // Failing to send a Request means a UAC action's Send failed.
    Self.Actions.Perform(FailedMessage, SendFailed, FailedMessage.IsRequest);
  finally
    SendFailed.Free;
  end;
end;

procedure TIdSipAbstractCore.RejectBadAuthorization(Request: TIdSipRequest);
var
  Response: TIdSipResponse;
begin
  Response := Self.CreateResponse(Request, SIPBadRequest);
  try
    Response.StatusText := BadAuthorizationTokens;

    Self.SendResponse(Response);
  finally
    Response.Free;
  end;
end;

procedure TIdSipAbstractCore.RejectMethodNotAllowed(Request: TIdSipRequest);
var
  Response: TIdSipResponse;
begin
  Response := Self.CreateResponse(Request, SIPMethodNotAllowed);
  try
    Response.AddHeader(AllowHeader).Value := Self.AllowedMethods(Request.RequestUri);

    Self.SendResponse(Response);
  finally
    Response.Free;
  end;
end;

procedure TIdSipAbstractCore.RejectRequestBadExtension(Request: TIdSipRequest);
var
  Response: TIdSipResponse;
begin
  // We simply reject ALL Requires
  Response := Self.CreateResponse(Request, SIPBadExtension);
  try
    Response.AddHeader(UnsupportedHeader).Value := Request.FirstHeader(RequireHeader).Value;

    Self.SendResponse(Response);
  finally
    Response.Free;
  end;
end;

procedure TIdSipAbstractCore.RejectRequestMethodNotSupported(Request: TIdSipRequest);
var
  Response: TIdSipResponse;
begin
  Response := Self.CreateResponse(Request, SIPNotImplemented);
  try
    Response.StatusText := Response.StatusText + ' (' + Request.Method + ')';
    Response.AddHeader(AllowHeader).Value := Self.KnownMethods;

    Self.SendResponse(Response);
  finally
    Response.Free;
  end;
end;

procedure TIdSipAbstractCore.RejectUnsupportedSipVersion(Request: TIdSipRequest);
var
  Response: TIdSipResponse;
begin
  Response := Self.CreateResponse(Request, SIPSIPVersionNotSupported);
  try
    Self.SendResponse(Response);
  finally
    Response.Free;
  end;
end;

procedure TIdSipAbstractCore.SetContact(Value: TIdSipContactHeader);
begin
  Assert(not Value.IsWildCard,
         'You may not use a wildcard Contact header for a User Agent''s '
       + 'Contact');

  Self.Contact.Assign(Value);

  if Self.Contact.IsMalformed then
    raise EBadHeader.Create(Self.Contact.Name);

  if not Self.Contact.Address.IsSipUri then
    raise EBadHeader.Create(Self.Contact.Name + ': MUST be a SIP/SIPS URI');
end;

procedure TIdSipAbstractCore.SetDispatcher(Value: TIdSipTransactionDispatcher);
begin
  Self.fDispatcher := Value;

  Self.fDispatcher.AddTransactionDispatcherListener(Self);
end;

procedure TIdSipAbstractCore.SetFrom(Value: TIdSipFromHeader);
begin
  Self.From.Assign(Value);

  if Self.From.IsMalformed then
    raise EBadHeader.Create(Self.From.Name);

  if not Self.From.Address.IsSipUri then
    raise EBadHeader.Create(Self.From.Name + ': MUST be a SIP/SIPS URI');
end;

procedure TIdSipAbstractCore.SetGruu(Value: TIdSipContactHeader);
begin
  Self.Gruu.Assign(Value);
end;

procedure TIdSipAbstractCore.SetInstanceID(Value: String);
begin
  if not TIdSipParser.IsUuidUrn(Value) then
    raise EIdSipTransactionUser.Create(Format(NotAnUUIDURN, [Value]));

  Self.fInstanceID := Value;
end;

procedure TIdSipAbstractCore.SetRealm(const Value: String);
begin
  Self.fRealm := Value;

  if Assigned(Self.Authenticator) then
    Self.Authenticator.Realm := Self.Realm;
end;

//******************************************************************************
//* TIdSipMessageModule                                                        *
//******************************************************************************
//* TIdSipMessageModule Public methods *****************************************

constructor TIdSipMessageModule.Create(UA: TIdSipAbstractCore);
begin
  inherited Create;

  Self.AcceptsMethodsList     := TStringList.Create;
  Self.AcceptsMethodsList.CaseSensitive := true;
  Self.AllowedContentTypeList := TStringList.Create;
  Self.Listeners              := TIdNotificationList.Create;

  Self.fUserAgent             := UA;
end;

destructor TIdSipMessageModule.Destroy;
begin
  Self.Listeners.Free;
  Self.AllowedContentTypeList.Free;
  Self.AcceptsMethodsList.Free;

  inherited Destroy;
end;

function TIdSipMessageModule.Accept(Request: TIdSipRequest;
                                    UsingSecureTransport: Boolean): TIdSipAction;
var
  WillAccept: TIdSipUserAgentReaction;
begin
  WillAccept := Self.WillAcceptRequest(Request);

  if (WillAccept = uarAccept) then
    Result := Self.AcceptRequest(Request, UsingSecureTransport)
  else begin
    Result := nil;
    Self.RejectRequest(WillAccept, Request);
  end;
end;

procedure TIdSipMessageModule.AddAllowedContentType(const MimeType: String);
begin
  if (Trim(MimeType) <> '') then begin
    if (Self.AllowedContentTypeList.IndexOf(MimeType) = ItemNotFoundIndex) then
      Self.AllowedContentTypeList.Add(MimeType);
  end;
end;

procedure TIdSipMessageModule.AddAllowedContentTypes(MimeTypes: TStrings);
var
  I: Integer;
begin
  for I := 0 to MimeTypes.Count - 1 do
    Self.AddAllowedContentType(MimeTypes[I]);
end;

procedure TIdSipMessageModule.AddLocalHeaders(OutboundMessage: TIdSipMessage);
begin
end;

function TIdSipMessageModule.AcceptsMethods: String;
begin
  Result := Self.ConvertToHeader(Self.AcceptsMethodsList);
end;

function TIdSipMessageModule.AllowedContentTypes: TStrings;
begin
  Result := Self.AllowedContentTypeList;
end;

function TIdSipMessageModule.AllowedExtensions: String;
begin
  Result := '';
end;

procedure TIdSipMessageModule.CleanUp;
begin
  // When the User Agent frees, it calls this method. Put any cleanup stuff
  // here.
end;

function TIdSipMessageModule.HasKnownAccept(Request: TIdSipRequest): Boolean;
var
  I: Integer;
begin
  // No Accept header means the same as "Accept: application/sdp" - cf. RFC
  // 3261, section 11.2
  Result := not Request.HasHeader(AcceptHeader);

  if not Result then begin
    Result := Request.Accept.ValueCount = 0;

    if not Result then begin
      for I := 0 to Request.Accept.ValueCount - 1 do begin
        Result := Self.SupportsMimeType(Request.Accept.Values[I].Value);

        if Result then Break;
      end;
    end;
  end;
end;

function TIdSipMessageModule.HasUnknownContentType(Request: TIdSipRequest): Boolean;
begin
  Result := Self.ListHasUnknownValue(Request,
                                     Self.AllowedContentTypeList,
                                     ContentTypeHeaderFull);
end;

function TIdSipMessageModule.IsNull: Boolean;
begin
  Result := false;
end;

function TIdSipMessageModule.SupportsMimeType(const MimeType: String): Boolean;
begin
  Result := Self.AllowedContentTypeList.IndexOf(MimeType) <> ItemNotFoundIndex;
end;

function TIdSipMessageModule.WillAccept(Request: TIdSipRequest): Boolean;
begin
  Result := Self.AcceptsMethodsList.IndexOf(Request.Method) <> ItemNotFoundIndex;
end;

//* TIdSipMessageModule Protected methods **************************************

function TIdSipMessageModule.AcceptRequest(Request: TIdSipRequest;
                                           UsingSecureTransport: Boolean): TIdSipAction;
begin
  Result := nil;
end;

function TIdSipMessageModule.ListHasUnknownValue(Request: TIdSipRequest;
                                                 ValueList: TStrings;
                                                 const HeaderName: String): Boolean;
begin
  Result := Request.HasHeader(HeaderName)
       and (ValueList.IndexOf(Request.FirstHeader(HeaderName).Value) = ItemNotFoundIndex);
end;

procedure TIdSipMessageModule.RejectBadRequest(Request: TIdSipRequest;
                                               const Reason: String);
var
  Response: TIdSipResponse;
begin
  Response := Self.UserAgent.CreateResponse(Request, SIPBadRequest);
  try
    Response.StatusText := Reason;
    Self.UserAgent.SendResponse(Response);
  finally
    Response.Free;
  end;
end;

procedure TIdSipMessageModule.RejectRequest(Reaction: TIdSipUserAgentReaction;
                                            Request: TIdSipRequest);
begin
  case Reaction of
    uarDoNotDisturb:
          Self.ReturnResponse(Request,
                              SIPTemporarilyUnavailable);
    uarDoNothing:; // Do nothing, and the Transaction-User core will drop the message.                          
    uarMethodNotAllowed:
      Self.UserAgent.RejectMethodNotAllowed(Request);
    uarMissingContact:
      Self.RejectBadRequest(Request, MissingContactHeader);
    uarNonInviteWithReplaces:
      Self.RejectBadRequest(Request, NonInviteWithReplacesHeader);
    uarNoSuchCall:
      Self.ReturnResponse(Request, SIPCallLegOrTransactionDoesNotExist);
    uarUnsupportedAccept:
      Self.RejectRequestUnknownAccept(Request);
    uarUnsupportedContentEncoding:
      Self.RejectRequestUnknownContentEncoding(Request);
    uarUnsupportedContentLanguage:
      Self.RejectRequestUnknownContentLanguage(Request);
    uarUnsupportedContentType:
      Self.RejectRequestUnknownContentType(Request);
    uarUnsupportedScheme:
      Self.ReturnResponse(Request, SIPUnsupportedURIScheme);
    uarUnSupportedSipVersion:
      Self.UserAgent.RejectUnsupportedSipVersion(Request);
  else
    // What do we do here? We've rejected the request for a good reason, but have
    // forgotten to implement the bit where we send a reasonable response.
    raise Exception.Create(Self.ClassName
                         + '.RejectRequest: Can''t handle a reaction '
                         + ReactionToStr(Reaction));
  end;
end;

procedure TIdSipMessageModule.ReturnResponse(Request: TIdSipRequest;
                                             Reason: Cardinal);
begin
  Self.UserAgent.ReturnResponse(Request, Reason);
end;

function TIdSipMessageModule.WillAcceptRequest(Request: TIdSipRequest): TIdSipUserAgentReaction;
begin
  Result := uarAccept;

  if (Request.SIPVersion <> SipVersion) then
    Result := uarUnsupportedSipVersion
  else if not Self.UserAgent.IsMethodAllowed(Request.RequestUri, Request.Method) then
    Result := uarMethodNotAllowed
  // inspect the headers - 8.2.2
  // To & Request-URI - 8.2.2.1
  else if not Self.UserAgent.IsSchemeAllowed(Request.RequestUri.Scheme) then
    Result := uarUnsupportedScheme
  // Content processing - 8.2.3
  // Does the Accept not contain ANY known MIME type?
  else if not Self.HasKnownAccept(Request) then
    Result := uarUnsupportedAccept
  else if not Self.HasKnownAccept(Request) then
    Result := uarUnsupportedAccept
  else if Self.UserAgent.HasUnknownContentEncoding(Request) then
    Result := uarUnsupportedContentEncoding
  else if Self.UserAgent.HasUnknownContentLanguage(Request) then
    Result := uarUnsupportedContentLanguage
  else if Self.HasUnknownContentType(Request) then
    Result := uarUnsupportedContentType
  else if not Request.IsInvite and Request.HasReplaces then
    Result := uarNonInviteWithReplaces;
end;

//* TIdSipMessageModule Private methods ****************************************

function TIdSipMessageModule.ConvertToHeader(ValueList: TStrings): String;
begin
  Result := StringReplace(ValueList.CommaText, ',', ', ', [rfReplaceAll]);
end;

procedure TIdSipMessageModule.RejectRequestUnknownAccept(Request: TIdSipRequest);
var
  Response: TIdSipResponse;
begin
  Response := Self.UserAgent.CreateResponse(Request, SIPNotAcceptableClient);
  try
    Response.AddHeader(AcceptHeader).Value := Self.ConvertToHeader(Self.AllowedContentTypes);

    Self.UserAgent.SendResponse(Response);
  finally
    Response.Free;
  end;
end;

procedure TIdSipMessageModule.RejectRequestUnknownContentEncoding(Request: TIdSipRequest);
var
  Response: TIdSipResponse;
begin
  Response := Self.UserAgent.CreateResponse(Request, SIPUnsupportedMediaType);
  try
    Response.AddHeader(AcceptEncodingHeader).Value := '';

    Self.UserAgent.SendResponse(Response);
  finally
    Response.Free;
  end;
end;

procedure TIdSipMessageModule.RejectRequestUnknownContentLanguage(Request: TIdSipRequest);
var
  Response: TIdSipResponse;
begin
  // It seems a stretch to say that an unsupported language would fall under
  //"unsupported media type, but the RFC says so (RFC 3261, cf section 8.2.3)
  Response := Self.UserAgent.CreateResponse(Request, SIPUnsupportedMediaType);
  try
    Response.AddHeader(AcceptLanguageHeader).Value := Self.UserAgent.AllowedLanguages;

    Self.UserAgent.SendResponse(Response);
  finally
    Response.Free;
  end;
end;

procedure TIdSipMessageModule.RejectRequestUnknownContentType(Request: TIdSipRequest);
var
  Response: TIdSipResponse;
begin
  Response := Self.UserAgent.CreateResponse(Request, SIPUnsupportedMediaType);
  try
    Response.Accept.Value := Self.ConvertToHeader(Self.AllowedContentTypes);

    Self.UserAgent.SendResponse(Response);
  finally
    Response.Free;
  end;
end;

//******************************************************************************
//* TIdSipNullModule                                                           *
//******************************************************************************
//* TIdSipNullModule Public methods ********************************************

function TIdSipNullModule.IsNull: Boolean;
begin
  Result := true;
end;

function TIdSipNullModule.WillAccept(Request: TIdSipRequest): Boolean;
begin
  Result := true;
end;

//* TIdSipNullModule Public methods ********************************************

function TIdSipNullModule.WillAcceptRequest(Request: TIdSipRequest): TIdSipUserAgentReaction;
begin
  Result := uarNoSuchCall;
end;

//******************************************************************************
//* TIdSipOptionsModule                                                        *
//******************************************************************************
//* TIdSipOptionsModule Public methods *****************************************

constructor TIdSipOptionsModule.Create(UA: TIdSipAbstractCore);
begin
  inherited Create(UA);;

  Self.AcceptsMethodsList.Add(MethodOptions);
  Self.AllowedContentTypeList.Add(SdpMimeType);
end;

function TIdSipOptionsModule.Accept(Request: TIdSipRequest;
                                    UsingSecureTransport: Boolean): TIdSipAction;
begin
  Result := inherited Accept(Request, UsingSecureTransport);

  if not Assigned(Result) then
    Result := TIdSipInboundOptions.CreateInbound(Self.UserAgent,
                                                 Request,
                                                 UsingSecureTransport);
end;

function TIdSipOptionsModule.AcceptsMethods: String;
begin
  Result := MethodOptions;
end;

function TIdSipOptionsModule.CreateOptions(Dest: TIdSipAddressHeader): TIdSipRequest;
begin
  Result := Self.UserAgent.CreateRequest(MethodOptions, Dest);
  try
    Result.AddHeader(AcceptHeader).Value := Self.UserAgent.AllowedContentTypes;
  except
    FreeAndNil(Result);

    raise;
  end;
end;

//* TIdSipOptionsModule Protected methods **************************************

function TIdSipOptionsModule.WillAcceptRequest(Request: TIdSipRequest): TIdSipUserAgentReaction;
var
  InviteModule: TIdSipInviteModule;
begin
  Result := inherited WillAcceptRequest(Request);

  if (Result = uarAccept) then begin
    InviteModule := Self.UserAgent.ModuleFor(MethodInvite) as TIdSipInviteModule;
    if Assigned(InviteModule) then begin
      if InviteModule.DoNotDisturb then
        Result := uarDoNotDisturb;
    end;
  end;
end;

//******************************************************************************
//* TIdSipAction                                                               *
//******************************************************************************
//* TIdSipAction Public methods ************************************************

constructor TIdSipAction.Create(UA: TIdSipAbstractCore);
begin
  inherited Create;

  Self.Initialise(UA, nil, false);
end;

constructor TIdSipAction.CreateInbound(UA: TIdSipAbstractCore;
                                       Request: TIdSipRequest;
                                       UsingSecureTransport: Boolean);
begin
  inherited Create;

  Self.Initialise(UA, Request, UsingSecureTransport);
  Self.ReceiveRequest(Request);
end;

destructor TIdSipAction.Destroy;
begin
  TIdSipActionRegistry.UnregisterAction(Self.ID);

  Self.TargetLocations.Free;
  Self.LocalGruu.Free;
  Self.InitialRequest.Free;
  Self.ActionListeners.Free;

  inherited Destroy;
end;

procedure TIdSipAction.AddActionListener(Listener: IIdSipActionListener);
begin
  Self.ActionListeners.AddListener(Listener);
end;

function TIdSipAction.IsInbound: Boolean;
begin
  Result := false;
end;

function TIdSipAction.IsInvite: Boolean;
begin
  Result := false;
end;

function TIdSipAction.IsOptions: Boolean;
begin
  Result := false;
end;

function TIdSipAction.IsRegistration: Boolean;
begin
  Result := false;
end;

function TIdSipAction.IsSession: Boolean;
begin
  Result := false;
end;

function TIdSipAction.Match(Msg: TIdSipMessage): Boolean;
begin
  if Msg.IsRequest and (Msg as TIdSipRequest).IsCancel then
    Result := Self.InitialRequest.MatchCancel(Msg as TIdSipRequest)
  else
    Result := Self.InitialRequest.Match(Msg);
end;

procedure TIdSipAction.NetworkFailureSending(Msg: TIdSipMessage);
var
  FailReason: String;
  NewAttempt: TIdSipRequest;
begin
  // You tried to send a request. It failed. The UA core invokes this method to
  // try the next possible location.

  if Msg.IsRequest then begin
    if (Msg as TIdSipRequest).IsAck then begin
      FailReason := Format(RSNoLocationSucceeded, [(Msg as TIdSipRequest).DestinationUri]);
      Self.NotifyOfNetworkFailure(NoLocationSucceeded,
                                  Format(OutboundActionFailed,
                                         [Self.Method, FailReason]));
    end
    else begin
      if not Self.TargetLocations.IsEmpty then begin
        NewAttempt := Self.CreateNewAttempt;
        try
          Self.TrySendRequest(NewAttempt, Self.TargetLocations.First)
        finally
          NewAttempt.Free;
        end;
      end
      else begin
        FailReason := Format(RSNoLocationSucceeded, [(Msg as TIdSipRequest).DestinationUri]);
        Self.NotifyOfNetworkFailure(NoLocationSucceeded,
                                  Format(OutboundActionFailed,
                                         [Self.Method, FailReason]));
      end;
    end;
  end;
end;

procedure TIdSipAction.ReceiveRequest(Request: TIdSipRequest);
begin
  Self.ReceiveOtherRequest(Request);
end;

procedure TIdSipAction.ReceiveResponse(Response: TIdSipResponse;
                                       UsingSecureTransport: Boolean);
var
  Succeeded: TIdSipActionResult;
begin
  // Each of the ReceiveXXXResponse functions returns true if we succeeded
  // in our Action, or we could re-issue the request. They only return
  // false when the action failed irrecoverably.

  case Response.StatusCode div 100 of
    SIPProvisionalResponseClass:
      Succeeded := Self.ReceiveProvisionalResponse(Response,
                                                   UsingSecureTransport);
    SIPOKResponseClass:
      Succeeded := Self.ReceiveOKResponse(Response,
                                          UsingSecureTransport);
    SIPRedirectionResponseClass:
      Succeeded := Self.ReceiveRedirectionResponse(Response,
                                                   UsingSecureTransport);
    SIPFailureResponseClass:
      Succeeded := Self.ReceiveFailureResponse(Response);
    SIPServerFailureResponseClass:
      Succeeded := Self.ReceiveServerFailureResponse(Response);
    SIPGlobalFailureResponseClass:
      Succeeded := Self.ReceiveGlobalFailureResponse(Response);
  else
    // This should never happen - response status codes lie in the range
    // 100 <= S < 700, so we handle these obviously malformed responses by
    // treating them as failure responses.
    Succeeded := arFailure;
  end;

  Self.SetResult(Succeeded);

  case Succeeded of
    arSuccess: if Response.IsOK then
      Self.ActionSucceeded(Response);
    arFailure:
      Self.NotifyOfFailure(Response);
  end;
end;

procedure TIdSipAction.RemoveActionListener(Listener: IIdSipActionListener);
begin
  Self.ActionListeners.RemoveListener(Listener);
end;

procedure TIdSipAction.Resend(AuthorizationCredentials: TIdSipAuthorizationHeader);
var
  AuthedRequest: TIdSipRequest;
begin
  if (Self.State = asInitialised) then
    raise EIdSipTransactionUser.Create('You cannot REsend if you didn''t send'
                                     + ' in the first place');

  Self.State := asResent;

  AuthedRequest := Self.CreateResend(AuthorizationCredentials);
  try
    Self.InitialRequest.Assign(AuthedRequest);
    Self.SendRequest(AuthedRequest);
  finally
    AuthedRequest.Free;
  end;
end;

procedure TIdSipAction.Send;
begin
  if (Self.State <> asInitialised) then
    raise EIdSipTransactionUser.Create(Format(MethodInProgress, [Self.Method]));

  Self.State := asSent;  
end;

procedure TIdSipAction.Terminate;
begin
  Self.MarkAsTerminated;
end;

//* TIdSipAction Protected methods *********************************************

procedure TIdSipAction.ActionSucceeded(Response: TIdSipResponse);
begin
  // By default do nothing.
  Self.State := asFinished;
end;

procedure TIdSipAction.Initialise(UA: TIdSipAbstractCore;
                                  Request: TIdSipRequest;
                                  UsingSecureTransport: Boolean);
begin
  Self.fUA := UA;

  Self.ActionListeners := TIdNotificationList.Create;
  Self.fID             := TIdSipActionRegistry.RegisterAction(Self);
  Self.fInitialRequest := TIdSipRequest.Create;
  Self.fIsOwned        := false;
  Self.fIsTerminated   := false;
  Self.fLocalGruu      := TIdSipContactHeader.Create;
  Self.NonceCount      := 0;
  Self.State           := asInitialised;
  Self.TargetLocations := TIdSipLocations.Create;

  Self.SetResult(arUnknown);

  if Self.IsInbound then
    Self.InitialRequest.Assign(Request);
end;

procedure TIdSipAction.MarkAsTerminated;
begin
  Self.fIsTerminated := true;
end;

procedure TIdSipAction.NotifyOfAuthenticationChallenge(Challenge: TIdSipResponse);
var
  Notification: TIdSipActionAuthenticationChallengeMethod;
begin
  Notification := TIdSipActionAuthenticationChallengeMethod.Create;
  try
    Notification.ActionAgent := Self;
    Notification.Challenge   := Challenge;

    Self.ActionListeners.Notify(Notification);
  finally
    Notification.Free;
  end;
end;

procedure TIdSipAction.NotifyOfFailure(Response: TIdSipResponse);
begin
  // By default do nothing
  Self.State := asFinished;
end;

procedure TIdSipAction.NotifyOfNetworkFailure(ErrorCode: Cardinal;
                                              const Reason: String);
var
  Notification: TIdSipActionNetworkFailureMethod;
begin
  Notification := TIdSipActionNetworkFailureMethod.Create;
  try
    Notification.ActionAgent := Self;
    Notification.ErrorCode   := ErrorCode;
    Notification.Reason      := Reason;

    Self.ActionListeners.Notify(Notification);
  finally
    Notification.Free;
  end;

  Self.MarkAsTerminated;
end;

function TIdSipAction.ReceiveFailureResponse(Response: TIdSipResponse): TIdSipActionResult;
begin
  case Response.StatusCode of
    SIPUnauthorized,
    SIPProxyAuthenticationRequired: begin
      Self.NotifyOfAuthenticationChallenge(Response);
      Result := arInterim;
    end;
  else
    Result := arFailure;
  end;
end;

function TIdSipAction.ReceiveGlobalFailureResponse(Response: TIdSipResponse): TIdSipActionResult;
begin
  Result := arFailure;
end;

function TIdSipAction.ReceiveOKResponse(Response: TIdSipResponse;
                                        UsingSecureTransport: Boolean): TIdSipActionResult;
begin
  Result := arSuccess;
end;

procedure TIdSipAction.ReceiveOtherRequest(Request: TIdSipRequest);
begin
end;

function TIdSipAction.ReceiveProvisionalResponse(Response: TIdSipResponse;
                                                 UsingSecureTransport: Boolean): TIdSipActionResult;
begin
  Result := arFailure;
end;

function TIdSipAction.ReceiveRedirectionResponse(Response: TIdSipResponse;
                                                 UsingSecureTransport: Boolean): TIdSipActionResult;
begin
  Result := arFailure;
end;

function TIdSipAction.ReceiveServerFailureResponse(Response: TIdSipResponse): TIdSipActionResult;
begin
  Result := arFailure;
end;

procedure TIdSipAction.SendRequest(Request: TIdSipRequest);
var
  FailReason: String;
begin
  if (Self.NonceCount = 0) then
    Inc(Self.NonceCount);

  // cf RFC 3263, section 4.3
  Self.UA.FindServersFor(Request, Self.TargetLocations);

  if Self.TargetLocations.IsEmpty then begin
    // The Locator should at the least return a location based on the
    // Request-URI. Thus this clause should never execute. Still, this
    // clause protects the code that follows.

    FailReason := Format(RSNoLocationFound, [Request.DestinationUri]);
    Self.NotifyOfNetworkFailure(NoLocationFound,
                                Format(OutboundActionFailed,
                                       [Self.Method, FailReason]));
  end
  else
    Self.TrySendRequest(Request, Self.TargetLocations.First);
end;

procedure TIdSipAction.SendResponse(Response: TIdSipResponse);
begin
  // RFC 3263, section 5
  try
    Self.UA.SendResponse(Response);
  except
    on E: EIdSipTransport do
      Self.NotifyOfNetworkFailure(InboundActionFailed,
                                  Format(RSInboundActionFailed, [Self.Method, E.Message]));
  end;
end;

procedure TIdSipAction.SetResult(Value: TIdSipActionResult);
begin
  Self.fResult := Value;
end;

//* TIdSipAction Private methods ***********************************************

function TIdSipAction.CreateResend(AuthorizationCredentials: TIdSipAuthorizationHeader): TIdSipRequest;
begin
  Result := Self.CreateNewAttempt;

  // cf. RFC 3665, section 3.3, messages F1 and F4.
  Result.CallID   := Self.InitialRequest.CallID;
  Result.From.Tag := Self.InitialRequest.From.Tag;

  // The re-attempt's created like an in-dialog request (even though it's not
  // really): cf. RFC 3261, section 14.
  // Note that since we may not have a dialog established (this is the initial
  // INVITE, for instance), we can not ask a Dialog to create this message.
  Result.CSeq.SequenceNo := Self.InitialRequest.CSeq.SequenceNo + 1;

  Result.CopyHeaders(Self.InitialRequest, AuthorizationHeader);
  Result.CopyHeaders(Self.InitialRequest, ProxyAuthorizationHeader);
  Result.AddHeader(AuthorizationCredentials);
end;

function TIdSipAction.GetUsername: String;
begin
  Result := Self.UA.Username;
end;

procedure TIdSipAction.SetLocalGruu(Value: TIdSipContactHeader);
begin
  Self.fLocalGruu.Assign(Value);
end;

procedure TIdSipAction.SetUsername(const Value: String);
begin
  Self.UA.From.DisplayName := Value;
end;

procedure TIdSipAction.TrySendRequest(Request: TIdSipRequest;
                                      Target: TIdSipLocation);
var
  ActualRequest: TIdSipRequest;
begin
  ActualRequest := TIdSipRequest.Create;
  try
    ActualRequest.Assign(Request);

    // This means that a message that travels to the Target using SCTP will have
    // SIP/2.0/SCTP in its topmost Via. Remember, we try to avoid having the
    // transport layer change the message.
    ActualRequest.LastHop.Transport := Target.Transport;

    // Synchronise our state to what actually went down to the network.
    // The condition means that an INVITE won't set its InitialRequest to a
    // CANCEL or BYE it's just sent. Perhaps we could eliminate this condition
    // by using TIdSipOutboundBye/Cancel objects. TODO.
    if (ActualRequest.Method = Self.InitialRequest.Method) then
      Self.InitialRequest.Assign(ActualRequest);

    Self.UA.SendRequest(ActualRequest, Target);

    if not Self.TargetLocations.IsEmpty then
      Self.TargetLocations.Remove(Target);
  finally
    ActualRequest.Free;
  end;
end;

//******************************************************************************
//* TIdSipOwnedAction                                                          *
//******************************************************************************
//* TIdSipOwnedAction Public methods *******************************************

destructor TIdSipOwnedAction.Destroy;
begin
  Self.OwningActionListeners.Free;

  inherited Destroy;
end;

procedure TIdSipOwnedAction.AddOwnedActionListener(Listener: IIdSipOwnedActionListener);
begin
  Self.OwningActionListeners.AddListener(Listener);
end;

procedure TIdSipOwnedAction.Cancel;
begin
  // You can't cancel most actions: as of now (2006/01/30) you can only cancel
  // INVITE transactions. Thus, by default, we do nothing.
end;

procedure TIdSipOwnedAction.RemoveOwnedActionListener(Listener: IIdSipOwnedActionListener);
begin
  Self.OwningActionListeners.RemoveListener(Listener);
end;

//* TIdSipOwnedAction Protected methods ****************************************

procedure TIdSipOwnedAction.ActionSucceeded(Response: TIdSipResponse);
begin
  Self.NotifyOfSuccess(Response);
end;

procedure TIdSipOwnedAction.Initialise(UA: TIdSipAbstractCore;
                                       Request: TIdSipRequest;
                                       UsingSecureTransport: Boolean);
begin
  inherited Initialise(UA, Request, UsingSecureTransport);

  Self.fIsOwned := true;

  Self.OwningActionListeners := TIdNotificationList.Create;
end;

procedure TIdSipOwnedAction.NotifyOfFailure(Response: TIdSipResponse);
var
  Notification: TIdSipOwnedActionFailureMethod;
begin
  Notification := TIdSipOwnedActionFailureMethod.Create;
  try
    Notification.ActionAgent := Self;
    Notification.Reason      := Response.Description;
    Notification.Response    := Response;

    Self.OwningActionListeners.Notify(Notification);
  finally
    Notification.Free;
  end;

  Self.MarkAsTerminated;
end;

procedure TIdSipOwnedAction.NotifyOfRedirect(Response: TIdSipResponse);
var
  Notification: TIdSipOwnedActionRedirectMethod;
begin
  Notification := TIdSipOwnedActionRedirectMethod.Create;
  try
    Notification.ActionAgent := Self;
    Notification.Response    := Response;

    Self.OwningActionListeners.Notify(Notification);
  finally
    Notification.Free;
  end;
end;

procedure TIdSipOwnedAction.NotifyOfSuccess(Msg: TIdSipMessage);
var
  Notification: TIdSipOwnedActionSuccessMethod;
begin
  Notification := TIdSipOwnedActionSuccessMethod.Create;
  try
    Notification.ActionAgent := Self;
    Notification.Msg         := Msg;

    Self.OwningActionListeners.Notify(Notification);
  finally
    Notification.Free;
  end;
end;

function TIdSipOwnedAction.ReceiveRedirectionResponse(Response: TIdSipResponse;
                                                      UsingSecureTransport: Boolean): TIdSipActionResult;
begin
  Result := inherited ReceiveRedirectionResponse(Response, UsingSecureTransport);

  Self.NotifyOfRedirect(Response);
end;

//******************************************************************************
//* TIdSipRedirectedAction                                                     *
//******************************************************************************
//* TIdSipRedirectedAction Public methods **************************************

destructor TIdSipRedirectedAction.Destroy;
begin
  Self.fOriginalRequest.Free;
  Self.fContact.Free;

  inherited Destroy;
end;

function TIdSipRedirectedAction.Method: String;
begin
  Result := Self.fMethod;
end;

procedure TIdSipRedirectedAction.SetMethod(const Method: String);
begin
  Self.fMethod := Method;
end;

procedure TIdSipRedirectedAction.Send;
var
  Sub: TIdSipRequest;
begin
  inherited Send;

  Sub := Self.CreateNewAttempt;
  try
    Self.InitialRequest.Assign(Sub);

    Self.SendRequest(Sub);
  finally
    Sub.Free;
  end;
end;

//* TIdSipRedirectedAction Protected methods ***************************

function TIdSipRedirectedAction.CreateNewAttempt: TIdSipRequest;
begin
  // Use this method in the context of a redirect to a Action.
  // cf. RFC 3261, section 8.1.3.4

  Result := Self.UA.CreateRedirectedRequest(Self.OriginalRequest,
                                            Self.Contact);
end;

procedure TIdSipRedirectedAction.Initialise(UA: TIdSipAbstractCore;
                                                       Request: TIdSipRequest;
                                                       UsingSecureTransport: Boolean);
begin
  inherited Initialise(UA, Request, UsingSecureTransport);

  Self.fContact         := TIdSipAddressHeader.Create;
  Self.fOriginalRequest := TIdSipRequest.Create;
end;

//* TIdSipRedirectedAction Private methods *************************************

procedure TIdSipRedirectedAction.SetContact(Value: TIdSipAddressHeader);
begin
  Self.fContact.Assign(Value);
end;

procedure TIdSipRedirectedAction.SetOriginalRequest(Value: TIdSipRequest);
begin
  Self.OriginalRequest.Assign(Value);
end;

//******************************************************************************
//* TIdSipOwningAction                                                         *
//******************************************************************************
//* TIdSipOwningAction Public methods ******************************************

function TIdSipOwningAction.CreateInitialAction: TIdSipOwnedAction;
begin
  raise Exception.Create(Self.ClassName
                       + ' must override TIdSipOwningAction.CreateInitialAction');
end;

function TIdSipOwningAction.CreateRedirectedAction(OriginalRequest: TIdSipRequest;
                                                   Contact: TIdSipContactHeader): TIdSipOwnedAction;
var
  Redir: TIdSipRedirectedAction;
begin
  Redir := Self.UA.AddOutboundAction(TIdSipRedirectedAction) as TIdSipRedirectedAction;
  Redir.Contact         := Contact;
  Redir.OriginalRequest := OriginalRequest;
  Redir.SetMethod(Self.Method);

  Result := Redir;
end;

//******************************************************************************
//* TIdSipOptions                                                              *
//******************************************************************************
//* TIdSipOptions Public methods ***********************************************

function TIdSipOptions.IsOptions: Boolean;
begin
  Result := true;
end;

function TIdSipOptions.Method: String;
begin
  Result := MethodOptions;
end;

//* TIdSipOptions Protected methods ********************************************

function TIdSipOptions.CreateNewAttempt: TIdSipRequest;
var
  TempTo: TIdSipToHeader;
begin
  TempTo := TIdSipToHeader.Create;
  try
    TempTo.Address := Self.InitialRequest.RequestUri;

    Result := Self.Module.CreateOptions(TempTo);
  finally
    TempTo.Free;
  end;
end;

procedure TIdSipOptions.Initialise(UA: TIdSipAbstractCore;
                                   Request: TIdSipRequest;
                                   UsingSecureTransport: Boolean);
begin
  inherited Initialise(UA, Request, UsingSecureTransport);

  Self.Module := Self.UA.ModuleFor(Self.Method) as TIdSipOptionsModule;
end;

//******************************************************************************
//* TIdSipInboundOptions                                                       *
//******************************************************************************
//* TIdSipInboundOptions Public methods ****************************************

function TIdSipInboundOptions.IsInbound: Boolean;
begin
  Result := true;
end;

procedure TIdSipInboundOptions.ReceiveRequest(Options: TIdSipRequest);
var
  Response: TIdSipResponse;
begin
  Assert(Options.IsOptions, 'TIdSipAction.ReceiveOptions must only receive OPTIONSes');

  Response := Self.UA.CreateResponse(Options,
                                     Self.UA.ResponseForInvite);
  try
    Response.AddHeader(AcceptHeader).Value := Self.UA.AllowedContentTypes;
    Response.AddHeader(AllowHeader).Value  := Self.UA.KnownMethods;
    Response.AddHeader(AcceptEncodingHeader).Value := Self.UA.AllowedEncodings;
    Response.AddHeader(AcceptLanguageHeader).Value := Self.UA.AllowedLanguages;
    Response.AddHeader(SupportedHeaderFull).Value := Self.UA.AllowedExtensions;
    Response.AddHeader(ContactHeaderFull).Assign(Self.UA.Contact);

    // For OPTIONS "traceroute"-like functionality. cf RFC 3261, section 11.2
    Response.FirstWarning.Code  := WarningMisc;
    Response.FirstWarning.Agent := Self.UA.HostName;
    // This should contain the IP of the transport that received the OPTIONS.
    Response.FirstWarning.Text  := '';

    Self.SendResponse(Response);
  finally
    Response.Free;
  end;

  Self.Terminate;
end;

//******************************************************************************
//* TIdSipOutboundOptions                                                      *
//******************************************************************************
//* TIdSipOutboundOptions Public methods ***************************************

destructor TIdSipOutboundOptions.Destroy;
begin
  Self.fServer.Free;

  inherited Destroy;
end;

procedure TIdSipOutboundOptions.AddListener(const Listener: IIdSipOptionsListener);
begin
  Self.ActionListeners.AddListener(Listener);
end;

procedure TIdSipOutboundOptions.RemoveListener(const Listener: IIdSipOptionsListener);
begin
  Self.ActionListeners.RemoveListener(Listener);
end;

procedure TIdSipOutboundOptions.Send;
var
  Options: TIdSipRequest;
begin
  inherited Send;

  Options := Self.CreateNewAttempt;
  try
    Self.InitialRequest.Assign(Options);
    Self.SendRequest(Options);
  finally
    Options.Free;
  end;
end;

//* TIdSipOutboundOptions Protected methods ************************************

procedure TIdSipOutboundOptions.ActionSucceeded(Response: TIdSipResponse);
begin
  Self.NotifyOfResponse(Response);
end;

function TIdSipOutboundOptions.CreateNewAttempt: TIdSipRequest;
begin
  Result := Self.Module.CreateOptions(Self.Server);
end;

procedure TIdSipOutboundOptions.Initialise(UA: TIdSipAbstractCore;
                                           Request: TIdSipRequest;
                                           UsingSecureTransport: Boolean);
begin
  inherited Initialise(UA, Request, UsingSecureTransport);

  Self.fServer := TIdSipAddressHeader.Create;
end;

procedure TIdSipOutboundOptions.NotifyOfFailure(Response: TIdSipResponse);
begin
  Self.NotifyOfResponse(Response);
end;

//* TIdSipOutboundOptions Private methods **************************************

procedure TIdSipOutboundOptions.NotifyOfResponse(Response: TIdSipResponse);
var
  Notification: TIdSipOptionsResponseMethod;
begin
  Notification := TIdSipOptionsResponseMethod.Create;
  try
    Notification.Options  := Self;
    Notification.Response := Response;

    Self.ActionListeners.Notify(Notification);
  finally
    Notification.Free;
  end;

  Self.Terminate;
end;

procedure TIdSipOutboundOptions.SetServer(Value: TIdSipAddressHeader);
begin
  Self.fServer.Assign(Value);
end;

//******************************************************************************
//* TIdSipActionRedirector                                                     *
//******************************************************************************
//* TIdSipActionRedirector Public methods **************************************

constructor TIdSipActionRedirector.Create(OwningAction: TIdSipOwningAction);
begin
  inherited Create;

  Self.OwningAction := OwningAction;
  Self.UA           := OwningAction.UA;

  Self.Listeners := TIdNotificationList.Create;

  // The UA manages the lifetimes of all outbound INVITEs!
  Self.RedirectedActions    := TObjectList.Create(false);
  Self.TargetUriSet := TIdSipContacts.Create;
end;

destructor TIdSipActionRedirector.Destroy;
begin
  Self.TargetUriSet.Free;

  Self.RedirectedActions.Free;

  Self.Listeners.Free;

  inherited Destroy;
end;

procedure TIdSipActionRedirector.AddListener(const Listener: IIdSipActionRedirectorListener);
begin
  Self.Listeners.AddListener(Listener);
end;

procedure TIdSipActionRedirector.Cancel;
begin
  if Self.FullyEstablished then Exit;
  if Self.Cancelling then Exit;

  if Assigned(Self.InitialAction) then
    Self.InitialAction.Terminate;

  Self.TerminateAllRedirects;

  Self.Cancelling := true;
end;

function TIdSipActionRedirector.Contains(OwnedAction: TIdSipAction): Boolean;
begin
  Result := (Self.InitialAction = OwnedAction)
         or (Self.RedirectedActions.IndexOf(OwnedAction) <> ItemNotFoundIndex);
end;

procedure TIdSipActionRedirector.RemoveListener(const Listener: IIdSipActionRedirectorListener);
begin
  Self.Listeners.RemoveListener(Listener);
end;

procedure TIdSipActionRedirector.Resend(ChallengedAction: TIdSipAction;
                                        AuthorizationCredentials: TIdSipAuthorizationHeader);
begin
  ChallengedAction.Resend(AuthorizationCredentials);
end;

procedure TIdSipActionRedirector.Send;
begin
  Self.fInitialAction := Self.OwningAction.CreateInitialAction;
  Self.InitialAction.AddOwnedActionListener(Self);

  Self.NotifyOfNewAction(Self.InitialAction);
  Self.InitialAction.Send;
end;

procedure TIdSipActionRedirector.Terminate;
begin
  if Assigned(Self.InitialAction) and (Self.InitialAction.Result = arInterim) then begin
    Self.InitialAction.Terminate;
  end
  else
    Self.Cancel;
end;

//* TIdSipActionRedirector Private methods *************************************

procedure TIdSipActionRedirector.AddNewRedirect(OriginalRequest: TIdSipRequest;
                                                Contact: TIdSipContactHeader);
var
  Redirect: TIdSipOwnedAction;
begin
  Redirect := Self.OwningAction.CreateRedirectedAction(OriginalRequest, Contact);

  Self.RedirectedActions.Add(Redirect);

  Redirect.AddOwnedActionListener(Self);
  Self.NotifyOfNewAction(Redirect);
  Redirect.Send;
end;

function TIdSipActionRedirector.HasOutstandingRedirects: Boolean;
begin
  Result := Self.RedirectedActions.Count <> 0;
end;

procedure TIdSipActionRedirector.NotifyOfFailure(ErrorCode: Cardinal;
                                                 const Reason: String);
var
  Notification: TIdSipRedirectorRedirectFailureMethod;
begin
  Notification := TIdSipRedirectorRedirectFailureMethod.Create;
  try
    Notification.ErrorCode  := ErrorCode;
    Notification.Reason     := Reason;
    Notification.Redirector := Self;

    Self.Listeners.Notify(Notification);
  finally
    Notification.Free;
  end;
end;

procedure TIdSipActionRedirector.NotifyOfNewAction(Action: TIdSipAction);
var
  Notification: TIdSipRedirectorNewActionMethod;
begin
  Notification := TIdSipRedirectorNewActionMethod.Create;
  try
    Notification.NewAction  := Action;
    Notification.Redirector := Self;

    Self.Listeners.Notify(Notification);
  finally
    Notification.Free;
  end;
end;

procedure TIdSipActionRedirector.NotifyOfSuccess(Action: TIdSipAction;
                                                 Response: TIdSipResponse);
var
  Notification: TIdSipRedirectorSuccessMethod;
begin
  Notification := TIdSipRedirectorSuccessMethod.Create;
  try
    Notification.Redirector       := Self;
    Notification.Response         := Response;
    Notification.SuccessfulAction := Action;

    Self.Listeners.Notify(Notification);
  finally
    Notification.Free;
  end;
end;

procedure TIdSipActionRedirector.OnAuthenticationChallenge(Action: TIdSipAction;
                                                           Challenge: TIdSipResponse);
begin
  // Do nothing.
end;

procedure TIdSipActionRedirector.OnFailure(Action: TIdSipAction;
                                           Response: TIdSipResponse;
                                           const Reason: String);
begin
  if Response.IsRedirect then
    Self.RemoveFinishedRedirectedInvite(Action)
  else begin
    if (Action = Self.InitialAction) then begin
      Self.fInitialAction := nil;
      Self.NotifyOfFailure(Response.StatusCode,
                           Response.StatusText);
      Exit;
    end;

    Self.RemoveFinishedRedirectedInvite(Action);

    if not Self.HasOutstandingRedirects then begin
      Self.NotifyOfFailure(RedirectWithNoSuccess,
                           RSRedirectWithNoSuccess);
    end;
  end;
end;

procedure TIdSipActionRedirector.OnNetworkFailure(Action: TIdSipAction;
                                                  ErrorCode: Cardinal;
                                                  const Reason: String);
begin
//  Self.RemoveFinishedRedirectedInvite(Action);
end;

procedure TIdSipActionRedirector.OnRedirect(Action: TIdSipAction;
                                            Redirect: TIdSipResponse);
var
  NewTargetsAdded: Boolean;
begin
  // cf RFC 3261, section 8.1.3.4.

  if not Self.FullyEstablished then begin
    if Redirect.Contacts.IsEmpty then begin
      Self.NotifyOfFailure(RedirectWithNoContacts, RSRedirectWithNoContacts);
    end
    else begin
      // Of course, if we receive a 3xx then that INVITE's over.
      Self.RemoveFinishedRedirectedInvite(Action);

      // We receive 3xxs with Contacts. We add these to our target URI set. We
      // send INVITEs to these URIs in some order. If we get 3xxs back from
      // these new targets we add the new Contacts to the target set. We of
      // course don't reattempt to INVITE a target that we've already contacted!
      // Sooner or later we'll either exhaust all the target URIs and report a
      // failed call, or a target will send a 2xx and fully establish a call, in
      // which case we simply do nothing with any other (redirect or failure)
      // responses.
      NewTargetsAdded := false;
      Redirect.Contacts.First;
      while Redirect.Contacts.HasNext do begin
        if not Self.TargetUriSet.HasContact(Redirect.Contacts.CurrentContact) then begin
          Self.AddNewRedirect(Action.InitialRequest,
                              Redirect.Contacts.CurrentContact);
          NewTargetsAdded := true;
        end;
        Redirect.Contacts.Next;
      end;

      Self.TargetUriSet.Add(Redirect.Contacts);

      if not NewTargetsAdded and not Self.HasOutstandingRedirects then
        Self.NotifyOfFailure(RedirectWithNoMoreTargets,
                             RSRedirectWithNoMoreTargets);
    end;
  end;

  Self.RemoveFinishedRedirectedInvite(Action);

  if (Action = Self.InitialAction) then
    Self.fInitialAction := nil;
end;

procedure TIdSipActionRedirector.OnSuccess(Action: TIdSipAction;
                                           Response: TIdSipMessage);
begin
  if not Self.FullyEstablished then begin
    Self.FullyEstablished := true;

    Self.RemoveFinishedRedirectedInvite(Action);
    Self.TerminateAllRedirects;
    Self.NotifyOfSuccess(Action, Response as TIdSipResponse);

    if (Action = Self.InitialAction) then
      Self.fInitialAction := nil;
  end;
end;

procedure TIdSipActionRedirector.RemoveFinishedRedirectedInvite(Agent: TIdSipAction);
begin
  Self.RedirectedActions.Remove(Agent);

  if Self.Cancelling and not Self.HasOutstandingRedirects then
    Self.NotifyOfFailure(NoError, '');
end;

procedure TIdSipActionRedirector.TerminateAllRedirects;
var
  I: Integer;
begin
  for I := 0 to Self.RedirectedActions.Count - 1 do
    (Self.RedirectedActions[I] as TIdSipAction).Terminate;
end;

//******************************************************************************
//* TIdSipActionRegistry                                                       *
//******************************************************************************
//* TIdSipActionRegistry Public methods ****************************************

class function TIdSipActionRegistry.RegisterAction(Instance: TIdSipAction): String;
begin
  repeat
    Result := GRandomNumber.NextHexString;
  until (Self.ActionRegistry.IndexOf(Result) = ItemNotFoundIndex);

  Self.ActionRegistry.AddObject(Result, Instance);
end;

class function TIdSipActionRegistry.FindAction(const ActionID: String): TIdSipAction;
var
  Index: Integer;
begin
  Index := Self.ActionRegistry.IndexOf(ActionID);

  if (Index = ItemNotFoundIndex) then
    Result := nil
  else
    Result := Self.ActionAt(Index);
end;

class procedure TIdSipActionRegistry.UnregisterAction(const ActionID: String);
var
  Index: Integer;
begin
  Index := Self.ActionRegistry.IndexOf(ActionID);
  if (Index <> ItemNotFoundIndex) then
    Self.ActionRegistry.Delete(Index);
end;

//* TIdSipActionRegistry Private methods ***************************************

class function TIdSipActionRegistry.ActionAt(Index: Integer): TIdSipAction;
begin
  Result := TIdSipAction(Self.ActionRegistry.Objects[Index]);
end;

class function TIdSipActionRegistry.ActionRegistry: TStrings;
begin
  Result := GActions;
end;

//******************************************************************************
//* TIdSipActionAuthenticationChallengeMethod                                  *
//******************************************************************************
//* TIdSipActionAuthenticationChallengeMethod Public methods *******************

procedure TIdSipActionAuthenticationChallengeMethod.Run(const Subject: IInterface);
begin
  (Subject as IIdSipActionListener).OnAuthenticationChallenge(Self.ActionAgent,
                                                              Self.Challenge);
end;

//******************************************************************************
//* TIdSipActionNetworkFailureMethod                                           *
//******************************************************************************
//* TIdSipActionNetworkFailureMethod Public methods ****************************

procedure TIdSipActionNetworkFailureMethod.Run(const Subject: IInterface);
begin
  (Subject as IIdSipActionListener).OnNetworkFailure(Self.ActionAgent,
                                                     Self.ErrorCode,
                                                     Self.Reason);
end;

//******************************************************************************
//* TIdSipOwnedActionFailureMethod                                             *
//******************************************************************************
//* TIdSipOwnedActionFailureMethod Public methods ******************************

procedure TIdSipOwnedActionFailureMethod.Run(const Subject: IInterface);
begin
  (Subject as IIdSipOwnedActionListener).OnFailure(Self.ActionAgent,
                                                   Self.Response,
                                                   Self.Reason);
end;

//******************************************************************************
//* TIdSipOwnedActionRedirectMethod                                            *
//******************************************************************************
//* TIdSipOwnedActionRedirectMethod Public methods *****************************

procedure TIdSipOwnedActionRedirectMethod.Run(const Subject: IInterface);
begin
  (Subject as IIdSipOwnedActionListener).OnRedirect(Self.ActionAgent,
                                                    Self.Response);
end;

//******************************************************************************
//* TIdSipOwnedActionSuccessMethod                                             *
//******************************************************************************
//* TIdSipOwnedActionSuccessMethod Public methods ******************************

procedure TIdSipOwnedActionSuccessMethod.Run(const Subject: IInterface);
begin
  (Subject as IIdSipOwnedActionListener).OnSuccess(Self.ActionAgent,
                                                   Self.Msg);
end;

//******************************************************************************
//* TIdSipOptionsResponseMethod                                                *
//******************************************************************************
//* TIdSipOptionsResponseMethod Public methods *********************************

procedure TIdSipOptionsResponseMethod.Run(const Subject: IInterface);
begin
  (Subject as IIdSipOptionsListener).OnResponse(Self.Options,
                                               Self.Response);
end;

//******************************************************************************
//* TIdSipRedirectorNewActionMethod                                            *
//******************************************************************************
//* TIdSipRedirectorNewActionMethod Public methods *****************************

procedure TIdSipRedirectorNewActionMethod.Run(const Subject: IInterface);
begin
  (Subject as IIdSipActionRedirectorListener).OnNewAction(Self.Redirector,
                                                          Self.NewAction);
end;

//******************************************************************************
//* TIdSipRedirectorRedirectFailureMethod                                      *
//******************************************************************************
//* TIdSipRedirectorRedirectFailureMethod Public methods ***********************

procedure TIdSipRedirectorRedirectFailureMethod.Run(const Subject: IInterface);
begin
  (Subject as IIdSipActionRedirectorListener).OnRedirectFailure(Self.Redirector,
                                                                Self.ErrorCode,
                                                                Self.Reason);
end;

//******************************************************************************
//* TIdSipRedirectorSuccessMethod                                              *
//******************************************************************************
//* TIdSipRedirectorSuccessMethod Public methods *******************************

procedure TIdSipRedirectorSuccessMethod.Run(const Subject: IInterface);
begin
  (Subject as IIdSipActionRedirectorListener).OnSuccess(Self.Redirector,
                                                        Self.SuccessfulAction,
                                                        Self.Response);
end;

//******************************************************************************
//* TIdSipUserAgentDroppedUnmatchedMessageMethod                               *
//******************************************************************************
//* TIdSipUserAgentDroppedUnmatchedMessageMethod Public methods ****************

procedure TIdSipUserAgentDroppedUnmatchedMessageMethod.Run(const Subject: IInterface);
begin
  (Subject as IIdSipTransactionUserListener).OnDroppedUnmatchedMessage(Self.UserAgent,
                                                                       Self.Message,
                                                                       Self.Receiver);
end;

initialization
  GActions := TStringList.Create;
finalization
// These objects are purely memory-based, so it's safe not to free them here.
// Still, perhaps we need to review this methodology. How else do we get
// something like class variables?
//  GActions.Free;
end.
