/// Result of an MCP request.
Class Agentic.Adapter.Msg.ToolResponse Extends Ens.Response
{

/// For a call: the extracted result, a scalar when ResultPath is set and a JSON
/// object otherwise. For list: the tool catalog as a JSON array. For describe:
/// one tool definition including its input schema.
Property ResultJSON As %String(MAXLEN = 32000);

/// The tool ran and reported failure. This is a business failure, distinct from a
/// transport failure, which surfaces as an error %Status instead.
Property IsError As %Boolean [ InitialExpression = 0 ];

/// Error text when the request did not succeed.
Property ErrorText As %String(MAXLEN = 2000);

/// Round-trip time in milliseconds.
Property DurationMs As %Integer;

/// Tool that was invoked or described, echoed for audit.
Property ToolName As %String(MAXLEN = 200);

}
