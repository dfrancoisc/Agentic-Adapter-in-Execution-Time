/// Identical to Demo.HL7Enrich, but the enrichment process is written in Python.
///
/// Same adapters, same selector, same settings. The only difference is the class on
/// the EnrichCodes item: Demo.Process.EnrichCodesPython instead of
/// Demo.Process.EnrichCodes.
///
/// Uses its own folders so it can run without clashing with the ObjectScript one.
Class Demo.HL7EnrichPython Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Demo.HL7EnrichPython" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>HL7 enrichment with the business process written in Python</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <Item Name="HL7FileIn" Category="Inbound" ClassName="EnsLib.HL7.Service.FileService" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="FilePath">/tmp/py/in</Setting>
    <Setting Target="Adapter" Name="FileSpec">*.hl7</Setting>
    <Setting Target="Adapter" Name="ArchivePath">/tmp/py/archive</Setting>
    <Setting Target="Host" Name="TargetConfigNames">EnrichCodes</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5</Setting>
  </Item>

  <Item Name="EnrichCodes" Category="Enrichment" ClassName="Demo.Process.EnrichCodesPython" PoolSize="1" Enabled="true" Foreground="false" Comment="Python implementation" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="MCPTarget">SnomedMCP</Setting>
    <Setting Target="Host" Name="OutputTarget">HL7FileOut</Setting>
    <Setting Target="Host" Name="SelectorTarget">ToolSelector</Setting>
    <Setting Target="Host" Name="SelectionMode">model</Setting>
    <Setting Target="Host" Name="Goal">Translate this observation code to SNOMED CT</Setting>
    <Setting Target="Host" Name="SegmentType">OBX</Setting>
  </Item>

  <Item Name="SnomedMCP" Category="Enrichment" ClassName="Agentic.Adapter.Operation" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="ServerURL">http://127.0.0.1:8765/</Setting>
    <Setting Target="Adapter" Name="OnErrorAction">fail</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">15</Setting>
  </Item>

  <Item Name="ToolSelector" Category="Enrichment" ClassName="Agentic.Adapter.SelectorOperation" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="ConnectionName">bedrock-default</Setting>
    <Setting Target="Adapter" Name="ConnectionNamespace">HSCUSTOM</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">40</Setting>
    <Setting Target="Host" Name="CacheEnabled">1</Setting>
    <Setting Target="Host" Name="CacheSeconds">86400</Setting>
  </Item>

  <Item Name="HL7FileOut" Category="Outbound" ClassName="EnsLib.HL7.Operation.FileOperation" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="FilePath">/tmp/py/out</Setting>
    <Setting Target="Host" Name="Filename">py_%f_%Q.hl7</Setting>
  </Item>

</Production>
}

}
