# Technical Specification — Agentic Adapter in Execution Time

Companion to [PRD.md](PRD.md). This document covers the how; the PRD covers the why.

Verified against IRIS for Health 2026.2.0AI. Statements below marked "verified" were
checked in a running instance, not inferred from documentation.

---

## 1. Architecture

```
   Business Process / BPL / Router
              │  ToolRequest  (production message)
              ▼
   ┌────────────────────────────────┐
   │ Agentic.Adapter.Operation      │   generic business operation
   │   Parameter ADAPTER = ...      │
   └───────────────┬────────────────┘
                   │ ..Adapter.CallTool(tool, argsJSON, path)
                   ▼
   ┌────────────────────────────────────────────────┐
   │ Agentic.Adapter.MCP                            │
   │   Extends EnsLib.HTTP.OutboundAdapter          │
   │                                                │
   │   Python: handshake, JSON-RPC, tools/list,     │
   │           tools/call, filtering, extraction    │
   │   ObjectScript: Send()  ← only wire access     │
   └───────────────┬────────────────────────────────┘
                   │ inherited HTTP machinery
                   │ (TLS, credentials, OAuth 2, proxy, timeouts)
                   ▼
              MCP server  (Streamable HTTP, JSON-RPC 2.0)
```

---

## 2. Why this class tree

Verified property origins:

| Setting | Originates on |
|---|---|
| `SSLConfig`, `SSLCheckServerIdentity`, `OAuth2GrantType`, `OAuth2AccessTokenPlacement`, `ProxyServer`, `ProxyPort`, `ProxyHTTPS`, `ProxyHttpTunnel`, `ConnectTimeout`, `ResponseTimeout`, `WriteTimeout`, `RetriesToFailover`, `ExtraHeaders`, `LocalInterface` | `EnsLib.HTTP.OutboundAdapter` |
| `OAuth2ApplicationName`, `OAuth2Scope`, `OAuth2GrantTypeSpecific`, `OAuth2JWTSubject`, `OAuth2AuthProperties`, `OAuth2SessionId`, `OAuth2CallBackHandler`, `OAuth2AuthorizationWorkFlowRole` | `Ens.Util.OAuth2.Settings` mixin |
| `Credentials`, `%CredentialsObj`, `KeepaliveInterval`, `BusinessHost` | `Ens.OutboundAdapter` |

Extending `EnsLib.HTTP.OutboundAdapter` inherits the entire security surface,
including OAuth 2 token acquisition, caching and refresh. The alternative considered
was a PEX Python adapter; `EnsLib.PEX.OutboundAdapter` extends only
`Ens.OutboundAdapter`, so every row of the first two blocks above would have been
code to write and test, plus an external language server process to supervise.

**Load-bearing constraint.** Every request must go through the inherited HTTP
machinery. If the Python layer opened its own socket — with `httpx`, `requests`, or
the MCP SDK — the TLS configuration, credentials, OAuth 2 and proxy settings would be
silently bypassed while still appearing configured in the portal. That failure mode
is invisible until an audit. This is why the language boundary sits exactly at the
HTTP request and response, and why `Send()` is the single point of wire access.

---

## 3. Language split

The adapter is written in Python. The class declaration is ObjectScript, because
that is what projects properties as Management Portal settings; an IRIS class
declaration cannot be expressed in Python at all.

Verified: a class extending `EnsLib.HTTP.OutboundAdapter` with `[ Language = python ]`
method bodies compiles and runs. Python reads settings through `self.<Property>` and
returns a `%Status` via `iris.system.Status.OK()`.

Verified: no outbound adapter callback uses `ByRef` or `Output` — `OnInit` and
`OnTearDown` take no parameters, `OnKeepalive` takes a plain `%Status`. The
constraint that forces ObjectScript callbacks applies to business *host* callbacks
such as `OnMessage(request, Output response)`, not to adapters.

One method is ObjectScript by necessity:

```objectscript
Method Send(pBody As %String) As %String [ Internal ]
```

It calls `SendFormDataArray(Output pHttpResponse, pOp, pHttpRequestIn, ...)`, whose
`Output` parameters cannot appear in a `Language = python` signature. It returns the
response body as a return value and stashes diagnostics in `LastHttpCode` and
`LastError`, so Python reads them off the instance rather than needing output
parameters.

---

## 4. Classes

Grouped by the level at which the call is made.

### Production level features

Invoke agents or MCP servers while exchanging data — on interface execution time.

| Class | Type | Feature | Purpose |
|---|---|---|---|
| `Agentic.Adapter.MCP` | Outbound adapter | MCP connectivity | Connection, security, protocol, filtering, extraction |
| `Agentic.Adapter.Operation` | Business operation | MCP connectivity | Optional ready-made host. Any operation may use the adapter instead |
| `Agentic.Adapter.Msg.ToolRequest` | `Ens.Request` | MCP connectivity | `Action`, `ToolName`, `ArgumentsJSON`, `ResultPath` |
| `Agentic.Adapter.Msg.ToolResponse` | `Ens.Response` | MCP connectivity | `ResultJSON`, `IsError`, `ErrorText`, `DurationMs`, `ToolName` |
| `Agentic.Adapter.LLM` | Outbound adapter | Model-chosen tools | Model provider: bedrock, anthropic, openai, custom |
| `Agentic.Adapter.SelectorOperation` | Business operation | Model-chosen tools | Model-based tool selection, with caching |
| `Agentic.Adapter.Msg.SelectRequest` | `Ens.Request` | Model-chosen tools | `Goal`, `CatalogJSON`, `ContextJSON`, `CacheKey` |
| `Agentic.Adapter.Msg.SelectResponse` | `Ens.Response` | Model-chosen tools | `ToolName`, `ArgumentsJSON`, `Reason`, `FromCache`, token counts |
| `Agentic.Adapter.EnrichmentProcess` | Business process, abstract | Enrichment process | Orchestration: catalog, selection, invocation, error policy |

### Transformation level features

Invoke agents or MCP servers while transforming data or applying rules — on data
execution time.

| Class | Type | Purpose |
|---|---|---|
| `Agentic.Adapter.Functions` | `Ens.Rule.FunctionSet` | `MCPCall` and `MCPLookup`, callable from a DTL or a rule condition. Resolves endpoint, TLS configuration and credential from a named production item |

### Shared

| Class | Type | Purpose |
|---|---|---|
| `Agentic.Adapter.Protocol` | Registered object | The MCP wire protocol with no transport: envelope, SSE unwrapping, JSON-RPC decoding, result-path extraction. Used by both levels so they cannot drift |
| `Agentic.Adapter.ContextSearch` | Registered object | Dropdown providers for settings |
| `Agentic.Install` | Registered object | Shared-database installer. Not mapped |

Message classes are deliberately flat scalars: format-agnostic, cheap to persist, and
readable in the Visual Trace without a viewer.

### Adapter API

| Method | Returns | Notes |
|---|---|---|
| `CallTool(tool, argsJSON, path)` | Extracted result | Blank `tool` uses `ToolName`; blank `path` uses `ResultPath` |
| `ListTools()` | JSON array | Paginated via `nextCursor`. Returns the FULL catalogue, each entry annotated `permitted` — filtering here would hide what you are missing |
| `DescribeTool(tool)` | JSON | One tool's input schema |
| `Handshake()` | JSON | `initialize` then `notifications/initialized` |
| `TestConnection()` | `%Status` | Handshake only, for a health check |

Private: `rpc()`, `permitted()`, `extract()`, `onError()`, `secret()`, `Send()`.

Note on cross-language calls: Embedded Python maps a leading `_` to `%`, so a
private ObjectScript method named `rpc` is called from Python as `self.rpc(...)`,
not `self._rpc(...)`.

### Functions API

The transformation level surface, in `Agentic.Adapter.Functions`.

| Method | Returns | Notes |
|---|---|---|
| `MCPCall(item, tool, argumentsJSON, resultPath, default)` | Extracted result, or `default` | Arbitrary arguments, supplied as a JSON object |
| `MCPLookup(item, tool, argument, value, resultPath, default)` | Extracted result, or `default` | Shorthand for a single named argument. `argument` is the argument's NAME, from the tool's `inputSchema` |

`item` is the name of a production item configured with `Agentic.Adapter.MCP`, or a
literal `http`/`https` URL. From the item it reads `ServerURL` (falling back to
`HTTPServer`/`HTTPPort`/`URL`), `SSLConfig`, `Credentials` and `AuthType` via
`Ens.Director.GetAdapterSettingValue()`, so a transformation names a server and never
carries an address, a certificate reference or a secret. The item does not have to be
enabled.

`resultPath` defaults to `content.0.text`, where MCP puts a plain text answer.

Neither raises. An exception escaping a DTL fails the whole transformation, and a
value a server cannot resolve is a data quality finding rather than a broken
interface — so failures go to the Event Log and `default` is returned. When assigning
back over a field, pass the field's existing value as `default`; without it a failed
lookup blanks what was already there.

Transport is `%Net.HttpRequest` rather than the adapter, because an
`EnsLib.HTTP.OutboundAdapter` subclass cannot be instantiated outside a running
business host. Everything above the socket comes from `Agentic.Adapter.Protocol`, so
the two levels cannot diverge. What this does *not* inherit: OAuth 2, proxy settings,
a traced message, retry and failover.

---

## 5. Settings

### Inherited

`HTTPServer`, `HTTPPort`, `URL`, `SSLConfig`, `SSLCheckServerIdentity`,
`Credentials`, `ConnectTimeout`, `ResponseTimeout`, `RetriesToFailover`, the proxy
settings, and the full OAuth 2 surface. Configured exactly as on any HTTP adapter.

`ServerURL` is the setting an interface engineer actually uses; it expands into
`HTTPServer`, `HTTPPort` and `URL` at host start and selects the default TLS
configuration for an `https` address. The three inherited fields remain available for
cases needing finer control, and are left blank otherwise.

### Added

| Setting | Default | Purpose |
|---|---|---|
| `ServerURL` | | The server address as a URL. Expanded into `HTTPServer`, `HTTPPort` and `URL` at host start, selecting the default TLS configuration for `https` |
| `ProtocolVersion` | `2025-06-18` | Negotiated MCP version, sent as `MCP-Protocol-Version` |
| `ClientName` | `IRIS-MCP-Adapter` | Reported in the handshake |
| `AuthType` | `none` | `none`, `basic`, `bearer`, `header`, `oauth2` |
| `HeaderName` | `X-API-Key` | Header used when `AuthType` is `header` |
| `ToolName` | | Default tool |
| `AllowedTools` | | Blank allows every tool the server offers. Otherwise plain tool names, comma separated, `*` wildcard |
| `ResultPath` | | Dotted path into the result |
| `OnErrorAction` | `fail` | `fail`, `passthrough`, `default` |
| `DefaultValue` | | Returned under `OnErrorAction = default` |

`basic` and `oauth2` are handled entirely by the inherited machinery. `bearer` and
`header` are applied in `Send()` from the configured credential's password, resolved
through `Ens.Config.Credentials.GetCredentialsObj()` — never from a setting value.

`AllowedTools` is allow-by-default: blank permits every tool the server offers,
which is correct because a catalogue is not known before it is fetched. When set, it
is a comma separated list of plain tool names with `*` as a wildcard — not a regular
expression, because the person configuring a production should not have to write one.

Settings for `Agentic.Adapter.LLM`, `Agentic.Adapter.SelectorOperation` and
`Agentic.Adapter.EnrichmentProcess` are listed in the README's settings reference and
are not repeated here.

---

## 6. Protocol scope

Implemented: `initialize`, `notifications/initialized`, `tools/list` with `nextCursor`
pagination, `tools/call` including `isError` and content blocks, `ping`. Session
identity carried in `Mcp-Session-Id`, captured from the initialize response and sent
on every subsequent request for the life of the host job.

`Accept: application/json, text/event-stream` is sent, as the specification requires
of clients, and a JSON-RPC payload is unwrapped from SSE data lines when a server
answers that way. This is not theoretical: of three public MCP servers tested, two
replied with `text/event-stream` even to a request asking for JSON.

Not implemented: resources, prompts, sampling, roots, server-initiated requests,
notification streams, `stdio` transport.

---

## 7. Error model

Two failure classes, deliberately distinguished, because conflating them produces
either dropped clinical data or false alarms.

| Class | Cause | Behaviour |
|---|---|---|
| Transport / protocol | Unreachable server, failed handshake, non-JSON response, JSON-RPC `error`, tool not permitted | `OnErrorAction` applies: raise and fail the message, return empty, or return `DefaultValue` |
| Tool failure | Tool ran and returned `isError` | Message does **not** fail. `ToolResponse.IsError` set, result returned, warning logged |

A tool reporting "I cannot translate that code" is a business outcome. Failing the
message for it would be wrong.

---

## 8. Verification

Executed against a mock MCP server through a running production:

| Case | Result |
|---|---|
| Configured tool, `ResultPath = structuredContent.code` | `44054006`, 30 ms |
| Per-call `ResultPath` override to `structuredContent.display` | `Diabetes mellitus type 2` |
| Named tool `echo`, `ResultPath = content.0.text` | `hello from IRIS` |
| Tool outside `AllowedTools` | Message failed: `tool not permitted by AllowedTools: drop_database` |
| Tool returning `isError` | `IsError = 1`, message did not fail |

Fixtures in `tests/`: a production definition and a dependency-free mock MCP server.

---

## 9. Known issues and deferred work

**Standalone instantiation fails.** An `EnsLib.HTTP.OutboundAdapter` subclass
created with `%New()` outside a production fails inside `SendFormDataArray` with
`<INVALID OREF>`; assigning a bare business host is not sufficient, as the adapter
expects production initialization. Irrelevant to the shipped scope, where the adapter
always runs inside a production — but it directly blocks the DTL-inline path below.

**Calling MCP from inside a DTL.** The goal is for a transformation author to invoke
a configured MCP item inline, the way `SET` assigns a value. Two candidate
mechanisms:

1. An `Ens.Rule.FunctionSet` subclass exposing `MCPCall("ItemName", value)` for DTL
   expressions and routing rule conditions. Configuration would resolve by item name
   through `Ens.Director.GetAdapterSettings(itemName, .settings)` — verified to
   exist — with the resolved adapter cached per job. Blocked by the standalone
   instantiation issue above, which must be solved first.
2. A dedicated DTL action, an `MCP CALL` element alongside `SET`, with typed
   parameters in the DTL editor. Better authoring experience by a wide margin.
   Custom DTL actions are not a documented extension point, so feasibility must be
   established before this is promised.

Note that `Ens.Director` exposes no API to invoke a business operation from arbitrary
code, which is why the DTL path cannot simply send a production message and needs its
own mechanism.

**Caching** is specified but not yet implemented. Required before the adapter is
recommended for per-message field-level enrichment at HL7 volumes.

**SSE responses** are not parsed.

---

## 10. Deployment

Standalone IPM module, version 1.0.0, no dependencies.

Requires IRIS, IRIS for Health or Health Connect **2026.2 or later**. The module
enforces this during the IPM **Validate** phase via `Agentic.Install.CheckVersion()`
and refuses to install on anything earlier — the load aborts before a single class
is compiled.

Validate rather than Verify: `Verify` is an opt-in phase that a plain `zpm "load"`
never runs, so a gate declared there never fires. Confirmed by pointing the same
`<Invoke>` at a method that does not exist — under `Verify` the install succeeded
anyway; under `Validate` it fails at `Validate START` with
`<METHOD DOES NOT EXIST>`.

Install once per instance:

```
do $system.OBJ.Load("<path>/src/cls/Agentic/Install.cls","ck")
do ##class(Agentic.Install).Setup()
zpm "load <path>"
```

`Setup()` creates the `AGENTICLIB` database, creates the `%ALL` pseudo-namespace when
absent, and maps the `Agentic.Adapter` package into it. The module resource is
`Agentic.PKG` rather than `Agentic.Adapter.PKG` so the installer ships with the
module while remaining outside the mapped package.

IPM must be enabled in the namespace the load runs from — it is not enabled in every
namespace by default, and `USER` and foundation namespaces frequently lack it. Any
IPM-enabled namespace will do, because the mapping places the code in the shared
database wherever the load happens.

Verified from clean: mappings removed, all classes deleted, `Setup()` re-run, module
installed via `zpm load`, `Verify()` reporting the adapter visible in all seven
namespaces, and an HL7 message enriched end to end afterwards.
