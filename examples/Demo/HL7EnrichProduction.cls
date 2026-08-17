/// End-to-end example: HL7 in from a folder, coded values enriched via an MCP
/// server, enriched HL7 written out to another folder.
///
///   /tmp/hl7in  →  HL7FileIn  →  EnrichCodes  ⇄  SnomedMCP  →  HL7FileOut  →  /tmp/hl7out
///
/// The MCP call is a synchronous request from the business process to an outbound
/// host, so it appears in the Visual Trace as its own message with its own timing
/// and its own retry behaviour.
///
/// Points at tests/mock_mcp_server.py. For a real terminology server, change
/// HTTPServer/HTTPPort/URL on SnomedMCP and add SSLConfig, Credentials and AuthType.
Class Demo.HL7EnrichProduction Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Demo.HL7EnrichProduction" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>HL7 file in, MCP terminology enrichment, HL7 file out</Description>
  <ActorPoolSize>1</ActorPoolSize>

  <Item Name="HL7FileIn" ClassName="EnsLib.HL7.Service.FileService" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="FilePath">/tmp/hl7in</Setting>
    <Setting Target="Adapter" Name="FileSpec">*.hl7</Setting>
    <Setting Target="Adapter" Name="ArchivePath">/tmp/hl7archive</Setting>
    <Setting Target="Host" Name="TargetConfigNames">EnrichCodes</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5</Setting>
  </Item>

  <Item Name="EnrichCodes" ClassName="Demo.Process.EnrichCodes" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="MCPTarget">SnomedMCP</Setting>
    <Setting Target="Host" Name="OutputTarget">HL7FileOut</Setting>
    <Setting Target="Host" Name="SegmentType">OBX</Setting>
  </Item>

  <Item Name="SnomedMCP" ClassName="Agentic.Adapter.Operation" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="HTTPServer">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="HTTPPort">8765</Setting>
    <Setting Target="Adapter" Name="URL">/</Setting>
    <Setting Target="Adapter" Name="ToolName">translate_code</Setting>
    <Setting Target="Adapter" Name="AllowedTools">^translate_code$</Setting>
    <Setting Target="Adapter" Name="OnErrorAction">fail</Setting>
  </Item>

  <Item Name="HL7FileOut" ClassName="EnsLib.HL7.Operation.FileOperation" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="FilePath">/tmp/hl7out</Setting>
    <Setting Target="Host" Name="Filename">enriched_%f_%Q.hl7</Setting>
  </Item>

</Production>
}

}
