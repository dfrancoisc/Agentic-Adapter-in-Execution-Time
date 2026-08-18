# Calling an MCP server from inside a DTL

Short answer: **it works.** It is also the option that gives up the three things the
adapter exists to provide. Both halves of that sentence matter.

## It works

`Agentic.Adapter.Functions` ships with the module — nobody writes an MCP client.
`examples/Demo/DTL/EnrichInline.cls` is a normal HL7-to-HL7 transformation with one
`<assign>` calling it:

```xml
<assign value='##class(Agentic.Adapter.Functions).MCPLookup("SnomedMCP","translate_icd",source.{...OBX:5(1).1},"structuredContent.display")'
        property='target.{...OBX:5(1).2}' action='set'/>
```

Run against a live MCP server:

```
in   OBX-5:  E11.9^WRONG DESCRIPTION^I10
out  OBX-5:  E11.9^Diabetes mellitus type 2^I10
```

No business process, no message hop, no orchestration. The transformation asked a
terminology server what the code meant and wrote the answer into the target message.

Two things had to be true for this, and both were verified:

- **Configuration is readable from arbitrary code.**
  `Ens.Director.GetAdapterSettings(itemName, .settings)` returns the settings of a
  running production item, so a DTL function can find the endpoint by naming the
  item rather than hard-coding a URL.
- **The call itself can be made from a class method.** `Agentic.Adapter.Functions`
  speaks the MCP handshake and `tools/call` through `Agentic.Adapter.Protocol` — the
  same protocol code the adapter uses, so the two cannot drift.

## Is the interoperability layer making the call?

No. This was tested rather than argued, because the first test did not prove it.

**The first test was not clean.** It ran in a namespace with the production up, and
the DTL named a config item (`SnomedMCP`), so the function read that running item's
settings to find the endpoint. That is a dependency on the interoperability
configuration, and it hid what was really required.

**The clean test.** Namespace `USER`, production **stopped**, only two classes
loaded — the function set and a DTL naming the endpoint as a plain URL. No config
item, no adapter, no production:

```
production=[] state=2        (stopped)

in   OBX-5:  E11.9^WRONG DESCRIPTION^I10
out  OBX-5:  E11.9^Diabetes mellitus type 2^I10
```

The HTTP call is made by the class method itself, in Embedded Python. Nothing in the
interoperability runtime is involved in it.

### What it does and does not need

| | Needed? |
|---|---|
| A running production | **No** — verified with it stopped |
| A production item for the MCP server | **No**, if you pass a URL. Yes, if you name an item to borrow its settings |
| `Agentic.Adapter.MCP` | **No** — the shipped function speaks MCP itself, sharing the adapter's protocol code |
| Anything else from this module | **No** |
| An interoperability-enabled namespace | **Yes** — see below |

The last row is not a property of this design. A DTL *is* an interoperability
artifact: it extends `Ens.DataTransformDTL` and its generated code includes
`EnsCompiler` and `Ensemble`. Attempting the same thing in a namespace without those
fails at compile time with `No include file 'EnsCompiler'` — which is what happened
when this was tried in a namespace that was not properly interoperability-enabled.

So: if you are writing a DTL at all, you already have the interoperability layer.
What this shows is that the *call* needs nothing beyond that — not the adapter, not
an operation, not a running production.

### Which is exactly the problem

Needing none of that is the same sentence as getting none of it. No adapter means no
inherited TLS, credentials or OAuth 2. No operation means no traced message. No
production involvement means no retry, no failover, no alerting.

## What it gives up

The function does **not** go through `Agentic.Adapter.MCP`, and cannot.

**Security.** The adapter inherits `SSLConfig`, `Credentials`, OAuth 2 and proxy
handling from `EnsLib.HTTP.OutboundAdapter`. A DTL function has none of that unless
it reimplements it. TLS and a bearer token are reachable with effort; OAuth 2 —
token acquisition, caching, refresh — realistically is not.

**Tracing.** There is no production message for the call. Nothing appears in the
Visual Trace or the Message Viewer. The argument for the whole adapter design was
that six months later you can answer "why did this code change?" — this option
cannot answer it.

**Retry, failover and timeout.** No `RetriesToFailover`, no queue, no alerting. A
slow server blocks the transformation. A failing one fails it.

## Why it cannot simply borrow the adapter

Two hard findings, both verified rather than assumed:

- An `EnsLib.HTTP.OutboundAdapter` subclass **cannot be instantiated outside a
  production**. `%New()` succeeds, but the first call fails inside
  `SendFormDataArray` with `<INVALID OREF>`, and assigning a bare business host to
  `BusinessHost` does not fix it — the adapter expects production initialization.
- **`Ens.Director` exposes no API to invoke a business operation** from arbitrary
  code. The supported way to reach an operation is for a business host to send it a
  message, and a DTL is not a business host.

So the configuration can be borrowed. The adapter cannot.

## Which to use

| | DTL inline | Business process |
|---|---|---|
| Moving parts | One function | A process plus an operation |
| Where the call appears in the trace | Nowhere | Its own message, with timing and body |
| TLS | Your responsibility | Inherited |
| Credentials, OAuth 2 | Bearer at best | Inherited |
| Retry, failover, alerting | None | The production's |
| Slow server | Blocks the transformation | Times out and retries per configuration |
| Tool selection by a model | Not available | Available |

Use the DTL form when the call is simple, fast, unauthenticated or bearer
authenticated, and nobody will need to audit it. Use a business process when any of
those is untrue — which, in a clinical interface, is most of the time.

## A third option, if the DTL ergonomics are what you want

The appeal of the inline form is the authoring experience: one line, where the
transformation already is. That can be had without giving up the rest, by doing the
lookup in a business process **before** the transform and passing the answer in — the
DTL then reads a value that is already in hand, and the call remains a traced,
retryable message.

It is more setup for the same result on the page, and it is the shape the shipped
`EnrichmentProcess` already implements.


## A note on bare function names

An earlier draft of this shipped a `Agentic.Adapter.DTL` base class, on the theory
that inheriting the functions would let a DTL call `MCPLookup(...)` by bare name the
way it calls `Lookup(...)`. It does not work, and the class was removed rather than
shipped broken.

Testing showed the generated code emits the bare name verbatim, and it fails at
runtime with `<UNDEFINED>` — inheritance or not. The same test on the built-in
`ToUpper()` in a hand-authored DTL fails identically, which is the tell: bare
resolution is not a property of the DTL class hierarchy.

So the documented form is `##class(Agentic.Adapter.Functions).MCPLookup(...)`, which
is verified. The function set still extends `Ens.Rule.FunctionSet`, which registers
it for the Rule editor, where bare names are the norm.
