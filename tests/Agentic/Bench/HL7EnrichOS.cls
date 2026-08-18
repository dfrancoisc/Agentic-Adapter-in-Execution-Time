/// Benchmark twin of Demo.HL7EnrichPython, using the ObjectScript process.
///
/// Deployed to a SECOND namespace so both can run at the same time against the
/// same input. IRIS runs one production per namespace, so a true side-by-side
/// comparison needs two.
///
/// Differences from the Python production, all deliberate and matched:
///   folders    /tmp/os/*  instead of /tmp/py/*
///   MCP server port 8768  instead of 8765 - its own instance, because the mock is
///                         single threaded and one shared instance would serialise
///                         the two productions and measure the mock, not the code
Class Demo.HL7EnrichOS Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Demo.HL7EnrichOS" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>ObjectScript enrichment process, benchmark twin</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <Item Name="HL7FileIn" Category="Inbound" ClassName="EnsLib.HL7.Service.FileService" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="FilePath">/tmp/os/in</Setting>
    <Setting Target="Adapter" Name="FileSpec">*.hl7</Setting>
    <Setting Target="Adapter" Name="ArchivePath">/tmp/os/archive</Setting>
    <Setting Target="Host" Name="TargetConfigNames">EnrichCodes</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5</Setting>
  </Item>

  <Item Name="EnrichCodes" Category="Enrichment" ClassName="Demo.Process.EnrichCodes" PoolSize="1" Enabled="true" Foreground="false" Comment="ObjectScript implementation" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="MCPTarget">SnomedMCP</Setting>
    <Setting Target="Host" Name="OutputTarget">HL7FileOut</Setting>
    <Setting Target="Host" Name="SelectorTarget">ToolSelector</Setting>
    <Setting Target="Host" Name="SelectionMode">model</Setting>
    <Setting Target="Host" Name="Goal">Translate this observation code to SNOMED CT</Setting>
    <Setting Target="Host" Name="SegmentType">OBX</Setting>
  </Item>

  <Item Name="SnomedMCP" Category="Enrichment" ClassName="Agentic.Adapter.Operation" PoolSize="1" Enabled="true" Foreground="false" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="ServerURL">http://127.0.0.1:8768/</Setting>
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
    <Setting Target="Adapter" Name="FilePath">/tmp/os/out</Setting>
    <Setting Target="Host" Name="Filename">os_%f_%Q.hl7</Setting>
  </Item>

</Production>
}

}
