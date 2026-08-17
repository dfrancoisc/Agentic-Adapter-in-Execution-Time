# Agentic MCP Adapter

A generic outbound adapter that lets any InterSystems IRIS interoperability
production call an MCP (Model Context Protocol) server.

Standalone. No dependency on any other module. Install it, add a business operation
to your production, point it at an MCP server, and call that server's tools.

Works on IRIS, IRIS for Health and Health Connect.

## What it is

The adapter is to MCP what `EnsLib.HTTP.OutboundAdapter` is to HTTP: configurable
connectivity, nothing more. It knows about MCP and nothing else — no message
formats, no domain concepts. Arguments go in as JSON, a tool result comes back as
JSON. What to call and what to do with the answer belongs to your interface.

## Step by step — from nothing to a working call

### 1. Install once, for the whole instance

The adapter is installed **once per instance**, into a shared database mapped to
every namespace. You do not install it per namespace, and namespaces created later
pick it up automatically.

If IRIS is in a container and the source is on your host, copy it in first:

```
docker cp /path/to/Agentic-Adapter-in-Execution-Time <container>:/opt/mcpadapter
```

In an IRIS session, load the installer and run it:

```
do $system.OBJ.Load("/opt/mcpadapter/setup/Agentic/Install.cls","ck")
do ##class(Agentic.Install).Setup()
```

That creates the `AGENTICLIB` database, creates the `%ALL` pseudo-namespace if the
instance does not have one, and maps the `Agentic.Adapter` package and its routines
into `%ALL`.

Then load the module, from any namespace — the mapping puts the code in the shared
database regardless of where you run it from:

```
zpm "load /opt/mcpadapter"
```

No IPM? `do $system.OBJ.ImportDir("/opt/mcpadapter/src/cls","*.cls","ck",,1)`

Confirm it is visible everywhere:

```
do ##class(Agentic.Install).Verify()
```

```
              FHIR : adapter visible
          HSCUSTOM : adapter visible
             HSLIB : adapter visible
             HSSYS : adapter visible
    HSSYSLOCALTEMP : adapter visible
             PAYER : adapter visible
              USER : adapter visible
```

Only the **code** is shared. Message data globals are deliberately not mapped, so
every namespace keeps its own message store and no production can see another's
traffic.

To reverse the mapping, `do ##class(Agentic.Install).Unmap()`. The database and its
contents are left in place.

#### Installing into one namespace only

If you would rather not touch instance-wide configuration, skip the installer and
just `zpm "load"` in the namespace you want. The adapter works exactly the same —
it is simply not visible from anywhere else.

### 2. Store the credential (skip if the server needs no auth)

Management Portal → Interoperability → Configure → **Credentials**.

Create an entry, for example `TerminologyMCP`. For a bearer token or API key, put
the token in the **Password** field; the User field can be anything. The adapter
reads the password and never exposes it as a setting.

For TLS, System Administration → Security → **SSL/TLS Configurations** — note the
configuration name, you will need it in step 4.

### 3. Add the operation to a production

Management Portal → Interoperability → Configure → **Production**.

Pick an existing production or create one. Then:

1. Click **+** next to **Operations**.
2. **Operation Class**: `Agentic.Adapter.Operation`
3. **Operation Name**: whatever the interface will call it, e.g. `SnomedMCP`
4. Click **OK**.

### 4. Configure it

Select the new operation. The settings panel on the right has three MCP groups plus
the standard HTTP ones.

Connection — where the server is:

| Setting | Example |
|---|---|
| `HTTPServer` | `terminology.internal` |
| `HTTPPort` | `443` |
| `URL` | `/mcp/terminology` |
| `SSLConfig` | your TLS configuration name (required for https) |

Security:

| Setting | Example |
|---|---|
| `Credentials` | `TerminologyMCP` |
| `AuthType` | `bearer` |

For OAuth 2, set `AuthType` to `oauth2` and fill `OAuth2ApplicationName`,
`OAuth2GrantType` and `OAuth2Scope` instead of `Credentials`.

MCP Tools:

| Setting | Example |
|---|---|
| `ToolName` | `translate_code` |
| `AllowedTools` | `^(translate_code\|lookup_display)$` |
| `ResultPath` | `structuredContent.code` |

MCP Behavior:

| Setting | Example |
|---|---|
| `OnErrorAction` | `fail` |

Click **Apply**.

`AllowedTools` matters: leave it blank and only `ToolName` can be called. That is
deliberate — an MCP server may expose tools this interface has no business invoking.

### 5. Start the production

Click **Start** in the production toolbar. The operation should show a green status.

### 6. Test it before wiring anything to it

Add `EnsLib.Testing.Service` to the production as a Service, then from a terminal in
that namespace:

```
set sc=##class(Ens.Director).CreateBusinessService("EnsLib.Testing.Service",.svc)
set r=##class(Agentic.Adapter.Msg.ToolRequest).%New()
set r.ArgumentsJSON="{""code"":""E11.9""}"
set sc=svc.SendRequestSync("SnomedMCP",r,.resp)
write resp.ResultJSON
```

Expect the extracted value, e.g. `44054006`. Then open Interoperability → View →
**Message Viewer** and you will see the request and response as traced messages.

If it fails, check Interoperability → View → **Event Log** — the adapter logs the
tool name and the error, never the payload.

### 7. Call it from your interface

From a BPL business process, use a `<call>` targeting the operation name, with a
`ToolRequest` as the request. From a routing rule, `<send>` to it. Either way it is
an ordinary production message, so it appears in the Visual Trace like everything
else.

To use a different tool or pull a different field on a given call, set `ToolName` or
`ResultPath` on the request — they override the configured defaults for that call
only.

### Trying it with no real MCP server

`tests/mock_mcp_server.py` is a dependency-free mock exposing `translate_code` and
`echo`. Run it wherever IRIS can reach it:

```
python3 tests/mock_mcp_server.py
```

It listens on `127.0.0.1:8765`, so configure `HTTPServer` `127.0.0.1`, `HTTPPort`
`8765`, `URL` `/`, no TLS and no credential. `tests/Agentic/Adapter/TestProduction.cls`
is a ready-made production wired to it.

## Classes

| Class | Purpose |
|---|---|
| `Agentic.Adapter.MCP` | The outbound adapter. Use it on any business operation |
| `Agentic.Adapter.Operation` | A ready-made generic business operation, if you do not want to write your own |
| `Agentic.Adapter.Msg.ToolRequest` | Request message: tool name, arguments JSON, optional result path |
| `Agentic.Adapter.Msg.ToolResponse` | Response message: result, isError, error text, duration |

You do not have to use `Agentic.Adapter.Operation`. Any business operation can set
`Parameter ADAPTER = "Agentic.Adapter.MCP"` and call the adapter directly.

## Settings

### Connection and security — inherited from `EnsLib.HTTP.OutboundAdapter`

`HTTPServer`, `HTTPPort`, `URL`, `SSLConfig`, `SSLCheckServerIdentity`,
`Credentials`, `ConnectTimeout`, `ResponseTimeout`, `RetriesToFailover`,
`ProxyServer`, `ProxyPort`, `ProxyHTTPS`, and the full OAuth 2 surface
(`OAuth2ApplicationName`, `OAuth2GrantType`, `OAuth2Scope`,
`OAuth2AccessTokenPlacement`, `OAuth2GrantTypeSpecific`, `OAuth2JWTSubject`).

Because these are inherited, tokens are acquired, cached and refreshed by the
platform. No secret is ever typed into a setting — secrets resolve through the IRIS
credentials store or the OAuth 2 client configuration.

### MCP settings

| Setting | Default | Purpose |
|---|---|---|
| `ProtocolVersion` | `2025-06-18` | MCP version to negotiate |
| `ClientName` | `IRIS-MCP-Adapter` | Client name sent in the handshake |
| `AuthType` | `none` | `none`, `basic`, `bearer`, `header`, `oauth2` |
| `HeaderName` | `X-API-Key` | Header to use when `AuthType` is `header` |
| `ToolName` | | Default tool, used when the caller does not name one |
| `AllowedTools` | | Regular-expression allow-list of invocable tools |
| `ResultPath` | | Dotted path into the result, so callers get a scalar |
| `OnErrorAction` | `fail` | `fail`, `passthrough`, or `default` |
| `DefaultValue` | | Returned when `OnErrorAction` is `default` |

`AllowedTools` is a security control, not a convenience. An MCP server may expose
destructive tools; a production item should be permitted only the subset it needs.
Blank means only `ToolName` may be called.

`ResultPath` turns an MCP content-block envelope into the value you actually want.
Without it every caller unwraps the envelope by hand.

## Worked example

An MCP server exposing `translate_code`, which returns
`{"code": "...", "display": "...", "system": "..."}`.

Production item settings:

```
HTTPServer     terminology.internal
HTTPPort       443
URL            /mcp/terminology
SSLConfig      default
Credentials    TerminologyMCP
AuthType       bearer
ToolName       translate_code
AllowedTools   ^(translate_code|lookup_display)$
ResultPath     structuredContent.code
OnErrorAction  fail
```

Sending a `ToolRequest` with `ArgumentsJSON = {"code": "E11.9"}` returns
`44054006`. Setting `ResultPath` to `structuredContent.display` on the request
instead returns `Diabetes mellitus type 2` from the same call.

## Error handling

Two failure modes, deliberately distinguished:

- **Transport or protocol failure** — the server is unreachable, the handshake
  fails, the response is not valid JSON. `OnErrorAction` decides: fail the message,
  return empty, or return `DefaultValue`.
- **Tool failure** — the tool ran and reported `isError`. The message does not fail.
  `ToolResponse.IsError` is set and the result is returned, because a tool saying
  "I could not translate that code" is a business outcome, not a broken interface.

## Implementation notes

The MCP protocol work is Embedded Python. The class itself is ObjectScript, because
that is what makes properties appear as Management Portal settings and what gives
the adapter its inherited security model.

One method, `Send()`, is ObjectScript by necessity: it calls `SendFormDataArray()`,
whose `Output` parameters cannot appear in a `Language = python` signature. It is
also the only method that touches the wire — everything goes through the inherited
HTTP machinery, so the security configuration is always honoured.

## Supported MCP surface

`initialize`, `notifications/initialized`, `tools/list` with pagination,
`tools/call` including `isError` and content blocks, `ping`. Streamable HTTP
transport.

Not implemented: resources, prompts, sampling, roots, server-initiated requests,
notification streams, `stdio` transport.

## Testing

`tests/` contains a minimal production fixture and a mock MCP server for exercising
the adapter without a real server.
