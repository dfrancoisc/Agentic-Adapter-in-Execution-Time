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
