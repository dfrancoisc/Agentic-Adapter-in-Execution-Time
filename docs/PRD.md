# Product Requirements Document

```
Product Initiative: Agentic Adapter in Execution Time
PM Owner:           Dan Franco
Status:             Draft
Last Updated:       2026-08-18
Product Area:       IRIS for Health / Health Connect — Interoperability Productions
```

---

## 1. Problem statement

### The customer problem

An interoperability engine moves messages between systems. Increasingly, something
useful sits outside it that the interface would benefit from asking while a message
is in flight — a terminology service, a mapping service, a reference dataset, a
model-backed service.

Maria is an integration engineer at a 400-bed health system, and she owns about
ninety interfaces. Her instance of this problem is codes: the lab sends ICD-10 where
the analytics platform wants SNOMED, one feed sends LOINC, another sends local codes
against a lookup table nobody has maintained since 2019. But the shape of the problem
is not specific to codes, and the next one she meets will not be. It might be
enriching an address, validating an identifier, classifying a document, or asking a
service what a segment maps to.

Whatever the question, reaching the service that answers it means writing code. A
custom business operation, a hand-rolled HTTP client, an endpoint pasted into a
setting or hard-coded, a token handled by hand, error semantics invented afresh.
Maria has written that code four times for four services, each slightly different,
each tested to a different standard. The engineer who wrote the oldest one left in
2023.

The cost is threefold. **Time**, because each new external capability is a small
development project rather than a configuration change. **Risk**, because
hand-rolled connectivity accumulates secrets in the wrong places and inconsistent
failure handling — and because when something goes wrong mid-interface, there is no
trace of what the external service was asked or what it said. **Opportunity**,
because when adding an external capability is expensive, teams do not do it. Problems
that could be fixed in flight get pushed downstream, or left alone.

### The business opportunity

MCP (Model Context Protocol) has become the common way for services to expose
callable tools, and the ecosystem is growing quickly — terminology, mapping,
retrieval, and model-backed services alike. The pattern is stable enough to build
against and early enough that being the interoperability engine where it "just plugs
in" is a differentiating position rather than table stakes.

Clinical data already flows through IRIS productions. If calling an external tool is
a configuration step inside that flow, the whole emerging service ecosystem becomes
reachable from where the data already is, governed by the platform's existing
security and audit model. Competing engines answer this with custom code in a
scripting step.

### Outcome hypothesis

If Maria can call an external tool service by configuring a production item rather
than writing code, adding an external capability becomes a task measured in minutes
rather than days, and it inherits TLS, credential, OAuth 2 and audit behaviour by
default instead of by discipline.

Leading indicator: time from "we should enrich this field" to a working, traced call
in a test production.

---

## 2. Value and risk assessment

| Risk dimension | Assessment | Mitigation |
|---|---|---|
| Value — will they use it? | Medium | MCP adoption is early. Mitigated by working for any HTTP JSON-RPC tool service, not only AI ones, and by a low build cost |
| Usability — can they figure it out? | Low | It is an adapter, configured like every other IRIS adapter, with setting names that match the HTTP adapter wherever the concept is the same |
| Feasibility | Low | Built and running: tool invocation, discovery, model-based selection, caching, and a 50-message benchmark |
| Business viability | Low | Standalone module. No new licensing, runtime, or deployment change |
| Regulatory and compliance | **Medium-High** | The adapter makes it easy to send clinical data to a third party. See §5 |

The regulatory row governs adoption, not the technology. Nothing about the adapter
is unsafe in itself, but it makes sending message content to an external endpoint a
configuration step. A customer sending PHI to a third party needs a business
associate agreement, needs to send the minimum necessary, and needs an audit trail.
The product's job is to make the safe path the easy one.

---

## 3. Personas

```
Maria — Integration Engineer
  Organization:  IDN, HIE, or Health Connect customer
  Job to be done: get a conformant message to the receiving system without
                  downstream complaints
  Influence:     end user and champion
```

```
Raj — Integration Architect
  Organization:  IDN, HIE, Payer
  Job to be done: standardize how interfaces reach outside services, and be able to
                  answer what called what
  Influence:     economic buyer, and potential blocker
```

```
Priya — Security and Compliance Officer
  Organization:  any covered entity
  Job to be done: ensure clinical data leaves the boundary only where permitted,
                  and is logged when it does
  Influence:     blocker
```

---

## 4. User stories

Tagged P0 for launch, P1 important, P2 desirable.

### Connecting to a service

- **P0** — As Maria, I need to point a production item at an external tool service
  by pasting the URL from its documentation, so that adding a service is
  configuration rather than a development ticket, and I am not decomposing an
  address into host, port and path by hand.
- **P0** — As Priya, I need credentials to resolve from the IRIS credential store or
  an OAuth 2 client configuration, so that no secret is typed into a setting, written
  to a production definition, or committed to source control.
- **P0** — As Priya, I need the connection to use our standard TLS configuration, so
  that certificate policy is set in one place and not per interface.
- **P1** — As Raj, I need OAuth 2 client credentials handled by the platform, so that
  token acquisition and refresh are not something each interface reimplements.
- **P1** — As Maria, I need to test the connection before wiring anything to it, so
  that I find configuration mistakes at build time rather than in a queue at 3 a.m.

### Knowing what a service can do

- **P0** — As Maria, I need to ask a service what tools it offers and what arguments
  they take, so that I can configure the right call without reading a vendor PDF.
- **P1** — As Maria, I need to see every tool a service offers even when my interface
  is only permitted to use some, so that I can tell what I am missing rather than
  what I already have.

### Making the call

- **P0** — As Maria, I need to send a value from the message to a named tool and get
  a structured answer back, so that I can use it in my transformation.
- **P0** — As Maria, I need the answer as a single value rather than a protocol
  envelope, so that my transformation is a line of code and not a parsing exercise.
- **P0** — As Maria, I need to write the answer back into the message and forward it,
  so that the interface produces an improved message rather than a report.
- **P1** — As Maria, I need one configured service to serve several call sites with
  different tools, so that I am not creating a production item per tool.
- **P2** — As Maria, I need to call the service from inside a transformation, where
  field-level work naturally lives. *(Known obstacle — see the technical
  specification. Not in launch scope.)*

### Choosing the right tool

- **P0** — As Maria, when I know which tool I need, I need to name it and have it
  called every time, so that behaviour is reproducible.
- **P0** — As Maria, when the message itself says which tool applies — an HL7 CWE
  field names its own coding system — I need a mapping to decide, so that I am not
  paying anything to re-derive what the data already states.
- **P1** — As Maria, when I genuinely do not know which tool applies, I need a
  language model to choose from the service's catalogue, so that an unfamiliar or
  changing service is still usable.
- **P0** — As Raj, I need a model's choice to be cached, so that a decision that is
  the same for every message is paid for once rather than per message.
- **P0** — As Priya, I need the model to be unable to invoke anything directly, so
  that a wrong or manipulated answer cannot become an action.

### Calling from a transformation or a rule

A DTL never runs on its own. It runs inside a business process, a BPL or a routing
rule, in a production. So the question is not only "can a transformation call an MCP
server" but "where does that transformation get the server address, the TLS
configuration and the credential from".

- **P0** — As Maria, I need to call an MCP tool from inside a DTL, because that is
  where field-level work lives and I do not want a business process for a lookup.
- **P0** — As Maria, I need one shipped function rather than a class method I write
  myself, so that ninety interfaces do not end up with ninety MCP clients.
- **P0** — As Maria, I need that function to work with any tool on any server — the
  argument name and the result shape come from the server's catalogue, not from
  assumptions baked into the function.
- **P0** — As Priya, I need the transformation to use our TLS configuration and our
  stored credential, not a URL and a token pasted into a transformation.
- **P0** — As Raj, I need the server configured in exactly one place, so that
  rotating a credential does not mean editing transformations.
- **P1** — As Raj, I need that configuration to live somewhere that does not force a
  running host, so that a server used only by transformations does not consume a job.
- **P0** — As Maria, I need a failed lookup to leave the field as it was, so that
  enrichment never destroys the value it was meant to improve.
- **P1** — As Maria, I need a failed lookup to be visible in the Event Log, so that
  a server quietly returning nothing does not go unnoticed for a month.
- **P0** — As Maria, I need to know, before I choose this route, what it does not
  give me — no traced message, no retry, no OAuth 2 — so that I can choose the
  business process when those matter.

The resolution: the settings live on an ordinary production item, and the
transformation names it. The item may be disabled — it then acts purely as a
configuration record — and the same item serves the business process lane when one
is present. A transformation therefore carries no endpoint, no certificate reference
and no secret; it carries a name.

### Keeping it safe

- **P0** — As Priya, I need to be able to restrict which tools an interface may
  invoke, so that a service exposing destructive tools cannot be misused from a
  clinical flow — while the default remains "whatever the server offers", because
  Maria does not know a catalogue before she calls it.
- **P1** — As Maria, I need that restriction expressed as tool names, not as a
  regular expression, because I am configuring a production and not writing code.
- **P0** — As Maria, I need a tool that ran and reported failure to be distinguishable
  from a service that is down, so that I handle a bad code differently from an outage.
- **P0** — As Maria, I need to choose whether a failed enrichment fails the message,
  passes it through, or substitutes a default, so that enrichment never silently
  drops clinical data.
- **P0** — As Raj, I need every call to the external service to appear as a traced
  message, so that six months later I can answer why a code was changed.
- **P1** — As Priya, I need to know what a model was asked and what it answered, so
  that a non-deterministic decision in a clinical flow is still auditable.
- **P1** — As Priya, I need payloads and secrets kept out of the Event Log, so that
  logging does not itself become a disclosure.

### Operating it

- **P0** — As Raj, I need to install once per instance and have every namespace see
  it, so that I am not repeating deployment per namespace.
- **P0** — As Raj, I need it to install as a standard package on any supported IRIS,
  so that deployment is the same as everything else I run.
- **P1** — As Raj, I need it to refuse to install on an unsupported version, so that
  I find out at install time rather than from a failed interface.
- **P1** — As Raj, I need message data to stay namespace-local, so that one
  production cannot see another's traffic.
- **P1** — As Raj, I need to name a model connection already configured elsewhere,
  so that rotating a key or changing model is one edit rather than one per interface.
- **P1** — As Maria, I need to pick that connection from a list of what is actually
  configured, so that I am not typing a name from memory and discovering the typo at
  runtime.
- **P1** — As Maria, I need a per-call timeout below the calling host's own, so that
  a slow service backs off rather than backing up a queue.
- **P2** — As Raj, I need throughput figures for a realistic message volume, so that
  I can size this before committing to it.

### Building an interface with it

- **P0** — As Maria, I need to write only the part that is specific to my message —
  where the values are and where the answer goes — so that I am not reimplementing
  protocol handling per interface.
- **P1** — As Maria, I need the same approach to work for HL7, FHIR and X12, so that
  learning it once pays off across the estate.
- **P0** — As Maria, I need to call an MCP tool from anywhere in a production —
  my own process, a BPL, an operation I already have — and not only through a
  helper class that assumes a particular shape of work, so that the mechanism fits
  my interface rather than the other way round.
- **P1** — As Maria, I need to write that part in ObjectScript or in Python,
  whichever my team maintains, without a performance penalty for choosing.

---

## 5. Non-functional and healthcare requirements

**Performance**
- Adapter overhead, excluding the remote service, negligible against network time.
  Measured: 50 messages and 400 traced production messages in about 3 s with
  selections cached.
- The implementation language of the process must not be a performance
  consideration. Measured: 3.59 s versus 3.65 s over 50 messages for Python and
  ObjectScript run concurrently in separate namespaces — a difference under 2%, and
  about 15 µs per message when isolated to the methods themselves.
- Model-based selection must be cached, or it is not viable at interface volumes.
  Measured: 2 model calls served 50 messages.
- Per-call timeout configurable and below the calling host's response timeout.

**Security**
- Every request traverses the platform's HTTP machinery, so TLS, credentials, OAuth 2
  and proxy settings always apply. Bypassing it is a defect, not an option.
- Secrets never appear in settings, logs, traces, production definitions, or source.
- Tool invocation is deny-by-default.
- A model can name a tool; it cannot invoke one. Enforcement sits between the two.

**Healthcare-specific**
- **Minimum necessary.** The design sends only the fields a tool needs — a code, not
  a patient, not a message. Documentation must be explicit that a business associate
  agreement is the customer's responsibility.
- **Audit.** Every invocation attributable: which item, which service, which tool,
  when, how long, success or failure. Tool arguments and results are message content
  and are traced as messages, not duplicated into logs.
- **Logging.** No PHI and no secrets in the Event Log.
- **Non-determinism.** Where a model chooses the tool, caching, full tracing and an
  explicit failure policy are the controls. Clinical use of a non-deterministic step
  is a customer decision that the audit trail must be able to support.

---

## 6. Anti-goals

- Not an MCP server. Exposing IRIS tools to external clients is a different product.
- Not an agent framework. The adapter calls tools; it does not plan or loop.
- Not a transformation engine. What to do with an answer belongs to the interface.
- Not `stdio` transport. Spawning child processes from an IRIS job is a materially
  different operational story.
- Not a replacement for a lookup table where a local table is the right answer.

---

## 7. Success metrics

**Customer (leading)**
- Time to add an external enrichment step: target under 30 minutes from a standing
  start, versus days for a hand-written operation.
- Distinct interfaces in an account using it after 90 days.
- Connectivity code written per additional service after the first: zero.

**Business (lagging)**
- Accounts with at least one production interface using it.
- Attach rate in interoperability deals where AI-era services are discussed.

---

## 8. Open questions

| # | Question | Owner | Status |
|---|---|---|---|
| 1 | Minimum supported version is set at 2026.2 and enforced at install. Whether earlier releases could be supported is untested | Eng | Open |
| 2 | Does any target service need OAuth 2 flows beyond client credentials? | Eng | Open |
| 3 | Should one production item ever fan out across several services? | PM | Open |
| 4 | Guidance on clinical data leaving the boundary — formal position, or reviewed documentation? | Compliance | Open |
| 5 | Distribution: internal module, Open Exchange, or supported component? | PM | Open |
| 6 | Calling from inside a transformation — function set, or a custom DTL action? Feasibility of the latter is unestablished | Eng | Open |

---

## 9. Appendix — competitive context

Rhapsody and Mirth both require a custom code step to call an external service
mid-interface, with connectivity, credentials and error handling written per
integration. Neither offers a configured, protocol-aware component with an inherited
enterprise security model.

The differentiator is not that IRIS can call an HTTP service — every engine can. It
is that the call is a configured production item that inherits TLS, credential and
OAuth 2 handling, appears in the Visual Trace, can be restricted to an allow-listed
set of tools, and — when a model is involved — records what it was asked and why it
answered as it did.
