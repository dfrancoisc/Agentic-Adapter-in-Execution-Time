/// MCP functions for DTLs and routing rules.
///
/// Extending Ens.Rule.FunctionSet registers these with the DTL and Rule editors, so
/// they appear in the function picker beside Lookup() and ConvertDateTime(). An
/// interface engineer selects one from the list; nobody writes a class method call
/// by hand, and nobody writes their own MCP client.
///
/// In a DTL:
///
///   MCPLookup("SnomedMCP", "translate_icd", {OBX:5.1}, "structuredContent.display")
///
/// The first argument names a production item configured with Agentic.Adapter.MCP.
/// Its endpoint, TLS configuration and credential are read from that item, so the
/// server is configured in one place and the transformation just names it.
///
/// WHAT THIS IS NOT
///
/// It is not the adapter, and cannot be — an EnsLib.HTTP.OutboundAdapter subclass
/// cannot be instantiated outside a production, and Ens.Director offers no way to
/// invoke a business operation from arbitrary code. So a call made here:
///
///   - is NOT a production message. It does not appear in the Visual Trace or the
///     Message Viewer, and nothing records what was asked six months later
///   - has NO retry, failover or alerting. A slow server blocks the transformation
///   - supports TLS, basic and bearer authentication, but NOT OAuth 2, whose token
///     acquisition and refresh belong to the adapter
///
/// Use it for a fast, simple lookup where the audit trail does not matter. Route
/// through a business process and Agentic.Adapter.Operation when it does — which in
/// a clinical interface is most of the time.
Class Agentic.Adapter.Functions Extends Ens.Rule.FunctionSet
{

/// Call an MCP tool and return one value from the result.
///
///   pItem    production item configured with Agentic.Adapter.MCP, or a plain URL
///   pTool    tool to invoke
///   pValue   value passed as the tool's "code" argument
///   pPath    dotted path into the result, e.g. structuredContent.display
///
/// Returns an empty string when the value is empty, the server cannot be reached,
/// or the tool reports isError. It never raises: an exception escaping a DTL fails
/// the whole transformation, and an unrecognised code is a data quality finding
/// rather than a broken interface. Failures are written to the Event Log.
ClassMethod MCPLookup(pItem As %String, pTool As %String, pValue As %String, pPath As %String = "structuredContent.display") As %String
{
    if pValue = "" quit ""
    set tArgs = {}
    set tArgs.code = pValue
    quit ..MCPCall(pItem, pTool, tArgs.%ToJSON(), pPath)
}

/// Call an MCP tool with arbitrary arguments.
/// Same contract as MCPLookup, but you supply the whole arguments object as JSON.
ClassMethod MCPCall(pItem As %String, pTool As %String, pArgumentsJSON As %String = "{}", pPath As %String = "") As %String
{
    set tResult = ""
    try {
        set tEndpoint = ..endpoint(pItem)
        if tEndpoint = "" {
            do ..log("no endpoint configured for '"_pItem_"'")
            quit
        }

        ; handshake, then the call, on one connection
        set tSession = ""
        set tRaw = ..post(tEndpoint, ##class(Agentic.Adapter.Protocol).Envelope(1, "initialize", ##class(Agentic.Adapter.Protocol).InitParams()), .tSession)
        set tRaw = ..post(tEndpoint, ##class(Agentic.Adapter.Protocol).Envelope(2, "tools/call", ##class(Agentic.Adapter.Protocol).CallParams(pTool, pArgumentsJSON)), .tSession)

        set tVerdict = ##class(%DynamicAbstractObject).%FromJSON(##class(Agentic.Adapter.Protocol).Decode(tRaw))
        if 'tVerdict.ok {
            do ..log("MCP call to '"_pItem_"' failed: "_tVerdict.error)
            quit
        }
        if $isobject(tVerdict.result) && tVerdict.result.%IsDefined("isError") && tVerdict.result.isError {
            do ..log("tool '"_pTool_"' reported isError")
            quit
        }
        set tResult = ##class(Agentic.Adapter.Protocol).Extract(tVerdict.result.%ToJSON(), pPath)
    }
    catch ex {
        do ..log("MCP call raised: "_ex.DisplayString())
    }
    quit tResult
}

/// Endpoint as scheme|host|port|path|sslconfig|credentials, from a production item
/// or from a URL given directly.
ClassMethod endpoint(pItem As %String) As %String [ Internal ]
{
    if ($extract(pItem, 1, 7) = "http://") || ($extract(pItem, 1, 8) = "https://") {
        quit ..splitURL(pItem)_"||"
    }

    set tURL = ##class(Ens.Director).GetAdapterSettingValue(pItem, "ServerURL")
    set tSSL = ##class(Ens.Director).GetAdapterSettingValue(pItem, "SSLConfig")
    set tCred = ##class(Ens.Director).GetAdapterSettingValue(pItem, "Credentials")
    set tAuth = ##class(Ens.Director).GetAdapterSettingValue(pItem, "AuthType")

    if tURL '= "" {
        set tParts = ..splitURL(tURL)
    } else {
        set tHost = ##class(Ens.Director).GetAdapterSettingValue(pItem, "HTTPServer")
        if tHost = "" quit ""
        set tPort = ##class(Ens.Director).GetAdapterSettingValue(pItem, "HTTPPort")
        set tPath = ##class(Ens.Director).GetAdapterSettingValue(pItem, "URL")
        set tScheme = $select(tSSL '= "": "https", 1: "http")
        set tParts = tScheme_"|"_tHost_"|"_$select(tPort '= "": tPort, 1: 80)_"|"_$select(tPath '= "": tPath, 1: "/")
    }
    quit tParts_"|"_tSSL_"|"_$select(tAuth = "bearer": tCred, tAuth = "basic": tCred, 1: "")
}

ClassMethod splitURL(pURL As %String) As %String [ Internal, Language = python ]
{
    from urllib.parse import urlparse
    u = urlparse((pURL or "").strip())
    if not u.scheme or not u.hostname:
        return ""
    port = u.port or (443 if u.scheme == "https" else 80)
    path = u.path or "/"
    if u.query:
        path = path + "?" + u.query
    return "%s|%s|%s|%s" % (u.scheme, u.hostname, port, path)
}

/// POST one JSON-RPC body. Uses %Net.HttpRequest so the item's TLS configuration
/// and credential are honoured — the part a hand-rolled DTL helper always skips.
ClassMethod post(pEndpoint As %String, pBody As %String, ByRef pSession As %String) As %String [ Internal ]
{
    set tScheme = $piece(pEndpoint, "|", 1)
    set tHost = $piece(pEndpoint, "|", 2)
    set tPort = $piece(pEndpoint, "|", 3)
    set tPath = $piece(pEndpoint, "|", 4)
    set tSSL = $piece(pEndpoint, "|", 5)
    set tCred = $piece(pEndpoint, "|", 6)

    set tReq = ##class(%Net.HttpRequest).%New()
    set tReq.Server = tHost
    set tReq.Port = tPort
    set tReq.ContentType = "application/json"
    if tScheme = "https" {
        set tReq.Https = 1
        set tReq.SSLConfiguration = $select(tSSL '= "": tSSL, 1: "default")
    }
    do tReq.SetHeader("Accept", "application/json, text/event-stream")
    if $get(pSession) '= "" { do tReq.SetHeader("Mcp-Session-Id", pSession) }

    if tCred '= "" {
        set tSC = ##class(Ens.Config.Credentials).GetCredentialsObj(.tCredObj, $classname(), "Ens.Config.Credentials", tCred)
        if $$$ISOK(tSC), $isobject(tCredObj) {
            do tReq.SetHeader("Authorization", "Bearer "_tCredObj.Password)
        }
    }

    do tReq.EntityBody.Write(pBody)
    set tSC = tReq.Post(tPath)
    if $$$ISERR(tSC) quit ""

    set tResp = tReq.HttpResponse
    if '$isobject(tResp) quit ""
    set tSid = tResp.GetHeader("MCP-SESSION-ID")
    if tSid '= "" { set pSession = tSid }

    set tBody = ""
    if $isobject(tResp.Data) {
        while 'tResp.Data.AtEnd { set tBody = tBody_tResp.Data.Read(32000) }
    }
    quit tBody
}

/// Failures go to the Event Log, never to the caller as an exception.
ClassMethod log(pText As %String) [ Internal ]
{
    do ##class(Ens.Util.Log).LogWarning("Agentic.Adapter.Functions", "MCPCall", pText)
}

}
