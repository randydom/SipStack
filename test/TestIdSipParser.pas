unit TestIdSipParser;

interface

uses
  Classes, IdSipMessage, IdSipParser, TestFramework, TestFrameworkEx;

type
  TestFunctions = class(TTestCase)
  published
    procedure TestIsEqual;
    procedure TestShortMonthToInt;
    procedure TestStrToTransport;
    procedure TestTransportToStr;
  end;

  TestTIdSipParser = class(TTestCase)
  private
    P:        TIdSipParser;
    Request:  TIdSipRequest;
    Response: TIdSipResponse;

    procedure CheckBasicMessage(const Msg: TIdSipMessage);
    procedure CheckBasicRequest(const Msg: TIdSipMessage);
    procedure CheckBasicResponse(const Msg: TIdSipMessage);
    procedure CheckTortureTest(const RequestStr, ExpectedExceptionMsg: String);
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCanonicaliseName;
    procedure TestCaseInsensitivityOfContentLengthHeader;
    procedure TestGetHeaderName;
    procedure TestGetHeaderNumberValue;
    procedure TestGetHeaderValue;
    procedure TestIsIPv6Reference;
    procedure TestIsMethod;
    procedure TestIsSipVersion;
    procedure TestIsToken;
    procedure TestIsTransport;
    procedure TestParseAndMakeMessageEmptyString;
    procedure TestParseAndMakeMessageMalformedRequest;
    procedure TestParseAndMakeMessageRequest;
    procedure TestParseAndMakeMessageResponse;
    procedure TestParseExtensiveRequest;
    procedure TestParseReallyLongViaHeader;
    procedure TestParseRequest;
    procedure TestParseRequestBadCSeq;
    procedure TestParseRequestEmptyString;
    procedure TestParseRequestFoldedHeader;
    procedure TestParseRequestMalformedMaxForwards;
    procedure TestParseRequestMalformedMethod;
    procedure TestParseRequestMalformedRequestLine;
    procedure TestParseRequestMessageBodyLongerThanContentLength;
    procedure TestParseRequestMissingCallID;
    procedure TestParseRequestMissingCSeq;
    procedure TestParseRequestMissingFrom;
    procedure TestParseRequestMissingMaxForwards;
    procedure TestParseRequestMissingTo;
    procedure TestParseRequestMissingVia;
    procedure TestParseRequestMultipleVias;
    procedure TestParseRequestRequestUriHasSpaces;
    procedure TestParseRequestRequestUriInAngleBrackets;
    procedure TestParseRequestWithLeadingCrLfs;
    procedure TestParseRequestWithBodyAndNoContentType;
    procedure TestParseResponse;
    procedure TestParseResponseEmptyString;
    procedure TestParseResponseFoldedHeader;
    procedure TestParseResponseInvalidStatusCode;
    procedure TestParseResponseWithLeadingCrLfs;
    procedure TestParseShortFormContentLength;
    procedure TestTortureTest1;
    procedure TestTortureTest8;
    procedure TestTortureTest11;
    procedure TestTortureTest13;
    procedure TestTortureTest15;
    procedure TestTortureTest19;
    procedure TestTortureTest21;
    procedure TestTortureTest22;
    procedure TestTortureTest23;
    procedure TestTortureTest24;
    procedure TestTortureTest35;
    procedure TestTortureTest40;
  end;

const
  BasicRequest = 'INVITE sip:wintermute@tessier-ashpool.co.lu SIP/2.0'#13#10
               + 'Via: SIP/2.0/TCP gw1.leo-ix.org;branch=z9hG4bK776asdhds'#13#10
               + 'Max-Forwards: 70'#13#10
               + 'To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>'#13#10
               + 'From: Case <sip:case@fried.neurons.org>;tag=1928301774'#13#10
               + 'Call-ID: a84b4c76e66710@gw1.leo-ix.org'#13#10
               + 'CSeq: 314159 INVITE'#13#10
               + 'Contact: sip:wintermute@tessier-ashpool.co.lu'#13#10
               + 'Content-Type: text/plain'#13#10
               + 'Content-Length: 29'#13#10
               + #13#10
               + 'I am a message. Hear me roar!';
  BasicResponse = 'SIP/2.0 486 Busy Here'#13#10
                + 'Via: SIP/2.0/TCP gw1.leo-ix.org;branch=z9hG4bK776asdhds'#13#10
                + 'Max-Forwards: 70'#13#10
                + 'To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>'#13#10
                + 'From: Case <sip:case@fried.neurons.org>;tag=1928301774'#13#10
                + 'Call-ID: a84b4c76e66710@gw1.leo-ix.org'#13#10
                + 'CSeq: 314159 INVITE'#13#10
                + 'Contact: sip:wintermute@tessier-ashpool.co.lu'#13#10
                + 'Content-Type: text/plain'#13#10
                + 'Content-Length: 29'#13#10
                + #13#10
                + 'I am a message. Hear me roar!';
  EmptyRequest = 'INVITE sip:wintermute@tessier-ashpool.co.lu SIP/2.0'#13#10
               + 'Via: SIP/2.0/TCP gw1.leo-ix.org;branch=z9hG4bK776asdhds'#13#10
               + 'Max-Forwards: 70'#13#10
               + 'To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>'#13#10
               + 'From: Case <sip:case@fried.neurons.org>;tag=1928301774'#13#10
               + 'Call-ID: a84b4c76e66710@gw1.leo-ix.org'#13#10
               + 'CSeq: 314159 INVITE'#13#10
               + 'Contact: sip:wintermute@tessier-ashpool.co.lu'#13#10;
  ExhaustiveRequest = 'INVITE sip:wintermute@tessier-ashpool.co.lu SIP/2.0'#13#10
                    + 'Call-ID: a84b4c76e66710@gw1.leo-ix.org'#13#10
                    + 'Contact: sip:wintermute@tessier-ashpool.co.lu'#13#10
                    + 'Content-Length: 29'#13#10
                    + 'Content-Type: text/plain'#13#10
                    + 'CSeq: 314159 INVITE'#13#10
                    + 'Date: Thu, 1 Jan 1970 00:00:00 GMT'#13#10
                    + 'Expires: 1000'#13#10
                    + 'From: Case <sip:case@fried.neurons.org>;tag=1928301774'#13#10
                    + 'Max-Forwards: 70'#13#10
                    + 'Subject: I am a SIP request with every legal header (even an extension)'#13#10
                    + 'To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>'#13#10
                    + 'Via: SIP/2.0/TCP gw1.leo-ix.org;branch=z9hG4bK776asdhds'#13#10
                    + 'X-Not-A-Header: I am not defined in RFC 3261'#13#10
                    + #13#10
                    + 'I am a message. Hear me roar!';

implementation

uses
  DateUtils, IdSimpleParser, SysUtils, TortureTests;

function Suite: ITestSuite;
begin
  Result := TTestSuite.Create('IdSipParser tests');
  Result.AddTest(TestFunctions.Suite);
  Result.AddTest(TestTIdSipParser.Suite);
end;

//******************************************************************************
//* TestFunctions                                                              *
//******************************************************************************
//* TestFunctions Published methods ********************************************

procedure TestFunctions.TestIsEqual;
begin
  Check(    IsEqual('', ''),         ''''' & ''''');
  Check(not IsEqual(' ', ''),        ''' '' & ''''');
  Check(    IsEqual('abcd', 'AbCd'), '''abcd'', ''AbCd''');
  Check(not IsEqual('absd', 'Abcd'), '''absd'', ''Abcd''');
end;

procedure TestFunctions.TestShortMonthToInt;
begin
  CheckEquals(1, ShortMonthToInt('JAN'), 'JAN');
  CheckEquals(1, ShortMonthToInt('jan'), 'jan');

  CheckEquals(1,  ShortMonthToInt('Jan'), 'Jan');
  CheckEquals(2,  ShortMonthToInt('Feb'), 'Feb');
  CheckEquals(3,  ShortMonthToInt('Mar'), 'Mar');
  CheckEquals(4,  ShortMonthToInt('Apr'), 'Apr');
  CheckEquals(5,  ShortMonthToInt('May'), 'May');
  CheckEquals(6,  ShortMonthToInt('Jun'), 'Jun');
  CheckEquals(7,  ShortMonthToInt('Jul'), 'Jul');
  CheckEquals(8,  ShortMonthToInt('Aug'), 'Aug');
  CheckEquals(9,  ShortMonthToInt('Sep'), 'Sep');
  CheckEquals(10, ShortMonthToInt('Oct'), 'Oct');
  CheckEquals(11, ShortMonthToInt('Nov'), 'Nov');
  CheckEquals(12, ShortMonthToInt('Dec'), 'Dec');

  try
    ShortMonthToInt('xxx');
    Fail('Failed to bail out on malformed short month name');
  except
    on E: EConvertError do
      CheckEquals('Failed to convert ''xxx'' to type Integer', E.Message, 'Unexpected error');
  end;
end;

procedure TestFunctions.TestStrToTransport;
begin
  Check(sttSCTP = StrToTransport('SCTP'), 'SCTP');
  Check(sttTCP  = StrToTransport('TCP'),  'TCP');
  Check(sttTLS  = StrToTransport('TLS'),  'TLS');
  Check(sttUDP  = StrToTransport('UDP'),  'UDP');

  try
    StrToTransport('not a transport');
    Fail('Failed to bail out on an unknown transport type');
  except
    on EConvertError do;
  end;
end;

procedure TestFunctions.TestTransportToStr;
var
  T: TIdSipTransportType;
begin
  for T := Low(TIdSipTransportType) to High(TIdSipTransportType) do
    Check(T = StrToTransport(TransportToStr(T)), 'Ord(T) = ' + IntToStr(Ord(T)));
end;

//******************************************************************************
//* TestTIdSipParser                                                           *
//******************************************************************************
//* TestTIdSipParser Public methods ********************************************

procedure TestTIdSipParser.SetUp;
begin
  P := TIdSipParser.Create;

  Request := TIdSipRequest.Create;
  Response := TIdSipResponse.Create;
end;

procedure TestTIdSipParser.TearDown;
begin
  Request.Free;
  Response.Free;
  P.Free;
end;

//* TestTIdSipParser Published methods *****************************************

procedure TestTIdSipParser.TestCanonicaliseName;
begin
  CheckEquals('', Self.P.CanonicaliseName(''), '''''');
  CheckEquals('New-Header', Self.P.CanonicaliseName('New-Header'), 'New-Header');
  CheckEquals('new-header', Self.P.CanonicaliseName('new-header'), 'new-header');

  CheckEquals(AcceptHeader, Self.P.CanonicaliseName('accept'),     'accept');
  CheckEquals(AcceptHeader, Self.P.CanonicaliseName('Accept'),     'Accept');
  CheckEquals(AcceptHeader, Self.P.CanonicaliseName(AcceptHeader), 'AcceptHeader constant');

  CheckEquals(AcceptEncodingHeader, Self.P.CanonicaliseName('accept-encoding'),    'accept-encoding');
  CheckEquals(AcceptEncodingHeader, Self.P.CanonicaliseName('Accept-Encoding'),    'Accept-Encoding');
  CheckEquals(AcceptEncodingHeader, Self.P.CanonicaliseName(AcceptEncodingHeader), 'AcceptEncodingHeader constant');

  CheckEquals(AcceptLanguageHeader, Self.P.CanonicaliseName('accept-language'),    'accept-language');
  CheckEquals(AcceptLanguageHeader, Self.P.CanonicaliseName('Accept-Language'),    'Accept-Language');
  CheckEquals(AcceptLanguageHeader, Self.P.CanonicaliseName(AcceptLanguageHeader), 'AcceptLanguageHeader constant');

  CheckEquals(AlertInfoHeader, Self.P.CanonicaliseName('alert-info'),    'alert-info');
  CheckEquals(AlertInfoHeader, Self.P.CanonicaliseName('Alert-Info'),    'Alert-Info');
  CheckEquals(AlertInfoHeader, Self.P.CanonicaliseName(AlertInfoHeader), 'AlertInfoHeader constant');

  CheckEquals(AllowHeader, Self.P.CanonicaliseName('allow'),     'allow');
  CheckEquals(AllowHeader, Self.P.CanonicaliseName('Allow'),     'Allow');
  CheckEquals(AllowHeader, Self.P.CanonicaliseName(AllowHeader), 'AllowHeader constant');

  CheckEquals(AuthenticationInfoHeader, Self.P.CanonicaliseName('authentication-info'),    'authentication-info');
  CheckEquals(AuthenticationInfoHeader, Self.P.CanonicaliseName('Authentication-Info'),    'Authentication-Info');
  CheckEquals(AuthenticationInfoHeader, Self.P.CanonicaliseName(AuthenticationInfoHeader), 'AuthenticationInfoHeader constant');

  CheckEquals(AuthorizationHeader, Self.P.CanonicaliseName('authorization'),     'authorization');
  CheckEquals(AuthorizationHeader, Self.P.CanonicaliseName('Authorization'),     'Authorization');
  CheckEquals(AuthorizationHeader, Self.P.CanonicaliseName(AuthorizationHeader), 'AuthorizationHeader constant');

  CheckEquals(CallIDHeaderFull, Self.P.CanonicaliseName('call-ID'),         'call-ID');
  CheckEquals(CallIDHeaderFull, Self.P.CanonicaliseName('Call-ID'),         'Call-ID');
  CheckEquals(CallIDHeaderFull, Self.P.CanonicaliseName('i'),               'i');
  CheckEquals(CallIDHeaderFull, Self.P.CanonicaliseName('I'),               'I');
  CheckEquals(CallIDHeaderFull, Self.P.CanonicaliseName(CallIDHeaderFull),  'CallIDHeaderFull constant');
  CheckEquals(CallIDHeaderFull, Self.P.CanonicaliseName(CallIDHeaderShort), 'CallIDHeaderShort constant');

  CheckEquals(CallInfoHeader, Self.P.CanonicaliseName('call-info'),     'call-info');
  CheckEquals(CallInfoHeader, Self.P.CanonicaliseName('Call-Info'),     'Call-Info');
  CheckEquals(CallInfoHeader, Self.P.CanonicaliseName(CallInfoHeader), 'CallInfoHeader constant');

  CheckEquals(ContactHeaderFull, Self.P.CanonicaliseName('contact'),          'contact');
  CheckEquals(ContactHeaderFull, Self.P.CanonicaliseName('Contact'),          'Contact');
  CheckEquals(ContactHeaderFull, Self.P.CanonicaliseName('m'),                'm');
  CheckEquals(ContactHeaderFull, Self.P.CanonicaliseName('M'),                'M');
  CheckEquals(ContactHeaderFull, Self.P.CanonicaliseName(ContactHeaderFull),  'ContactHeaderFull constant');
  CheckEquals(ContactHeaderFull, Self.P.CanonicaliseName(ContactHeaderShort), 'ContactHeaderShort constant');

  CheckEquals(ContentDispositionHeader, Self.P.CanonicaliseName('content-disposition'),    'content-disposition');
  CheckEquals(ContentDispositionHeader, Self.P.CanonicaliseName('Content-Disposition'),    'Content-Disposition');
  CheckEquals(ContentDispositionHeader, Self.P.CanonicaliseName(ContentDispositionHeader), 'ContentDispositionHeader constant');

  CheckEquals(ContentEncodingHeaderFull, Self.P.CanonicaliseName('content-encoding'),         'content-encoding');
  CheckEquals(ContentEncodingHeaderFull, Self.P.CanonicaliseName('Content-Encoding'),         'Content-Encoding');
  CheckEquals(ContentEncodingHeaderFull, Self.P.CanonicaliseName('e'),                        'e');
  CheckEquals(ContentEncodingHeaderFull, Self.P.CanonicaliseName('E'),                        'E');
  CheckEquals(ContentEncodingHeaderFull, Self.P.CanonicaliseName(ContentEncodingHeaderFull),  'ContentEncodingHeaderFull constant');
  CheckEquals(ContentEncodingHeaderFull, Self.P.CanonicaliseName(ContentEncodingHeaderShort), 'ContentEncodingHeaderShort constant');

  CheckEquals(ContentLanguageHeader, Self.P.CanonicaliseName('content-language'),    'content-language');
  CheckEquals(ContentLanguageHeader, Self.P.CanonicaliseName('Content-Language'),    'Content-Language');
  CheckEquals(ContentLanguageHeader, Self.P.CanonicaliseName(ContentLanguageHeader), 'ContentLanguageHeader constant');

  CheckEquals(ContentLengthHeaderFull, Self.P.CanonicaliseName('Content-Length'),         'Content-Length');
  CheckEquals(ContentLengthHeaderFull, Self.P.CanonicaliseName('Content-Length'),         'Content-Length');
  CheckEquals(ContentLengthHeaderFull, Self.P.CanonicaliseName('l'),                      'l');
  CheckEquals(ContentLengthHeaderFull, Self.P.CanonicaliseName('L'),                      'L');
  CheckEquals(ContentLengthHeaderFull, Self.P.CanonicaliseName(ContentLengthHeaderFull),  'ContentLengthHeaderFull constant');
  CheckEquals(ContentLengthHeaderFull, Self.P.CanonicaliseName(ContentLengthHeaderShort), 'ContentLengthHeaderShort constant');

  CheckEquals(ContentTypeHeaderFull, Self.P.CanonicaliseName('content-type'),         'content-type');
  CheckEquals(ContentTypeHeaderFull, Self.P.CanonicaliseName('Content-Type'),         'Content-Type');
  CheckEquals(ContentTypeHeaderFull, Self.P.CanonicaliseName('c'),                    'c');
  CheckEquals(ContentTypeHeaderFull, Self.P.CanonicaliseName('C'),                    'C');
  CheckEquals(ContentTypeHeaderFull, Self.P.CanonicaliseName(ContentTypeHeaderFull),  'ContentTypeHeaderFull constant');
  CheckEquals(ContentTypeHeaderFull, Self.P.CanonicaliseName(ContentTypeHeaderShort), 'ContentTypeHeaderShort constant');

  CheckEquals(CSeqHeader, Self.P.CanonicaliseName('cseq'),     'cseq');
  CheckEquals(CSeqHeader, Self.P.CanonicaliseName('CSeq'),     'CSeq');
  CheckEquals(CSeqHeader, Self.P.CanonicaliseName(CSeqHeader), 'CSeqHeader constant');

  CheckEquals(DateHeader, Self.P.CanonicaliseName('date'),     'date');
  CheckEquals(DateHeader, Self.P.CanonicaliseName('Date'),     'Date');
  CheckEquals(DateHeader, Self.P.CanonicaliseName(DateHeader), 'DateHeader constant');

  CheckEquals(ErrorInfoHeader, Self.P.CanonicaliseName('error-info'),     'irror-info');
  CheckEquals(ErrorInfoHeader, Self.P.CanonicaliseName('Error-Info'),     'Error-Info');
  CheckEquals(ErrorInfoHeader, Self.P.CanonicaliseName(ErrorInfoHeader), 'ErrorInfoHeader constant');

  CheckEquals(ExpiresHeader, Self.P.CanonicaliseName('expires'),     'expires');
  CheckEquals(ExpiresHeader, Self.P.CanonicaliseName('Expires'),     'Expires');
  CheckEquals(ExpiresHeader, Self.P.CanonicaliseName(ExpiresHeader), 'ExpiresHeader constant');

  CheckEquals(FromHeaderFull, Self.P.CanonicaliseName('from'),          'from');
  CheckEquals(FromHeaderFull, Self.P.CanonicaliseName('From'),          'From');
  CheckEquals(FromHeaderFull, Self.P.CanonicaliseName('f'),             'f');
  CheckEquals(FromHeaderFull, Self.P.CanonicaliseName('F'),             'F');
  CheckEquals(FromHeaderFull, Self.P.CanonicaliseName(FromHeaderFull),  'FromHeaderFull constant');
  CheckEquals(FromHeaderFull, Self.P.CanonicaliseName(FromHeaderShort), 'FromHeaderShort constant');

  CheckEquals(InReplyToHeader, Self.P.CanonicaliseName('in-reply-to'),   'in-reply-to');
  CheckEquals(InReplyToHeader, Self.P.CanonicaliseName('In-Reply-To'),   'In-Reply-To');
  CheckEquals(InReplyToHeader, Self.P.CanonicaliseName(InReplyToHeader), 'InReplyToHeader constant');

  CheckEquals(MaxForwardsHeader, Self.P.CanonicaliseName('max-forwards'),    'max-forwards');
  CheckEquals(MaxForwardsHeader, Self.P.CanonicaliseName('Max-Forwards'),    'Max-Forwards');
  CheckEquals(MaxForwardsHeader, Self.P.CanonicaliseName(MaxForwardsHeader), 'MaxForwardsHeader constant');

  CheckEquals(MIMEVersionHeader, Self.P.CanonicaliseName('mime-version'),    'mime-version');
  CheckEquals(MIMEVersionHeader, Self.P.CanonicaliseName('MIME-Version'),    'MIME-Version');
  CheckEquals(MIMEVersionHeader, Self.P.CanonicaliseName(MIMEVersionHeader), 'MIMEVersionHeader constant');

  CheckEquals(MinExpiresHeader, Self.P.CanonicaliseName('min-expires'),    'min-expires');
  CheckEquals(MinExpiresHeader, Self.P.CanonicaliseName('Min-Expires'),    'Min-Expires');
  CheckEquals(MinExpiresHeader, Self.P.CanonicaliseName(MinExpiresHeader), 'MinExpiresHeader constant');

  CheckEquals(OrganizationHeader, Self.P.CanonicaliseName('organization'),     'organization');
  CheckEquals(OrganizationHeader, Self.P.CanonicaliseName('Organization'),     'Organization');
  CheckEquals(OrganizationHeader, Self.P.CanonicaliseName(OrganizationHeader), 'OrganizationHeader constant');

  CheckEquals(PriorityHeader, Self.P.CanonicaliseName('priority'),     'priority');
  CheckEquals(PriorityHeader, Self.P.CanonicaliseName('Priority'),     'Priority');
  CheckEquals(PriorityHeader, Self.P.CanonicaliseName(PriorityHeader), 'PriorityHeader constant');

  CheckEquals(ProxyAuthenticateHeader, Self.P.CanonicaliseName('proxy-authenticate'),    'proxy-authenticate');
  CheckEquals(ProxyAuthenticateHeader, Self.P.CanonicaliseName('Proxy-Authenticate'),    'Proxy-Authenticate');
  CheckEquals(ProxyAuthenticateHeader, Self.P.CanonicaliseName(ProxyAuthenticateHeader), 'ProxyAuthenticateHeader constant');

  CheckEquals(ProxyAuthorizationHeader, Self.P.CanonicaliseName('proxy-authorization'),    'proxy-authorization');
  CheckEquals(ProxyAuthorizationHeader, Self.P.CanonicaliseName('Proxy-Authorization'),    'Proxy-Authorization');
  CheckEquals(ProxyAuthorizationHeader, Self.P.CanonicaliseName(ProxyAuthorizationHeader), 'ProxyAuthorizationHeader constant');

  CheckEquals(ProxyRequireHeader, Self.P.CanonicaliseName('proxy-require'),    'proxy-require');
  CheckEquals(ProxyRequireHeader, Self.P.CanonicaliseName('Proxy-Require'),    'Proxy-Require');
  CheckEquals(ProxyRequireHeader, Self.P.CanonicaliseName(ProxyRequireHeader), 'ProxyRequireHeader constant');

  CheckEquals(RecordRouteHeader, Self.P.CanonicaliseName('record-route'),    'record-route');
  CheckEquals(RecordRouteHeader, Self.P.CanonicaliseName('Record-Route'),    'Record-Route');
  CheckEquals(RecordRouteHeader, Self.P.CanonicaliseName(RecordRouteHeader), 'RecordRouteHeader constant');

  CheckEquals(ReplyToHeader, Self.P.CanonicaliseName('reply-to'),    'reply-to');
  CheckEquals(ReplyToHeader, Self.P.CanonicaliseName('Reply-To'),    'Reply-To');
  CheckEquals(ReplyToHeader, Self.P.CanonicaliseName(ReplyToHeader), 'ReplyToHeader constant');

  CheckEquals(RequireHeader, Self.P.CanonicaliseName('require'),     'require');
  CheckEquals(RequireHeader, Self.P.CanonicaliseName('Require'),     'Require');
  CheckEquals(RequireHeader, Self.P.CanonicaliseName(RequireHeader), 'RequireHeader constant');

  CheckEquals(RetryAfterHeader, Self.P.CanonicaliseName('retry-after'),    'retry-after');
  CheckEquals(RetryAfterHeader, Self.P.CanonicaliseName('Retry-After'),    'Retry-After');
  CheckEquals(RetryAfterHeader, Self.P.CanonicaliseName(RetryAfterHeader), 'RetryAfterHeader constant');

  CheckEquals(RouteHeader, Self.P.CanonicaliseName('route'),     'route');
  CheckEquals(RouteHeader, Self.P.CanonicaliseName('Route'),     'Route');
  CheckEquals(RouteHeader, Self.P.CanonicaliseName(RouteHeader), 'RouteHeader constant');

  CheckEquals(ServerHeader, Self.P.CanonicaliseName('server'),     'server');
  CheckEquals(ServerHeader, Self.P.CanonicaliseName('Server'),     'Server');
  CheckEquals(ServerHeader, Self.P.CanonicaliseName(ServerHeader), 'ServerHeader constant');

  CheckEquals(SubjectHeaderFull, Self.P.CanonicaliseName('subject'),          'subject');
  CheckEquals(SubjectHeaderFull, Self.P.CanonicaliseName('Subject'),          'Subject');
  CheckEquals(SubjectHeaderFull, Self.P.CanonicaliseName('s'),                's');
  CheckEquals(SubjectHeaderFull, Self.P.CanonicaliseName('S'),                'S');
  CheckEquals(SubjectHeaderFull, Self.P.CanonicaliseName(SubjectHeaderFull),  'SubjectHeaderFull constant');
  CheckEquals(SubjectHeaderFull, Self.P.CanonicaliseName(SubjectHeaderShort), 'SubjectHeaderShort constant');

  CheckEquals(SupportedHeaderFull, Self.P.CanonicaliseName('supported'),          'supported');
  CheckEquals(SupportedHeaderFull, Self.P.CanonicaliseName('Supported'),          'Supported');
  CheckEquals(SupportedHeaderFull, Self.P.CanonicaliseName('k'),                  'k');
  CheckEquals(SupportedHeaderFull, Self.P.CanonicaliseName('K'),                  'K');
  CheckEquals(SupportedHeaderFull, Self.P.CanonicaliseName(SupportedHeaderFull),  'SupportedHeaderFull constant');
  CheckEquals(SupportedHeaderFull, Self.P.CanonicaliseName(SupportedHeaderShort), 'SupportedHeaderShort constant');

  CheckEquals(TimestampHeader, Self.P.CanonicaliseName('timestamp'),     'timestamp');
  CheckEquals(TimestampHeader, Self.P.CanonicaliseName('Timestamp'),     'Timestamp');
  CheckEquals(TimestampHeader, Self.P.CanonicaliseName(TimestampHeader), 'TimestampHeader constant');

  CheckEquals(ToHeaderFull, Self.P.CanonicaliseName('to'),          'to');
  CheckEquals(ToHeaderFull, Self.P.CanonicaliseName('To'),          'To');
  CheckEquals(ToHeaderFull, Self.P.CanonicaliseName('t'),           't');
  CheckEquals(ToHeaderFull, Self.P.CanonicaliseName('T'),           'T');
  CheckEquals(ToHeaderFull, Self.P.CanonicaliseName(ToHeaderFull),  'ToHeaderFull constant');
  CheckEquals(ToHeaderFull, Self.P.CanonicaliseName(ToHeaderShort), 'ToHeaderShort constant');

  CheckEquals(UnsupportedHeader, Self.P.CanonicaliseName('unsupported'),     'unsupported');
  CheckEquals(UnsupportedHeader, Self.P.CanonicaliseName('Unsupported'),     'Unsupported');
  CheckEquals(UnsupportedHeader, Self.P.CanonicaliseName(UnsupportedHeader), 'UnsupportedHeader constant');

  CheckEquals(UserAgentHeader, Self.P.CanonicaliseName('user-agent'),    'user-agent');
  CheckEquals(UserAgentHeader, Self.P.CanonicaliseName('User-Agent'),    'User-Agent');
  CheckEquals(UserAgentHeader, Self.P.CanonicaliseName(UserAgentHeader), 'UserAgentHeader constant');

  CheckEquals(ViaHeaderFull, Self.P.CanonicaliseName('via'),          'via');
  CheckEquals(ViaHeaderFull, Self.P.CanonicaliseName('Via'),          'Via');
  CheckEquals(ViaHeaderFull, Self.P.CanonicaliseName('v'),            'v');
  CheckEquals(ViaHeaderFull, Self.P.CanonicaliseName('V'),            'V');
  CheckEquals(ViaHeaderFull, Self.P.CanonicaliseName(ViaHeaderFull),  'ViaHeaderFull constant');
  CheckEquals(ViaHeaderFull, Self.P.CanonicaliseName(ViaHeaderShort), 'ViaHeaderShort constant');

  CheckEquals(WarningHeader, Self.P.CanonicaliseName('warning'),     'warning');
  CheckEquals(WarningHeader, Self.P.CanonicaliseName('Warning'),     'Warning');
  CheckEquals(WarningHeader, Self.P.CanonicaliseName(WarningHeader), 'WarningHeader constant');

  CheckEquals(WWWAuthenticateHeader, Self.P.CanonicaliseName('www-authenticate'),    'www-authenticate');
  CheckEquals(WWWAuthenticateHeader, Self.P.CanonicaliseName('WWW-Authenticate'),    'WWW-Authenticate');
  CheckEquals(WWWAuthenticateHeader, Self.P.CanonicaliseName(WWWAuthenticateHeader), 'WWWAuthenticateHeader constant');
end;

procedure TestTIdSipParser.TestCaseInsensitivityOfContentLengthHeader;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create(StringReplace(BasicRequest,
                                            'Content-Length',
                                            'Content-LENGTH',
                                            [rfReplaceAll]));
  try
    Self.P.Source := Str;

    Self.P.ParseRequest(Request);

    CheckEquals(29, Request.ContentLength, 'ContentLength');
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestGetHeaderName;
begin
  CheckEquals('haha', Self.P.GetHeaderName('haha'),        'haha');
  CheckEquals('haha', Self.P.GetHeaderName('haha: kief'),  'haha: kief');
  CheckEquals('haha', Self.P.GetHeaderName('haha:kief'),   'haha:kief');
  CheckEquals('haha', Self.P.GetHeaderName('haha :kief'),  'haha :kief');
  CheckEquals('haha', Self.P.GetHeaderName('haha : kief'), 'haha : kief');
  CheckEquals('haha', Self.P.GetHeaderName(' haha'),       ' haha');
  CheckEquals('',     Self.P.GetHeaderName(''),            '''''');
  CheckEquals('',     Self.P.GetHeaderName(#0),            '#0');
end;

procedure TestTIdSipParser.TestGetHeaderNumberValue;
begin
  CheckEquals(12, Self.P.GetHeaderNumberValue(Request, 'one :12'), 'one :12');
  CheckEquals(13, Self.P.GetHeaderNumberValue(Request, 'one:13'), 'one:13');
  CheckEquals(14, Self.P.GetHeaderNumberValue(Request, 'one : 14'), 'one : 14');

  try
    Self.P.GetHeaderNumberValue(Request, '');
    Fail('Failed to bail getting numeric value of '''' (request)');
  except
    on EBadRequest do;
  end;

  try
    Self.P.GetHeaderNumberValue(Response, '');
    Fail('Failed to bail getting numeric value of '''' (response)');
  except
    on EBadResponse do;
  end;

  try
    Self.P.GetHeaderNumberValue(Response, 'haha: one');
    Fail('Failed to bail getting numeric value of ''haha: one''');
  except
    on EBadResponse do;
  end;
end;

procedure TestTIdSipParser.TestGetHeaderValue;
begin
  CheckEquals('',     Self.P.GetHeaderValue('haha'),        'haha');
  CheckEquals('kief', Self.P.GetHeaderValue('haha: kief'),  'haha: kief');
  CheckEquals('kief', Self.P.GetHeaderValue('haha:kief'),   'haha:kief');
  CheckEquals('kief', Self.P.GetHeaderValue('haha :kief'),  'haha :kief');
  CheckEquals('kief', Self.P.GetHeaderValue('haha : kief'), 'haha : kief');
  CheckEquals('kief', Self.P.GetHeaderValue(' : kief'),  ' : kief');
  CheckEquals('kief', Self.P.GetHeaderValue(': kief'),  ': kief');
  CheckEquals('',     Self.P.GetHeaderValue(' haha'),       ' haha');
  CheckEquals('',     Self.P.GetHeaderValue(''),            '''''');
  CheckEquals('',     Self.P.GetHeaderValue(#0),            '#0');
end;

procedure TestTIdSipParser.TestIsIPv6Reference;
begin
  Check(not TIdSipParser.IsIPv6Reference(''),                       '''''');
  Check(not TIdSipParser.IsIPv6Reference('ff01:0:0:0:0:0:0:101'),   'ff01:0:0:0:0:0:0:101');
  Check(not TIdSipParser.IsIPv6Reference('[]'),                     '[]');
  Check(    TIdSipParser.IsIPv6Reference('[ff01:0:0:0:0:0:0:101]'), '[ff01:0:0:0:0:0:0:101]');
end;

procedure TestTIdSipParser.TestIsMethod;
begin
  Check(not TIdSipParser.IsMethod(''),                             '''''');
  Check(not TIdSipParser.IsMethod('Cra.-zy''+prea"cher%20man~`!'), 'Cra.-zy''+prea"cher%20man~`!'); // no "'s
  Check(not TIdSipParser.IsMethod('LastChar"'),                    'LastChar"'); // no "'s
  Check(    TIdSipParser.IsMethod('INVITE'),                       'INVITE');
  Check(    TIdSipParser.IsMethod('X-INVITE'),                     'X-INVITE');
  Check(    TIdSipParser.IsMethod('1'),                            '1');
  Check(    TIdSipParser.IsMethod('a'),                            'a');
  Check(    TIdSipParser.IsMethod('---'),                          '---');
  Check(    TIdSipParser.IsMethod('X_CITE'),                       'X_CITE');
  Check(    TIdSipParser.IsMethod('Cra.-zy''+preacher%20man~`!'),  'Cra.-zy''+preacher%20man~`!');
end;

procedure TestTIdSipParser.TestIsSipVersion;
begin
  Check(not TIdSipParser.IsSipVersion(''),         '''''');
  Check(    TIdSipParser.IsSipVersion('SIP/2.0'),  'SIP/2.0');
  Check(    TIdSipParser.IsSipVersion('sip/2.0'),  'sip/2.0');
  Check(    TIdSipParser.IsSipVersion(SIPVersion), 'SIPVersion constant');
  Check(not TIdSipParser.IsSipVersion('SIP/X.Y'),  'SIP/X.Y');
end;

procedure TestTIdSipParser.TestIsToken;
begin
  Check(not TIdSipParser.IsToken(''),         '''''');
  Check(    TIdSipParser.IsToken('one'),      'one');
  Check(    TIdSipParser.IsToken('1two'),     '1two');
  Check(    TIdSipParser.IsToken('1-two'),    '1-two');
  Check(    TIdSipParser.IsToken('.'),        '.');
  Check(    TIdSipParser.IsToken('!'),        '!');
  Check(    TIdSipParser.IsToken('%'),        '%');
  Check(    TIdSipParser.IsToken('*'),        '*');
  Check(    TIdSipParser.IsToken('_'),        '_');
  Check(    TIdSipParser.IsToken('+'),        '+');
  Check(    TIdSipParser.IsToken('`'),        '`');
  Check(    TIdSipParser.IsToken(''''),        '''');
  Check(    TIdSipParser.IsToken('~'),        '~');
  Check(    TIdSipParser.IsToken('''baka'''), '''baka''');
end;

procedure TestTIdSipParser.TestIsTransport;
begin
  Check(not TIdSipParser.IsTransport(''), '''''');
end;

procedure TestTIdSipParser.TestParseAndMakeMessageEmptyString;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create('');
  try
    Self.P.Source := Str;

    try
      Self.P.ParseAndMakeMessage.Free;
    except
      on E: EParser do
        CheckEquals(EmptyInputStream, E.Message, 'Unexpected exception');
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseAndMakeMessageMalformedRequest;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create('INVITE sip:wintermute@tessier-ashpool.co.lu SIP/;2.0'#13#10
                            + #13#10);
  try
    Self.P.Source := Str;

    try
      Self.P.ParseAndMakeMessage;
      Fail('Failed to bail out on parsing a malformed message');
    except
      on E: EBadRequest do;
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseAndMakeMessageRequest;
var
  Msg: TIdSipMessage;
  Str: TStringStream;
begin
  Str := TStringStream.Create(BasicRequest);
  try
    Self.P.Source := Str;

    Msg := Self.P.ParseAndMakeMessage;
    try
      Self.CheckBasicRequest(Msg);
    finally
      Msg.Free;
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseAndMakeMessageResponse;
var
  Msg: TIdSipMessage;
  Str: TStringStream;
begin
  Str := TStringStream.Create(BasicResponse);
  try
    Self.P.Source := Str;

    Msg := Self.P.ParseAndMakeMessage;
    try
      Self.CheckBasicResponse(Msg);
    finally
      Msg.Free;
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseExtensiveRequest;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create(ExhaustiveRequest);
  try
    Self.P.Source := Str;

    Self.P.ParseRequest(Request);
    CheckEquals('a84b4c76e66710@gw1.leo-ix.org',
                Self.Request.Headers[CallIdHeaderFull].Value,
                'Call-ID');
    CheckEquals(TIdSipAddressHeader.ClassName,
                Self.Request.Headers[ContactHeaderFull].ClassName,
                'Contact class');
    CheckEquals('sip:wintermute@tessier-ashpool.co.lu',
                Self.Request.Headers[ContactHeaderFull].Value,
                'Contact');
    CheckEquals('',
                (Self.Request.Headers[ContactHeaderFull] as TIdSipAddressHeader).DisplayName,
                'Contact DisplayName');
    CheckEquals('sip:wintermute@tessier-ashpool.co.lu',
                (Self.Request.Headers[ContactHeaderFull] as TIdSipAddressHeader).Address.GetFullURI,
                'Contact Address');
    CheckEquals(TIdSipNumericHeader.ClassName,
                Self.Request.Headers[ContentLengthHeaderFull].ClassName,
                'Content-Length class');
    CheckEquals(29,
                (Self.Request.Headers[ContentLengthHeaderFull] as TIdSipNumericHeader).NumericValue,
                'Content-Length');
    CheckEquals('text/plain',
                Self.Request.Headers[ContentTypeHeaderFull].Value,
                'Content-Type');
    CheckEquals(TIdSipCSeqHeader.ClassName,
                Self.Request.Headers[CSeqHeader].ClassName,
                'CSeq class');
    CheckEquals(314159,
                (Self.Request.Headers[CSeqHeader] as TIdSipCSeqHeader).SequenceNo,
                'CSeq SequenceNo');
    CheckEquals('INVITE',
                (Self.Request.Headers[CSeqHeader] as TIdSipCSeqHeader).Method,
                'CSeq Method');
    CheckEquals(TIdSipDateHeader.ClassName,
                Self.Request.Headers[DateHeader].ClassName,
                'Date class');
    CheckEquals('Thu, 1 Jan 1970 00:00:00 +0000',
                (Self.Request.Headers[DateHeader] as TIdSipDateHeader).Time.GetAsRFC822,
                'Date');
    CheckEquals(TIdSipNumericHeader.ClassName,
                Self.Request.Headers[ExpiresHeader].ClassName,
                'Expires class');
    CheckEquals(1000,
                (Self.Request.Headers[ExpiresHeader] as TIdSipNumericHeader).NumericValue,
                'Expires');
    CheckEquals(TIdSipAddressHeader.ClassName,
                Self.Request.Headers[FromHeaderFull].ClassName,
                'From class');
    CheckEquals('Case',
                (Self.Request.Headers[FromHeaderFull] as TIdSipAddressHeader).DisplayName,
                'From DisplayName');
    CheckEquals('sip:case@fried.neurons.org',
                (Self.Request.Headers[FromHeaderFull] as TIdSipAddressHeader).Address.GetFullURI,
                'From Address');
    CheckEquals(';tag=1928301774',
                Self.Request.Headers[FromHeaderFull].ParamsAsString,
                'From parameters');
    CheckEquals(TIdSipMaxForwardsHeader.ClassName,
                Self.Request.Headers[MaxForwardsHeader].ClassName,
                'Max-Forwards class');
    CheckEquals(70,
                (Self.Request.Headers[MaxForwardsHeader] as TIdSipMaxForwardsHeader).NumericValue,
                'Max-Forwards');
    CheckEquals(TIdSipAddressHeader.ClassName,
                Self.Request.Headers[ToHeaderFull].ClassName,
                'To class');
    CheckEquals('Wintermute',
                (Self.Request.Headers[ToHeaderFull] as TIdSipAddressHeader).DisplayName,
                ' DisplayName');
    CheckEquals('sip:wintermute@tessier-ashpool.co.lu',
                (Self.Request.Headers[ToHeaderFull] as TIdSipAddressHeader).Address.GetFullURI,
                'To Address');
    CheckEquals(TIdSipViaHeader.ClassName,
                Self.Request.Headers[ViaHeaderFull].ClassName,
                'Via class');
    CheckEquals('gw1.leo-ix.org',
                (Self.Request.Headers[ViaHeaderFull] as TIdSipViaHeader).Host,
                'Via Host');
    CheckEquals(5060,
                (Self.Request.Headers[ViaHeaderFull] as TIdSipViaHeader).Port,
                'Via Port');
    CheckEquals('SIP/2.0',
                (Self.Request.Headers[ViaHeaderFull] as TIdSipViaHeader).SipVersion,
                'Via SipVersion');
    Check       (sttTCP =
                (Self.Request.Headers[ViaHeaderFull] as TIdSipViaHeader).Transport,
                'Via Transport');
    CheckEquals(';branch=z9hG4bK776asdhds',
                (Self.Request.Headers[ViaHeaderFull] as TIdSipViaHeader).ParamsAsString,
                'Via Parameters');
    CheckEquals('I am not defined in RFC 3261',
                Self.Request.Headers['X-Not-A-Header'].Value,
                'X-Not-A-Header');
    CheckEquals(13, Self.Request.Headers.Count, 'Headers.Count');
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseReallyLongViaHeader;
const
  IterCount = 49;
var
  Msg: TIdSipMessage;
  Str: TStringStream;
  S:   String;
  I, J: Integer;
begin
  S := 'Via: ';
  for I := 0 to IterCount do
    for J := 0 to IterCount do
      S := S + 'SIP/2.0/UDP 127.0.' + IntToStr(I) + '.' + IntToStr(J) + ',';
  Delete(S, Length(S), 1);

  Str := TStringStream.Create('INVITE sip:wintermute@tessier-ashpool.co.lu SIP/2.0'#13#10
               + 'Via: SIP/2.0/TCP gw1.leo-ix.org;branch=z9hG4bK776asdhds'#13#10
               + 'Max-Forwards: 70'#13#10
               + 'To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>'#13#10
               + 'From: Case <sip:case@fried.neurons.org>;tag=1928301774'#13#10
               + 'Call-ID: a84b4c76e66710@gw1.leo-ix.org'#13#10
               + 'CSeq: 314159 INVITE'#13#10
               + 'Contact: sip:wintermute@tessier-ashpool.co.lu'#13#10
               + 'Content-Type: text/plain'#13#10
               + 'Content-Length: 29'#13#10
               + S + #13#10
               + #13#10
               + 'I am a message. Hear me roar!');
  try
    Self.P.Source := Str;

    Msg := Self.P.ParseAndMakeMessage;
    try
      Self.CheckEquals((IterCount+1)*(IterCount+1) + 1, Msg.Path.Length, 'Length');
    finally
      Msg.Free;
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequest;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create(BasicRequest);
  try
    Self.P.Source := Str;

    Self.P.ParseRequest(Request);
    Self.CheckBasicRequest(Request);
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequestBadCSeq;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create(StringReplace(BasicRequest,
                                            'CSeq: 314159 INVITE',
                                            'CSeq: 314159 REGISTER',
                                            []));
  try
    Self.P.Source := Str;

    try
      Self.P.ParseRequest(Request);
      Fail('Failed to bail out');
    except
      on E: EBadRequest do
        CheckEquals(CSeqMethodMismatch,
                    E.Message,
                    'Unexpected exception');
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequestEmptyString;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create('');
  try
    Self.P.Source := Str;

    try
      Self.P.ParseRequest(Request);
      Fail('Failed to bail out on parsing an empty string');
    except
      on EBadRequest do;
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequestFoldedHeader;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create('INVITE sip:wintermute@tessier-ashpool.co.lu SIP/2.0'#13#10
                            + 'Via: SIP/2.0/TCP gw1.leo-ix.org;branch=z9hG4bK776asdhds'#13#10
                            + 'Call-ID: a84b4c76e66710@gw1.leo-ix.org'#13#10
                            + 'Max-Forwards: 70'#13#10
                            + 'From: Case'#13#10
                            + ' <sip:case@fried.neurons.org>'#13#10
                            + #9';tag=1928301774'#13#10
                            + 'To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>'#13#10
                            + 'CSeq: 8'#13#10
                            + '  INVITE'#13#10
                            + #13#10);
  try
    Self.P.Source := Str;
    Self.P.ParseRequest(Request);
    CheckEquals('From: Case <sip:case@fried.neurons.org>;tag=1928301774',
                Request.Headers['from'].AsString,
                'From header');
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequestMalformedMaxForwards;
var
  Str: TStringStream;
begin
  // Section 20.22 states that 0 <= Max-Forwards <= 255
  Str := TStringStream.Create('INVITE sip:wintermute@tessier-ashpool.co.lu SIP/2.0'#13#10
                            + 'Max-Forwards: 666'#13#10
                            + #13#10);
  try
    Self.P.Source := Str;

    try
      Self.P.ParseRequest(Request);
      Fail('Failed to bail out on a Bad Request');
    except
      on E: EBadRequest do
        CheckEquals(Format(MalformedToken, [MaxForwardsHeader,
                                            'Max-Forwards: 666']),
                    E.Message,
                    'Exception type');
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequestMalformedMethod;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create('Bad"method sip:wintermute@tessier-ashpool.co.lu SIP/2.0'#13#10
                          + 'From: Case'#13#10
                          + ' <sip:case@fried.neurons.org>'#13#10
                          + #9';tag=1928301774'#13#10
                          + 'To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>'#13#10
                          + #13#10);
  try
    Self.P.Source := Str;

    try
      Self.P.ParseRequest(Request);
      Fail('Failed to bail out on a Bad Request');
    except
      on E: EBadRequest do
        CheckEquals(Format(MalformedToken, ['Method', 'Bad"method']), E.Message, 'Exception type');
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequestMalformedRequestLine;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create('INVITE  sip:wintermute@tessier-ashpool.co.lu SIP/2.0'#13#10);
  try
    Self.P.Source := Str;
    try
      Self.P.ParseRequest(Request);
      Fail('Malformed start line (too many spaces between Method and Request-URI) parsed without error');
    except
      on E: EBadRequest do
        CheckEquals(RequestUriNoSpaces, E.Message, 'Too many spaces');
    end;
  finally
    Str.Free;
  end;

  Str := TStringStream.Create('INVITEsip:wintermute@tessier-ashpool.co.luSIP/2.0'#13#10);
  try
    Self.P.Source := Str;
    try
      Self.P.ParseRequest(Request);
      Fail('Malformed start line (no spaces between Method and Request-URI) parsed without error');
    except
      on E: EBadRequest do
        CheckEquals(Format(MalformedToken, ['Request-Line', 'INVITEsip:wintermute@tessier-ashpool.co.luSIP/2.0']),
                    E.Message,
                    'Missing spaces');
    end;
  finally
    Str.Free;
  end;

  Str := TStringStream.Create('sip:wintermute@tessier-ashpool.co.lu SIP/2.0');
  try
    Self.P.Source := Str;
    try
      Self.P.ParseRequest(Request);
      Fail('Malformed start line (no Method) parsed without error');
    except
      on E: EBadRequest do
        CheckEquals(Format(MalformedToken, ['Request-Line', 'sip:wintermute@tessier-ashpool.co.lu SIP/2.0']),
                    E.Message,
                    'Missing Method');
    end;
  finally
    Str.Free;
  end;

  Str := TStringStream.Create('INVITE'#13#10);
  try
    Self.P.Source := Str;
    try
      Self.P.ParseRequest(Request);
      Fail('Malformed start line (no Request-URI, no SIP-Version) parsed without error');
    except
      on E: EBadRequest do
        CheckEquals(Format(MalformedToken, ['Request-Line', 'INVITE']),
                    E.Message,
                    'Missing Request & SIP Version');
    end;
  finally
    Str.Free;
  end;

  Str := TStringStream.Create('INVITE sip:wintermute@tessier-ashpool.co.lu SIP/;2.0'#13#10);
  try
    Self.P.Source := Str;
    try
      Self.P.ParseRequest(Request);
      Fail('Malformed start line (malformed SIP-Version) parsed without error');
    except
      on E: EBadRequest do
        CheckEquals(Format(InvalidSipVersion, ['SIP/;2.0']), E.Message, 'Malformed SIP-Version');
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequestMessageBodyLongerThanContentLength;
var
  Leftovers: array[0..99] of Char;
  Str:       TStringStream;
begin
  Str := TStringStream.Create(StringReplace(BasicRequest,
                                            'Content-Length: 29',
                                            'Content-Length: 4',
                                            []));
  try
    Self.P.Source := Str;

    Self.P.ParseRequest(Request);
    CheckEquals(4,  Request.ContentLength, 'ContentLength');
    CheckEquals('', Request.Body,          'Body');

    CheckEquals(Length('I am a message. Hear me roar!'),
                Str.Read(LeftOvers, Length(Leftovers)),
                'Read unexpected number of bytes from the stream');
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequestMissingCallID;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create('INVITE sip:wintermute@tessier-ashpool.co.lu SIP/2.0'#13#10
                            + 'Via: SIP/2.0/TCP gw1.leo-ix.org;branch=z9hG4bK776asdhds'#13#10
                            + 'Max-Forwards: 70'#13#10
                            + 'To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>'#13#10
                            + 'From: Case <sip:case@fried.neurons.org>;tag=1928301774'#13#10
                            + 'CSeq: 314159 INVITE'#13#10
                            + 'Contact: sip:wintermute@tessier-ashpool.co.lu'#13#10
                            + 'Content-Type: text/plain'#13#10
                            + 'Content-Length: 29'#13#10
                            + #13#10
                            + 'I am a message. Hear me roar!');
  try
    Self.P.Source := Str;
    try
      Self.P.ParseRequest(Self.Request);
      Fail('Failed to bail out');
    except
      on E: EBadRequest do
        CheckEquals(MissingCallID,
                    E.Message,
                    'Unexpected exception');
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequestMissingCSeq;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create('INVITE sip:wintermute@tessier-ashpool.co.lu SIP/2.0'#13#10
                            + 'Via: SIP/2.0/TCP gw1.leo-ix.org;branch=z9hG4bK776asdhds'#13#10
                            + 'Max-Forwards: 70'#13#10
                            + 'To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>'#13#10
                            + 'From: Case <sip:case@fried.neurons.org>;tag=1928301774'#13#10
                            + 'Call-ID: a84b4c76e66710@gw1.leo-ix.org'#13#10
                            + 'Contact: sip:wintermute@tessier-ashpool.co.lu'#13#10
                            + 'Content-Type: text/plain'#13#10
                            + 'Content-Length: 29'#13#10
                            + #13#10
                            + 'I am a message. Hear me roar!');
  try
    Self.P.Source := Str;
    try
      Self.P.ParseRequest(Self.Request);
      Fail('Failed to bail out');
    except
      on E: EBadRequest do
        CheckEquals(MissingCSeq,
                    E.Message,
                    'Unexpected exception');
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequestMissingFrom;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create('INVITE sip:wintermute@tessier-ashpool.co.lu SIP/2.0'#13#10
                            + 'Via: SIP/2.0/TCP gw1.leo-ix.org;branch=z9hG4bK776asdhds'#13#10
                            + 'Max-Forwards: 70'#13#10
                            + 'To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>'#13#10
                            + 'Call-ID: a84b4c76e66710@gw1.leo-ix.org'#13#10
                            + 'CSeq: 314159 INVITE'#13#10
                            + 'Contact: sip:wintermute@tessier-ashpool.co.lu'#13#10
                            + 'Content-Type: text/plain'#13#10
                            + 'Content-Length: 29'#13#10
                            + #13#10
                            + 'I am a message. Hear me roar!');
  try
    Self.P.Source := Str;
    try
      Self.P.ParseRequest(Self.Request);
      Fail('Failed to bail out');
    except
      on E: EBadRequest do
        CheckEquals(MissingFrom,
                    E.Message,
                    'Unexpected exception');
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequestMissingMaxForwards;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create('INVITE sip:wintermute@tessier-ashpool.co.lu SIP/2.0'#13#10
                            + 'Via: SIP/2.0/TCP gw1.leo-ix.org;branch=z9hG4bK776asdhds'#13#10
                            + 'To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>'#13#10
                            + 'From: Case <sip:case@fried.neurons.org>;tag=1928301774'#13#10
                            + 'Call-ID: a84b4c76e66710@gw1.leo-ix.org'#13#10
                            + 'CSeq: 314159 INVITE'#13#10
                            + 'Contact: sip:wintermute@tessier-ashpool.co.lu'#13#10
                            + 'Content-Type: text/plain'#13#10
                            + 'Content-Length: 29'#13#10
                            + #13#10
                            + 'I am a message. Hear me roar!');
  try
    Self.P.Source := Str;
    try
      Self.P.ParseRequest(Self.Request);
      Fail('Failed to bail out');
    except
      on E: EBadRequest do
        CheckEquals(MissingMaxForwards,
                    E.Message,
                    'Unexpected exception');
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequestMissingTo;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create('INVITE sip:wintermute@tessier-ashpool.co.lu SIP/2.0'#13#10
                            + 'Via: SIP/2.0/TCP gw1.leo-ix.org;branch=z9hG4bK776asdhds'#13#10
                            + 'Max-Forwards: 70'#13#10
                            + 'From: Case <sip:case@fried.neurons.org>;tag=1928301774'#13#10
                            + 'Call-ID: a84b4c76e66710@gw1.leo-ix.org'#13#10
                            + 'CSeq: 314159 INVITE'#13#10
                            + 'Contact: sip:wintermute@tessier-ashpool.co.lu'#13#10
                            + 'Content-Type: text/plain'#13#10
                            + 'Content-Length: 29'#13#10
                            + #13#10
                            + 'I am a message. Hear me roar!');
  try
    Self.P.Source := Str;
    try
      Self.P.ParseRequest(Self.Request);
      Fail('Failed to bail out');
    except
      on E: EBadRequest do
        CheckEquals(MissingTo,
                    E.Message,
                    'Unexpected exception');
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequestMissingVia;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create('INVITE sip:wintermute@tessier-ashpool.co.lu SIP/2.0'#13#10
                            + 'Max-Forwards: 70'#13#10
                            + 'To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>'#13#10
                            + 'From: Case <sip:case@fried.neurons.org>;tag=1928301774'#13#10
                            + 'Call-ID: a84b4c76e66710@gw1.leo-ix.org'#13#10
                            + 'CSeq: 314159 INVITE'#13#10
                            + 'Contact: sip:wintermute@tessier-ashpool.co.lu'#13#10
                            + 'Content-Type: text/plain'#13#10
                            + 'Content-Length: 29'#13#10
                            + #13#10
                            + 'I am a message. Hear me roar!');
  try
    Self.P.Source := Str;
    try
      Self.P.ParseRequest(Self.Request);
      Fail('Failed to bail out');
    except
      on E: EBadRequest do
        CheckEquals(MissingVia,
                    E.Message,
                    'Unexpected exception');
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequestMultipleVias;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create('INVITE sip:wintermute@tessier-ashpool.co.lu SIP/2.0'#13#10
                            + 'Via: SIP/2.0/TCP gw1.leo-ix.org:5061;branch=z9hG4bK776asdhds'#13#10
                            + 'Max-Forwards: 70'#13#10
                            + 'To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>'#13#10
                            + 'From: Case <sip:case@fried.neurons.org>;tag=1928301774'#13#10
                            + 'Call-ID: a84b4c76e66710@gw1.leo-ix.org'#13#10
                            + 'CSeq: 314159 INVITE'#13#10
                            + 'Contact: sip:wintermute@tessier-ashpool.co.lu'#13#10
                            + 'Via: SIP/3.0/TLS gw5.cust1.leo_ix.org;branch=z9hG4bK776aheh'#13#10
                            + 'Content-Type: text/plain'#13#10
                            + 'Content-Length: 4'#13#10
                            + #13#10
                            + 'I am a message. Hear me roar!');
  try
    Self.P.Source := Str;
    Self.P.ParseRequest(Request);

    CheckEquals(2,                       Request.Path.Length,                   'Path.Length');
    Check      (Request.Path.FirstHop <> Request.Path.LastHop,                  'Sanity check on Path');
    CheckEquals('Via',                   Request.Path.LastHop.Name,             'LastHop.Name');
    CheckEquals('SIP/2.0',               Request.Path.LastHop.SipVersion,       'LastHop.SipVersion');
    Check      (sttTCP =                 Request.Path.LastHop.Transport,        'LastHop.Transport');
    CheckEquals('gw1.leo-ix.org',        Request.Path.LastHop.Host,             'LastHop.Host');
    CheckEquals(5061,                    Request.Path.LastHop.Port,             'LastHop.Port');
    CheckEquals('z9hG4bK776asdhds',      Request.Path.LastHop.Params['branch'], 'LastHop.Params[''branch'']');
    CheckEquals('SIP/2.0/TCP gw1.leo-ix.org:5061',
                Request.Path.LastHop.Value,
                'LastHop.Value');
    CheckEquals('Via: SIP/2.0/TCP gw1.leo-ix.org:5061;branch=z9hG4bK776asdhds',
                Request.Path.LastHop.AsString,
                'LastHop.AsString');

    CheckEquals('Via',                   Request.Path.FirstHop.Name,             'FirstHop.Name');
    CheckEquals('SIP/3.0',               Request.Path.FirstHop.SipVersion,       'FirstHop.SipVersion');
    Check      (sttTLS =                 Request.Path.FirstHop.Transport,        'FirstHop.Transport');
    CheckEquals('gw5.cust1.leo_ix.org',  Request.Path.FirstHop.Host,             'FirstHop.Host');
    CheckEquals(IdPORT_SIP_TLS,          Request.Path.FirstHop.Port,             'FirstHop.Port');
    CheckEquals('z9hG4bK776aheh',        Request.Path.FirstHop.Params['branch'], 'FirstHop.Params[''branch'']');
    CheckEquals('SIP/3.0/TLS gw5.cust1.leo_ix.org',
                Request.Path.FirstHop.Value,
                'FirstHop.Value');
    CheckEquals('Via: SIP/3.0/TLS gw5.cust1.leo_ix.org;branch=z9hG4bK776aheh',
                Request.Path.FirstHop.AsString,
                'FirstHop.AsString');
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequestRequestUriHasSpaces;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create('INVITE sip:wintermute@tessier ashpool.co.lu SIP/2.0'#13#10);
  try
    Self.P.Source := Str;
    try
      Self.P.ParseRequest(Request);
      Fail('Malformed start line (Request-URI has spaces) parsed without error');
    except
      on E: EBadRequest do
        CheckEquals(RequestUriNoSpaces,
                    E.Message,
                    '<>');
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequestRequestUriInAngleBrackets;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create('INVITE <sip:wintermute@tessier-ashpool.co.lu> SIP/2.0'#13#10);
  try
    Self.P.Source := Str;
    try
      Self.P.ParseRequest(Request);
      Fail('Malformed start line (Request-URI enclosed in angle brackets) parsed without error');
    except
      on E: EBadRequest do
        CheckEquals(RequestUriNoAngleBrackets,
                    E.Message,
                    '<>');
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequestWithLeadingCrLfs;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create(#13#10#13#10 + BasicRequest);
  try
    Self.P.Source := Str;
    Self.P.ParseRequest(Request);

    Self.CheckBasicRequest(Request);
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseRequestWithBodyAndNoContentType;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create(EmptyRequest
                            + 'Content-Length: 29'#13#10
                            + #13#10
                            + 'I am a message. Hear me roar!');
  try
    Self.P.Source := Str;

    try
      Self.P.ParseRequest(Request);
      Fail('Failed to bail out');
    except
      on E: EParser do
        CheckEquals(MissingContentType,
                    E.Message,
                    'Unexpected exception');
    end;

  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseResponse;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create(BasicResponse);
  try
    Self.P.Source := Str;

    Self.P.ParseResponse(Response);
    Self.CheckBasicResponse(Response);
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseResponseEmptyString;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create('');
  try
    Self.P.Source := Str;
    Self.P.ParseResponse(Response);

    CheckEquals(0,  Response.StatusCode, 'StatusCode');
    CheckEquals('', Response.StatusText, 'StatusText');
    CheckEquals('', Response.SipVersion, 'SipVersion');
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseResponseFoldedHeader;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create('SIP/1.0 200 OK'#13#10
                          + 'From: Case'#13#10
                          + ' <sip:case@fried.neurons.org>'#13#10
                          + #9';tag=1928301774'#13#10
                          + 'To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>'#13#10
                          + #13#10);
  try
    Self.P.Source := Str;
    Self.P.ParseResponse(Response);

    CheckEquals('SIP/1.0', Response.SipVersion, 'SipVersion');
    CheckEquals(200,       Response.StatusCode, 'StatusCode');
    CheckEquals('OK',      Response.StatusText, 'StatusTest');

//    CheckEquals(2, Response.Headers.Count, 'Header count');
    CheckEquals('From: Case <sip:case@fried.neurons.org>;tag=1928301774',
                Response.Headers['from'].AsString,
                'From header');
    CheckEquals('To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>',
                Response.Headers['to'].AsString,
                'To header');
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseResponseInvalidStatusCode;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create('SIP/1.0 Aheh OK'#13#10);
  try
    Self.P.Source := Str;
    try
      Self.P.ParseResponse(Response);
      Fail('Failed to reject a non-numeric Status-Code');
    except
      on E: EBadResponse do
        CheckEquals(Format(InvalidStatusCode, ['Aheh']),
                    E.Message,
                    '<>');
    end;
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseResponseWithLeadingCrLfs;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create(#13#10#13#10 + BasicResponse);
  try
    Self.P.Source := Str;
    Self.P.ParseResponse(Response);

    Self.CheckBasicResponse(Response);
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestParseShortFormContentLength;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create(StringReplace(BasicRequest,
                                            'Content-Length',
                                            'l',
                                            [rfReplaceAll]));
  try
    Self.P.Source := Str;
    Self.P.ParseRequest(Request);
    CheckEquals(29, Request.ContentLength, 'ContentLength');
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestTortureTest1;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create(TortureTest1);
  try
    Self.P.Source := Str;
    Self.P.ParseRequest(Request);
    
    CheckEquals('INVITE',                              Request.Method,      'Method');
    CheckEquals('SIP/2.0',                             Request.SipVersion,  'SipVersion');
    CheckEquals('sip:vivekg@chair.dnrc.bell-labs.com', Request.Request,     'Request');
    CheckEquals(6,                                     Request.MaxForwards, 'MaxForwards');
    CheckEquals('0ha0isndaksdj@10.1.1.1',              Request.CallID,      'CallID');

    CheckEquals('',
                Request.ToHeader.DisplayName,
                'ToHeader.DisplayName');
    CheckEquals('sip:vivekg@chair.dnrc.bell-labs.com',
                Request.ToHeader.Address.GetFullURI,
                'ToHeader.Address.GetFullURI');
    CheckEquals(';tag=1918181833n',
                Request.ToHeader.ParamsAsString,
                'ToHeader.ParamsAsString');

    CheckEquals('J Rosenberg \"',
                Request.From.DisplayName,
                'From.DisplayName');
    CheckEquals('sip:jdrosen@lucent.com',
                Request.From.Address.GetFullURI,
                'From.Address.GetFullURI');
    CheckEquals(';tag=98asjd8',
                Request.From.ParamsAsString,
                'From.ParamsAsString');

    CheckEquals(3, Request.Path.Length, 'Path.Length');

    CheckEquals('To: sip:vivekg@chair.dnrc.bell-labs.com;tag=1918181833n',
                Request.Headers.Items[0].AsString,
                'To header');
    CheckEquals('From: "J Rosenberg \\\"" <sip:jdrosen@lucent.com>;tag=98asjd8',
                Request.Headers.Items[1].AsString,
                'From header');
    CheckEquals('Max-Forwards: 6',
                Request.Headers.Items[2].AsString,
                'Max-Forwards header');
    CheckEquals('Call-ID: 0ha0isndaksdj@10.1.1.1',
                Request.Headers.Items[3].AsString,
                'Call-ID header');
    CheckEquals('CSeq: 8 INVITE',
                Request.Headers.Items[4].AsString,
                'CSeq header');
    CheckEquals('Via: SIP/2.0/UDP 135.180.130.133;branch=z9hG4bKkdjuw',
                Request.Headers.Items[5].AsString,
                'Via header #1');
    CheckEquals('Subject: ',
                Request.Headers.Items[6].AsString,
                'Subject header');
    CheckEquals('NewFangledHeader: newfangled value more newfangled value',
                Request.Headers.Items[7].AsString,
                'NewFangledHeader');
    CheckEquals('Content-Type: application/sdp',
                Request.Headers.Items[8].AsString,
                'Content-Type');
    CheckEquals('Via: SIP/2.0/TCP 1192.168.156.222;branch=9ikj8',
                Request.Headers.Items[9].AsString,
                'Via header #2');
    CheckEquals('Via: SIP/2.0/UDP 192.168.255.111;hidden',
                Request.Headers.Items[10].AsString,
                'Via header #3');
    CheckEquals('Contact: "Quoted string \"\"" <sip:jdrosen@bell-labs.com>;newparam=newvalue;secondparam=secondvalue;q=0.33',
                Request.Headers.Items[11].AsString,
                'Contact header #1');
    CheckEquals('Contact: tel:4443322',
                Request.Headers.Items[12].AsString,
                'Contact header #2');
//    CheckEquals(13, Request.Headers.Count, 'Header count');
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestTortureTest8;
begin
  Self.CheckTortureTest(TortureTest8, CSeqMethodMismatch);
end;

procedure TestTIdSipParser.TestTortureTest11;
begin
  Self.CheckTortureTest(TortureTest11, MissingCallID);
end;

procedure TestTIdSipParser.TestTortureTest13;
begin
  Self.CheckTortureTest(TortureTest13,
                        Format(MalformedToken, [ExpiresHeader,
                                                'Expires: Thu, 44 Dec 19999 16:00:00 EDT']));
end;

procedure TestTIdSipParser.TestTortureTest15;
begin
  Self.CheckTortureTest(TortureTest15,
                        Format(MalformedToken, [ViaHeaderFull,
                                                'Via: SIP/2.0/UDP 135.180.130.133;;,;']));
end;

procedure TestTIdSipParser.TestTortureTest19;
begin
  Self.CheckTortureTest(TortureTest19,
                        Format(MalformedToken, [ToHeaderFull,
                                                'To: "Mr. J. User <sip:j.user@company.com>']));
end;

procedure TestTIdSipParser.TestTortureTest21;
begin
  Self.CheckTortureTest(TortureTest21, RequestUriNoAngleBrackets);
end;

procedure TestTIdSipParser.TestTortureTest22;
begin
  Self.CheckTortureTest(TortureTest22, RequestUriNoSpaces);
end;

procedure TestTIdSipParser.TestTortureTest23;
begin
  Self.CheckTortureTest(TortureTest23, RequestUriNoSpaces);
end;

procedure TestTIdSipParser.TestTortureTest24;
var
  Str: TStringStream;
begin
  Str := TStringStream.Create(TortureTest24);
  try
    Self.P.Source := Str;
    Self.P.ParseRequest(Request);

    CheckEquals('sip:sip%3Auser%40example.com@company.com;other-param=summit',
                Request.Request,
                'Request-URI');
  finally
    Str.Free;
  end;
end;

procedure TestTIdSipParser.TestTortureTest35;
begin
  Self.CheckTortureTest(TortureTest35,
                        Format(MalformedToken, [ExpiresHeader,
                                                'Expires: 0 0l@company.com']));
end;

procedure TestTIdSipParser.TestTortureTest40;
begin
  Self.CheckTortureTest(TortureTest40,
                        Format(MalformedToken, [FromHeaderFull,
                                                'From:    Bell, Alexander <sip:a.g.bell@bell-tel.com>;tag=43']));
end;

//* TestTIdSipParser Private methods *******************************************

procedure TestTIdSipParser.CheckBasicMessage(const Msg: TIdSipMessage);
begin
  CheckEquals('SIP/2.0',                              Msg.SIPVersion,                   'SipVersion');
  CheckEquals(29,                                     Msg.ContentLength,                'ContentLength');
  CheckEquals('text/plain',                           Msg.ContentType,                  'ContentType');
  CheckEquals(70,                                     Msg.MaxForwards,                  'MaxForwards');
  CheckEquals('a84b4c76e66710@gw1.leo-ix.org',        Msg.CallID,                       'CallID');
  CheckEquals('Wintermute',                           Msg.ToHeader.DisplayName,         'ToHeader.DisplayName');
  CheckEquals('sip:wintermute@tessier-ashpool.co.lu', Msg.ToHeader.Address.GetFullURI,  'ToHeader.Address.GetFullURI');
  CheckEquals('',                                     Msg.ToHeader.ParamsAsString,      'Msg.ToHeader.ParamsAsString');
  CheckEquals('Case',                                 Msg.From.DisplayName,             'From.DisplayName');
  CheckEquals('sip:case@fried.neurons.org',           Msg.From.Address.GetFullURI,      'From.Address.GetFullURI');
  CheckEquals(';tag=1928301774',                      Msg.From.ParamsAsString,          'Msg.From.ParamsAsString');
  CheckEquals(314159,                                 Msg.CSeq.SequenceNo,              'Msg.CSeq.SequenceNo');
  CheckEquals('INVITE',                               Msg.CSeq.Method,                  'Msg.CSeq.Method');

  CheckEquals(TIdSipAddressHeader.ClassName,
              Msg.Headers[ContactHeaderFull].ClassName,
              'Contact header type');

  CheckEquals(1,                  Msg.Path.Length,                   'Path.Length');
  Check      (Msg.Path.FirstHop = Msg.Path.LastHop,                  'Sanity check on Path');
  CheckEquals('SIP/2.0',          Msg.Path.LastHop.SipVersion,       'LastHop.SipVersion');
  Check      (sttTCP =            Msg.Path.LastHop.Transport,        'LastHop.Transport');
  CheckEquals('gw1.leo-ix.org',   Msg.Path.LastHop.Host,             'LastHop.Host');
  CheckEquals(IdPORT_SIP,         Msg.Path.LastHop.Port,             'LastHop.Port');
  CheckEquals('z9hG4bK776asdhds', Msg.Path.LastHop.Params['branch'], 'LastHop.Params[''branch'']');

  CheckEquals('To: Wintermute <sip:wintermute@tessier-ashpool.co.lu>',  Msg.Headers['to'].AsString,           'To');
  CheckEquals('From: Case <sip:case@fried.neurons.org>;tag=1928301774', Msg.Headers['from'].AsString,         'From');
  CheckEquals('CSeq: 314159 INVITE',                                    Msg.Headers['cseq'].AsString,         'CSeq');
  CheckEquals('Contact: sip:wintermute@tessier-ashpool.co.lu',          Msg.Headers['contact'].AsString,      'Contact');
  CheckEquals('Content-Type: text/plain',                               Msg.Headers['content-type'].AsString, 'Content-Type');
  CheckEquals(9, Msg.Headers.Count, 'Header count');

  CheckEquals('', Msg.Body, 'message-body');
end;

procedure TestTIdSipParser.CheckBasicRequest(const Msg: TIdSipMessage);
begin
  CheckEquals(TIdSipRequest.Classname, Msg.ClassName, 'Class type');

  CheckEquals('INVITE',                               TIdSipRequest(Msg).Method,  'Method');
  CheckEquals('sip:wintermute@tessier-ashpool.co.lu', TIdSipRequest(Msg).Request, 'Request');

  Self.CheckBasicMessage(Msg);
end;

procedure TestTIdSipParser.CheckBasicResponse(const Msg: TIdSipMessage);
begin
  CheckEquals(TIdSipResponse.Classname, Msg.ClassName, 'Class type');

  CheckEquals(486,         TIdSipResponse(Msg).StatusCode, 'StatusCode');
  CheckEquals('Busy Here', TIdSipResponse(Msg).StatusText, 'StatusText');

  Self.CheckBasicMessage(Msg);
end;

procedure TestTIdSipParser.CheckTortureTest(const RequestStr, ExpectedExceptionMsg: String);
var
  Str: TStringStream;
begin
  Str := TStringStream.Create(RequestStr);
  try
    Self.P.Source := Str;

    try
      Self.P.ParseRequest(Request);
      Fail('Failed to bail out of a bad request');
    except
      on E: EBadRequest do
        CheckEquals(ExpectedExceptionMsg,
                    E.Message,
                    'Unexpected exception');
    end;
  finally
    Str.Free;
  end;
end;

initialization
  RegisterTest('SIP Request Parsing', Suite);
end.
