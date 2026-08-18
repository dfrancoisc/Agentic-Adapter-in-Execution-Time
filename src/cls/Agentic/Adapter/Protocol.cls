/// The MCP wire protocol, with no transport.
///
/// Exists so there is exactly one implementation of the protocol in this module.
/// Two things need to speak MCP and they cannot share a transport:
///
///   Agentic.Adapter.MCP        goes through the inherited HTTP machinery, so it
///                              gets TLS, credentials, OAuth 2 and proxy handling
///   Agentic.Adapter.Functions  called from a DTL, where no adapter instance exists
///
/// Everything above the socket — envelope construction, SSE unwrapping, JSON-RPC
/// error handling, result-path extraction — lives here and is used by both. Without
/// this, the two drift, and the first divergence is always the one nobody notices.
///
/// Part of: Shared by both levels. See README.
Class Agentic.Adapter.Protocol [ Abstract ]
{

/// Protocol version this module speaks.
Parameter VERSION As STRING = "2025-06-18";

/// Build a JSON-RPC 2.0 envelope. Pass id = 0 for a notification, which carries no
/// id and expects no reply.
ClassMethod Envelope(pId As %Integer, pMethod As %String, pParamsJSON As %String = "") As %String [ Language = python ]
{
    import json
    envelope = {"jsonrpc": "2.0", "method": pMethod}
    if pId and int(pId) > 0:
        envelope["id"] = int(pId)
    envelope["params"] = json.loads(pParamsJSON) if pParamsJSON else {}
    return json.dumps(envelope)
}

/// The initialize handshake parameters.
ClassMethod InitParams(pClientName As %String = "IRIS-MCP-Adapter", pVersion As %String = "") As %String [ Language = python ]
{
    import json
    return json.dumps({
        "protocolVersion": pVersion or "2025-06-18",
        "capabilities": {},
        "clientInfo": {"name": pClientName or "IRIS-MCP-Adapter", "version": "1.0.0"},
    })
}

/// Streamable HTTP allows a server to answer with plain JSON or with an SSE stream,
/// and real servers choose SSE even when the request asks for JSON. Pull the payload
/// out of the data lines; pass anything else through untouched.
ClassMethod Unwrap(pRaw As %String) As %String [ Language = python ]
{
    text = (pRaw or "").lstrip()
    if not text.startswith("event:") and not text.startswith("data:"):
        return pRaw
    payload = [line[5:].strip() for line in text.splitlines() if line.startswith("data:")]
    return "\n".join(payload) if payload else pRaw
}

/// Turn a raw response into a verdict: {"ok":1,"result":{...}} or
/// {"ok":0,"error":"..."}. Handles SSE, malformed JSON and JSON-RPC errors.
///
/// A verdict rather than an Output parameter because a Language=python signature
/// cannot carry one, and every caller here is Python.
ClassMethod Decode(pRaw As %String) As %String [ Language = python ]
{
    import iris, json

    def verdict(ok, result=None, error=""):
        return json.dumps({"ok": ok, "result": result if result is not None else {},
                           "error": error})

    if not pRaw:
        return verdict(0, error="empty response")

    text = iris.cls("Agentic.Adapter.Protocol").Unwrap(pRaw)

    try:
        message = json.loads(text)
    except ValueError as e:
        return verdict(0, error="response is not JSON: %s" % e)

    if isinstance(message, dict) and message.get("error"):
        err = message["error"] or {}
        if isinstance(err, dict):
            return verdict(0, error="MCP error %s: %s" % (err.get("code"), err.get("message")))
        return verdict(0, error="MCP error: %s" % err)

    return verdict(1, result=message.get("result", {}))
}

/// Extract a dotted path from a JSON object. Blank path returns the whole object.
/// A leading "result." is tolerated and ignored, because callers think in terms of
/// the response they can see rather than the envelope around it.
ClassMethod Extract(pJSON As %String, pPath As %String = "") As %String [ Language = python ]
{
    import json

    try:
        node = json.loads(pJSON) if isinstance(pJSON, str) else pJSON
    except (ValueError, TypeError):
        return ""

    if not pPath:
        return json.dumps(node)

    for part in pPath.split("."):
        if not part or part == "result":
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

/// Arguments object for tools/call.
ClassMethod CallParams(pTool As %String, pArgumentsJSON As %String = "") As %String [ Language = python ]
{
    import json
    try:
        args = json.loads(pArgumentsJSON) if pArgumentsJSON else {}
    except ValueError:
        args = {}
    return json.dumps({"name": pTool, "arguments": args})
}

}
