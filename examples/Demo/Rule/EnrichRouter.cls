/// Routing rule for the MCP enrichment production.
///
/// Decides what actually needs enriching. Observation messages go through the MCP
/// enrichment process; everything else passes straight to the outbound file
/// operation without paying for a remote call.
///
/// This is the point of putting a router in front: enrichment costs a network
/// round trip per coded value, so deciding what deserves one is a routing decision,
/// not something to bury in process code.
Class Demo.Rule.EnrichRouter Extends Ens.Rule.Definition
{

Parameter RuleAssistClass = "EnsLib.HL7.MsgRouter.RuleAssist";

XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.HL7.MsgRouter.RoutingEngine" production="Demo.HL7EnrichRouted">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="EnrichObservations" disabled="false">
<constraint name="msgClass" value="EnsLib.HL7.Message"></constraint>
<when condition="Document.{MSH:9.1}=&quot;ORU&quot;">
<send transform="" target="EnrichCodes"></send>
<return></return>
</when>
</rule>
<rule name="PassThroughEverythingElse" disabled="false">
<when condition="1">
<send transform="" target="HL7FileOut"></send>
<return></return>
</when>
</rule>
</ruleSet>
</ruleDefinition>
}

}
