# Example — HL7 in, MCP enrichment, HL7 out

A complete interface: pick up HL7 from a folder, have an MCP server translate the
coded values, write the improved message to another folder.

Verified end to end. The before and after are at the bottom.

---

## Production layout

```
/tmp/hl7in   →  HL7FileIn   →  EnrichCodes   →  HL7FileOut  →  /tmp/hl7out
                (service)      (process)  ⇅      (operation)
                                       SnomedMCP
                                       (operation + MCP adapter)
```

Four items. The important structural point is that the MCP call is a **synchronous
request from the business process to an outbound host**, not something buried inside
the process. That is what makes each translation its own message in the Visual
Trace, with its own timing, its own error, and its own retry behaviour.

| Item | Host type | Class | Role |
|---|---|---|---|
| `HL7FileIn` | Service (Inbound Host) | `EnsLib.HL7.Service.FileService` | Watches the folder, parses HL7 |
| `EnrichCodes` | Process | `Demo.Process.EnrichCodes` | Finds codes, calls MCP, writes results back |
| `SnomedMCP` | Operation (Outbound Host) | `Agentic.Adapter.Operation` | Calls the MCP server |
| `HL7FileOut` | Operation (Outbound Host) | `EnsLib.HL7.Operation.FileOperation` | Writes the enriched message |

Ready to load: `examples/Demo/HL7EnrichProduction.cls`.

---

## Settings

### HL7FileIn — `EnsLib.HL7.Service.FileService`

| Target | Setting | Value |
|---|---|---|
| Adapter | `FilePath` | `/tmp/hl7in` |
| Adapter | `FileSpec` | `*.hl7` |
| Adapter | `ArchivePath` | `/tmp/hl7archive` |
| Host | `TargetConfigNames` | `EnrichCodes` |
| Host | `MessageSchemaCategory` | `2.5` |

`ArchivePath` moves the consumed file aside with a timestamp rather than deleting
it, which matters the first few times you run this.

### EnrichCodes — `Demo.Process.EnrichCodes`

| Setting | Value | Notes |
|---|---|---|
| `MCPTarget` | `SnomedMCP` | Config name of the MCP item |
| `OutputTarget` | `HL7FileOut` | Where the enriched message goes |
| `SegmentType` | `OBX` | Segment to scan. `DG1` for diagnoses in an ADT |
| `CodeField` / `TextField` / `SystemField` | `5.1` / `5.2` / `5.3` | Primary triplet |
| `AltCodeField` / `AltTextField` / `AltSystemField` | `5.4` / `5.5` / `5.6` | Alternate triplet |
| `TargetSystemLabel` | `SCT` | Written into the coding system field |

### SnomedMCP — `Agentic.Adapter.Operation`

| Target | Setting | Value |
|---|---|---|
| Adapter | `HTTPServer` | `127.0.0.1` (the mock) or your terminology host |
| Adapter | `HTTPPort` | `8765` or `443` |
| Adapter | `URL` | `/` or `/mcp/terminology` |
| Adapter | `ToolName` | `translate_code` |
| Adapter | `AllowedTools` | `^translate_code$` |
| Adapter | `OnErrorAction` | `fail` |

For a real server add `SSLConfig`, `Credentials` and `AuthType`.

### HL7FileOut — `EnsLib.HL7.Operation.FileOperation`

| Target | Setting | Value |
|---|---|---|
| Adapter | `FilePath` | `/tmp/hl7out` |
| Host | `Filename` | `enriched_%f_%Q.hl7` |

---

## How the result gets back into the message

This is the part that is easy to get wrong.

**Work on a copy.** The process clones the inbound message with
`%ConstructClone(1)` and edits the clone. The message that arrived is part of the
audit trail; the trace has to show what was actually received, not a mutated
version of it.

**Preserve the original code.** The translated code goes into the primary triplet
and the original is moved into the alternate triplet. That is exactly what the HL7
CWE datatype is for, and it means a downstream system that does not speak SNOMED can
still read what was originally sent. Overwriting the source code destroys
information and is very hard to unpick later.

**Ask for the object, not a scalar.** The process sets `ResultPath` to
`structuredContent` on the request, because it needs both the code and its
description. Leaving `ResultPath` configured as a single scalar on the adapter is
right when a caller wants one value; overriding it per call is right when it wants
several.

**A tool that cannot translate is not a broken interface.** If the MCP server
returns `isError`, the process logs a warning and leaves that code untouched rather
than failing the message. A code the terminology server does not recognize is a data
quality finding, not an outage.

---

## Run it

Create the folders, in the container or on the host running IRIS:

```
mkdir -p /tmp/hl7in /tmp/hl7out /tmp/hl7archive
```

Start the mock MCP server, if you do not have a real one:

```
python3 tests/mock_mcp_server.py
```

Load and start:

```
do $system.OBJ.Load("examples/Demo/Process/EnrichCodes.cls","ck")
do $system.OBJ.Load("examples/Demo/HL7EnrichProduction.cls","ck")
do ##class(Ens.Director).StartProduction("Demo.HL7EnrichProduction")
```

Drop a message into `/tmp/hl7in` and watch `/tmp/hl7out`.

---

## Verified result

Input:

```
MSH|^~\&|LAB|HOSP|EMR|HOSP|20260817120000||ORU^R01|MSG0001|P|2.5
PID|1||123456^^^HOSP^MR||DOE^JOHN||19700101|M
OBR|1|ORD123|FILL456|PANEL^Diagnosis Panel^L
OBX|1|CWE|DIAG^Diagnosis^L||E11.9^Type 2 diabetes mellitus without complications^I10||||||F
```

Output:

```
MSH|^~\&|LAB|HOSP|EMR|HOSP|20260817120000||ORU^R01|MSG0001|P|2.5
PID|1||123456^^^HOSP^MR||DOE^JOHN||19700101|M
OBR|1|ORD123|FILL456|PANEL^Diagnosis Panel^L
OBX|1|CWE|DIAG^Diagnosis^L||44054006^Diabetes mellitus type 2^SCT^E11.9^Type 2 diabetes mellitus without complications^I10||||||F
```

OBX-5 went from

```
E11.9 ^ Type 2 diabetes mellitus without complications ^ I10
```

to

```
44054006 ^ Diabetes mellitus type 2 ^ SCT ^ E11.9 ^ Type 2 diabetes mellitus without complications ^ I10
```

SNOMED in the primary triplet, ICD-10 preserved in the alternate. The consumed file
is archived with a timestamp, and the whole exchange — inbound message, MCP request,
MCP response, outbound message — is in the Message Viewer.

---

## Adapting it

Nothing in `Demo.Process.EnrichCodes` is specific to SNOMED or terminology. The
segment and field paths are settings and the MCP item decides which server and tool
are called. Point `MCPTarget` at a different MCP item and the same process enriches
something else — units, identifiers, a mapping lookup.

For a mapping-assistance flow rather than field enrichment, keep the same shape but
send the segment or the whole message as the tool argument and use the answer to
drive a transformation instead of writing single fields back.
