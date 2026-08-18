# Writing the enrichment process

*Production level feature — the extendable enrichment process.*

The adapter handles MCP. The base class handles orchestration. What is left for you
is the only part nobody else can write: where the values are in *your* message, and
what to do with the answer.

Two methods. Two versions of the same class are shipped — one in ObjectScript, one
in Python — and they are interchangeable in a production.

| | Class | Methods you write |
|---|---|---|
| ObjectScript | `Demo.Process.EnrichCodes` | `FindCandidates()`, `ApplyResult()` |
| Python | `Demo.Process.EnrichCodesPython` | `Candidates()`, `Apply()` |

Both produce identical output. Pick whichever your team writes.

## The contract

Your job is to produce a list of candidates, and later to write results back.

A candidate is a plain object:

```json
{"id":     4,                        anything you need to find it again
 "value":  "E11.9",                  the value to be worked on
 "system": "I10",                    discriminator for rule and model selection
 "text":   "Type 2 diabetes..."}     optional context
```

`id` is yours — a segment index here, a FHIR path or an X12 loop reference
elsewhere. The base class never looks inside it. It never touches your message at
all, which is why the same base works for HL7, FHIR, X12 or a custom class.

---

## ObjectScript version

```objectscript
Class Demo.Process.EnrichCodes Extends Agentic.Adapter.EnrichmentProcess
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
    ; blank TargetSystemLabel means the coding system does not change - the case
    ; when a code is being validated and normalised rather than translated
    if ..TargetSystemLabel '= "" {
        do pMessage.SetValueAt(..TargetSystemLabel, i_":"_..SystemField)
    }

    do pMessage.SetValueAt(pCandidate.value, i_":"_..AltCodeField)
    do pMessage.SetValueAt(pCandidate.text, i_":"_..AltTextField)
    do pMessage.SetValueAt(pCandidate.system, i_":"_..AltSystemField)

    $$$LOGINFO("enriched "_..SegmentType_" "_i_": "_pCandidate.value_" -> "_tNewCode)
    quit $$$OK
}

}
```

---

## Python version

Same class, same settings, same result. Only the two method bodies change.

```objectscript
Class Demo.Process.EnrichCodesPython Extends Agentic.Adapter.EnrichmentProcess
{

/// Where the codes live, in Python.
/// The HL7 message arrives as an object proxy, so its methods are called exactly
/// as they would be from ObjectScript: SegCount, GetSegmentAt, GetValueAt.
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
    if self.TargetSystemLabel:
        pMessage.SetValueAt(self.TargetSystemLabel, "%d:%s" % (i, self.SystemField))

    pMessage.SetValueAt(candidate.get("value") or "", "%d:%s" % (i, self.AltCodeField))
    pMessage.SetValueAt(candidate.get("text") or "", "%d:%s" % (i, self.AltTextField))
    pMessage.SetValueAt(candidate.get("system") or "", "%d:%s" % (i, self.AltSystemField))

    iris.cls("Ens.Util.Log").LogInfo(
        "Demo.Process.EnrichCodesPython", "Apply",
        "enriched %s %d: %s -> %s" % (self.SegmentType, i,
                                      candidate.get("value"), new_code))

    return iris.system.Status.OK()
}

}
```

### Why Python uses different method names

`FindCandidates()` carries an `Output` parameter and `ApplyResult()` takes
`%DynamicObject` arguments. Neither is comfortable in Embedded Python: a
`Language = python` signature cannot declare an `Output` parameter at all, and
dynamic objects do not marshal cleanly across the boundary.

So the base class offers a second pair with the awkward parts removed —
`Candidates()` returns a JSON string, and `Apply()` receives JSON strings. Python
reads both with `json.loads` and returns with `json.dumps`. The default
implementations of `FindCandidates()` and `ApplyResult()` simply delegate to them,
so overriding either pair works and neither costs anything.

### Things that catch people out in Embedded Python

- **`self.LOGINFO()` does not exist.** That is a PEX method. Embedded Python reaches
  the Event Log through `iris.cls("Ens.Util.Log").LogInfo(class, method, text)`,
  which is what the `$$$LOGINFO` macro expands to. This cost a failed run to find.
- **Return a real `%Status`** with `iris.system.Status.OK()`, not `1` or `True`.
- **Settings are read as plain attributes** — `self.SegmentType` — because the class
  is still an IRIS class and they are still its properties.
- **The message is a proxy object.** Call its methods exactly as ObjectScript does;
  `SegCount` is a property, `GetValueAt` and `SetValueAt` are methods.
- **`%` becomes `_`** in Python identifiers: `%New()` is `_New()`.

---

## Verified

Both classes were run through their own productions against the same input.

Input:

```
OBX|1|CWE|DIAG^Diagnosis^L||E11.9^Type 2 diabetes mellitus without complications^I10||||||F
OBX|2|CWE|LAB^Lab^L||2345-7^Glucose measurement^LN||||||F
```

Output, identical from both:

```
OBX|1|CWE|DIAG^Diagnosis^L||44054006^Diabetes mellitus type 2^SCT^E11.9^Type 2 diabetes mellitus without complications^I10||||||F
OBX|2|CWE|LAB^Lab^L||33747003^Glucose measurement^SCT^2345-7^Glucose measurement^LN||||||F
```

Productions: `Demo.HL7Enrich` (ObjectScript) and `Demo.HL7EnrichPython` (Python).
Both used model-based tool selection against Bedrock, which chose `translate_icd`
for the ICD-10 code and `translate_loinc` for the LOINC code.
