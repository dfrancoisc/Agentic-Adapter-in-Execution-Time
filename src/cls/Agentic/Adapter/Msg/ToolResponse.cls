/// Result of an MCP tool invocation.
Class Agentic.Adapter.Msg.ToolResponse Extends Ens.Response
{

/// The extracted result. A scalar when ResultPath is set, otherwise a JSON object.
Property ResultJSON As %String(MAXLEN = 32000);

/// The tool ran and reported failure. This is a business failure, distinct from a
/// transport failure, which surfaces as an error %Status instead.
Property IsError As %Boolean [ InitialExpression = 0 ];

/// Error text when the call did not succeed.
Property ErrorText As %String(MAXLEN = 2000);

/// Round-trip time in milliseconds.
Property DurationMs As %Integer;

/// Tool that was invoked, echoed for audit.
Property ToolName As %String(MAXLEN = 200);

Storage Default
{
<Data name="ToolResponseDefaultData">
<Subscript>"ToolResponse"</Subscript>
<Value name="1">
<Value>ResultJSON</Value>
</Value>
<Value name="2">
<Value>IsError</Value>
</Value>
<Value name="3">
<Value>ErrorText</Value>
</Value>
<Value name="4">
<Value>DurationMs</Value>
</Value>
<Value name="5">
<Value>ToolName</Value>
</Value>
</Data>
<DefaultData>ToolResponseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
