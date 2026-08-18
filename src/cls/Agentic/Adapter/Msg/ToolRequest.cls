/// Request to an MCP server: invoke a tool, or ask what tools exist.
///
/// Deliberately flat and format-agnostic: the adapter knows nothing about the
/// domain, so callers pass arguments as JSON and get a result back as JSON.
///
/// Part of: Production level feature — MCP connectivity. See README.
Class Agentic.Adapter.Msg.ToolRequest Extends Ens.Request
{

/// What to do:
///   call     - invoke ToolName (the default)
///   list     - return the server's tool catalog, filtered by AllowedTools
///   describe - return one tool's input schema
///
/// list and describe are discovery. They exist so an interface author can ask a
/// server what it offers, and with what argument shape, before pinning a tool into
/// configuration.
Property Action As %String(VALUELIST = ",call,list,describe") [ InitialExpression = "call" ];

/// Tool to invoke or describe. Blank uses the adapter's configured ToolName.
Property ToolName As %String(MAXLEN = 200);

/// Tool arguments as a JSON object. Ignored for list and describe.
Property ArgumentsJSON As %String(MAXLEN = 32000);

/// Overrides the adapter's ResultPath for this call. Blank uses the configured value.
Property ResultPath As %String(MAXLEN = 200);

}
