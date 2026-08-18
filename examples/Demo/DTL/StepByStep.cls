/// The worked DTL from docs/DTL_STEP_BY_STEP.md.
///
/// Takes the ICD-10 code in OBX-5.1 and replaces the description in OBX-5.2 with
/// whatever the terminology server says that code actually means. Leaves everything
/// else in the message alone.
///
/// TxLookup is a production item configured with Agentic.Adapter.MCP. The server
/// address, TLS configuration and credential live there, so this transformation
/// names the item and nothing else.
///
/// The last argument is the existing description, passed as the default: if the
/// server does not recognise the code, the field keeps what it already had rather
/// than being blanked.
Class Demo.DTL.StepByStep Extends Ens.DataTransformDTL
{

Parameter IGNOREMISSINGSOURCE = 1;

Parameter REPORTERRORS = 1;

XData DTL [ XMLNamespace = "http://www.intersystems.com/dtl" ]
{
<transform sourceClass='EnsLib.HL7.Message' targetClass='EnsLib.HL7.Message' sourceDocType='2.5:ORU_R01' targetDocType='2.5:ORU_R01' create='copy' language='objectscript'>
<assign value='##class(Agentic.Adapter.Functions).MCPLookup("TxLookup","translate_icd","code",source.{PIDgrpgrp(1).ORCgrp(1).OBXgrp(1).OBX:5(1).1},"structuredContent.display",source.{PIDgrpgrp(1).ORCgrp(1).OBXgrp(1).OBX:5(1).2})' property='target.{PIDgrpgrp(1).ORCgrp(1).OBXgrp(1).OBX:5(1).2}' action='set'/>
</transform>
}

}
