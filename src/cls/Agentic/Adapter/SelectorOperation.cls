/// Business operation that asks a language model which MCP tool to call.
///
/// This is the agentic layer, and it lives here rather than inside a business
/// process on purpose: as its own outbound host it gets its own credentials, its
/// own timeouts, and — most importantly — every selection becomes a traced message.
/// When a selection later looks wrong, the trace holds what the model was asked,
/// what it answered, and why.
///
/// It selects a tool. It does not call one, and it never sees a whole message —
/// only the goal, the tool catalog, and whichever fields the caller chooses to send.
///
/// Part of: Production level feature — model-chosen tools. See README.
Class Agentic.Adapter.SelectorOperation Extends Ens.BusinessOperation
{

Parameter ADAPTER = "Agentic.Adapter.LLM";

Parameter INVOCATION = "Queue";

Parameter SETTINGS = "CacheSeconds:Selection,CacheEnabled:Selection,RequireKnownTool:Selection";

Property Adapter As Agentic.Adapter.LLM;

/// How long a selection stays valid. Selections are stable — the tool that
/// translates ICD does not change between messages — so this should be generous.
/// A day is a reasonable default; the cache is what makes this affordable.
Property CacheSeconds As %Integer [ InitialExpression = 86400 ];

Property CacheEnabled As %Boolean [ InitialExpression = 1 ];

/// Reject a selection naming a tool that is not in the supplied catalog.
/// Leave this on: a model that invents a tool name should fail loudly rather than
/// produce a confusing error from the MCP server later.
Property RequireKnownTool As %Boolean [ InitialExpression = 1 ];

Method OnMessage(pRequest As Agentic.Adapter.Msg.SelectRequest, Output pResponse As Agentic.Adapter.Msg.SelectResponse) As %Status
{
    set pResponse = ##class(Agentic.Adapter.Msg.SelectResponse).%New()
    set tStart = $zhorolog
    set tSC = $$$OK
    try {
        set tKey = ..cacheKey(pRequest)

        if ..CacheEnabled && 'pRequest.Refresh {
            set tHit = ..cacheGet(tKey)
            if tHit '= "" {
                set pResponse.ToolName = $listget(tHit, 1)
                set pResponse.ArgumentsJSON = $listget(tHit, 2)
                set pResponse.Reason = $listget(tHit, 3)
                set pResponse.FromCache = 1
                set pResponse.DurationMs = $normalize(($zhorolog - tStart) * 1000, 0)
                quit
            }
        }

        set tJSON = ..Ask(pRequest.Goal, pRequest.CatalogJSON, pRequest.ContextJSON)
        if ..Adapter.LastError '= "" {
            set pResponse.IsError = 1
            set pResponse.ErrorText = ..Adapter.LastError
            set tSC = $$$ERROR($$$GeneralError, "tool selection failed: "_..Adapter.LastError)
            quit
        }

        set pResponse.InputTokens = ..Adapter.LastInputTokens
        set pResponse.OutputTokens = ..Adapter.LastOutputTokens

        set tVerdict = ##class(%DynamicAbstractObject).%FromJSON(..Parse(tJSON, pRequest.CatalogJSON, ..RequireKnownTool))
        set tTool = tVerdict.tool
        set tArgs = tVerdict.arguments
        set tReason = tVerdict.reason
        if 'tVerdict.ok {
            set pResponse.IsError = 1
            set pResponse.ErrorText = tReason
            set tSC = $$$ERROR($$$GeneralError, "unusable tool selection: "_tReason)
            quit
        }

        set pResponse.ToolName = tTool
        set pResponse.ArgumentsJSON = tArgs
        set pResponse.Reason = tReason

        if ..CacheEnabled { do ..cachePut(tKey, tTool, tArgs, tReason) }
        $$$LOGINFO("selected tool '"_tTool_"': "_tReason)
    }
    catch ex {
        set tSC = ex.AsStatus()
        set pResponse.IsError = 1
        set pResponse.ErrorText = ex.DisplayString()
    }
    set pResponse.DurationMs = $normalize(($zhorolog - tStart) * 1000, 0)
    quit tSC
}

/// Build the prompt and ask the model. Returns its raw reply.
Method Ask(pGoal As %String, pCatalogJSON As %String, pContextJSON As %String) As %String [ Language = python ]
{
    import json

    system = (
        "You select exactly one tool from a catalog to accomplish a goal.\n"
        "Reply with JSON only, no prose, no code fences, in this form:\n"
        '{"tool": "<tool name>", "arguments": {...}, "reason": "<one sentence>"}\n'
        "The tool name must be copied exactly from the catalog. Build arguments that "
        "satisfy that tool's inputSchema using the supplied context. If no tool fits, "
        'reply {"tool": "", "reason": "<why>"}.'
    )

    user = "GOAL:\n%s\n\nCATALOG:\n%s\n\nCONTEXT:\n%s" % (
        pGoal or "", pCatalogJSON or "[]", pContextJSON or "{}")

    return self.Adapter.Complete(system, user)
}

/// Parse the model's reply. Returns 1 on success.
/// Tolerates a reply wrapped in prose or code fences, because models do that.
ClassMethod Parse(pReply As %String, pCatalogJSON As %String, pRequireKnown As %Boolean) As %String [ Language = python ]
{
    import json, re

    def verdict(ok, tool="", args="", reason=""):
        return json.dumps({"ok": ok, "tool": tool, "arguments": args, "reason": reason})

    reply = (pReply or "").strip()
    if not reply:
        return verdict(0, reason="empty reply from the model")

    # models wrap JSON in fences or prose more often than they should
    if "```" in reply:
        m = re.search(r"```(?:json)?\s*(.*?)```", reply, re.S)
        if m:
            reply = m.group(1).strip()
    if not reply.startswith("{"):
        m = re.search(r"\{.*\}", reply, re.S)
        if m:
            reply = m.group(0)

    try:
        answer = json.loads(reply)
    except ValueError:
        return verdict(0, reason="model reply was not JSON: %s" % reply[:200])

    tool = (answer.get("tool") or "").strip()
    reason = (answer.get("reason") or "").strip()
    args = answer.get("arguments")
    args_json = json.dumps(args) if isinstance(args, dict) else ""

    if not tool:
        return verdict(0, reason=reason or "the model selected no tool")

    if pRequireKnown:
        try:
            names = {t.get("name") for t in json.loads(pCatalogJSON or "[]")}
        except ValueError:
            names = set()
        if names and tool not in names:
            return verdict(0, reason="model chose '%s', which is not in the catalog" % tool)

    return verdict(1, tool, args_json, reason)
}

/// Derive a cache key. Blank CacheKey means: the goal, the catalog, and the context
/// keys plus any short scalar values that distinguish one case from another.
///
/// Values longer than 32 characters are excluded deliberately - a code or a coding
/// system discriminates between cases, a free-text description does not, and
/// including it would make every message a cache miss.
Method cacheKey(pRequest As Agentic.Adapter.Msg.SelectRequest) As %String [ Internal, Language = python ]
{
    import json, hashlib

    if pRequest.CacheKey:
        return pRequest.CacheKey

    parts = [pRequest.Goal or "", pRequest.CatalogJSON or ""]
    try:
        ctx = json.loads(pRequest.ContextJSON or "{}")
        if isinstance(ctx, dict):
            for k in sorted(ctx):
                v = ctx[k]
                if isinstance(v, str) and len(v) <= 32:
                    parts.append("%s=%s" % (k, v))
                elif isinstance(v, (int, float, bool)):
                    parts.append("%s=%s" % (k, v))
    except ValueError:
        pass

    return hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()
}

/// Seconds since the IRIS epoch. Plain integer arithmetic beats date juggling.
ClassMethod now() As %Integer [ CodeMode = expression, Internal ]
{
($piece($horolog, ",", 1) * 86400) + $piece($horolog, ",", 2)
}

ClassMethod cacheGet(pKey As %String) As %List [ Internal ]
{
    set tEntry = $get(^Agentic.Adapter.SelectCache($namespace, pKey))
    if tEntry = "" quit ""
    set tExpiry = $listget(tEntry, 4)
    if (tExpiry '= "") && (..now() > tExpiry) {
        kill ^Agentic.Adapter.SelectCache($namespace, pKey)
        quit ""
    }
    quit tEntry
}

Method cachePut(pKey As %String, pTool As %String, pArgs As %String, pReason As %String) [ Internal ]
{
    set tSeconds = +..CacheSeconds
    set tExpiry = $select(tSeconds > 0: ..now() + tSeconds, 1: "")
    set ^Agentic.Adapter.SelectCache($namespace, pKey) = $listbuild(pTool, pArgs, pReason, tExpiry)
}

/// Clear cached selections for this namespace. Use after a server's catalog changes.
ClassMethod ClearCache() As %Status
{
    kill ^Agentic.Adapter.SelectCache($namespace)
    quit $$$OK
}

}
