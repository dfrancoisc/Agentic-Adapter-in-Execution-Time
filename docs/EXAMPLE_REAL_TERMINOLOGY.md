# Real example — validating HL7 codes against a live terminology server

Everything in this example is real except the MCP server process itself, which is a
thin wrapper. The terminology answers come from **tx.fhir.org**, the public HL7 FHIR
terminology server, against real published releases:

- ICD-10
- LOINC 2.82
- SNOMED CT, January 2025 edition

The model choosing the tool is Claude Sonnet 4 on Amazon Bedrock. No credentials are
needed for the terminology server.

## The problem

A sending system puts a code in OBX-5 with whatever description it happens to hold.
Some are abbreviated, some stale, some simply wrong, and some codes do not exist at
all. Downstream systems and analytics then key off descriptions that do not match
the code.

This interface replaces the description with the official display text for that code,
preserves what was actually sent, and flags codes the terminology server does not
recognise.

## Production

```
/tmp/tx/in → HL7FileIn → ValidateCodes ⇄ TerminologyMCP → HL7FileOut → /tmp/tx/out
                              ⇅
                         ToolSelector          Bedrock picks the lookup tool
```

Load `examples/Demo/HL7Validate.cls` and start `tests/terminology_mcp_server.py`.

The MCP server exposes three tools, each a real FHIR `CodeSystem/$lookup`:
`lookup_icd10`, `lookup_loinc`, `lookup_snomed`.

## Result

Sent by the lab — sloppy descriptions, and one invalid code:

```
OBX|1|CWE|DIAG^Diagnosis^L||E11.9^DIABETES TYPE II^I10||||||F
OBX|2|CWE|LAB^Lab^L||2345-7^GLUC^LN||||||F
OBX|3|CWE|DIAG^Diagnosis^L||XX.999^Bogus code^I10||||||F
```

Written out:

```
OBX|1|CWE|DIAG^Diagnosis^L||E11.9^Type 2 diabetes mellitus : Without complications^I10^E11.9^DIABETES TYPE II^I10||||||F
OBX|2|CWE|LAB^Lab^L||2345-7^Glucose [Mass/volume] in Serum or Plasma^LN^2345-7^GLUC^LN||||||F
OBX|3|CWE|DIAG^Diagnosis^L||XX.999^Bogus code^I10||||||F
```

- `DIABETES TYPE II` became the official ICD-10 display, with what the lab sent
  preserved in the CWE alternate triplet.
- `GLUC` became the official LOINC 2.82 long common name.
- `XX.999` was left exactly as it arrived. The terminology server does not recognise
  it, so the tool returned `isError`, the process logged a data quality finding, and
  the message went on unharmed.

The coding system is not changed — nothing is being translated, only normalised, so
`TargetSystemLabel` is left blank.

Bedrock's choices, from the real catalog:

```
lookup_icd10   for I10   "the context shows an ICD-10 code that needs its official display"
lookup_loinc   for LN    "The context shows a LOINC code (system 'LN') '2345-7' that
                          needs its official display text retrieved."
```

Two model calls, one per coding system, then cached.

## What this does not do, and why

**It does not translate ICD-10 to SNOMED.** That was the original intent, and the
public terminology server cannot support it honestly:

- `ConceptMap/$translate` for ICD-10 to SNOMED returns 404 — there is no such map
  published there.
- Matching by display text does not work. Expanding SNOMED for
  "type 2 diabetes mellitus" returns `Hyperosmolar coma due to type 2 diabetes
  mellitus`, `Type 2 diabetes mellitus with ulcer`, `Arthropathy due to type 2
  diabetes mellitus`, and — fifth — `Type-casting-machine operator`. It never
  returns concept 44054006, which is the answer.

Cross-terminology mapping needs a real map: UMLS, a licensed SNOMED extension, or a
curated local ConceptMap. String similarity produces confidently wrong clinical
codes, which is worse than producing none. An earlier draft of this server did
exactly that and mapped E11.9 to "Type-casting-machine operator".

If you have a real mapping source, the interface does not change — only the MCP
server behind it does. That is the point of the adapter.

## Performance note

Slower than the mock benchmark, and honestly so. Each lookup is a real HTTPS round
trip to tx.fhir.org, and cold-start adds two Bedrock calls. Three codes in one
message took roughly a minute cold. With selections cached and the terminology server
warm, per-code cost is one external call.

For volume, cache aggressively: code-to-display is about as stable a mapping as
exists, and belongs in a local lookup table refreshed periodically rather than a
per-message call to a public server.
