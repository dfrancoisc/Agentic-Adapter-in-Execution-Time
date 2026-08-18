/// End-to-end example: HL7 in from a folder, coded values translated via an MCP
/// server, enriched HL7 written out to another folder.
///
///   /tmp/fhir/hl7in → HL7FileIn → EnrichCodes ⇄ SnomedMCP → HL7FileOut → /tmp/fhir/hl7out
///                                      ⇅
///                                 ToolSelector  (only used when SelectionMode=model)
///
/// EnrichCodes is shipped in rule mode: OBX-5.3 names the coding system, so a
/// lookup decides the tool deterministically and for free. Switch SelectionMode to
/// model to have a language model choose from the server's catalog instead - the
/// wiring is already here.
///
/// Points at tests/mock_mcp_server.py and tests/mock_llm_server.py. For real
/// endpoints change HTTPServer/HTTPPort/URL and add SSLConfig, Credentials, AuthType.
Class Demo.HL7Enrich Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Demo.HL7Enrich" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>HL7 file in, MCP terminology translation, HL7 file out</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <Item Name="HL7FileIn" Category="Inbound" ClassName="EnsLib.HL7.Service.FileService" PoolSize="1" Enabled="true" Foreground="false" Comment="Picks up HL7 files" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="FilePath">/tmp/fhir/hl7in</Setting>
    <Setting Target="Adapter" Name="FileSpec">*.hl7</Setting>
    <Setting Target="Adapter" Name="ArchivePath">/tmp/fhir/hl7archive</Setting>
    <Setting Target="Host" Name="TargetConfigNames">EnrichCodes</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5</Setting>
  </Item>

  <Item Name="EnrichCodes" Category="Enrichment" ClassName="Demo.Process.EnrichCodes" PoolSize="1" Enabled="true" Foreground="false" Comment="Decides the tool, calls MCP, writes results back" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="MCPTarget">SnomedMCP</Setting>
    <Setting Target="Host" Name="OutputTarget">HL7FileOut</Setting>
    <Setting Target="Host" Name="SelectorTarget">ToolSelector</Setting>
    <Setting Target="Host" Name="SelectionMode">rule</Setting>
    <Setting Target="Host" Name="RuleMap">I10=translate_icd,LN=translate_loinc,SCT=</Setting>
    <Setting Target="Host" Name="Goal">Translate this observation code to SNOMED CT</Setting>
    <Setting Target="Host" Name="SegmentType">OBX</Setting>
  </Item>

  <Item Name="SnomedMCP" Category="Enrichment" ClassName="Agentic.Adapter.Operation" PoolSize="1" Enabled="true" Foreground="false" Comment="Terminology MCP server" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="HTTPServer">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="HTTPPort">8765</Setting>
    <Setting Target="Adapter" Name="URL">/</Setting>
    <Setting Target="Adapter" Name="AllowedTools">^translate_</Setting>
    <Setting Target="Adapter" Name="OnErrorAction">fail</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">15</Setting>
  </Item>

  <Item Name="ToolSelector" Category="Enrichment" ClassName="Agentic.Adapter.SelectorOperation" PoolSize="1" Enabled="true" Foreground="false" Comment="Asks a model which tool to call; caches the answer" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="HTTPServer">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="HTTPPort">8766</Setting>
    <Setting Target="Adapter" Name="URL">/v1/messages</Setting>
    <Setting Target="Adapter" Name="Provider">anthropic</Setting>
    <Setting Target="Adapter" Name="Model">mock-model</Setting>
    <Setting Target="Adapter" Name="AuthType">none</Setting>
    <Setting Target="Host" Name="CacheEnabled">1</Setting>
    <Setting Target="Host" Name="CacheSeconds">86400</Setting>
    <Setting Target="Host" Name="RequireKnownTool">1</Setting>
  </Item>

  <Item Name="HL7FileOut" Category="Outbound" ClassName="EnsLib.HL7.Operation.FileOperation" PoolSize="1" Enabled="true" Foreground="false" Comment="Writes the improved message" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="FilePath">/tmp/fhir/hl7out</Setting>
    <Setting Target="Host" Name="Filename">enriched_%f_%Q.hl7</Setting>
  </Item>

</Production>
}

}
