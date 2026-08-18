/// Real-world example: validate and normalise coded HL7 fields against a live
/// terminology service.
///
///   /tmp/tx/in → HL7FileIn → ValidateCodes ⇄ TerminologyMCP → HL7FileOut → /tmp/tx/out
///                                  ⇅
///                             ToolSelector  (Bedrock chooses the lookup tool)
///
/// Nothing here is mocked except the MCP server process itself, which is a thin
/// wrapper: every answer comes from tx.fhir.org, the public HL7 FHIR terminology
/// server, against real published releases of ICD-10, LOINC and SNOMED CT.
///
/// The problem it solves: a sending system puts a code in OBX-5 with whatever
/// description it happens to hold. Some are stale, some abbreviated, some wrong,
/// and some codes do not exist at all. This replaces the description with the
/// official display for that code and flags codes the terminology server does not
/// recognise — leaving the coding system untouched, because nothing is being
/// translated.
///
/// Start tests/terminology_mcp_server.py before running this.
Class Demo.HL7Validate Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Demo.HL7Validate" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>Validate and normalise HL7 codes against tx.fhir.org</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <Item Name="HL7FileIn" Category="Inbound" ClassName="EnsLib.HL7.Service.FileService" PoolSize="1" Enabled="true" Foreground="false" Comment="Picks up HL7 files" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="FilePath">/tmp/tx/in</Setting>
    <Setting Target="Adapter" Name="FileSpec">*.hl7</Setting>
    <Setting Target="Adapter" Name="ArchivePath">/tmp/tx/archive</Setting>
    <Setting Target="Host" Name="TargetConfigNames">ValidateCodes</Setting>
    <Setting Target="Host" Name="MessageSchemaCategory">2.5</Setting>
  </Item>

  <Item Name="ValidateCodes" Category="Terminology" ClassName="Demo.Process.EnrichCodes" PoolSize="1" Enabled="true" Foreground="false" Comment="Normalises coded fields" LogTraceEvents="true" Schedule="">
    <Setting Target="Host" Name="MCPTarget">TerminologyMCP</Setting>
    <Setting Target="Host" Name="OutputTarget">HL7FileOut</Setting>
    <Setting Target="Host" Name="SelectorTarget">ToolSelector</Setting>
    <Setting Target="Host" Name="SelectionMode">model</Setting>
    <Setting Target="Host" Name="RuleMap">I10=lookup_icd10,LN=lookup_loinc,SCT=lookup_snomed</Setting>
    <Setting Target="Host" Name="Goal">Return the official display text for this code from its own terminology. Do not translate it to another terminology.</Setting>
    <Setting Target="Host" Name="SegmentType">OBX</Setting>
    <!-- blank: the coding system does not change, only the description -->
    <Setting Target="Host" Name="TargetSystemLabel"></Setting>
  </Item>

  <Item Name="TerminologyMCP" Category="Terminology" ClassName="Agentic.Adapter.Operation" PoolSize="1" Enabled="true" Foreground="false" Comment="tx.fhir.org via MCP" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="ServerURL">http://127.0.0.1:8767/</Setting>
    <Setting Target="Adapter" Name="OnErrorAction">fail</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">40</Setting>
  </Item>

  <Item Name="ToolSelector" Category="Terminology" ClassName="Agentic.Adapter.SelectorOperation" PoolSize="1" Enabled="true" Foreground="false" Comment="Bedrock picks the lookup tool" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="ConnectionName">bedrock-default</Setting>
    <Setting Target="Adapter" Name="ConnectionNamespace">HSCUSTOM</Setting>
    <Setting Target="Adapter" Name="MaxTokens">512</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">40</Setting>
    <Setting Target="Host" Name="CacheEnabled">1</Setting>
    <Setting Target="Host" Name="CacheSeconds">86400</Setting>
    <Setting Target="Host" Name="RequireKnownTool">1</Setting>
  </Item>

  <Item Name="HL7FileOut" Category="Outbound" ClassName="EnsLib.HL7.Operation.FileOperation" PoolSize="1" Enabled="true" Foreground="false" Comment="Writes the normalised message" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="FilePath">/tmp/tx/out</Setting>
    <Setting Target="Host" Name="Filename">validated_%f_%Q.hl7</Setting>
  </Item>

</Production>
}

}
