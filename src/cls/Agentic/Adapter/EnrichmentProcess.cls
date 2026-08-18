/// Base class for a business process that enriches values in a message using an
/// MCP server.
///
/// It owns everything that is the same for every enrichment: fetching the tool
/// catalog, deciding which tool to call, invoking it, caching selections, logging,
/// error policy, and telling the Production Configuration diagram what it talks to.
///
/// A subclass implements two things, and they are the only two things that are
/// genuinely yours:
///
///   FindCandidates()  where the values live in YOUR message
///   ApplyResult()     what to do with the answer
///
/// Optionally override BuildArguments() when a tool wants a different argument
/// shape, and CloneMessage() when a plain deep clone is not how your message type
/// should be copied.
///
/// Message-format agnostic: HL7, FHIR, X12 or a custom class all work, because the
/// base class never touches the message. It only ever holds candidates, which are
/// plain JSON objects the subclass produced.
///
/// Part of: Production level feature — the enrichment process you extend. See README.
Class Agentic.Adapter.EnrichmentProcess Extends Ens.BusinessProcess [ Abstract ]
{

Parameter SETTINGS = "MCPTarget:Basic,OutputTarget:Basic,SelectionMode:Selection,RuleMap:Selection,SelectorTarget:Selection,Goal:Selection,ResultPath:Selection,FailOnToolError:Selection";

/// Config name of the production item using Agentic.Adapter.MCP.
Property MCPTarget As %String [ InitialExpression = "MCPServer" ];

/// Config name of the item the enriched message is forwarded to.
/// Leave blank to reply to the caller instead of forwarding.
Property OutputTarget As %String;

/// How the tool is chosen for each candidate:
///   fixed  the MCP item's configured ToolName
///   rule   the candidate's discriminator maps to a tool via RuleMap
///   model  a language model picks from the server's catalog
///
/// Prefer rule wherever the message already states what it is. Paying a model to
/// re-derive something the data says outright buys nothing and makes the result
/// non-deterministic.
Property SelectionMode As %String(VALUELIST = ",fixed,rule,model") [ InitialExpression = "fixed" ];

/// For rule mode: discriminator to tool name, comma separated.
/// e.g. I10=translate_icd,LN=translate_loinc,SCT=
/// An empty tool name means "recognised, and deliberately not translated".
Property RuleMap As %String(MAXLEN = 2000);

/// For model mode: config name of the Agentic.Adapter.SelectorOperation item.
Property SelectorTarget As %String [ InitialExpression = "ToolSelector" ];

/// For model mode: what to tell the model we are trying to achieve.
Property Goal As %String(MAXLEN = 1000);

/// Path into the tool result handed to ApplyResult(). The default returns the
/// structured object, because enrichment usually needs more than one field of it.
Property ResultPath As %String(MAXLEN = 200) [ InitialExpression = "structuredContent" ];

/// Fail the whole message when a tool reports isError, rather than leaving that
/// candidate untouched and carrying on. Off by default: a code the server cannot
/// translate is a data quality finding, not an outage.
Property FailOnToolError As %Boolean [ InitialExpression = 0 ];

/// Return the values to enrich, as a %DynamicArray of candidate objects:
///
///   {"id": <anything you need to find it again>,
///    "value": "E11.9",                 the value to translate
///    "system": "I10",                  discriminator, used by rule and model modes
///    "text": "Type 2 diabetes..."}     optional context
///
/// Called with the OUTGOING copy, so ids taken here are valid in ApplyResult().
///
/// Override this in ObjectScript, or override Candidates() to write the same logic
/// in Python. The Output parameter here is why the two exist: a Language=python
/// signature cannot carry one.
Method FindCandidates(pMessage As %Persistent, Output pSC As %Status) As %DynamicArray
{
    set pSC = $$$OK
    set tJSON = ..Candidates(pMessage)
    if tJSON = "" quit []
    quit ##class(%DynamicAbstractObject).%FromJSON(tJSON)
}

/// Python-friendly form of FindCandidates: return the candidate array as a JSON
/// string. No Output parameters, so this can be written entirely in Python.
Method Candidates(pMessage As %Persistent) As %String
{
    quit "[]"
}

/// Write one translated result back into the outgoing message.
/// pCandidate is the entry you produced; pResult is whatever the tool returned at
/// ResultPath.
///
/// Override this in ObjectScript, or override Apply() to write it in Python.
Method ApplyResult(pMessage As %Persistent, pCandidate As %DynamicObject, pResult As %DynamicObject) As %Status
{
    quit ..Apply(pMessage, pCandidate.%ToJSON(), pResult.%ToJSON())
}

/// Python-friendly form of ApplyResult: both objects arrive as JSON strings, which
/// Python reads with json.loads and ObjectScript never has to marshal.
Method Apply(pMessage As %Persistent, pCandidateJSON As %String, pResultJSON As %String) As %Status
{
    quit $$$OK
}

/// Arguments for one tool call. Override when a tool wants a different shape.
Method BuildArguments(pCandidate As %DynamicObject) As %DynamicObject
{
    set tArgs = {}
    set tArgs.code = pCandidate.value
    if pCandidate.%IsDefined("text") { set tArgs.text = pCandidate.text }
    quit tArgs
}

/// Produce the message to modify. The inbound message is audit trail and must not
/// be touched - the trace has to show what actually arrived.
Method CloneMessage(pRequest As %Persistent) As %Persistent
{
    quit pRequest.%ConstructClone(1)
}

/// Cache key for a model selection. Keyed on the discriminator, NOT the value:
/// which tool translates ICD does not depend on which ICD code it is. Keying on
/// the value would mean a model call per distinct code.
Method SelectionCacheKey(pCandidate As %DynamicObject) As %String
{
    quit ..Goal_"|"_pCandidate.system
}

Method OnRequest(pRequest As %Persistent, Output pResponse As %Persistent) As %Status
{
    set tSC = $$$OK
    try {
        set tOut = ..CloneMessage(pRequest)

        set tCandidates = ..FindCandidates(tOut, .tSC)
        if $$$ISERR(tSC) quit
        if '$isobject(tCandidates) set tCandidates = []

        set tCatalog = "", tDone = 0

        for i = 0:1:(tCandidates.%Size() - 1) {
            set tCand = tCandidates.%Get(i)
            continue:'$isobject(tCand)
            continue:('tCand.%IsDefined("value"))||(tCand.value = "")

            set tTool = ..chooseTool(tCand, .tCatalog, .tSkip, .tSC)
            if $$$ISERR(tSC) quit
            continue:tSkip

            set tResult = ..CallTool(tTool, ..BuildArguments(tCand), .tSC)
            if $$$ISERR(tSC) quit
            continue:'$isobject(tResult)

            set tSC = ..ApplyResult(tOut, tCand, tResult)
            if $$$ISERR(tSC) quit
            set tDone = tDone + 1
        }
        if $$$ISERR(tSC) quit

        if tDone = 0 { $$$LOGWARNING("nothing enriched; forwarding unchanged") }

        if ..OutputTarget '= "" {
            set tSC = ..SendRequestAsync(..OutputTarget, tOut, 0)
        } else {
            set pResponse = tOut
        }
    }
    catch ex {
        set tSC = ex.AsStatus()
    }
    quit tSC
}

/// Decide which tool handles this candidate. Sets pSkip when the candidate should
/// be left alone. An empty tool name means "use the MCP item's configured ToolName".
Method chooseTool(pCandidate As %DynamicObject, ByRef pCatalog As %String, Output pSkip As %Boolean, Output pSC As %Status) As %String [ Internal ]
{
    set pSC = $$$OK, pSkip = 0, tTool = ""

    if ..SelectionMode = "rule" {
        set tFound = ..RuleLookup(..RuleMap, pCandidate.system, .tTool)
        if 'tFound {
            $$$LOGWARNING("no rule for '"_pCandidate.system_"'; leaving "_pCandidate.value_" alone")
            set pSkip = 1
        } elseif tTool = "" {
            ; mapped to nothing on purpose
            set pSkip = 1
        }
        quit tTool
    }

    if ..SelectionMode = "model" {
        if pCatalog = "" {
            set pCatalog = ..FetchCatalog(.pSC)
            if $$$ISERR(pSC) quit ""
        }
        set tTool = ..AskSelector(pCatalog, pCandidate, .pSC)
        if $$$ISERR(pSC) quit ""
        if tTool = "" set pSkip = 1
        quit tTool
    }

    ; fixed: empty tool name, so the MCP item uses its configured ToolName
    quit ""
}

/// Ask the MCP item what tools the server offers.
Method FetchCatalog(Output pSC As %Status) As %String
{
    set pSC = $$$OK
    set tReq = ##class(Agentic.Adapter.Msg.ToolRequest).%New()
    set tReq.Action = "list"
    set pSC = ..SendRequestSync(..MCPTarget, tReq, .tResp)
    if $$$ISERR(pSC) quit ""
    quit $select($isobject(tResp): tResp.ResultJSON, 1: "")
}

/// Ask the selector which tool handles this candidate.
Method AskSelector(pCatalog As %String, pCandidate As %DynamicObject, Output pSC As %Status) As %String
{
    set pSC = $$$OK
    set tReq = ##class(Agentic.Adapter.Msg.SelectRequest).%New()
    set tReq.Goal = ..Goal
    set tReq.CatalogJSON = pCatalog
    set tReq.ContextJSON = pCandidate.%ToJSON()
    set tReq.CacheKey = ..SelectionCacheKey(pCandidate)

    set pSC = ..SendRequestSync(..SelectorTarget, tReq, .tResp)
    if $$$ISERR(pSC) quit ""
    if '$isobject(tResp) quit ""
    if tResp.IsError {
        $$$LOGWARNING("tool selection failed for "_pCandidate.value_": "_tResp.ErrorText)
        quit ""
    }
    $$$LOGINFO("selector chose '"_tResp.ToolName_"' for '"_pCandidate.system_"' ("_$select(tResp.FromCache: "cached", 1: "asked the model")_")")
    quit tResp.ToolName
}

/// Invoke one MCP tool and return the result at ResultPath, or null.
Method CallTool(pTool As %String, pArgs As %DynamicObject, Output pSC As %Status) As %DynamicObject
{
    set pSC = $$$OK
    set tReq = ##class(Agentic.Adapter.Msg.ToolRequest).%New()
    set tReq.ToolName = pTool
    set tReq.ArgumentsJSON = pArgs.%ToJSON()
    set tReq.ResultPath = ..ResultPath

    set pSC = ..SendRequestSync(..MCPTarget, tReq, .tResp)
    if $$$ISERR(pSC) quit ""
    if '$isobject(tResp) quit ""

    if tResp.IsError {
        ; the tool ran and reported failure - a business outcome, not a broken
        ; interface, unless this process is configured to treat it as one
        $$$LOGWARNING("tool could not handle '"_pArgs.code_"': "_tResp.ErrorText)
        if ..FailOnToolError {
            set pSC = $$$ERROR($$$GeneralError, "tool reported isError for "_pArgs.code)
        }
        quit ""
    }
    if tResp.ResultJSON = "" quit ""

    set tResult = ""
    try { set tResult = ##class(%DynamicAbstractObject).%FromJSON(tResp.ResultJSON) }
    catch { $$$LOGWARNING("tool result was not JSON") }
    quit tResult
}

/// Look up a discriminator in a comma separated map. Returns 1 when the key was
/// present at all - the mapped tool may legitimately be empty.
ClassMethod RuleLookup(pMap As %String, pKey As %String, Output pTool As %String) As %Boolean
{
    set pTool = ""
    for i = 1:1:$length(pMap, ",") {
        set tPair = $zstrip($piece(pMap, ",", i), "<>W")
        continue:(tPair = "")
        if $zconvert($piece(tPair, "=", 1), "U") = $zconvert(pKey, "U") {
            set pTool = $zstrip($piece(tPair, "=", 2), "<>W")
            return 1
        }
    }
    quit 0
}

/// Tell the Production Configuration diagram who this process talks to.
/// Without this the MCP and selector operations are drawn as unconnected islands:
/// the default implementation only understands the standard TargetConfigNames
/// setting, and this process reaches its targets through settings of its own.
ClassMethod OnGetConnections(Output pArray As %String, pItem As Ens.Config.Item)
{
    do ##super(.pArray, pItem)
    for i = 1:1:pItem.Settings.Count() {
        set tSetting = pItem.Settings.GetAt(i)
        continue:'$isobject(tSetting)
        ; postconditional expressions must not contain spaces - the parser ends
        ; them at the first whitespace
        continue:((tSetting.Name'="MCPTarget")&&(tSetting.Name'="OutputTarget")&&(tSetting.Name'="SelectorTarget"))
        continue:(tSetting.Value="")
        set pArray(tSetting.Value) = ""
    }
}

}
