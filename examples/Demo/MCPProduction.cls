/// Example production showing the MCP adapter configured on a business operation.
///
/// This is what the Management Portal generates when you click New and then add an
/// operation — shown here so the settings are copy-pasteable and reviewable in
/// source control.
///
/// It points at tests/mock_mcp_server.py. For a real server, change HTTPServer,
/// HTTPPort and URL, add SSLConfig and Credentials, and set AuthType.
///
/// Load it, then start it from the portal or with:
///     do ##class(Ens.Director).StartProduction("Demo.MCPProduction")
Class Demo.MCPProduction Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Demo.MCPProduction" TestingEnabled="true" LogGeneralTraceEvents="false">
  <Description>MCP adapter example</Description>
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="SnomedMCP" Category="" ClassName="Agentic.Adapter.Operation" PoolSize="1" Enabled="true" Foreground="false" Comment="Calls an MCP server tool" LogTraceEvents="true" Schedule="">
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
