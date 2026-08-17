/// Minimal production for exercising the MCP adapter.
/// Not part of the shipped module — this is a test fixture.
Class Agentic.Adapter.TestProduction Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Agentic.Adapter.TestProduction" LogGeneralTraceEvents="false">
  <Description>MCP adapter test harness</Description>
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="EnsLib.Testing.Service" Category="" ClassName="EnsLib.Testing.Service" PoolSize="1" Enabled="true" Foreground="false" Comment="drives test messages" LogTraceEvents="true" Schedule=""/>
  <Item Name="MCPTest" Category="" ClassName="Agentic.Adapter.Operation" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="true" Schedule="">
    <Setting Target="Adapter" Name="HTTPServer">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="HTTPPort">8765</Setting>
    <Setting Target="Adapter" Name="URL">/</Setting>
    <Setting Target="Adapter" Name="ToolName">translate_code</Setting>
    <Setting Target="Adapter" Name="AllowedTools">^(translate_code|echo)$</Setting>
    <Setting Target="Adapter" Name="ResultPath">structuredContent.code</Setting>
    <Setting Target="Adapter" Name="OnErrorAction">fail</Setting>
  </Item>
</Production>
}

}
