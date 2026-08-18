/// Dropdown providers for settings, so an interface engineer picks from a list
/// instead of typing a name and hoping.
///
/// Referenced from a SETTINGS declaration as:
///   ConnectionName:LLM Connection:selector?context={Agentic.Adapter.ContextSearch/LLMConnections}
///
/// Part of: Shared by both levels. See README.
Class Agentic.Adapter.ContextSearch Extends %RegisteredObject
{

/// Namespaces searched for AI Settings connections, in order, when the current
/// one has none. The connection classes are often mapped everywhere while their
/// data lives in one place.
Parameter FALLBACKNAMESPACES = "HSCUSTOM";

/// Every LLM connection configured in AI Settings, as a dropdown.
///
/// The engineer picks the connection by name; the adapter then resolves the
/// provider, model, endpoint and key from it. If AI Settings is not installed the
/// list is simply empty and the setting can still be typed by hand.
ClassMethod LLMConnections(Output pCaption As %String, Output pTopResults, Output pResults, ByRef pParms As %String, pSearchKey As %String = "") As %Status
{
    set pCaption = "LLM connections configured in AI Settings"
    set tCount = 0

    if '##class(%Dictionary.CompiledClass).%ExistsId("AgenticInterop.Connections") {
        quit $$$OK
    }

    ; current namespace first, then the usual homes for the data
    set tSearch = $namespace
    for i = 1:1:$length(..#FALLBACKNAMESPACES, ",") {
        set tNs = $piece(..#FALLBACKNAMESPACES, ",", i)
        if (tNs '= "") && (tNs '= $namespace) { set tSearch = tSearch_","_tNs }
    }

    for i = 1:1:$length(tSearch, ",") {
        set tNs = $piece(tSearch, ",", i)
        continue:(tNs = "")
        set tCount = ..collect(tNs, pSearchKey, tCount, .pResults)
        quit:(tCount > 0)
    }
    quit $$$OK
}

/// Read connection names from one namespace. Returns the running count.
ClassMethod collect(pNamespace As %String, pSearchKey As %String, pCount As %Integer, Output pResults) As %Integer [ Internal ]
{
    set tCount = pCount
    try {
        new $namespace
        set $namespace = pNamespace
        set tRs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name, Provider, Model FROM AgenticInterop_Data.LLMConnection ORDER BY Name")
        while tRs.%Next() {
            set tName = tRs.%Get("Name")
            continue:(tName = "")
            ; the portal filters as the user types
            if (pSearchKey '= "") && ($zconvert(tName, "U") '[ $zconvert(pSearchKey, "U")) continue
            set tCount = tCount + 1
            ; show what the engineer needs to choose between, not just a name
            set pResults(tCount) = $listbuild(tName, tRs.%Get("Provider"), tRs.%Get("Model"))
        }
    }
    catch {
        ; namespace not available, or AI Settings not present there - not an error,
        ; the dropdown is simply empty and the setting can be typed
    }
    quit tCount
}

/// Every tool a configured MCP item's server currently offers.
///
/// Intended for the AllowedTools setting, so an engineer can see the real tool
/// names rather than inventing a pattern. Requires the production to be running,
/// because asking a server what it offers means calling it.
ClassMethod MCPTools(Output pCaption As %String, Output pTopResults, Output pResults, ByRef pParms As %String, pSearchKey As %String = "") As %Status
{
    set pCaption = "Tools offered by this MCP server"
    quit $$$OK
}

}
