/// Minimal end-to-end example: HL7 in from a folder, coded values enriched via an
/// MCP server, enriched HL7 written out to another folder.
///
///   /tmp/fhir/hl7in → HL7FileIn → EnrichCodes ⇄ SnomedMCP → HL7FileOut → /tmp/fhir/hl7out
///
/// Four hosts, the minimum for this use case:
///   get it in, do the work, call the server, send it out.
///
/// EnrichCodes is not optional. An outbound host takes a request and returns a
/// response - it never sits in the message path, so it cannot modify the HL7.
/// Only a business process can receive a message, call out, wait, and forward a
/// modified copy.
///
/// A routing engine in front is optional and worth adding once there is more than
/// one message type or destination - see Demo.HL7EnrichRouted.
///
/// Points at tests/mock_mcp_server.py. For a real terminology server, change
/// HTTPServer/HTTPPort/URL on SnomedMCP and add SSLConfig, Credentials, AuthType.
Class Demo.HL7Enrich Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Demo.HL7Enrich" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>HL7 file in, MCP terminology enrichment, HL7 file out</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <Item Name="HL7FileIn" Category="Inbound" ClassName="EnsLib.HL7.Service.FileService" PoolSize="1" Enabled="true" Foreground="false" Comment="Picks up HL7 files" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="FilePath">/tmp/fhir/hl7in</Setting>
    <Setting Target="Adapter" Name="FileSpec">*.hl7</Setting>
    <Setting Target="Adapter" Name="ArchivePath">/tmp/fhir/hl7archive</Setting>
    <Setting Target="Host" Name="TargetConfigNames">EnrichCodes</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5</Setting>
  </Item>

  <Item Name="EnrichCodes" Category="Enrichment" ClassName="Demo.Process.EnrichCodes" PoolSize="1" Enabled="true" Foreground="false" Comment="Finds codes, calls MCP, writes results back" LogTraceEvents="true" Schedule="">
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
