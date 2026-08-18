/// Generic business operation that exposes an MCP server to a production.
///
/// Add it to any production, point its adapter at an MCP server, and send it a
/// ToolRequest. It carries no domain logic — deciding which tool to call and what
/// to do with the answer belongs to the interface, not here.
Class Agentic.Adapter.Operation Extends Ens.BusinessOperation
{

Parameter ADAPTER = "Agentic.Adapter.MCP";

Parameter INVOCATION = "Queue";

Property Adapter As Agentic.Adapter.MCP;

Method OnMessage(pRequest As Agentic.Adapter.Msg.ToolRequest, Output pResponse As Agentic.Adapter.Msg.ToolResponse) As %Status
{
    set pResponse = ##class(Agentic.Adapter.Msg.ToolResponse).%New()
    set tStart = $zhorolog
    set tSC = $$$OK
    try {
        set tTool = $select(pRequest.ToolName '= "": pRequest.ToolName, 1: ..Adapter.ToolName)
        set pResponse.ToolName = tTool
        set tAction = $select(pRequest.Action '= "": pRequest.Action, 1: "call")

        ; Discovery. Ask the server what it offers, and with what argument shape.
        ; This is how an interface author finds the right tool before pinning it
        ; into configuration - the MCP server never chooses a tool itself.
        if tAction = "list" {
            set pResponse.ResultJSON = ..Adapter.ListTools()
        } elseif tAction = "describe" {
            set pResponse.ResultJSON = ..Adapter.DescribeTool(tTool)
        } else {
            set pResponse.ResultJSON = ..Adapter.CallTool(pRequest.ToolName, pRequest.ArgumentsJSON, pRequest.ResultPath)
        }
        set pResponse.IsError = ..Adapter.LastIsError
        set pResponse.ErrorText = ..Adapter.LastError
        ; A tool that ran and reported failure is a business outcome: it is returned
        ; to the caller rather than failing the message. A transport or protocol
        ; failure raises, and is caught below as an error %Status.
        if pResponse.IsError {
            $$$LOGWARNING("MCP tool '"_tTool_"' returned isError")
        }
    }
    catch ex {
        set tSC = ex.AsStatus()
        set pResponse.ErrorText = $select(..Adapter.LastError '= "": ..Adapter.LastError, 1: ex.DisplayString())
    }
    set pResponse.DurationMs = $normalize(($zhorolog - tStart) * 1000, 0)
    quit tSC
}

/// Verify the MCP server is reachable and the handshake succeeds.
Method OnInit() As %Status
{
    quit $$$OK
}

}
