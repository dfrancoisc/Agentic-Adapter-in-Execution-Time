/// Request to invoke one MCP tool.
///
/// Deliberately flat and format-agnostic: the adapter knows nothing about the
/// domain, so callers pass arguments as JSON and get a result back as JSON.
Class Agentic.Adapter.Msg.ToolRequest Extends Ens.Request
{

/// Tool to invoke. Blank uses the adapter's configured ToolName.
Property ToolName As %String(MAXLEN = 200);

/// Tool arguments as a JSON object.
Property ArgumentsJSON As %String(MAXLEN = 32000);

/// Overrides the adapter's ResultPath for this call. Blank uses the configured value.
Property ResultPath As %String(MAXLEN = 200);

Storage Default
{
<Data name="ToolRequestDefaultData">
<Subscript>"ToolRequest"</Subscript>
<Value name="1">
<Value>ToolName</Value>
</Value>
<Value name="2">
<Value>ArgumentsJSON</Value>
</Value>
<Value name="3">
<Value>ResultPath</Value>
</Value>
</Data>
<DefaultData>ToolRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
