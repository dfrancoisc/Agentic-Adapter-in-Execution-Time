/// A DTL that calls an MCP server during the transformation itself.
///
/// Replaces the description in OBX-5.2 with whatever the terminology server says the
/// code in OBX-5.1 actually means. One `<assign>`, no business process involved.
///
/// This is the "bypass" option: simpler and with fewer moving parts than a business
/// process, at the cost of tracing, retry and the inherited security model. Read the
/// warnings on Demo.MCPFunctions before using this pattern in anger.
Class Demo.DTL.EnrichInline Extends Ens.DataTransformDTL
{

Parameter IGNOREMISSINGSOURCE = 1;

Parameter REPORTERRORS = 1;

XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='EnsLib.HL7.Message' targetClass='EnsLib.HL7.Message' sourceDocType='2.5:ORU_R01' targetDocType='2.5:ORU_R01' create='copy' language='objectscript'>
<assign value='##class(Demo.MCPFunctions).MCPCall("SnomedMCP","translate_icd",source.{PIDgrpgrp(1).ORCgrp(1).OBXgrp(1).OBX:5(1).1},"structuredContent.display")' property='target.{PIDgrpgrp(1).ORCgrp(1).OBXgrp(1).OBX:5(1).2}' action='set'/>
</transform>
}

}
