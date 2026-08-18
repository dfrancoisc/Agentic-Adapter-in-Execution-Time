/// A DTL that calls an MCP server during the transformation itself.
///
/// Replaces the description in OBX-5.2 with whatever the terminology server says the
/// code in OBX-5.1 actually means. One `<assign>`, no business process involved.
///
/// MCPLookup is a shipped function from Agentic.Adapter.Functions, so nobody writes
/// an MCP client. It is called with ##class(...) rather than by bare name: bare
/// function names do not resolve in a hand-authored DTL - not even the built-in
/// ToUpper() does - so the qualified form is the reliable one.
///
/// This is the "bypass" option: simpler and with fewer moving parts than a business
/// process, at the cost of tracing, retry and the production's failover behaviour.
/// Read the warnings on Agentic.Adapter.Functions before using it in anger.
Class Demo.DTL.EnrichInline Extends Ens.DataTransformDTL
{

Parameter IGNOREMISSINGSOURCE = 1;

Parameter REPORTERRORS = 1;

XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='EnsLib.HL7.Message' targetClass='EnsLib.HL7.Message' sourceDocType='2.5:ORU_R01' targetDocType='2.5:ORU_R01' create='copy' language='objectscript'>
<assign value='##class(Agentic.Adapter.Functions).MCPLookup("SnomedMCP","translate_icd",source.{PIDgrpgrp(1).ORCgrp(1).OBXgrp(1).OBX:5(1).1},"structuredContent.display")' property='target.{PIDgrpgrp(1).ORCgrp(1).OBXgrp(1).OBX:5(1).2}' action='set'/>
</transform>
}

}
