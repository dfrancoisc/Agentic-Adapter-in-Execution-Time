/// Call an MCP tool from inside a DTL or a routing rule.
///
/// READ THIS BEFORE USING IT.
///
/// This works — it is verified, and the example DTL alongside it produces a real
/// answer from a real server during the transformation. But it does NOT go through
/// Agentic.Adapter.MCP, and that costs three things the adapter exists to provide:
///
///   1. SECURITY. The adapter inherits SSLConfig, Credentials, OAuth 2 and proxy
///      handling from EnsLib.HTTP.OutboundAdapter. This does not. It reads the
///      endpoint from the item's settings and makes the call itself, so an https
///      endpoint needs a TLS configuration applied here, and OAuth 2 is not
///      available at all.
///   2. TRACING. There is no production message for the call. It will not appear in
///      the Visual Trace or the Message Viewer. Six months later there is no record
///      of what the server was asked or what it answered.
///   3. RETRY AND FAILOVER. No RetriesToFailover, no queue, no alerting. A slow
///      server blocks the transformation; a failing one fails it.
///
/// Use it when the call is simple, unauthenticated or bearer-authenticated, fast,
/// and the audit trail does not matter. Use a business process calling the MCP
/// operation when any of those are untrue — which in a clinical interface is most
/// of the time.
///
/// The reason this cannot simply borrow the adapter: an EnsLib.HTTP.OutboundAdapter
/// subclass cannot be instantiated outside a production (it fails inside
/// SendFormDataArray with an INVALID OREF), and Ens.Director exposes no API to
/// invoke a business operation from arbitrary code. Configuration can be read from
/// a running item by name; the adapter itself cannot be reached.
Class Demo.MCPFunctions Extends Ens.Rule.FunctionSet
{

/// Call a tool on the MCP server configured on pItem, and return one value from
/// the result.
///
///   pItem   config item name of the Agentic.Adapter.Operation host
///   pTool   tool to invoke
///   pValue  the value passed as the tool's "code" argument
///   pPath   dotted path into the result, e.g. structuredContent.display
///
/// Returns an empty string on any failure. It does not raise, because an exception
/// escaping a DTL fails the whole transformation, and a code the server does not
/// recognise is a data quality finding rather than a broken interface.
ClassMethod MCPCall(pItem As %String, pTool As %String, pValue As %String, pPath As %String = "structuredContent.display") As %String [ Language = python ]
{
    import iris, json, urllib.request

    if not pValue:
        return ""

    director = iris.cls("Ens.Director")
    url = director.GetAdapterSettingValue(pItem, "ServerURL")
    if not url:
        host = director.GetAdapterSettingValue(pItem, "HTTPServer")
        port = director.GetAdapterSettingValue(pItem, "HTTPPort") or "80"
        path = director.GetAdapterSettingValue(pItem, "URL") or "/"
        if not host:
            return ""
        url = "http://%s:%s%s" % (host, port, path)

    def rpc(method, params, session=None):
        payload = json.dumps({"jsonrpc": "2.0", "id": 1,
                              "method": method, "params": params}).encode()
        headers = {"Content-Type": "application/json",
                   "Accept": "application/json, text/event-stream"}
        if session:
            headers["Mcp-Session-Id"] = session
        request = urllib.request.Request(url, data=payload, headers=headers)
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.headers.get("Mcp-Session-Id"), response.read().decode()

    try:
        session, _ = rpc("initialize", {"protocolVersion": "2025-06-18",
                                        "capabilities": {},
                                        "clientInfo": {"name": "iris-dtl", "version": "1.0"}})
        _, raw = rpc("tools/call", {"name": pTool,
                                    "arguments": {"code": pValue}}, session)

        # a server may answer with an SSE stream even when asked for JSON
        text = raw.lstrip()
        if text.startswith("event:") or text.startswith("data:"):
            text = "\n".join(line[5:].strip() for line in text.splitlines()
                             if line.startswith("data:"))

        node = json.loads(text).get("result", {})
        if node.get("isError"):
            return ""
        for part in (pPath or "").split("."):
            if not part:
                continue
            if isinstance(node, dict):
                node = node.get(part)
            elif isinstance(node, list):
                node = node[int(part)]
            else:
                return ""
            if node is None:
                return ""
        return node if isinstance(node, str) else json.dumps(node)
    except Exception:
        return ""
}

}
