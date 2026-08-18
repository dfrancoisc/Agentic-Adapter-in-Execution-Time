/// The same enrichment as Demo.Process.EnrichCodes, written in Python.
///
/// Both classes do exactly the same job and are interchangeable in a production.
/// This one exists to show that the domain half — where the values are in your
/// message, and what to do with the answer — can be written entirely in Python if
/// that is what your team writes.
///
/// Two methods, both `[ Language = python ]`:
///
///   Candidates()  returns the candidate list as a JSON string
///   Apply()       receives the candidate and the tool result as JSON strings
///
/// These are the Python-friendly forms of FindCandidates() and ApplyResult(). They
/// exist because a Language=python signature cannot carry an Output parameter or
/// marshal a %DynamicObject comfortably — passing JSON strings across the boundary
/// sidesteps both problems and costs nothing.
///
/// Everything else — the MCP call, tool selection, caching, error policy, tracing —
/// is inherited and unchanged.
Class Demo.Process.EnrichCodesPython Extends Agentic.Adapter.EnrichmentProcess
{

Parameter SETTINGS = "SegmentType:Fields,CodeField:Fields,TextField:Fields,SystemField:Fields,AltCodeField:Fields,AltTextField:Fields,AltSystemField:Fields,TargetSystemLabel:Fields";

Property SegmentType As %String [ InitialExpression = "OBX" ];

Property CodeField As %String [ InitialExpression = "5.1" ];

Property TextField As %String [ InitialExpression = "5.2" ];

Property SystemField As %String [ InitialExpression = "5.3" ];

Property AltCodeField As %String [ InitialExpression = "5.4" ];

Property AltTextField As %String [ InitialExpression = "5.5" ];

Property AltSystemField As %String [ InitialExpression = "5.6" ];

Property TargetSystemLabel As %String [ InitialExpression = "SCT" ];

/// Where the codes live, in Python.
///
/// The HL7 message arrives as an object proxy, so its methods are called exactly as
/// they would be from ObjectScript: SegCount, GetSegmentAt, GetValueAt.
Method Candidates(pMessage As %Persistent) As %String [ Language = python ]
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

/// What to do with the answer, in Python.
///
/// The translated code goes into the primary CWE triplet and the original into the
/// alternate, so a receiver that does not speak the target terminology can still
/// read what was sent.
Method Apply(pMessage As %Persistent, pCandidateJSON As %String, pResultJSON As %String) As %Status [ Language = python ]
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
    # a blank TargetSystemLabel means the coding system does not change - the case
    # when a code is being validated rather than translated
    if self.TargetSystemLabel:
        pMessage.SetValueAt(self.TargetSystemLabel, "%d:%s" % (i, self.SystemField))

    pMessage.SetValueAt(candidate.get("value") or "", "%d:%s" % (i, self.AltCodeField))
    pMessage.SetValueAt(candidate.get("text") or "", "%d:%s" % (i, self.AltTextField))
    pMessage.SetValueAt(candidate.get("system") or "", "%d:%s" % (i, self.AltSystemField))

    # Embedded Python has no self.LOGINFO - that is a PEX method. The Event Log is
    # reached through Ens.Util.Log, which is what the $$$LOGINFO macro expands to.
    iris.cls("Ens.Util.Log").LogInfo(
        "Demo.Process.EnrichCodesPython", "Apply",
        "enriched %s %d: %s (%s) -> %s" % (
            self.SegmentType, i, candidate.get("value"),
            candidate.get("system"), new_code))

    return iris.system.Status.OK()
}

}
