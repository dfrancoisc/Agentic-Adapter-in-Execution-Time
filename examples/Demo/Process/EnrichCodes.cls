/// Example business process: enrich coded HL7 fields using an MCP server.
///
/// Walks the inbound message for a given segment type, sends each coded value to a
/// configured MCP operation, and writes the translated code back into a copy of the
/// message before forwarding it on.
///
/// Nothing here is specific to SNOMED or to terminology. The segment and field paths
/// are settings, and the MCP item decides which server and tool are actually called.
/// Point it at a different MCP item and it enriches something else.
///
/// The translated code is written into the primary triplet and the ORIGINAL code is
/// preserved in the alternate triplet, which is what the HL7 CWE datatype is for.
/// A receiver that does not understand SNOMED can still read what was sent.
Class Demo.Process.EnrichCodes Extends Ens.BusinessProcess
{

Parameter SETTINGS = "MCPTarget:Basic,OutputTarget:Basic,SegmentType:Basic,CodeField:Basic,TextField:Basic,SystemField:Basic,AltCodeField:Basic,AltTextField:Basic,AltSystemField:Basic,TargetSystemLabel:Basic";

/// Config name of the production item using Agentic.Adapter.MCP.
Property MCPTarget As %String [ InitialExpression = "SnomedMCP" ];

/// Config name of the item the enriched message is forwarded to.
Property OutputTarget As %String [ InitialExpression = "HL7FileOut" ];

/// Segment type to scan, e.g. OBX or DG1.
Property SegmentType As %String [ InitialExpression = "OBX" ];

/// Field path holding the code to translate, relative to the segment.
Property CodeField As %String [ InitialExpression = "5.1" ];

/// Field path holding the code's display text.
Property TextField As %String [ InitialExpression = "5.2" ];

/// Field path holding the coding system.
Property SystemField As %String [ InitialExpression = "5.3" ];

/// Alternate triplet, where the original code is preserved.
Property AltCodeField As %String [ InitialExpression = "5.4" ];

Property AltTextField As %String [ InitialExpression = "5.5" ];

Property AltSystemField As %String [ InitialExpression = "5.6" ];

/// Label written into the coding system field for translated codes.
Property TargetSystemLabel As %String [ InitialExpression = "SCT" ];

/// Tell the Production Configuration diagram who this process talks to.
///
/// Without this, the MCP operation appears as an unconnected island. The default
/// implementation only understands the standard `TargetConfigNames` setting, and
/// this process reaches its targets through `MCPTarget` and `OutputTarget`, so the
/// UI has no way to know about them. Any host that dispatches to a config item
/// named by a custom setting has to declare it here or the drawing lies.
ClassMethod OnGetConnections(Output pArray As %String, pItem As Ens.Config.Item)
{
    do ##super(.pArray, pItem)
    for i = 1:1:pItem.Settings.Count() {
        set tSetting = pItem.Settings.GetAt(i)
        continue:'$isobject(tSetting)
        ; postconditional expressions must not contain spaces - the parser ends
        ; them at the first whitespace
        continue:((tSetting.Name'="MCPTarget")&&(tSetting.Name'="OutputTarget"))
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

        for i = 1:1:tOut.SegCount {
            set tSeg = tOut.GetSegmentAt(i)
            continue:'$isobject(tSeg)
            continue:(tSeg.Name '= ..SegmentType)

            set tCode = tOut.GetValueAt(i_":"_..CodeField)
            continue:(tCode = "")

            set tOrigText = tOut.GetValueAt(i_":"_..TextField)
            set tOrigSystem = tOut.GetValueAt(i_":"_..SystemField)

            set tResult = ..translate(tCode, .tSC)
            if $$$ISERR(tSC) quit
            continue:'$isobject(tResult)

            ; new code into the primary triplet
            set tNewCode = $select(tResult.%IsDefined("code"): tResult.code, 1: "")
            set tNewText = $select(tResult.%IsDefined("display"): tResult.display, 1: "")
            continue:(tNewCode = "")

            do tOut.SetValueAt(tNewCode, i_":"_..CodeField)
            do tOut.SetValueAt(tNewText, i_":"_..TextField)
            do tOut.SetValueAt(..TargetSystemLabel, i_":"_..SystemField)

            ; original preserved in the alternate triplet
            do tOut.SetValueAt(tCode, i_":"_..AltCodeField)
            do tOut.SetValueAt(tOrigText, i_":"_..AltTextField)
            do tOut.SetValueAt(tOrigSystem, i_":"_..AltSystemField)

            set tEnriched = tEnriched + 1
            $$$LOGINFO("enriched "_..SegmentType_" segment "_i_": "_tCode_" -> "_tNewCode)
        }
        if $$$ISERR(tSC) quit

        if tEnriched = 0 {
            $$$LOGWARNING("no "_..SegmentType_" codes found to enrich; forwarding unchanged")
        }

        set tSC = ..SendRequestAsync(..OutputTarget, tOut, 0)
    }
    catch ex {
        set tSC = ex.AsStatus()
    }
    quit tSC
}

/// Send one code to the MCP operation and return the structured result, or null.
/// The MCP item owns the server, the tool and the security - this process only
/// knows the config name.
Method translate(pCode As %String, Output pSC As %Status) As %DynamicObject [ Internal ]
{
    set pSC = $$$OK
    set tResult = ""
    set tArgs = {}
    set tArgs.code = pCode

    set tReq = ##class(Agentic.Adapter.Msg.ToolRequest).%New()
    set tReq.ArgumentsJSON = tArgs.%ToJSON()
    ; ask for the structured object rather than a single scalar, because both the
    ; code and its description are needed
    set tReq.ResultPath = "structuredContent"

    set pSC = ..SendRequestSync(..MCPTarget, tReq, .tResp)
    if $$$ISERR(pSC) quit ""

    if '$isobject(tResp) quit ""
    if tResp.IsError {
        $$$LOGWARNING("MCP could not translate "_pCode_": "_tResp.ErrorText)
        quit ""
    }
    if tResp.ResultJSON = "" quit ""

    try {
        set tResult = ##class(%DynamicAbstractObject).%FromJSON(tResp.ResultJSON)
    }
    catch {
        $$$LOGWARNING("MCP result for "_pCode_" was not JSON")
        set tResult = ""
    }
    quit tResult
}

}
