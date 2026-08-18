# Calling an MCP server from a DTL — step by step

One page, current, verified end to end in one sitting. Every output below is real.

If you want the reasoning behind the design, or the things I got wrong on the way
here, that is in [DTL_INLINE_CALLS.md](DTL_INLINE_CALLS.md). This page is only the
instructions.

---

## What you are building

A transformation that takes the ICD-10 code in OBX-5.1 and replaces the description
in OBX-5.2 with what the terminology server says that code actually means.

```
IN   OBX-5:  E11.9^DIABETES TYPE II^I10
OUT  OBX-5:  E11.9^Diabetes mellitus type 2^I10
```

No business process. No custom MCP client. One `<assign>`.

## Before you start

- The module installed — see the README. It provides `Agentic.Adapter.Functions`.
- An interoperability-enabled namespace. A DTL is itself an interoperability
  artifact, so this is a given if you are writing one.
- An MCP server you can reach. `tests/mock_mcp_server.py` will do for a trial.

---

## Step 1 — Add an MCP item to a production

The item holds the server address, TLS configuration and credential. The
transformation will name it, so nothing about the server appears in the DTL.

Management Portal → Interoperability → Configure → Production → **+** on Outbound
Hosts:

| Field | Value |
|---|---|
| Operation Class | `Agentic.Adapter.Operation` |
| Operation Name | `TxLookup` |

Then on its settings:

| Setting | Value | Notes |
|---|---|---|
| `ServerURL` | `http://127.0.0.1:8765/` | The whole address. For a real server, `https://terminology.example.com/mcp` |
| `SSLConfig` | your TLS configuration | Required for `https`. Blank for `http` |
| `Credentials` | your credential entry | Only if the server needs authentication |
| `AuthType` | `bearer` | Or `basic`. Leave `none` if unauthenticated |

Apply, and start the production.

Confirm the item resolves:

```objectscript
write ##class(Ens.Director).GetAdapterSettingValue("TxLookup","ServerURL")
```

```
http://127.0.0.1:8765/
```

## Step 2 — Find out what the server offers

You need a tool name and its result shape before you can write the assign.

```objectscript
set sc=##class(Ens.Director).CreateBusinessService("EnsLib.Testing.Service",.svc)
set r=##class(Agentic.Adapter.Msg.ToolRequest).%New()
set r.Action="list"
set sc=svc.SendRequestSync("TxLookup",r,.resp)
write resp.ResultJSON
```

```json
[{"name": "translate_icd",
  "description": "Translate an ICD-10 diagnosis code to SNOMED CT.",
  "inputSchema": {"properties": {"code": {"type":"string"}}, "required": ["code"]},
  "permitted": true}, ...]
```

Two things to take from this: the tool name, `translate_icd`, and where the answer
sits in its result — here `structuredContent.display`.

## Step 3 — Write the transformation

```objectscript
Class Demo.DTL.StepByStep Extends Ens.DataTransformDTL
{

Parameter IGNOREMISSINGSOURCE = 1;

Parameter REPORTERRORS = 1;

XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='EnsLib.HL7.Message' targetClass='EnsLib.HL7.Message'
           sourceDocType='2.5:ORU_R01' targetDocType='2.5:ORU_R01'
           create='copy' language='objectscript'>

<assign action='set'
        property='target.{PIDgrpgrp(1).ORCgrp(1).OBXgrp(1).OBX:5(1).2}'
        value='##class(Agentic.Adapter.Functions).MCPLookup(
                 "TxLookup",
                 "translate_icd",
                 "code",
                 source.{PIDgrpgrp(1).ORCgrp(1).OBXgrp(1).OBX:5(1).1},
                 "structuredContent.display",
                 source.{PIDgrpgrp(1).ORCgrp(1).OBXgrp(1).OBX:5(1).2})'/>

</transform>
}

}
```

(The `value` is one line in the real class; it is wrapped here to be readable.)

Six arguments, in order. Nothing about them is terminology-specific — every one
comes from the server's own catalogue or from your message:

| Argument | Here | What it is |
|---|---|---|
| item | `"TxLookup"` | the production item — where the server, TLS and credential come from |
| tool | `"translate_icd"` | the tool name, from step 2 |
| argument | `"code"` | **the name of the tool's argument**, from its `inputSchema` in step 2. Another tool might call it `text`, `query`, `term` or `id` |
| value | `source.{...OBX:5(1).1}` | what to send as that argument |
| path | `"structuredContent.display"` | where the answer sits in the result. Defaults to `content.0.text`, which is where MCP puts a plain text answer |
| default | `source.{...OBX:5(1).2}` | what to keep if the lookup finds nothing |

The same function against three different servers and three different argument
names, all verified:

```
MCPLookup("TxLookup","translate_icd","code","E11.9","structuredContent.display")
    → Diabetes mellitus type 2

MCPLookup("TxLookup","echo","text","hello from a DTL")
    → hello from a DTL

MCPCall("https://mcp.deepwiki.com/mcp","ask_question",
        {"repoName":"...","question":"What transports are supported?"},"content.0.text")
    → The "Everything Server" ... supports three transport mechanisms: stdio, SSE ...
```

Use `MCPCall` when a tool takes more than one argument — you supply the whole
arguments object as JSON. `MCPLookup` is the shorthand for the common
one-argument case.

Four things that matter and are easy to get wrong:

- **`create='copy'`** carries the rest of the message through untouched. With
  `create='new'` you get only what you assign, and an HL7 target loses its segment
  terminator.
- **The group path.** Once a DocType is set, `{OBX:5.1}` on its own does not resolve;
  the path needs its groups. Getting this wrong fails silently — the assign writes
  nothing and the message passes through unchanged.
- **The last argument, the default.** Without it, a value the server cannot resolve
  blanks whatever was already in the field. That is data loss dressed up as
  enrichment.
- **Call it qualified**, with `##class(...)`. Bare function names do not resolve in a
  hand-authored DTL — not even the built-in `ToUpper()` does.

## Step 4 — Run it

```objectscript
set src=##class(EnsLib.HL7.Message).ImportFromFile("/tmp/step.hl7",,.sc)
do src.PokeDocType("2.5:ORU_R01")
do ##class(Demo.DTL.StepByStep).Transform(src,.tgt)
```

A code the server knows:

```
IN   E11.9^DIABETES TYPE II^I10
OUT  E11.9^Diabetes mellitus type 2^I10
```

A code it does not:

```
IN   ZZ.999^Made up code^I10
OUT  ZZ.999^Made up code^I10
```

The transformation succeeds either way. The unrecognised code keeps its original
description and a warning goes to the Event Log — an unknown code is a data quality
finding, not a broken interface.

---

## What this does and does not carry over

Verified, not assumed:

| | |
|---|---|
| TLS | **Yes** — `SSLConfig` from the item, or `default` for a bare `https` URL |
| Credentials | **Yes** — bearer or basic from the IRIS credential store |
| OAuth 2 | No — token acquisition and refresh are adapter machinery |
| Proxy settings | No |
| A traced production message | No — nothing in the Visual Trace |
| Retry, failover, alerting | No — a slow server blocks the transformation |

If the call needs to be an auditable, retryable event in its own right, or needs
OAuth 2, use a business process calling the MCP operation instead. Everything else
about the setup is the same; only the caller changes.

## Files

| | |
|---|---|
| `examples/Demo/DTL/StepByStep.cls` | the transformation above |
| `src/cls/Agentic/Adapter/Functions.cls` | `MCPLookup`, `MCPCall` |
| `tests/mock_mcp_server.py` | the server used for this walkthrough |
