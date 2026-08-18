/// Microbenchmark: the same enrichment logic in ObjectScript and in Python.
///
/// Business processes cannot be instantiated outside a production, so the two
/// implementations are copied here verbatim onto a plain object that can be. This
/// isolates the language from the network: the end-to-end production runs are
/// dominated by HTTP round trips and file I/O, which are identical either way.
///
/// Run:  do ##class(Agentic.Bench.LanguageCompare).Run(2000)
Class Agentic.Bench.LanguageCompare Extends %RegisteredObject
{

Property SegmentType As %String [ InitialExpression = "OBX" ];

Property CodeField As %String [ InitialExpression = "5.1" ];

Property TextField As %String [ InitialExpression = "5.2" ];

Property SystemField As %String [ InitialExpression = "5.3" ];

Property AltCodeField As %String [ InitialExpression = "5.4" ];

Property AltTextField As %String [ InitialExpression = "5.5" ];

Property AltSystemField As %String [ InitialExpression = "5.6" ];

Property TargetSystemLabel As %String [ InitialExpression = "SCT" ];

/// ObjectScript: find the coded fields.
Method FindOS(pMessage As EnsLib.HL7.Message) As %DynamicArray
{
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

/// Python: find the coded fields.
Method FindPy(pMessage As %Persistent) As %String [ Language = python ]
{
    import json
    found = []
    for i in range(1, int(pMessage.SegCount) + 1):
        segment = pMessage.GetSegmentAt(i)
        if segment is None or segment.Name != self.SegmentType:
            continue
        code = pMessage.GetValueAt("%d:%s" % (i, self.CodeField))
        if not code:
            continue
        found.append({
            "id": i,
            "value": code,
            "system": pMessage.GetValueAt("%d:%s" % (i, self.SystemField)),
            "text": pMessage.GetValueAt("%d:%s" % (i, self.TextField)),
        })
    return json.dumps(found)
}

/// ObjectScript: write one result back.
Method ApplyOS(pMessage As EnsLib.HL7.Message, pCandidate As %DynamicObject, pResult As %DynamicObject) As %Status
{
    set tNewCode = $select(pResult.%IsDefined("code"): pResult.code, 1: "")
    if tNewCode = "" quit $$$OK
    set tNewText = $select(pResult.%IsDefined("display"): pResult.display, 1: "")
    set i = pCandidate.id
    do pMessage.SetValueAt(tNewCode, i_":"_..CodeField)
    do pMessage.SetValueAt(tNewText, i_":"_..TextField)
    if ..TargetSystemLabel '= "" { do pMessage.SetValueAt(..TargetSystemLabel, i_":"_..SystemField) }
    do pMessage.SetValueAt(pCandidate.value, i_":"_..AltCodeField)
    do pMessage.SetValueAt(pCandidate.text, i_":"_..AltTextField)
    do pMessage.SetValueAt(pCandidate.system, i_":"_..AltSystemField)
    quit $$$OK
}

/// Python: write one result back.
Method ApplyPy(pMessage As %Persistent, pCandidateJSON As %String, pResultJSON As %String) As %Status [ Language = python ]
{
    import iris, json
    candidate = json.loads(pCandidateJSON or "{}")
    result = json.loads(pResultJSON or "{}")
    new_code = result.get("code") or ""
    if not new_code:
        return iris.system.Status.OK()
    i = candidate.get("id")
    pMessage.SetValueAt(new_code, "%d:%s" % (i, self.CodeField))
    pMessage.SetValueAt(result.get("display") or "", "%d:%s" % (i, self.TextField))
    if self.TargetSystemLabel:
        pMessage.SetValueAt(self.TargetSystemLabel, "%d:%s" % (i, self.SystemField))
    pMessage.SetValueAt(candidate.get("value") or "", "%d:%s" % (i, self.AltCodeField))
    pMessage.SetValueAt(candidate.get("text") or "", "%d:%s" % (i, self.AltTextField))
    pMessage.SetValueAt(candidate.get("system") or "", "%d:%s" % (i, self.AltSystemField))
    return iris.system.Status.OK()
}

/// Time both implementations over pIterations passes of a real HL7 message.
ClassMethod Run(pIterations As %Integer = 2000) As %Status
{
    set tRs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM EnsLib_HL7.Message ORDER BY ID DESC")
    if 'tRs.%Next() {
        write "no HL7 message in the store to test against", !
        quit $$$OK
    }
    set tMsg = ##class(EnsLib.HL7.Message).%OpenId(tRs.%GetData(1))
    if '$isobject(tMsg) { write "could not open message", ! quit $$$OK }

    set b = ..%New()
    set tCand = {"id": 4, "value": "E11.9", "system": "I10", "text": "Type 2 diabetes"}
    set tRes = {"code": "44054006", "display": "Diabetes mellitus type 2"}
    set tCandJSON = tCand.%ToJSON(), tResJSON = tRes.%ToJSON()

    ; warm both paths so neither pays first-call setup in the measurement
    do b.FindOS(tMsg), b.FindPy(tMsg)
    do b.ApplyOS(tMsg, tCand, tRes), b.ApplyPy(tMsg, tCandJSON, tResJSON)

    write "segments in test message: ", tMsg.SegCount, "   iterations: ", pIterations, !, !

    set t = $zhorolog
    for i = 1:1:pIterations { set x = b.FindOS(tMsg) }
    set tFindOS = $zhorolog - t

    set t = $zhorolog
    for i = 1:1:pIterations { set x = b.FindPy(tMsg) }
    set tFindPy = $zhorolog - t

    set t = $zhorolog
    for i = 1:1:pIterations { do b.ApplyOS(tMsg, tCand, tRes) }
    set tApplyOS = $zhorolog - t

    set t = $zhorolog
    for i = 1:1:pIterations { do b.ApplyPy(tMsg, tCandJSON, tResJSON) }
    set tApplyPy = $zhorolog - t

    do ..report("find candidates", tFindOS, tFindPy, pIterations)
    do ..report("apply result", tApplyOS, tApplyPy, pIterations)
    quit $$$OK
}

ClassMethod report(pLabel As %String, pOS As %Numeric, pPy As %Numeric, pN As %Integer) [ Internal ]
{
    write pLabel, !
    write "  objectscript: ", $justify($normalize(pOS * 1000, 1), 8), " ms   ", $justify($normalize(pOS / pN * 1000000, 1), 8), " us per call", !
    write "  python      : ", $justify($normalize(pPy * 1000, 1), 8), " ms   ", $justify($normalize(pPy / pN * 1000000, 1), 8), " us per call", !
    if pOS > 0 {
        write "  ratio       : python is ", $normalize(pPy / pOS, 2), "x the ObjectScript time", !
    }
    write !
}

}
