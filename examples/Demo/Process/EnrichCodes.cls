/// Enrich coded HL7 fields using an MCP server.
///
/// Everything about MCP — fetching the catalog, choosing a tool, calling it,
/// caching selections, error policy, tracing — lives in the base class. This class
/// contains only what is genuinely HL7: where the codes are, and how to write an
/// answer back.
///
/// The write-back puts the translated code in the primary CWE triplet and preserves
/// the original in the alternate triplet, which is what that datatype is for: a
/// receiver that does not speak SNOMED can still read what was sent.
Class Demo.Process.EnrichCodes Extends Agentic.Adapter.EnrichmentProcess
{

Parameter SETTINGS = "SegmentType:Fields,CodeField:Fields,TextField:Fields,SystemField:Fields,AltCodeField:Fields,AltTextField:Fields,AltSystemField:Fields,TargetSystemLabel:Fields";

/// Segment type to scan, e.g. OBX or DG1.
Property SegmentType As %String [ InitialExpression = "OBX" ];

Property CodeField As %String [ InitialExpression = "5.1" ];

Property TextField As %String [ InitialExpression = "5.2" ];

Property SystemField As %String [ InitialExpression = "5.3" ];

Property AltCodeField As %String [ InitialExpression = "5.4" ];

Property AltTextField As %String [ InitialExpression = "5.5" ];

Property AltSystemField As %String [ InitialExpression = "5.6" ];

Property TargetSystemLabel As %String [ InitialExpression = "SCT" ];

/// Where the codes live: every segment of the configured type that carries one.
/// The segment index is the id, so ApplyResult can find its way back.
Method FindCandidates(pMessage As EnsLib.HL7.Message, Output pSC As %Status) As %DynamicArray
{
    set pSC = $$$OK
    set tOut = []
    for i = 1:1:pMessage.SegCount {
        set tSeg = pMessage.GetSegmentAt(i)
        continue:'$isobject(tSeg)
        continue:(tSeg.Name '= ..SegmentType)

        set tCode = pMessage.GetValueAt(i_":"_..CodeField)
        continue:(tCode = "")

        do tOut.%Push({
            "id": (i),
            "value": (tCode),
            "system": (pMessage.GetValueAt(i_":"_..SystemField)),
            "text": (pMessage.GetValueAt(i_":"_..TextField))
        })
    }
    quit tOut
}

/// Translated code into the primary triplet, original into the alternate.
Method ApplyResult(pMessage As EnsLib.HL7.Message, pCandidate As %DynamicObject, pResult As %DynamicObject) As %Status
{
    set tNewCode = $select(pResult.%IsDefined("code"): pResult.code, 1: "")
    if tNewCode = "" quit $$$OK

    set tNewText = $select(pResult.%IsDefined("display"): pResult.display, 1: "")
    set i = pCandidate.id

    do pMessage.SetValueAt(tNewCode, i_":"_..CodeField)
    do pMessage.SetValueAt(tNewText, i_":"_..TextField)
    do pMessage.SetValueAt(..TargetSystemLabel, i_":"_..SystemField)

    do pMessage.SetValueAt(pCandidate.value, i_":"_..AltCodeField)
    do pMessage.SetValueAt(pCandidate.text, i_":"_..AltTextField)
    do pMessage.SetValueAt(pCandidate.system, i_":"_..AltSystemField)

    $$$LOGINFO("enriched "_..SegmentType_" "_i_": "_pCandidate.value_" ("_pCandidate.system_") -> "_tNewCode)
    quit $$$OK
}

}
