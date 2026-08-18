# Walkthrough — configuring a production that uses the MCP adapter

*Production level features — invoke agents or MCP servers while exchanging data, on
interface execution time.*

From an empty namespace to a working, traced MCP tool call.

Assumes the adapter is already installed on the instance — see the Install section
of the [README](../README.md). Check with:

```
do ##class(Agentic.Install).Verify()
```

Every namespace should report `adapter visible`.

---

## Step 1 — Open the production configuration page

Management Portal → **Interoperability**.

If the namespace selector at the top is not on the namespace you want, switch it
now. Interoperability pages are per-namespace and it is easy to build a production
in the wrong one.

Then **Configure → Production**.

If the namespace has never had a production, the page opens empty.

---

## Step 2 — Create the production

Click **New** in the toolbar.

| Field | Value |
|---|---|
| Package Name | `Demo` |
| Production Name | `MCPProduction` |
| Description | anything |

Click **OK**.

This generates a class, `Demo.MCPProduction`, extending `Ens.Production`. That class
is the production — the portal is an editor for it. Everything you configure from
here is stored in its `XData ProductionDefinition` block, which is why a production
can be exported, diffed and put in source control.

---

## Step 3 — Turn on testing

With the production selected (not an item), open the **Settings** tab on the right.

Tick **Testing Enabled**, then **Apply**.

This is what makes the Test button available on business hosts. Without it, testing
fails with `Business dispatch name 'EnsLib.Testing.Service' is not registered to run`.

Turn it off before the production goes anywhere near live traffic.

---

## Step 4 — Add the business operation

### Which host type is the adapter?

**An Operation. An Outbound Host.** Not a service, and not a business process.

This matters in the new Production Configuration UI, where Create asks you to pick a
host category first, and picking Process leads to a **Process Type** dropdown —
General, HL7, X12, Component. None of those apply here. That dropdown chooses what
kind of business process to *generate*; it is not asking which class you have.

Verified against the API the new UI calls: `hostType` takes `Service`, `Process` or
`Operation`, and

```
GetHostSettings(ns, production, "Operation", "Agentic.Adapter.Operation", "")
```

returns the adapter's full settings list, with the class documentation as help text.

| You are creating | Host category | Type |
|---|---|---|
| The MCP adapter itself | **Outbound Host** | class `Agentic.Adapter.Operation` |
| A process that calls it | Process Host | `General`, or `HL7` for an HL7 router |
| Something feeding the interface | Inbound Host | per your source |

### New Production Configuration UI

1. Click the caret next to **Create** and choose the **Outbound Host** option — or
   use the **+** in the **Outbound Hosts** column.
2. Class: `Agentic.Adapter.Operation`
3. Name: `SnomedMCP`
4. **Create**, then configure it in the **Host Configuration** panel on the right.

### Standard UI

In the **Operations** column, click **+**.

| Field | Value |
|---|---|
| Operation Class | `Agentic.Adapter.Operation` |
| Operation Name | `SnomedMCP` |
| Enable Now | ticked |

Click **OK**.

The operation name is the address other components use. A BPL `<call>` or a routing
rule `<send>` targets `SnomedMCP`, not the class name — so name it after the job it
does, not the technology.

---

## Step 5 — Configure the adapter

Select `SnomedMCP`, then the **Settings** tab on the right. The adapter settings
appear in groups.

### Where the server is

| Setting | Example | Notes |
|---|---|---|
| `ServerURL` | `https://terminology.internal/mcp` | The whole address, pasted from the vendor's documentation |

That is the only connection setting most people need. It fills in `HTTPServer`,
`HTTPPort` and `URL` for you and selects the default TLS configuration for an
`https` address. Set those three by hand only if you need finer control.

### Security

| Setting | Example | Notes |
|---|---|---|
| `SSLConfig` | `default` | Required for https. Create under System Administration → Security → SSL/TLS Configurations |
| `SSLCheckServerIdentity` | ticked | Leave on unless you have a reason |
| `Credentials` | `TerminologyMCP` | Create under Interoperability → Configure → Credentials. For a token, put it in the Password field |
| `AuthType` | `bearer` | `none`, `basic`, `bearer`, `header`, `oauth2` |

For OAuth 2, set `AuthType` to `oauth2` and fill `OAuth2ApplicationName`,
`OAuth2GrantType` and `OAuth2Scope` instead of `Credentials`. Token acquisition and
refresh are handled by the platform.

### Which tools it may call

| Setting | Example | Notes |
|---|---|---|
| `ToolName` | `translate_code` | Used when the caller does not name a tool |
| `AllowedTools` | leave blank | Blank allows every tool the server offers |
| `ResultPath` | `structuredContent.code` | Dotted path into the result, so callers get a scalar |

Leave `AllowedTools` blank. You do not know a server's tool names before you call it,
and finding out is what the server is for. Fill it in only when you already know a
catalogue and want this interface restricted — plain tool names, comma separated,
with `*` as a wildcard. Not regular expressions.

### What happens when it fails

| Setting | Example | Notes |
|---|---|---|
| `OnErrorAction` | `fail` | `fail`, `passthrough`, or `default` |
| `DefaultValue` | | Returned when `OnErrorAction` is `default` |
| `ResponseTimeout` | `30` | Inherited. Keep below the caller's own timeout |

Click **Apply**.

---

## Step 6 — Start the production

Click **Start**. The operation should go green.

If it does not, Interoperability → View → **Event Log** will say why. A red operation
at this point is almost always the endpoint or the TLS configuration.

---

## Step 7 — Test it before wiring anything to it

Select `SnomedMCP` → **Actions** tab → **Test**.

Request class: `Agentic.Adapter.Msg.ToolRequest`. Fill in:

| Property | Value |
|---|---|
| `ArgumentsJSON` | `{"code": "E11.9"}` |
| `ToolName` | leave blank to use the configured tool |
| `ResultPath` | leave blank to use the configured path |

Click **Invoke Testing Service**.

The response shows `ResultJSON` with the extracted value, plus `IsError`,
`DurationMs` and `ToolName`.

Same thing from a terminal, if you prefer:

```
set sc=##class(Ens.Director).CreateBusinessService("EnsLib.Testing.Service",.svc)
set r=##class(Agentic.Adapter.Msg.ToolRequest).%New()
set r.ArgumentsJSON="{""code"":""E11.9""}"
set sc=svc.SendRequestSync("SnomedMCP",r,.resp)
write resp.ResultJSON
```

Verified output against the bundled mock server:

```
result=44054006  isError=0  ms=45
```

---

## Step 8 — Look at the trace

Interoperability → View → **Message Viewer**, then open the message and click
**Trace**.

The request and response are ordinary production messages. That is the point of
doing this in the adapter rather than in code: the call to the external service is
as visible, as searchable and as replayable as every other hop in the interface.

---

## Step 9 — Call it from your interface

From a BPL business process, add a `<call>` targeting `SnomedMCP` with a
`ToolRequest` as the request message. From a routing rule, `<send>` to it.

To use a different tool or pull a different field on a given call, set `ToolName` or
`ResultPath` on the request — they override the configured defaults for that call
only, and `AllowedTools` still applies.

---

## Trying it with no real MCP server

`tests/mock_mcp_server.py` is a dependency-free mock exposing `translate_code` and
`echo`. Run it where IRIS can reach it:

```
python3 tests/mock_mcp_server.py
```

It listens on `127.0.0.1:8765`. Use `HTTPServer` `127.0.0.1`, `HTTPPort` `8765`,
`URL` `/`, no TLS, no credential.

`examples/Demo/MCPProduction.cls` is that exact production, ready to load:

```
do $system.OBJ.Load("examples/Demo/MCPProduction.cls","ck")
do ##class(Ens.Director).StartProduction("Demo.MCPProduction")
```

---

## When it does not work

| Symptom | Cause |
|---|---|
| Create asks for a Process Type (General / HL7 / X12 / Component) | You are creating a business process. The adapter is an Outbound Host — see step 4 |
| The adapter class does not appear in the class list | You are in the wrong host category. It only appears under Operation / Outbound Host |
| `Business dispatch name 'EnsLib.Testing.Service' is not registered to run` | Testing Enabled is off — step 3 |
| `<CLASS DOES NOT EXIST>` on start | The production class was not created or not compiled. A production is a class, not just a configuration row |
| Operation red on start | Endpoint unreachable, or `SSLConfig` missing for an https endpoint |
| `tool not permitted by AllowedTools` | You set an allow-list that excludes it. Blank allows everything |
| Empty result, no error | `ResultPath` does not match the response shape. Blank it to see the whole result, then narrow |
| `IsError = 1` but the message succeeded | Correct behaviour. The tool ran and reported failure — a business outcome, not a broken interface |
