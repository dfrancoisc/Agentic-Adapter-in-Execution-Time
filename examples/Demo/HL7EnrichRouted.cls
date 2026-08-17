/// HL7 enrichment production with a proper routing engine.
///
///   /tmp/fhir/hl7in → HL7FileIn → HL7Router ─ ORU ─→ EnrichCodes ⇄ SnomedMCP
///                                     │                    │
///                                     └─ anything else ────┴──→ HL7FileOut → /tmp/fhir/hl7out
///
/// The router decides what is worth enriching. Enrichment costs a network round
/// trip per coded value, so that is a routing decision, not something to bury
/// inside process code.
Class Demo.HL7EnrichRouted Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Demo.HL7EnrichRouted" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>HL7 file in, routed, MCP terminology enrichment, HL7 file out</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <Item Name="HL7FileIn" Category="Inbound" ClassName="EnsLib.HL7.Service.FileService" PoolSize="1" Enabled="true" Foreground="false" Comment="Picks up HL7 files" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="FilePath">/tmp/fhir/hl7in</Setting>
    <Setting Target="Adapter" Name="FileSpec">*.hl7</Setting>
    <Setting Target="Adapter" Name="ArchivePath">/tmp/fhir/hl7archive</Setting>
    <Setting Target="Adapter" Name="ConfirmComplete">1</Setting>
    <Setting Target="Host" Name="TargetConfigNames">HL7Router</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5</Setting>
  </Item>

  <Item Name="HL7Router" Category="Routing" ClassName="EnsLib.HL7.MsgRouter.RoutingEngine" PoolSize="1" Enabled="true" Foreground="false" Comment="Decides what needs enrichment" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="BusinessRuleName">Demo.Rule.EnrichRouter</Setting>
    <!-- d = DocType must resolve, m = required segments must be present.
         A message failing this is not forwarded and is logged. Leave blank to
         accept anything; keep it on if you would rather catch malformed input
         at the door than halfway through an enrichment call. -->
    <Setting Target="Host" Name="Validation">dm</Setting>
  </Item>

  <Item Name="EnrichCodes" Category="Enrichment" ClassName="Demo.Process.EnrichCodes" PoolSize="1" Enabled="true" Foreground="false" Comment="Calls MCP, writes results back" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="MCPTarget">SnomedMCP</Setting>
    <Setting Target="Host" Name="OutputTarget">HL7FileOut</Setting>
    <Setting Target="Host" Name="SegmentType">OBX</Setting>
    <Setting Target="Host" Name="TargetSystemLabel">SCT</Setting>
  </Item>

  <Item Name="SnomedMCP" Category="Enrichment" ClassName="Agentic.Adapter.Operation" PoolSize="1" Enabled="true" Foreground="false" Comment="MCP terminology server" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="HTTPServer">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="HTTPPort">8765</Setting>
    <Setting Target="Adapter" Name="URL">/</Setting>
    <Setting Target="Adapter" Name="ToolName">translate_code</Setting>
    <Setting Target="Adapter" Name="AllowedTools">^translate_code$</Setting>
    <Setting Target="Adapter" Name="OnErrorAction">fail</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">15</Setting>
  </Item>

  <Item Name="HL7FileOut" Category="Outbound" ClassName="EnsLib.HL7.Operation.FileOperation" PoolSize="1" Enabled="true" Foreground="false" Comment="Writes the improved message" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="FilePath">/tmp/fhir/hl7out</Setting>
    <Setting Target="Host" Name="Filename">enriched_%f_%Q.hl7</Setting>
  </Item>

</Production>
}

}
