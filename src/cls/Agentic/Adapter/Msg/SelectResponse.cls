/// A model's answer about which MCP tool to call.
///
/// Part of: Production level feature — model-chosen tools. See README.
Class Agentic.Adapter.Msg.SelectResponse Extends Ens.Response
{

/// The chosen tool.
Property ToolName As %String(MAXLEN = 200);

/// Arguments the model proposes, as a JSON object. May be empty if the caller
/// intends to build the arguments itself.
Property ArgumentsJSON As %String(MAXLEN = 8000);

/// The model's stated reason. Worth persisting: when a selection later looks wrong,
/// this is the only record of why it was made.
Property Reason As %String(MAXLEN = 2000);

/// The decision came from the cache and cost nothing.
Property FromCache As %Boolean [ InitialExpression = 0 ];

Property IsError As %Boolean [ InitialExpression = 0 ];

Property ErrorText As %String(MAXLEN = 2000);

Property DurationMs As %Integer;

Property InputTokens As %Integer;

Property OutputTokens As %Integer;

}
