# Benchmark — 50 HL7 messages through the full agentic path

Measured, not estimated. Reproduce it with the fixtures in `tests/`.

## What was measured

50 HL7 v2.5 ORU messages, each carrying one coded OBX observation, rotating through
four codes across two coding systems (ICD-10 and LOINC). Every message went through
the complete path: file pickup, tool selection, MCP tool call, write-back, file
write.

`SelectionMode` was `model`, the most expensive setting — a language model chooses
the tool. Amazon Bedrock, Claude Sonnet 4, us-east-1.

Timing is file-to-file: the moment the first message was picked up, to the moment
the last enriched message was written. That includes the file adapter's own polling
and I/O, so it is what an operator would actually observe.

## Results

| | Cold cache | Warm cache |
|---|---|---|
| 50 messages, first pickup to last write | **23 s** | **3 s** |
| Throughput | 2.2 msg/s | ~17 msg/s |
| Calls to Bedrock | **2** | **0** |
| Selection cache hits | 48 | 50 |
| Average Bedrock latency | 10.3 s | — |
| Production messages traced | 400 | 400 |

Environment: IRIS for Health 2026.2 in Docker on a laptop, `PoolSize` 1 on every
host, `ActorPoolSize` 2. The MCP server was the local mock, so MCP round trips are
loopback and near-free; a remote terminology server would add its own latency to
every call.

## Reading the numbers

**Two model calls served fifty messages.** Not fifty. The selection cache is keyed
on the coding system rather than the code, so the model is asked once per system —
once for ICD-10, once for LOINC — and never again. Had the key included the code,
this run would have made four calls; a real day's traffic with thousands of distinct
codes would have made thousands.

**The model calls are the entire cold-start cost.** Two calls at 10.3 s each is
20.6 s of a 23 s run. Everything else — 50 file reads, 100 MCP round trips, 50 file
writes, 400 traced production messages — took about 3 s. That is what the warm run
measures.

**So the steady state is the warm number.** After the first message of each kind,
the pipeline runs at roughly 17 messages a second with no model in the path at all.
The cold cost is paid once per deployment, not once per message.

**Rule mode would remove even that.** OBX-5.3 names the coding system, so a lookup
decides the tool for nothing. Model mode is worth its cold start when the intent is
genuinely open; it is not worth it to re-derive what the message already says.

## Message volume

Eight production messages per HL7 message — every step is traced, replayable and
individually retryable:

```
#2147 01:19:09.534     HL7FileIn ->   EnrichCodes   HL7 Message
#2393 01:19:09.616   EnrichCodes ->     SnomedMCP   ToolRequest     tools/list
#2394 01:19:09.616     SnomedMCP ->   EnrichCodes   ToolResponse    the catalog
#2395 01:19:09.616   EnrichCodes ->  ToolSelector   SelectRequest   goal + catalog
#2396 01:19:09.617  ToolSelector ->   EnrichCodes   SelectResponse  cached decision
#2397 01:19:09.617   EnrichCodes ->     SnomedMCP   ToolRequest     tools/call
#2398 01:19:09.617     SnomedMCP ->   EnrichCodes   ToolResponse    SNOMED result
#2399 01:19:09.617   EnrichCodes ->    HL7FileOut   HL7 Message
```

400 messages for 50 inputs. That is the cost of full traceability, and it is the
reason you can answer "why did this code change?" six months later.

## Reproducing

Start the mock MCP server, load `Demo.HL7Enrich`, then generate and drop 50 files:

```
for i in $(seq 1 50); do
  printf "MSH|^~\\&|LAB|HOSP|EMR|HOSP|20260818200000||ORU^R01|BENCH%03d|P|2.5\rPID|1||%06d^^^HOSP^MR||PATIENT^TEST||19700101|M\rOBR|1|O|F|PANEL^Panel^L\rOBX|1|CWE|DIAG^Diagnosis^L||E11.9^Type 2 diabetes^I10||||||F\r" $i $i > /tmp/fhir/hl7in/bench$i.hl7
done
```

For a cold run, clear the cache first:

```
do ##class(Agentic.Adapter.SelectorOperation).ClearCache()
```

## Caveats

- One laptop, one container, `PoolSize` 1. Raising pool sizes on `EnrichCodes` and
  `SnomedMCP` would parallelise the MCP calls; this run did not try to.
- The MCP server was local. Add the real network latency of your terminology
  service to every tool call.
- Bedrock latency varies with region, model and load. 10.3 s was what this run saw;
  treat it as an order of magnitude, not a guarantee.
- Selection caching is per namespace and survives restarts. A production restarted
  mid-day does not pay the cold cost again.

---

# Python versus ObjectScript, for the business process

Both versions of the enrichment process — `Demo.Process.EnrichCodes` in ObjectScript
and `Demo.Process.EnrichCodesPython` in Embedded Python — were run against the same
50 messages, with the selection cache warm so no model calls were involved.

## End to end: no measurable difference

Three runs each, file in to file out, 50 messages:

| Run | Python | ObjectScript |
|---|---|---|
| 1 | 3.225 s | 5.059 s |
| 2 | 5.148 s | 3.791 s |
| 3 | 3.701 s | 4.483 s |
| **mean** | **4.02 s** | **4.44 s** |

The ranges overlap almost completely. The first pair of runs suggested Python was
36% faster; two more runs showed that was run-to-run variance, not a difference.

That is the expected result. A message costs roughly 80 ms end to end, and almost
all of it is two MCP round trips, a selector round trip, file reads and file writes —
identical whichever language the process is written in.

## Method level: ObjectScript is about 30% faster

To isolate the language from the network, both implementations were copied verbatim
onto a plain object and called directly. 5000 iterations against a real four-segment
HL7 message:

| Method | ObjectScript | Python | Ratio |
|---|---|---|---|
| find candidates | 23.8 µs | 30.3 µs | 1.28x |
| apply result | 28.6 µs | 36.5 µs | 1.27x |

Stable across runs at 2000 and 5000 iterations.

Reproduce with `do ##class(Agentic.Bench.LanguageCompare).Run(5000)`.

## What that means

ObjectScript is consistently faster in the method itself, and it does not matter.
The gap is about 15 µs per message, against roughly 80,000 µs of end-to-end cost —
under 0.02%. It would take about 65,000 messages for the difference to add up to one
second.

So choose on other grounds: what your team writes fluently, what your libraries are
in, what the next person to maintain the interface will read comfortably. Both
classes are shipped, both are supported by the base class, and they produce
byte-identical output.

If a process ever does something genuinely compute-heavy per message — parsing large
payloads, running a real algorithm — measure it then. For reading a few fields and
writing a few back, the language is not the variable that matters.
