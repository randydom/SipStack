unit IdSipMessage;

interface

uses
  Classes, Contnrs, IdDateTimeStamp, IdGlobal, IdSimpleParser, IdSipHeaders,
  IdURI, SysUtils;

type
  TIdSipRequest = class;
  TIdSipResponse = class;

  IIdSipMessageVisitor = interface
    ['{E2900B55-A1CA-47F1-9DB0-D72D6A846EA0}']
    procedure VisitRequest(const Request: TIdSipRequest);
    procedure VisitResponse(const Response: TIdSipResponse);
  end;

  TIdSipMessage = class(TPersistent)
  private
    fBody:       String;
    fPath:       TIdSipViaPath;
    fHeaders:    TIdSipHeaders;
    fSIPVersion: String;

    function  GetCallID: String;
    function  GetContentLength: Cardinal;
    function  GetContentType: String;
    function  GetCSeq: TIdSipCSeqHeader;
    function  GetFrom: TIdSipFromHeader;
    function  GetMaxForwards: Byte;
    function  GetTo: TIdSipToHeader;
    procedure SetCallID(const Value: String);
    procedure SetContentLength(const Value: Cardinal);
    procedure SetContentType(const Value: String);
    procedure SetCSeq(const Value: TIdSipCSeqHeader);
    procedure SetFrom(const Value: TIdSipFromHeader);
    procedure SetMaxForwards(const Value: Byte);
    procedure SetPath(const Value: TIdSipViaPath);
    procedure SetTo(const Value: TIdSipToHeader);
  protected
    function FirstLine: String; virtual; abstract;
  public
    constructor Create;
    destructor  Destroy; override;

    procedure Accept(const Visitor: IIdSipMessageVisitor); virtual;
    procedure Assign(Src: TPersistent); override;
    function  AsString: String;
    function  HasHeader(const HeaderName: String): Boolean;
    function  IsRequest: Boolean; virtual; abstract;
    function  MalformedException: ExceptClass; virtual; abstract;
    procedure ReadBody(const S: TStream);

    property Body:          String           read fBody write fBody;
    property CallID:        String           read GetCallID write SetCallID;
    property ContentLength: Cardinal         read GetContentLength write SetContentLength;
    property ContentType:   String           read GetContentType write SetContentType;
    property CSeq:          TIdSipCSeqHeader read GetCSeq write SetCSeq;
    property From:          TIdSipFromHeader read GetFrom write SetFrom;
    property Headers:       TIdSipHeaders    read fHeaders;
    property MaxForwards:   Byte             read GetMaxForwards write SetMaxForwards;
    property Path:          TIdSipViaPath    read fPath write SetPath;
    property SIPVersion:    String           read fSIPVersion write fSIPVersion;
    property ToHeader:      TIdSipToHeader   read GetTo write SetTo;
  end;

  TIdSipMessageClass = class of TIdSipMessage;

  TIdSipRequest = class(TIdSipMessage)
  private
    fMethod:     String;
    fRequestUri: String;
  protected
    function FirstLine: String; override;
  public
    procedure Accept(const Visitor: IIdSipMessageVisitor); override;
    procedure Assign(Src: TPersistent); override;
    function  HasSipsUri: Boolean;
    function  IsAck: Boolean;
    function  IsInvite: Boolean;
    function  IsRequest: Boolean; override;
    function  MalformedException: ExceptClass; override;

    property Method:     String read fMethod write fMethod;
    property RequestUri: String read fRequestUri write fRequestUri;
  end;

  TIdSipResponse = class(TIdSipMessage)
  private
    fStatusCode: Integer;
    fStatusText: String;

    procedure SetStatusCode(const Value: Integer);
  protected
    function FirstLine: String; override;
  public
    procedure Accept(const Visitor: IIdSipMessageVisitor); override;
    procedure Assign(Src: TPersistent); override;
    function  MalformedException: ExceptClass; override;
    function  IsFinal: Boolean;
    function  IsProvisional: Boolean;
    function  IsRequest: Boolean; override;

    property StatusCode: Integer read fStatusCode write SetStatusCode;
    property StatusText: String  read fStatusText write fStatusText;
  end;

  {*
   * Some implementation principles we follow:
   *  * The original headers may be folded, may contain all manner of guff. We
   *    don't make any attempt to store the raw header - we parse it, and when
   *    we write out the headers we write them in the simplest possible way. As
   *    a result we CANNOT duplicate the exact form of the original message, even
   *    though the new message will have identical, semantically speaking.
   *  * We do (because we have to) keep the order of headers. Any newly created
   *    headers are simply appended.
   *  * Any and all parsing errors are raised as exceptions that descend from
   *    EParser as soon as we can.
   *  * New headers can be created that weren't present in the original message.
   *    These messages will, by default, have the empty string as value. For example,
   *    querying the value of Content-Type will create a TIdSipHeader with Value ''.
   *  * Each header is regarded as using a particular language, and are parsers for
   *    that language (in the SetValue method).
   *  * Comma-separated headers are always separated into separate headers.
   *}
  TIdSipParser = class(TIdSimpleParser, IIdSipMessageVisitor)
  private
    procedure AddHeader(const Msg: TIdSipMessage; Header: String);
    procedure CheckContentLengthContentType(const Msg: TIdSipMessage);
    procedure CheckCSeqMethod(const Request: TIdSipRequest);
    procedure CheckRequiredHeaders(const Request: TIdSipRequest);
    function  CreateResponseOrRequest(const Token: String): TIdSipMessage;
    procedure InitialiseMessage(Msg: TIdSipMessage);
    procedure ParseCompoundHeader(const Msg: TIdSipMessage; const Header: String; Parms: String);
    procedure ParseHeader(const Msg: TIdSipMessage; const Header: String);
    procedure ParseHeaders(const Msg: TIdSipMessage);
    procedure ParseRequestLine(const Request: TIdSipRequest);
    procedure ParseStatusLine(const Response: TIdSipResponse);

    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  public
    class function IsIPv6Reference(const Token: String): Boolean;
    class function IsMethod(Method: String): Boolean;
    class function IsQuotedString(const Token: String): Boolean;
    class function IsQValue(const Token: String): Boolean;
    class function IsSipVersion(Version: String): Boolean;
    class function IsToken(const Token: String): Boolean;
    class function IsTransport(const Token: String): Boolean;
    class function IsWord(const Token: String): Boolean;

    function  GetHeaderName(Header: String): String;
    function  GetHeaderNumberValue(const Msg: TIdSipMessage; const Header: String): Cardinal;
    function  GetHeaderValue(Header: String): String;
//    function  MakeBadRequestResponse(const Reason: String): TIdSipResponse;
    function  ParseAndMakeMessage: TIdSipMessage; overload;
    function  ParseAndMakeMessage(const Src: String): TIdSipMessage; overload;
    function  ParseAndMakeMessage(const Src: String; const MessageType: TIdSipMessageClass): TIdSipMessage; overload;
    function  ParseAndMakeRequest: TIdSipRequest; overload;
    function  ParseAndMakeRequest(const Src: String): TIdSipRequest; overload;
    function  ParseAndMakeResponse: TIdSipResponse; overload;
    function  ParseAndMakeResponse(const Src: String): TIdSipResponse; overload;
    procedure ParseMessage(const Msg: TIdSipMessage);
    procedure ParseRequest(const Request: TIdSipRequest);
    procedure ParseResponse(const Response: TIdSipResponse);

    procedure VisitRequest(const Request: TIdSipRequest);
    procedure VisitResponse(const Response: TIdSipResponse);
  end;

  EBadHeader = class(EParser);
  EBadRequest = class(EParser);
  EBadResponse = class(EParser);

const
  LegalTokenChars = Alphabet + Digits
                  + ['-', '.', '!', '%', '*', '_',
                     '+', '`', '''', '~'];
  LegalWordChars = LegalTokenChars
                 + ['(', ')', '<', '>', ':', '\', '"', '/', '[',
                    ']', '?', '{', '}'];
  LWSChars = [' ', #9, #10, #13];

const
  BadStatusCode             = -1;
  CSeqMethodMismatch        = 'CSeq header method doesn''t match request method';
  InvalidSipVersion         = 'Invalid Sip-Version: ''%s''';
  InvalidStatusCode         = 'Invalid Status-Code: ''%s''';
  MissingCallID             = 'Missing Call-ID header';
  MissingContentType        = 'Missing Content-Type header with a non-empty message-body';
  MissingCSeq               = 'Missing CSeq header';
  MissingFrom               = 'Missing From header';
  MissingMaxForwards        = 'Missing Max-Forwards header';
  MissingTo                 = 'Missing To header';
  MissingSipVersion         = 'Missing SIP-Version';
  MissingVia                = 'Missing Via header';
  RequestLine               = '%s %s %s' + EOL;
  RequestUriNoAngleBrackets = 'Request-URI may not be enclosed in <>';
  RequestUriNoSpaces        = 'Request-URI may not contain spaces';
  StatusLine                = '%s %d %s' + EOL;
  UnexpectedMessageLength   = 'Expected message-body length of %d but was %d';
  UnmatchedQuotes           = 'Unmatched quotes';

function DecodeQuotedStr(const S: String; var Dest: String): Boolean;
function IsEqual(const S1, S2: String): Boolean;
function ShortMonthToInt(const Month: String): Integer;

implementation

uses
  IdSipConsts;

//******************************************************************************
//* Unit public procedures & functions                                         *
//******************************************************************************

function DecodeQuotedStr(const S: String; var Dest: String): Boolean;
var
  I: Integer;
  FoundSlash: Boolean;
begin
  Result := true;

  // in summary:
  // '\' is illegal, '%s\' is illegal.

  Dest := S;

  if (Dest <> '') then begin
    if (Dest = '\') or (Dest = '"') then
      Result := false;

    if (Length(Dest) >= 2) and (Dest[Length(Dest)] = '\') and (Dest[Length(Dest) - 1] <> '\') then
      Result := Result and false;

    // We use "<" and not "<=" because if a \ is the last character we have
    // a malformed string. Too, this allows use to Dest[I + 1]
    I := 1;
    while (I < Length(Dest)) and Result do begin
      Result := Dest[I] <> '"';
      FoundSlash := Dest[I] = '\';
      if (FoundSlash) then begin
        Delete(Dest, I, 1);

        // protect '\\'
        if (FoundSlash) then begin
          Inc(I);
        end;
      end
      else
        Inc(I);
    end;
  end;
end;

function IsEqual(const S1, S2: String): Boolean;
begin
  Result := Lowercase(S1) = Lowercase(S2);
end;

function ShortMonthToInt(const Month: String): Integer;
var
  Found: Boolean;
begin
  Found := false;
  for Result := Low(ShortMonthNames) to High(ShortMonthNames) do
    if IsEqual(ShortMonthNames[Result], Month) then begin
      Found := true;
      Break;
    end;

  if not Found then
    raise EConvertError.Create('Failed to convert ''' + Month + ''' to type Integer');
end;

//******************************************************************************
//* TIdSipMessage                                                              *
//******************************************************************************
//* TIdSipMessage Public methods ***********************************************

constructor TIdSipMessage.Create;
begin
  inherited Create;

  fHeaders := TIdSipHeaders.Create;
  fPath := TIdSipViaPath.Create(Self.Headers);

  Self.SIPVersion  := IdSipConsts.SIPVersion;
end;

destructor TIdSipMessage.Destroy;
begin
  fPath.Free;
  fHeaders.Free;

  inherited Destroy;
end;

procedure TIdSipMessage.Accept(const Visitor: IIdSipMessageVisitor);
begin
end;

procedure TIdSipMessage.Assign(Src: TPersistent);
var
  S: TIdSipMessage;
  I: Integer;
begin
  if (Src is Self.ClassType) then begin
    S := Src as TIdSipMessage;

    Self.SIPVersion := S.SIPVersion;

    Self.Headers.Clear;
    for I := 0 to S.Headers.Count - 1 do
      Self.Headers.Add(S.Headers.Items[I]);
  end
  else
    inherited Assign(Src);
end;

function TIdSipMessage.AsString: String;
begin
  Result := Self.FirstLine;

  Result := Result + Self.Headers.AsString;

  Result := Result + EOL;
  Result := Result + Self.Body;
end;

function TIdSipMessage.HasHeader(const HeaderName: String): Boolean;
begin
  Result := Self.Headers.HasHeader(HeaderName);
end;

procedure TIdSipMessage.ReadBody(const S: TStream);
begin
  // It is the responsibility of the transport to ensure that
  // Content-Length is set before this method is called.
  SetLength(fBody, Self.ContentLength);
  S.Read(fBody[1], Self.ContentLength);
end;

//* TIdSipMessage Private methods **********************************************

function TIdSipMessage.GetCallID: String;
begin
  Result := Self.Headers[CallIDHeaderFull].Value;
end;

function TIdSipMessage.GetContentLength: Cardinal;
begin
  Result := StrToInt(Self.Headers[ContentLengthHeaderFull].Value);
end;

function TIdSipMessage.GetContentType: String;
begin
  Result := Self.Headers[ContentTypeHeaderFull].Value;
end;

function TIdSipMessage.GetCSeq: TIdSipCSeqHeader;
begin
  Result := Self.Headers[CSeqHeader] as TIdSipCSeqHeader;
end;

function TIdSipMessage.GetFrom: TIdSipFromHeader;
begin
  Result := Self.Headers[FromHeaderFull] as TIdSipFromHeader;
end;

function TIdSipMessage.GetMaxForwards: Byte;
begin
  if (Self.Headers[MaxForwardsHeader].Value = '') then
    Self.MaxForwards := DefaultMaxForwards;

  Result := StrToInt(Self.Headers[MaxForwardsHeader].Value);
end;

function TIdSipMessage.GetTo: TIdSipToHeader;
begin
  Result := Self.Headers[ToHeaderFull] as TIdSipToHeader;
end;

procedure TIdSipMessage.SetCallID(const Value: String);
begin
  Self.Headers[CallIDHeaderFull].Value := Value;
end;

procedure TIdSipMessage.SetContentLength(const Value: Cardinal);
begin
  Self.Headers[ContentLengthHeaderFull].Value := IntToStr(Value);
end;

procedure TIdSipMessage.SetContentType(const Value: String);
begin
  Self.Headers[ContentTypeHeaderFull].Value := Value;
end;

procedure TIdSipMessage.SetCSeq(const Value: TIdSipCSeqHeader);
begin
  Self.CSeq.Assign(Value);
end;

procedure TIdSipMessage.SetFrom(const Value: TIdSipFromHeader);
begin
  Self.Headers[FromHeaderFull].Assign(Value);
end;

procedure TIdSipMessage.SetMaxForwards(const Value: Byte);
begin
  Self.Headers[MaxForwardsHeader].Value := IntToStr(Value);
end;

procedure TIdSipMessage.SetPath(const Value: TIdSipViaPath);
var
  I: Integer;
begin
  Self.Path.Clear;

  for I := 0 to Value.Count - 1 do
    Self.Path.Add(Value.Items[I]);
end;

procedure TIdSipMessage.SetTo(const Value: TIdSipToHeader);
begin
  Self.Headers[ToHeaderFull].Assign(Value);
end;

//*******************************************************************************
//* TIdSipRequest                                                               *
//*******************************************************************************
//* TIdSipRequest Public methods ************************************************

procedure TIdSipRequest.Accept(const Visitor: IIdSipMessageVisitor);
begin
  Visitor.VisitRequest(Self);
end;

procedure TIdSipRequest.Assign(Src: TPersistent);
var
  R: TIdSipRequest;
begin
  inherited Assign(Src);

  R := Src as TIdSipRequest;

  Self.Method     := R.Method;
  Self.RequestUri := R.RequestUri;
end;

function TIdSipRequest.HasSipsUri: Boolean;
var
  S: String;
begin
  S := Self.RequestUri;
  Result := Lowercase(Fetch(S, ':')) = SipsScheme;
end;

function TIdSipRequest.IsAck: Boolean;
begin
  Result := Self.Method = MethodAck;
end;

function TIdSipRequest.IsInvite: Boolean;
begin
  Result := Self.Method = MethodInvite;
end;

function TIdSipRequest.IsRequest: Boolean;
begin
  Result := true;
end;

function TIdSipRequest.MalformedException: ExceptClass;
begin
  Result := EBadRequest;
end;

//* TIdSipRequest Protected methods ********************************************

function TIdSipRequest.FirstLine: String;
begin
  Result := Format(RequestLine, [Self.Method, Self.RequestUri, Self.SIPVersion]);
end;

//*******************************************************************************
//* TIdSipResponse                                                              *
//*******************************************************************************
//* TIdSipResponse Public methods ***********************************************

procedure TIdSipResponse.Accept(const Visitor: IIdSipMessageVisitor);
begin
  Visitor.VisitResponse(Self);
end;

procedure TIdSipResponse.Assign(Src: TPersistent);
var
  R: TIdSipResponse;
begin
  inherited Assign(Src);

  R := Src as TIdSipResponse;

  Self.StatusCode := R.StatusCode;
  Self.StatusText := R.StatusText;
end;

function TIdSipResponse.MalformedException: ExceptClass;
begin
  Result := EBadResponse;
end;

function TIdSipResponse.IsFinal: Boolean;
begin
  Result := Self.StatusCode div 100 > 1;
end;

function TIdSipResponse.IsProvisional: Boolean;
begin
  Result := Self.StatusCode div 100 = 1;
end;

function TIdSipResponse.IsRequest: Boolean;
begin
  Result := false;
end;

//* TIdSipResponse Protected methods *******************************************

function TIdSipResponse.FirstLine: String;
begin
  Result := Format(StatusLine, [Self.SIPVersion, Self.StatusCode, Self.StatusText]);
end;

//* TIdSipResponse Private methods **********************************************

procedure TIdSipResponse.SetStatusCode(const Value: Integer);
begin
  Self.fStatusCode := Value;

  case Self.StatusCode of
    SIPTrying:                           Self.StatusText := RSSIPTrying;
    SIPRinging:                          Self.StatusText := RSSIPRinging;
    SIPCallIsBeingForwarded:             Self.StatusText := RSSIPCallIsBeingForwarded;
    SIPQueued:                           Self.StatusText := RSSIPQueued;
    SIPSessionProgess:                   Self.StatusText := RSSIPSessionProgess;
    SIPOK:                               Self.StatusText := RSSIPOK;
    SIPMultipleChoices:                  Self.StatusText := RSSIPMultipleChoices;
    SIPMovedPermanently:                 Self.StatusText := RSSIPMovedPermanently;
    SIPMovedTemporarily:                 Self.StatusText := RSSIPMovedTemporarily;
    SIPUseProxy:                         Self.StatusText := RSSIPUseProxy;
    SIPAlternativeService:               Self.StatusText := RSSIPAlternativeService;
    SIPBadRequest:                       Self.StatusText := RSSIPBadRequest;
    SIPUnauthorized:                     Self.StatusText := RSSIPUnauthorized;
    SIPPaymentRequired:                  Self.StatusText := RSSIPPaymentRequired;
    SIPForbidden:                        Self.StatusText := RSSIPForbidden;
    SIPNotFound:                         Self.StatusText := RSSIPNotFound;
    SIPMethodNotAllowed:                 Self.StatusText := RSSIPMethodNotAllowed;
    SIPNotAcceptableClient:              Self.StatusText := RSSIPNotAcceptableClient;
    SIPProxyAuthenticationRequired:      Self.StatusText := RSSIPProxyAuthenticationRequired;
    SIPRequestTimeout:                   Self.StatusText := RSSIPRequestTimeout;
    SIPGone:                             Self.StatusText := RSSIPGone;
    SIPRequestEntityTooLarge:            Self.StatusText := RSSIPRequestEntityTooLarge;
    SIPRequestURITooLarge:               Self.StatusText := RSSIPRequestURITooLarge;
    SIPUnsupportedMediaType:             Self.StatusText := RSSIPUnsupportedMediaType;
    SIPUnsupportedURIScheme:             Self.StatusText := RSSIPUnsupportedURIScheme;
    SIPBadExtension:                     Self.StatusText := RSSIPBadExtension;
    SIPExtensionRequired:                Self.StatusText := RSSIPExtensionRequired;
    SIPIntervalTooBrief:                 Self.StatusText := RSSIPIntervalTooBrief;
    SIPTemporarilyNotAvailable:          Self.StatusText := RSSIPTemporarilyNotAvailable;
    SIPCallLegOrTransactionDoesNotExist: Self.StatusText := RSSIPCallLegOrTransactionDoesNotExist;
    SIPLoopDetected:                     Self.StatusText := RSSIPLoopDetected;
    SIPTooManyHops:                      Self.StatusText := RSSIPTooManyHops;
    SIPAddressIncomplete:                Self.StatusText := RSSIPAddressIncomplete;
    SIPAmbiguous:                        Self.StatusText := RSSIPAmbiguous;
    SIPBusyHere:                         Self.StatusText := RSSIPBusyHere;
    SIPRequestTerminated:                Self.StatusText := RSSIPRequestTerminated;
    SIPNotAcceptableHere:                Self.StatusText := RSSIPNotAcceptableHere;
    SIPRequestPending:                   Self.StatusText := RSSIPRequestPending;
    SIPUndecipherable:                   Self.StatusText := RSSIPUndecipherable;
    SIPInternalServerError:              Self.StatusText := RSSIPInternalServerError;
    SIPNotImplemented:                   Self.StatusText := RSSIPNotImplemented;
    SIPBadGateway:                       Self.StatusText := RSSIPBadGateway;
    SIPServiceUnavailable:               Self.StatusText := RSSIPServiceUnavailable;
    SIPServerTimeOut:                    Self.StatusText := RSSIPServerTimeOut;
    SIPSIPVersionNotSupported:           Self.StatusText := RSSIPSIPVersionNotSupported;
    SIPMessageTooLarge:                  Self.StatusText := RSSIPMessageTooLarge;
    SIPBusyEverywhere:                   Self.StatusText := RSSIPBusyEverywhere;
    SIPDecline:                          Self.StatusText := RSSIPDecline;
    SIPDoesNotExistAnywhere:             Self.StatusText := RSSIPDoesNotExistAnywhere;
    SIPNotAcceptableGlobal:              Self.StatusText := RSSIPNotAcceptableGlobal;
  else
    Self.StatusText := RSSIPUnknownResponseCode;
  end;
end;

//******************************************************************************
//* TIdSipParser                                                               *
//******************************************************************************
//* TIdSipParser Public methods ************************************************

class function TIdSipParser.IsIPv6Reference(const Token: String): Boolean;
begin
  Result := (Copy(Token, 1, 1) = '[')
        and (Copy(Token, Length(Token), 1) = ']')
        and Self.IsIPv6Address(Copy(Token, 2, Length(Token) - 2));
end;

class function TIdSipParser.IsMethod(Method: String): Boolean;
begin
  Result := Self.IsToken(Method);
end;

class function TIdSipParser.IsQuotedString(const Token: String): Boolean;
var
  S: String;
begin
  Result := Token <> '';

  if Result then begin
    Result := DecodeQuotedStr(Copy(Token, 2, Length(Token) - 2), S)
              and (Token[1] = '"')
              and (Token[Length(Token)] = '"');
  end;
end;

class function TIdSipParser.IsQValue(const Token: String): Boolean;
begin
  try
    StrToQValue(Token);
    Result := true;
  except
    Result := false;
  end;
end;

class function TIdSipParser.IsSipVersion(Version: String): Boolean;
var
  Token: String;
begin
  Token := Fetch(Version, '/');
  Result := IsEqual(Token, SipName);

  if (Result) then begin
    Token := Fetch(Version, '.');

    Result := Result and Self.IsNumber(Token);
    Result := Result and Self.IsNumber(Version);
  end;
end;

class function TIdSipParser.IsToken(const Token: String): Boolean;
var
  I: Integer;
begin
  Result := Token <> '';

  if Result then
    for I := 1 to Length(Token) do begin
      Result := Result and (Token[I] in LegalTokenChars);
      if not Result then Break;
    end;
end;

class function TIdSipParser.IsTransport(const Token: String): Boolean;
begin
  try
    StrToTransport(Token);
    Result := true;
  except
    Result := false;
  end;
end;

class function TIdSipParser.IsWord(const Token: String): Boolean;
var
  I: Integer;
begin
  Result := Token <> '';

  if Result then
    for I := 1 to Length(Token) do begin
      Result := Result and (Token[I] in LegalWordChars);

      if not Result then Break;
    end;
end;

function TIdSipParser.GetHeaderName(Header: String): String;
begin
  Result := Trim(Fetch(Header, ':'));
end;

function TIdSipParser.GetHeaderNumberValue(const Msg: TIdSipMessage; const Header: String): Cardinal;
var
  Name:  String;
  Value: String;
  E:     Integer;
begin
  Name := Self.GetHeaderName(Header);
  Value := Self.GetHeaderValue(Header);
  Val(Value, Result, E);
  if (E <> 0) then
    raise Msg.MalformedException.Create(Format(MalformedToken, [Name, Header]));
end;

function TIdSipParser.GetHeaderValue(Header: String): String;
begin
  if (IndyPos(':', Header) = 0) then
    Result := ''
  else begin
    Result := Header;
    Fetch(Result, ':');
    Result := Trim(Result);
  end;
end;
{
function TIdSipParser.MakeBadRequestResponse(const Reason: String): TIdSipResponse;
begin
  // This is wrong. We need the original request's details - via headers, etc.
  // Sometimes we cannot get this information, though, especially if the
  // original message we malformed and unparseable.

  Result := TIdSipResponse.Create;
  Result.StatusCode := SIPBadRequest;
  Result.StatusText := Reason;
  Result.SipVersion := SIPVersion;
end;
}
function TIdSipParser.ParseAndMakeMessage: TIdSipMessage;
var
  FirstLine: String;
  FirstToken: String;
begin
  if not Self.Eof then begin
    FirstLine := Self.PeekLine;
    FirstToken := Fetch(FirstLine);
    FirstToken := Fetch(FirstToken, '/');

    // It's safe to do this because we know a SIP response starts with "SIP/",
    // and the "/" is not allowed in a Method.
    Result := Self.CreateResponseOrRequest(FirstToken);
    try
      Self.ParseMessage(Result);
    except
      Result.Free;

      raise;
    end;
  end
  else
    raise EParser.Create(EmptyInputStream);
end;

function TIdSipParser.ParseAndMakeMessage(const Src: String): TIdSipMessage;
var
  OriginalSrc: TStream;
  S:           TStringStream;
begin
  OriginalSrc := Self.Source;
  try
    S := TStringStream.Create(Src);
    try
      Self.Source := S;

      Result := Self.ParseAndMakeMessage;
      try
        Result.Body := S.ReadString(Result.ContentLength);
      except
        Result.Free;

        raise;
      end;
    finally
      S.Free;
    end;
  finally
    Self.Source := OriginalSrc;
  end;
end;

function TIdSipParser.ParseAndMakeMessage(const Src: String; const MessageType: TIdSipMessageClass): TIdSipMessage;
var
  OriginalSrc: TStream;
  S:           TStringStream;
begin
  OriginalSrc := Self.Source;
  try
    S := TStringStream.Create(Src);
    try
      Self.Source := S;

      Result := MessageType.Create;
      try
        Self.ParseMessage(Result);
        Result.Body := S.ReadString(Result.ContentLength);
      except
        Result.Free;

        raise;
      end;
    finally
      S.Free;
    end;
  finally
    Self.Source := OriginalSrc;
  end;
end;

function TIdSipParser.ParseAndMakeRequest: TIdSipRequest;
begin
  Result := TIdSipRequest.Create;
  try
    Self.ParseRequest(Result);
  except
    Result.Free;

    raise;
  end;
end;

function TIdSipParser.ParseAndMakeRequest(const Src: String): TIdSipRequest;
begin
  Result := Self.ParseAndMakeMessage(Src, TIdSipRequest) as TIdSipRequest;
end;

function TIdSipParser.ParseAndMakeResponse: TIdSipResponse;
begin
  Result := TIdSipResponse.Create;
  try
    Self.ParseResponse(Result);
  except
    Result.Free;

    raise;
  end;
end;

function TIdSipParser.ParseAndMakeResponse(const Src: String): TIdSipResponse;
begin
  Result := Self.ParseAndMakeMessage(Src, TIdSipResponse) as TIdSipResponse;
end;

procedure TIdSipParser.ParseMessage(const Msg: TIdSipMessage);
begin
  Msg.Accept(Self);
end;

procedure TIdSipParser.ParseRequest(const Request: TIdSipRequest);
begin
  Self.InitialiseMessage(Request);

  if not Self.Eof then begin
    Self.ResetCurrentLine;
    Self.ParseRequestLine(Request);
    Self.ParseHeaders(Request);
  end;

  Self.CheckRequiredHeaders(Request);
  Self.CheckContentLengthContentType(Request);
  Self.CheckCSeqMethod(Request);
end;

procedure TIdSipParser.ParseResponse(const Response: TIdSipResponse);
begin
  Self.InitialiseMessage(Response);

  if not Self.Eof then begin
    Self.ResetCurrentLine;
    Self.ParseStatusLine(Response);
    Self.ParseHeaders(Response);
  end;

  Self.CheckContentLengthContentType(Response);
end;

procedure TIdSipParser.VisitRequest(const Request: TIdSipRequest);
begin
  Self.ParseRequest(Request);
end;

procedure TIdSipParser.VisitResponse(const Response: TIdSipResponse);
begin
  Self.ParseResponse(Response);
end;

//* TIdSipParser Private methods ***********************************************

procedure TIdSipParser.AddHeader(const Msg: TIdSipMessage; Header: String);
var
  Name: String;
  S:    String;
begin
  S := Header;
  Name := Trim(Fetch(S, ':'));
  Name := TIdSipHeaders.CanonicaliseName(Name);

  Msg.Headers.Add(Name).Value := Trim(S);
end;

procedure TIdSipParser.CheckContentLengthContentType(const Msg: TIdSipMessage);
begin
  if (Msg.ContentLength > 0) and (Msg.ContentType = '') then
    raise Msg.MalformedException.Create(MissingContentType);
end;

procedure TIdSipParser.CheckCSeqMethod(const Request: TIdSipRequest);
begin
  if (Request.CSeq.Method <> Request.Method) then
    raise Request.MalformedException.Create(CSeqMethodMismatch);
end;

procedure TIdSipParser.CheckRequiredHeaders(const Request: TIdSipRequest);
begin
  if not Request.HasHeader(CallIDHeaderFull) then
    raise Request.MalformedException.Create(MissingCallID);

  if not Request.HasHeader(CSeqHeader) then
    raise Request.MalformedException.Create(MissingCSeq);

  if not Request.HasHeader(FromHeaderFull) then
    raise Request.MalformedException.Create(MissingFrom);

  if not Request.HasHeader(MaxForwardsHeader) then
    raise Request.MalformedException.Create(MissingMaxForwards);

  if not Request.HasHeader(ToHeaderFull) then
    raise Request.MalformedException.Create(MissingTo);

  if not Request.HasHeader(ViaHeaderFull) then
    raise Request.MalformedException.Create(MissingVia);
end;

function TIdSipParser.CreateResponseOrRequest(const Token: String): TIdSipMessage;
begin
  if (Token = SipName) then
    Result := TIdSipResponse.Create
  else
    Result := TIdSipRequest.Create;
end;

procedure TIdSipParser.InitialiseMessage(Msg: TIdSipMessage);
begin
  Msg.Headers.Clear;
  Msg.SipVersion := '';
end;


procedure TIdSipParser.ParseCompoundHeader(const Msg: TIdSipMessage; const Header: String; Parms: String);
begin
  while (Parms <> '') do
    Msg.Headers.Add(Header).Value := Fetch(Parms, ',');
end;

procedure TIdSipParser.ParseHeader(const Msg: TIdSipMessage; const Header: String);
begin
  try
    if TIdSipHeaders.IsCompoundHeader(Header) then
      Self.ParseCompoundHeader(Msg, Self.GetHeaderName(Header), Self.GetHeaderValue(Header))
    else
      Self.AddHeader(Msg, Header);
  except
    on E: EBadHeader do
      raise Msg.MalformedException.Create(Format(MalformedToken, [E.Message, Header]));
  end;
end;

procedure TIdSipParser.ParseHeaders(const Msg: TIdSipMessage);
var
  FoldedHeader: String;
  Line:         String;
begin
  FoldedHeader := Self.ReadLn;
  if (FoldedHeader <> '') then begin
    Line := Self.ReadLn;
    while (Line <> '') do begin
      if (Line[1] in [' ', #9]) then begin
        FoldedHeader := FoldedHeader + ' ' + Trim(Line);
        Line := Self.ReadLn;
      end
      else begin
        Self.ParseHeader(Msg, FoldedHeader);
        FoldedHeader := Line;
        Line := Self.ReadLn;
      end;
    end;
    if (FoldedHeader <> '') then
      Self.ParseHeader(Msg, FoldedHeader);
  end;

  //TODO: check for required headers - To, From, Call-ID, Call-Seq, Max-Forwards, Via
end;

procedure TIdSipParser.ParseRequestLine(const Request: TIdSipRequest);
var
  Line:   String;
  Tokens: TStrings;
begin
  // chew up leading blank lines (Section 7.5)
  Line := Self.ReadFirstNonBlankLine;

  Tokens := TStringList.Create;
  try
    BreakApart(Line, ' ', Tokens);

    if (Tokens.Count > 3) then
      raise Request.MalformedException.Create(RequestUriNoSpaces)
    else if (Tokens.Count < 3) then
      raise Request.MalformedException.Create(Format(MalformedToken, ['Request-Line', Line]));

    Request.Method := Tokens[0];
    // we want to check the Method
    if not Self.IsMethod(Request.Method) then
      raise Request.MalformedException.Create(Format(MalformedToken, ['Method', Request.Method]));

    Request.RequestUri := Tokens[1];

    if (Request.RequestUri[1] = '<') and (Request.RequestUri[Length(Request.RequestUri)] = '>') then
      raise Request.MalformedException.Create(RequestUriNoAngleBrackets);

    Request.SIPVersion := Tokens[2];

    if not Self.IsSipVersion(Request.SIPVersion) then
      raise Request.MalformedException.Create(Format(InvalidSipVersion, [Request.SIPVersion]));
  finally
    Tokens.Free;
  end;
end;

procedure TIdSipParser.ParseStatusLine(const Response: TIdSipResponse);
var
  Line:   String;
  StatusCode: String;
begin
  // chew up leading blank lines (Section 7.5)
  Line := Self.ReadFirstNonBlankLine;

  Response.SIPVersion := Fetch(Line);
  if not Self.IsSipVersion(Response.SIPVersion) then
    raise Response.MalformedException.Create(Format(InvalidSipVersion, [Response.SIPVersion]));

  StatusCode := Fetch(Line);
  if not Self.IsNumber(StatusCode) then
    raise Response.MalformedException.Create(Format(InvalidStatusCode, [StatusCode]));

  Response.StatusCode := StrToIntDef(StatusCode, BadStatusCode);

  Response.StatusText := Line;
end;

function TIdSipParser.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  Result := 0;
end;

function TIdSipParser._AddRef: Integer;
begin
  Result := -1;
end;

function TIdSipParser._Release: Integer;
begin
  Result := -1;
end;

end.
