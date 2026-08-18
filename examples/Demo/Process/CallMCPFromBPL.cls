/// Calling an MCP tool from a BPL, with no ObjectScript of your own.
///
/// This exists to prove a claim the documentation makes: that the MCP item is an
/// ordinary business operation, so anything that can send a production message can
/// use it — including a graphical business process built in the BPL editor.
///
/// The whole integration is one `<call>` with a ToolRequest as its request type.
/// Nothing here inherits from the adapter module.
///
/// Send it an Ens.StringRequest whose StringValue is the code to translate; it
/// returns an Ens.StringResponse carrying whatever the tool answered.
Class Demo.Process.CallMCPFromBPL Extends Ens.BusinessProcessBPL
{

XData BPL [ XMLNamespace = "http://www.intersystems.com/bpl" ]
{
<process language='objectscript' request='Ens.StringRequest' response='Ens.StringResponse' height='2000' width='2000'>
<context>
<property name='Answer' type='%String' initialexpression='""'/>
<property name='Failed' type='%Boolean' initialexpression='0'/>
</context>
<sequence xend='400' yend='800'>

<call name='Translate' target='SnomedMCP' async='0' xpos='300' ypos='250'>
<annotation>Ask the configured MCP server to translate the code.</annotation>
<request type='Agentic.Adapter.Msg.ToolRequest'>
<assign property="callrequest.ToolName" value='"translate_icd"' action="set"/>
<assign property="callrequest.ArgumentsJSON" value='"{""code"":"""_request.StringValue_"""}"' action="set"/>
<assign property="callrequest.ResultPath" value='"structuredContent.display"' action="set"/>
</request>
<response type='Agentic.Adapter.Msg.ToolResponse'>
<assign property="context.Answer" value='callresponse.ResultJSON' action="set"/>
<assign property="context.Failed" value='callresponse.IsError' action="set"/>
</response>
</call>

<if name='Recognised' condition='context.Failed=0' xpos='300' ypos='400'>
<true>
<assign name='Return the answer' property="response.StringValue" value='context.Answer' action="set" xpos='300' ypos='550'/>
</true>
<false>
<assign name='Say so plainly' property="response.StringValue" value='"code not recognised"' action="set" xpos='600' ypos='550'/>
</false>
</if>

</sequence>
</process>
}

}
