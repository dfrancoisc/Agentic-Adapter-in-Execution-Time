/// Generic outbound adapter for calling an MCP (Model Context Protocol) server
/// from an interoperability production.
///
/// Configure it on any business operation, in any production. It knows about MCP
/// and nothing else — no message formats, no domain concepts. Arguments go in as
/// JSON, a tool result comes back as JSON.
///
/// Connection, TLS, credentials, OAuth 2 and proxy settings are inherited from
/// EnsLib.HTTP.OutboundAdapter. Every request goes through that machinery, so the
/// security configuration is always honoured.
///
/// The MCP protocol work is Embedded Python. The only ObjectScript logic is Send(),
/// which must be ObjectScript because SendFormDataArray() uses Output parameters.
Class Agentic.Adapter.MCP Extends EnsLib.HTTP.OutboundAdapter
{

Parameter SETTINGS = "ProtocolVersion:MCP Connection,ClientName:MCP Connection,AuthType:MCP Connection,HeaderName:MCP Connection,ToolName:MCP Tools,AllowedTools:MCP Tools,ResultPath:MCP Tools,OnErrorAction:MCP Behavior,DefaultValue:MCP Behavior";

/// MCP protocol version to negotiate. Blank sends the latest this adapter supports.
Property ProtocolVersion As %String [ InitialExpression = "2025-06-18" ];

/// Client name reported to the server during the handshake.
Property ClientName As %String [ InitialExpression = "IRIS-MCP-Adapter" ];

/// How to present credentials: none, basic, bearer, header, oauth2.
/// basic and oauth2 are handled by the inherited HTTP machinery.
Property AuthType As %String(VALUELIST = ",none,basic,bearer,header,oauth2") [ InitialExpression = "none" ];

/// Header name when AuthType is header, e.g. X-API-Key.
Property HeaderName As %String [ InitialExpression = "X-API-Key" ];

/// Default tool to invoke when the caller does not name one.
Property ToolName As %String;

/// Regular expression allow-list of invocable tool names.
/// Blank means only ToolName may be called. This is a security control:
/// an MCP server may expose destructive tools that this item must not use.
Property AllowedTools As %String(MAXLEN = 500);

/// Dotted path into the tool result, so callers receive a scalar instead of an
/// MCP content-block envelope. Blank returns the whole result object.
/// Example: result.structuredContent.code
Property ResultPath As %String(MAXLEN = 200);

/// What to do when the call fails: fail, passthrough, or default.
Property OnErrorAction As %String(VALUELIST = ",fail,passthrough,default") [ InitialExpression = "fail" ];

/// Value returned when OnErrorAction is default.
Property DefaultValue As %String(MAXLEN = 500);

/// Negotiated MCP session id, held for the life of the host job.
Property SessionId As %String [ Internal ];

/// Last HTTP status code seen, for diagnostics.
Property LastHttpCode As %String [ Internal ];

/// Set when the last CallTool returned an MCP-level isError result.
/// An isError result is a business failure, not a transport failure.
Property LastIsError As %Boolean [ Internal ];

/// Last error text, transport or protocol.
Property LastError As %String(MAXLEN = 2000) [ Internal ];

/// Monotonic JSON-RPC request id.
Property RequestId As %Integer [ InitialExpression = 0, Internal ];

/// Reset per-job protocol state when the host starts.
Method OnInit() As %Status
{
    set ..SessionId = ""
    set ..RequestId = 0
    set ..LastError = ""
    quit $$$OK
}

/// The only method that touches the wire.
/// Must be ObjectScript: SendFormDataArray() uses Output parameters, which cannot
/// appear in a Language=python signature. Returns the response body; diagnostics
/// land in LastHttpCode and LastError so Python can read them off the instance.
Method Send(pBody As %String) As %String [ Internal ]
{
    set ..LastHttpCode = "", ..LastError = ""
    set tBody = ""
    try {
        set tReq = ##class(%Net.HttpRequest).%New()
        set tReq.ContentType = "application/json"
        do tReq.SetHeader("Accept", "application/json, text/event-stream")
        if ..SessionId '= "" { do tReq.SetHeader("Mcp-Session-Id", ..SessionId) }
        if ..ProtocolVersion '= "" { do tReq.SetHeader("MCP-Protocol-Version", ..ProtocolVersion) }
        if (..AuthType = "bearer") || (..AuthType = "header") {
            set tSecret = ..secret()
            if tSecret '= "" {
                if ..AuthType = "bearer" {
                    do tReq.SetHeader("Authorization", "Bearer "_tSecret)
                } else {
                    do tReq.SetHeader(..HeaderName, tSecret)
                }
            }
        }
        do tReq.EntityBody.Write(pBody)
        set tSC = ..SendFormDataArray(.tResp, "POST", tReq)
        if $$$ISERR(tSC) {
            set ..LastError = $system.Status.GetErrorText(tSC)
            quit
        }
        if '$isobject(tResp) {
            set ..LastError = "no HTTP response"
            quit
        }
        set ..LastHttpCode = tResp.StatusCode
        set tSid = tResp.GetHeader("MCP-SESSION-ID")
        if tSid '= "" { set ..SessionId = tSid }
        if $isobject(tResp.Data) {
            while 'tResp.Data.AtEnd { set tBody = tBody_tResp.Data.Read(32000) }
        }
    }
    catch ex {
        set ..LastError = ex.DisplayString()
    }
    quit tBody
}

/// Resolve the configured credential's password, used as a bearer token or API key.
/// Never logged, never a setting value.
Method secret() As %String [ Internal ]
{
    if ..Credentials = "" quit ""
    set tSC = ##class(Ens.Config.Credentials).GetCredentialsObj(.tCred, $classname(), "Ens.Config.Credentials", ..Credentials)
    if $$$ISERR(tSC) || '$isobject(tCred) quit ""
    quit tCred.Password
}

/// Handshake only. Drives a health check and confirms configuration.
Method TestConnection() As %Status
{
    set tJSON = ..Handshake()
    if ..LastError '= "" quit $$$ERROR($$$GeneralError, "MCP handshake failed: "_..LastError)
    quit $$$OK
}

/// Perform initialize + notifications/initialized. Returns the server info as JSON.
Method Handshake() As %String [ Language = python ]
{
    import json
    self.SessionId = ""
    params = {
        "protocolVersion": self.ProtocolVersion or "2025-06-18",
        "capabilities": {},
        "clientInfo": {"name": self.ClientName or "IRIS-MCP-Adapter", "version": "1.0.0"},
    }
    resp = self.rpc("initialize", params)
    if resp is None:
        return ""
    # the initialized notification carries no id and expects no result
    self.rpc("notifications/initialized", {}, notify=True)
    return json.dumps(resp)
}

/// The server's full tool catalog as a JSON array, each entry annotated with
/// "permitted" according to AllowedTools.
///
/// Everything the server offers is returned, not just the permitted subset. This
/// is a discovery call: an interface author needs to see what exists in order to
/// decide what to allow. Filtering the catalog here would make it impossible to
/// find out what you are missing. Enforcement happens at CallTool, which is where
/// it matters.
Method ListTools() As %String [ Language = python ]
{
    import json
    if not self.SessionId:
        self.Handshake()
    tools, cursor = [], None
    while True:
        params = {"cursor": cursor} if cursor else {}
        resp = self.rpc("tools/list", params)
        if resp is None:
            return json.dumps([])
        tools.extend(resp.get("tools", []))
        cursor = resp.get("nextCursor")
        if not cursor:
            break
    for t in tools:
        t["permitted"] = bool(self.permitted(t.get("name", "")))
    return json.dumps(tools)
}

/// Return one tool's input schema as JSON, or an empty string if not permitted.
Method DescribeTool(tool As %String) As %String [ Language = python ]
{
    import json
    for t in json.loads(self.ListTools()):
        if t.get("name") == tool:
            return json.dumps(t)
    return ""
}

/// Invoke a tool. Pass an empty tool name to use the configured ToolName.
/// argsJSON is the tool's arguments object. path overrides ResultPath for this call.
///
/// Returns the extracted result. On an MCP isError result LastIsError is set;
/// on a transport or protocol failure OnErrorAction decides what comes back.
Method CallTool(tool As %String = "", argsJSON As %String = "", path As %String = "") As %String [ Language = python ]
{
    import json

    self.LastIsError = 0
    name = tool or self.ToolName
    if not name:
        return self.onError("no tool named and no ToolName configured")
    if not self.permitted(name):
        return self.onError("tool not permitted by AllowedTools: %s" % name)

    try:
        args = json.loads(argsJSON) if argsJSON else {}
    except ValueError as e:
        return self.onError("arguments are not valid JSON: %s" % e)

    if not self.SessionId:
        self.Handshake()

    resp = self.rpc("tools/call", {"name": name, "arguments": args})
    if resp is None:
        return self.onError(self.LastError or "no result")

    if resp.get("isError"):
        # A tool that ran and reported failure. Distinct from a transport failure:
        # surfaced to the caller rather than routed through OnErrorAction.
        self.LastIsError = 1
        return json.dumps(resp)

    return self.extract(resp, path or self.ResultPath)
}

/// Send one JSON-RPC message and return its result object, or None.
Method rpc(method As %String, params, notify As %Boolean = 0) [ Internal, Language = python ]
{
    import json
    env = {"jsonrpc": "2.0", "method": method, "params": params or {}}
    if not notify:
        self.RequestId = int(self.RequestId or 0) + 1
        env["id"] = int(self.RequestId)

    raw = self.Send(json.dumps(env))

    if notify:
        return {}
    if self.LastError:
        return None
    if not raw:
        self.LastError = "empty response (HTTP %s)" % self.LastHttpCode
        return None

    raw = self.unwrapSSE(raw)

    try:
        msg = json.loads(raw)
    except ValueError as e:
        self.LastError = "response is not JSON: %s" % e
        return None
    if "error" in msg:
        err = msg["error"] or {}
        self.LastError = "MCP error %s: %s" % (err.get("code"), err.get("message"))
        return None
    return msg.get("result", {})
}

/// Streamable HTTP allows a server to answer either with plain JSON or with an SSE
/// stream, and real servers pick SSE even when the request asks for JSON. Pull the
/// JSON-RPC payload out of the data lines; pass anything else through untouched.
Method unwrapSSE(raw As %String) As %String [ Internal, Language = python ]
{
    text = (raw or "").lstrip()
    if not text.startswith("event:") and not text.startswith("data:"):
        return raw
    payload = []
    for line in text.splitlines():
        if line.startswith("data:"):
            payload.append(line[5:].strip())
    return "\n".join(payload) if payload else raw
}

/// Is this tool name allowed by configuration?
Method permitted(name As %String) As %Boolean [ Internal, Language = python ]
{
    import re
    allowed = self.AllowedTools or ""
    if not allowed:
        return 1 if (self.ToolName and name == self.ToolName) else 0
    try:
        return 1 if re.search(allowed, name) else 0
    except re.error:
        return 0
}

/// Pull a dotted path out of a result object. Blank path returns the whole object.
Method extract(node, path As %String) [ Internal, Language = python ]
{
    import json
    if not path:
        return json.dumps(node)
    for part in path.split("."):
        if part == "result":
            continue
        if isinstance(node, list):
            try:
                node = node[int(part)]
            except (ValueError, IndexError):
                return ""
        elif isinstance(node, dict):
            node = node.get(part)
        else:
            return ""
        if node is None:
            return ""
    return node if isinstance(node, str) else json.dumps(node)
}

/// Apply OnErrorAction to a failure.
Method onError(msg As %String) [ Internal, Language = python ]
{
    self.LastError = msg
    action = self.OnErrorAction or "fail"
    if action == "default":
        return self.DefaultValue or ""
    if action == "passthrough":
        return ""
    raise Exception("MCP call failed: %s" % msg)
}

}
