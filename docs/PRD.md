# Product Requirements Document

```
Product Initiative: Agentic Adapter in Execution Time
PM Owner:           Dan Franco
Status:             Draft
Last Updated:       2026-08-17
Target Release:     TBD
Product Area:       IRIS for Health / Health Connect — Interoperability Productions
```

---

## 1. Problem statement

### The customer problem

An integration engineer maintaining HL7 v2 and FHIR interfaces at a hospital system
spends a large share of their time on work that is not really integration: making
imperfect data good enough for the receiving system. A local diagnosis code has to
become a SNOMED code. A sending facility's units have to be normalized. A segment
has to be mapped to a FHIR resource in a way nobody has written down yet.

The knowledge needed to do this lives outside the interface engine — in a
terminology server, a mapping service, a reference dataset, increasingly in a
model-backed service. Today, reaching any of them from a production means writing
code. A custom business operation, bespoke HTTP client code, an endpoint pasted into
a setting or hard-coded, a token handled by hand, error semantics invented fresh each
time. That work is repeated per service and per interface, it is rarely tested to the
standard the rest of the production is held to, and it decays: the engineer who wrote
it moves on and the next person inherits a bespoke integration inside an integration.

The cost is threefold. Time, because each new external capability is a small
development project rather than a configuration change. Risk, because hand-rolled
connectivity tends to accumulate secrets in the wrong places and inconsistent failure
handling. And opportunity, because when adding an external capability is expensive,
teams simply do not do it — data quality problems that could be fixed in flight get
pushed downstream or left alone.

### The business opportunity

MCP (Model Context Protocol) has become the common way for services to expose
callable tools, and the ecosystem of MCP servers is growing quickly — terminology,
mapping, retrieval, and model-backed services alike. The pattern is stable enough to
build against, and early enough that being the interoperability engine where MCP
"just plugs in" is a differentiating position rather than table stakes.

For InterSystems the significance is that clinical data already flows through IRIS
productions. If calling an MCP server is a configuration step inside that flow, then
the AI-era service ecosystem becomes reachable from the place the data already is,
governed by the platform's existing security and audit model. That is a materially
different story from competitors where the equivalent is custom code or an external
orchestration layer.

The cost of building it is small — the prototype works — and it requires no new
licensing, no new runtime, and no change to how productions are deployed.

### Outcome hypothesis

If an interface author can call an MCP server by configuring a production item rather
than writing code, then adding an external capability to an interface becomes a
task measured in minutes rather than days, and it inherits the platform's TLS,
credential, OAuth 2 and audit behaviour by default instead of by discipline.

Leading indicator: time from "we should enrich this field" to a working, traced call
in a test production.

---

## 2. Value and risk assessment

| Risk dimension | Assessment | Mitigation |
|---|---|---|
| Value — will customers use it? | Medium | MCP adoption is early. Mitigated by the adapter being useful for any HTTP JSON-RPC tool service, not only AI ones, and by the build cost being low enough that the bet is cheap |
| Usability — can they figure it out? | Low | It is an adapter configured like every other IRIS adapter. Setting names match `EnsLib.HTTP.OutboundAdapter` wherever the concept is the same |
| Feasibility — can we build it? | Low | Already built and working end to end against a live MCP server, including auth-model inheritance and tool allow-listing |
| Business viability | Low | Ships as a standalone IPM module. No new licensing, no new runtime, no deployment change |
| Regulatory and compliance | **Medium-High** | The adapter can send PHI to a third-party service. See §6 healthcare requirements — this is the risk that governs adoption, not the technology |

The regulatory row deserves emphasis. Nothing about the adapter is unsafe in itself,
but it makes it trivially easy to send message content to an external endpoint. A
customer sending PHI to a third party needs a business associate agreement, needs to
send the minimum necessary, and needs an audit trail. The product's job is to make
the safe path the easy one — allow-listing by default, secrets that cannot be typed
into a setting, and every call traceable.

---

## 3. Goals and success metrics

**Primary business goal.** Make IRIS productions the place where external tool
services are called during clinical data flow, without custom code.

**Customer success metrics (leading)**
- Time to add an external enrichment step to an interface: target under 30 minutes
  from a standing start, versus days for a hand-written operation.
- Number of distinct interfaces in an account using the adapter after 90 days.
- Zero connectivity code written per additional MCP server after the first.

**Business metrics (lagging)**
- Accounts with at least one production MCP-backed interface.
- Attach rate in new interoperability deals where AI-era services are discussed.

**Anti-goals — explicitly out of scope**
- Not an MCP server. Exposing IRIS tools to external clients is a different product.
- Not an agent and not an LLM loop. The adapter calls tools; it does not decide
  which to call.
- Not a transformation engine. What to do with a result belongs to the interface.
- Not `stdio` transport. Spawning and supervising child processes from an IRIS job
  is a materially different operational story.
- Not a replacement for lookup tables where a local table is the right answer.

---

## 4. Personas

```
Persona:            Integration Engineer
Organization type:  IDN, HIE, or Health Connect customer
Primary goal:       Get a conformant message to the receiving system without
                    downstream complaints
Pain solved:        Adding an external enrichment or mapping call stops being a
                    development project
Decision influence: End user and champion
```

```
Persona:            Integration Architect / Interoperability Lead
Organization type:  IDN, HIE, Payer
Primary goal:       Standardize how interfaces reach outside services, and be able
                    to answer what called what
Pain solved:        One governed, audited mechanism instead of N bespoke ones
Decision influence: Economic buyer and potential blocker
```

```
Persona:            Security / Compliance Officer
Organization type:  Any covered entity
Primary goal:       Ensure PHI leaves the boundary only where permitted, and is
                    logged when it does
Pain solved:        Credentials in the credential store, tool allow-listing,
                    traceable calls
Decision influence: Blocker
```

---

## 5. Functional requirements

Written as user stories, tagged P0 for launch, P1 important, P2 desirable.

**Configuration**
- P0 — As an integration engineer, I need to configure which MCP server a production
  item calls, so that no endpoint is hard-coded.
- P0 — As an integration engineer, I need to configure the tool to call and its
  arguments, so that behaviour is a setting rather than code.
- P0 — As a security officer, I need credentials to resolve from the IRIS credential
  store or OAuth 2 client configuration, so that no secret is typed into a setting or
  committed to source.
- P0 — As a security officer, I need to restrict which tools a production item may
  invoke, so that a server exposing destructive tools cannot be misused from an
  interface.
- P1 — As an integration engineer, I need to extract a single value from a tool
  result, so that callers are not forced to unwrap protocol envelopes.
- P2 — As an integration architect, I need to point several production items at the
  same server with different tool permissions, so that least privilege is per use.

**Invocation**
- P0 — As an interface author, I need a business operation that invokes a tool and
  returns the result as a production message, so that the call appears in the Visual
  Trace like any other.
- P0 — As an interface author, I need to override the tool and result path per call,
  so that one configured item can serve related uses.
- P1 — As an interface author, I need to list the tools a server exposes, so that I
  can discover what is available while building.
- P2 — As an interface author, I need to call the configured MCP item from inside a
  DTL, so that field-level enrichment happens where the transformation happens. See
  the technical specification — this has a known obstacle and is deliberately not in
  the launch scope.

**Failure behaviour**
- P0 — As an integration engineer, I need a tool that ran and reported failure to be
  distinguishable from an unreachable server, so that I can handle each correctly.
- P0 — As an integration engineer, I need to choose whether a failed call fails the
  message, passes it through, or substitutes a default, so that enrichment failure
  does not silently drop clinical data.
- P1 — As an integration engineer, I need a connection test, so that I can validate
  configuration before running traffic.
- P1 — As an integration engineer, I need repeated identical calls to be cached, so
  that high-volume enrichment is viable.

---

## 6. Non-functional and healthcare requirements

**Performance**
- Per-call overhead added by the adapter itself, excluding the remote service, under
  10 ms. Measured at 30 ms round trip against a local mock server.
- Caching required before the adapter is recommended for per-message field-level
  enrichment at HL7 volumes.
- Adapter call timeout must be configurable and must sit below the calling host's
  response timeout.

**Security**
- All requests traverse the inherited HTTP machinery, so TLS configuration,
  credentials, OAuth 2 and proxy settings are always applied. Bypassing it is a
  defect, not an option.
- Secrets never appear in settings, logs, traces, or source.
- Tool invocation is deny-by-default: blank allow-list permits only the configured
  default tool.

**Interoperability**
- MCP over Streamable HTTP, JSON-RPC 2.0.
- Protocol version negotiated and configurable.
- Message-format agnostic: the adapter carries JSON and has no HL7, FHIR or X12
  dependency.

**Healthcare-specific**
- PHI handling — the adapter can transmit message content to a third party. The
  product must make minimum-necessary practice easy: callers pass only the arguments
  a tool needs, never a whole message by default. Documentation must state plainly
  that a business associate agreement is the customer's responsibility.
- Audit — every invocation must be attributable: which item, which server, which
  tool, when, how long, and success or failure. Tool arguments and results are
  message content and must be traceable through the standard message trace rather
  than duplicated into logs.
- Logging — no PHI and no secrets in the Event Log. Failures log the tool name and
  error, not the payload.
- Non-determinism — where the MCP server is model-backed, the same input may not
  produce the same output. Caching, full tracing, and explicit failure policy are the
  controls. Clinical use of a non-deterministic enrichment is a customer decision
  that the audit trail must be able to support.

---

## 7. Technical considerations

Architecture, the class model, the language split and the protocol scope are
specified in [02_Technical_Specification.md](02_Technical_Specification.md).

In brief: the adapter extends `EnsLib.HTTP.OutboundAdapter`, which is what supplies
the inherited security model; the MCP protocol work is Embedded Python; and exactly
one method is ObjectScript by necessity because it calls a method with `Output`
parameters.

Dependencies: an interoperability-enabled namespace, and an IRIS version providing
Embedded Python and the OAuth 2 adapter settings. Verified on IRIS for Health
2026.2. The minimum supported version is an open question below.

Known technical risk carried forward: an `EnsLib.HTTP.OutboundAdapter` subclass
cannot be instantiated standalone — it requires production initialization. This does
not affect the launch scope, where the adapter always runs inside a production, but
it directly blocks the deferred DTL-inline path and must be solved before that is
promised.

---

## 8. Open questions and assumptions

| # | Question or assumption | Owner | Status |
|---|---|---|---|
| 1 | Minimum supported IRIS / Health Connect version. Verified only on 2026.2 | Eng | Open |
| 2 | Assumes Streamable HTTP is sufficient; no customer has asked for `stdio` | PM | Open |
| 3 | Should the cache be per-job, per-namespace, or persistent? Terminology answers are stable enough to persist; mapping answers are not | Eng | Open |
| 4 | Does any target server require OAuth 2 flows beyond client credentials? Interactive grants are inherited but make little sense unattended | Eng | Open |
| 5 | Is one MCP server per production item the right granularity, or should one item fan out across servers? | PM | Open |
| 6 | Guidance needed on PHI leaving the boundary — does this need a formal position or reviewed documentation? | Compliance | Open |
| 7 | Distribution: internal module, Open Exchange, or supported component? Affects the support commitment | PM | Open |

---

## 9. Stakeholder map

| Stakeholder | Role | Involvement |
|---|---|---|
| Dan Franco | Product / Engineering | R, A |
| Interoperability engineering | Engineering | C |
| Security / Compliance | Compliance review of PHI transmission guidance | C |
| Sales engineering | Field validation, demo asset | I |
| Early-access customer | Design partner | C |

---

## 10. Appendix — competitive context

Rhapsody and Mirth both require custom code — a JavaScript or Java step — to call an
external service mid-interface, with connectivity, credentials and error handling
written per integration. Neither offers a configured, protocol-aware component with
an inherited enterprise security model.

The differentiator is not that IRIS can call an HTTP service; every engine can. It is
that the call is a configured production item that inherits TLS, credential and
OAuth 2 handling, appears in the Visual Trace, and can be restricted to an
allow-listed set of tools.
