/// Example business process: enrich coded HL7 fields using an MCP server.
///
/// Walks the inbound message for a given segment type, works out which tool should
/// translate each coded value, calls it through the MCP operation, and writes the
/// result back into a copy of the message before forwarding it on.
///
/// Three ways to decide which tool to call, set by SelectionMode:
///
///   fixed  The MCP item's configured ToolName. One job, one tool.
///   rule   A value in the message picks the tool, via RuleMap. Deterministic,
///          free, instant. Right whenever the data already says what it is - an
///          HL7 CWE field names its own coding system in the third component.
///   model  A language model picks from the server's catalog, through the selector
///          operation. For open intent, unfamiliar servers, or catalogs that change.
///
/// Prefer rule over model wherever the message answers the question. Paying a model
/// to re-derive "I10 means ICD-10" on every message buys nothing and introduces
/// non-determinism into a clinical flow.
///
/// Nothing here is specific to SNOMED or to terminology. Segment and field paths are
/// settings, and the MCP item decides which server is actually called.
Class Demo.Process.EnrichCodes Extends Ens.BusinessProcess
{

Parameter SETTINGS = "MCPTarget:Basic,OutputTarget:Basic,SelectionMode:Selection,RuleMap:Selection,SelectorTarget:Selection,Goal:Selection,SegmentType:Fields,CodeField:Fields,TextField:Fields,SystemField:Fields,AltCodeField:Fields,AltTextField:Fields,AltSystemField:Fields,TargetSystemLabel:Fields";

/// Config name of the production item using Agentic.Adapter.MCP.
Property MCPTarget As %String [ InitialExpression = "SnomedMCP" ];

/// Config name of the item the enriched message is forwarded to.
Property OutputTarget As %String [ InitialExpression = "HL7FileOut" ];

/// How the tool is chosen: fixed, rule, or model.
Property SelectionMode As %String(VALUELIST = ",fixed,rule,model") [ InitialExpression = "rule" ];

/// For rule mode: coding system to tool name, comma separated.
/// e.g. I10=translate_icd,LN=translate_loinc,SCT=
/// An empty tool name means "already in the target system, leave it alone".
Property RuleMap As %String(MAXLEN = 2000) [ InitialExpression = "I10=translate_icd,LN=translate_loinc,SCT=" ];

/// For model mode: config name of the Agentic.Adapter.SelectorOperation item.
Property SelectorTarget As %String [ InitialExpression = "ToolSelector" ];

/// For model mode: what to tell the model we are trying to achieve.
Property Goal As %String(MAXLEN = 1000) [ InitialExpression = "Translate this observation code to SNOMED CT" ];

/// Segment type to scan, e.g. OBX or DG1.
Property SegmentType As %String [ InitialExpression = "OBX" ];

Property CodeField As %String [ InitialExpression = "5.1" ];

Property TextField As %String [ InitialExpression = "5.2" ];

Property SystemField As %String [ InitialExpression = "5.3" ];

Property AltCodeField As %String [ InitialExpression = "5.4" ];

Property AltTextField As %String [ InitialExpression = "5.5" ];

Property AltSystemField As %String [ InitialExpression = "5.6" ];

Property TargetSystemLabel As %String [ InitialExpression = "SCT" ];

/// Tell the Production Configuration diagram who this process talks to.
/// Without this the MCP and selector operations appear as unconnected islands: the
/// default implementation only understands the standard TargetConfigNames setting,
/// and this process reaches its targets through settings of its own.
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

Method OnRequest(pRequest As EnsLib.HL7.Message, Output pResponse As Ens.Response) As %Status
{
    set tSC = $$$OK
    try {
        ; Work on a copy. The inbound message is part of the audit trail and must
        ; not be modified - the trace has to show what actually arrived.
        set tOut = pRequest.%ConstructClone(1)
        set tEnriched = 0
        set tCatalog = ""

        for i = 1:1:tOut.SegCount {
            set tSeg = tOut.GetSegmentAt(i)
            continue:'$isobject(tSeg)
            continue:(tSeg.Name '= ..SegmentType)

            set tCode = tOut.GetValueAt(i_":"_..CodeField)
            continue:(tCode = "")

            set tOrigText = tOut.GetValueAt(i_":"_..TextField)
            set tOrigSystem = tOut.GetValueAt(i_":"_..SystemField)

            ; ---- decide which tool translates this code ----
            set tTool = ""
            if ..SelectionMode = "rule" {
                set tMatched = ..ruleLookup(..RuleMap, tOrigSystem, .tTool)
                if 'tMatched {
                    $$$LOGWARNING("no rule for coding system '"_tOrigSystem_"'; leaving "_tCode_" alone")
                    continue
                }
                if tTool = "" {
                    ; mapped to nothing on purpose: already in the target system
                    continue
                }
            } elseif ..SelectionMode = "model" {
                if tCatalog = "" {
                    set tCatalog = ..fetchCatalog(.tSC)
                    if $$$ISERR(tSC) quit
                }
                set tTool = ..askSelector(tCatalog, tCode, tOrigSystem, tOrigText, .tSC)
                if $$$ISERR(tSC) quit
                continue:(tTool = "")
            }
            ; fixed mode leaves tTool empty, so the MCP item uses its ToolName

            set tResult = ..translate(tTool, tCode, tOrigText, .tSC)
            if $$$ISERR(tSC) quit
            continue:'$isobject(tResult)

            set tNewCode = $select(tResult.%IsDefined("code"): tResult.code, 1: "")
            set tNewText = $select(tResult.%IsDefined("display"): tResult.display, 1: "")
            continue:(tNewCode = "")

            ; translated code into the primary triplet
            do tOut.SetValueAt(tNewCode, i_":"_..CodeField)
            do tOut.SetValueAt(tNewText, i_":"_..TextField)
            do tOut.SetValueAt(..TargetSystemLabel, i_":"_..SystemField)

            ; original preserved in the alternate triplet
            do tOut.SetValueAt(tCode, i_":"_..AltCodeField)
            do tOut.SetValueAt(tOrigText, i_":"_..AltTextField)
            do tOut.SetValueAt(tOrigSystem, i_":"_..AltSystemField)

            set tEnriched = tEnriched + 1
            $$$LOGINFO("enriched "_..SegmentType_" "_i_": "_tCode_" ("_tOrigSystem_") -> "_tNewCode_" via "_$select(tTool="": "configured tool", 1: tTool))
        }
        if $$$ISERR(tSC) quit

        if tEnriched = 0 {
            $$$LOGWARNING("nothing enriched; forwarding unchanged")
        }
        set tSC = ..SendRequestAsync(..OutputTarget, tOut, 0)
    }
    catch ex {
        set tSC = ex.AsStatus()
    }
    quit tSC
}

/// Look up a coding system in RuleMap. Returns 1 if the system was found at all,
/// with the tool name in pTool - which may legitimately be empty, meaning
/// "recognised, and deliberately not translated".
ClassMethod ruleLookup(pMap As %String, pSystem As %String, Output pTool As %String) As %Boolean [ Internal ]
{
    set pTool = ""
    for i = 1:1:$length(pMap, ",") {
        set tPair = $zstrip($piece(pMap, ",", i), "<>W")
        continue:(tPair = "")
        if $zconvert($piece(tPair, "=", 1), "U") = $zconvert(pSystem, "U") {
            set pTool = $zstrip($piece(tPair, "=", 2), "<>W")
            return 1
        }
    }
    quit 0
}

/// Ask the MCP item what tools the server offers.
Method fetchCatalog(Output pSC As %Status) As %String [ Internal ]
{
    set pSC = $$$OK
    set tReq = ##class(Agentic.Adapter.Msg.ToolRequest).%New()
    set tReq.Action = "list"
    set pSC = ..SendRequestSync(..MCPTarget, tReq, .tResp)
    if $$$ISERR(pSC) quit ""
    if '$isobject(tResp) quit ""
    quit tResp.ResultJSON
}

/// Ask the selector which tool handles this code. Returns the tool name.
Method askSelector(pCatalog As %String, pCode As %String, pSystem As %String, pText As %String, Output pSC As %Status) As %String [ Internal ]
{
    set pSC = $$$OK
    set tCtx = {}
    set tCtx.code = pCode
    set tCtx.system = pSystem
    set tCtx.text = pText

    set tReq = ##class(Agentic.Adapter.Msg.SelectRequest).%New()
    set tReq.Goal = ..Goal
    set tReq.CatalogJSON = pCatalog
    set tReq.ContextJSON = tCtx.%ToJSON()

    ; Cache on the coding system, not the code. Which tool translates ICD does not
    ; depend on WHICH ICD code it is, so keying on the code would mean a model call
    ; per distinct code - thousands of paid decisions to answer one question. The
    ; automatic key errs on the safe side by including every short scalar in the
    ; context; a caller that knows what actually discriminates should say so.
    set tReq.CacheKey = ..Goal_"|"_pSystem

    set pSC = ..SendRequestSync(..SelectorTarget, tReq, .tResp)
    if $$$ISERR(pSC) quit ""
    if '$isobject(tResp) quit ""
    if tResp.IsError {
        $$$LOGWARNING("tool selection failed for "_pCode_": "_tResp.ErrorText)
        quit ""
    }
    $$$LOGINFO("selector chose '"_tResp.ToolName_"' for "_pSystem_" ("_$select(tResp.FromCache: "cached", 1: "asked the model")_")")
    quit tResp.ToolName
}

/// Invoke the MCP tool and return the structured result, or null.
Method translate(pTool As %String, pCode As %String, pText As %String, Output pSC As %Status) As %DynamicObject [ Internal ]
{
    set pSC = $$$OK
    set tArgs = {}
    set tArgs.code = pCode
    set tArgs.text = pText

    set tReq = ##class(Agentic.Adapter.Msg.ToolRequest).%New()
    set tReq.ToolName = pTool
    set tReq.ArgumentsJSON = tArgs.%ToJSON()
    ; ask for the object rather than a scalar: both the code and its description
    ; are needed
    set tReq.ResultPath = "structuredContent"

    set pSC = ..SendRequestSync(..MCPTarget, tReq, .tResp)
    if $$$ISERR(pSC) quit ""
    if '$isobject(tResp) quit ""
    if tResp.IsError {
        $$$LOGWARNING("MCP could not translate "_pCode_": "_tResp.ErrorText)
        quit ""
    }
    if tResp.ResultJSON = "" quit ""

    set tResult = ""
    try {
        set tResult = ##class(%DynamicAbstractObject).%FromJSON(tResp.ResultJSON)
    }
    catch {
        $$$LOGWARNING("MCP result for "_pCode_" was not JSON")
    }
    quit tResult
}

}
