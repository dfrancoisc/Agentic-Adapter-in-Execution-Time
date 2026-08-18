/// Ask a model which MCP tool to call.
///
/// Part of: Production level feature — model-chosen tools. See README.
Class Agentic.Adapter.Msg.SelectRequest Extends Ens.Request
{

/// What the caller is trying to achieve, in plain language.
/// e.g. "Translate this observation code to SNOMED CT"
Property Goal As %String(MAXLEN = 2000);

/// The candidate tools, as returned by the MCP adapter's list action.
Property CatalogJSON As %String(MAXLEN = 32000);

/// The specific data being acted on, so the model can tell the cases apart.
/// e.g. {"code":"E11.9","system":"I10","text":"Type 2 diabetes"}
Property ContextJSON As %String(MAXLEN = 8000);

/// Key under which this decision is cached. Blank derives one from the goal, the
/// catalog and the discriminating fields of the context.
///
/// This is the setting that makes model-based selection affordable: the decision
/// "an I10 code goes to translate_icd" is stable, so it should be made once and
/// reused, not paid for on every message.
Property CacheKey As %String(MAXLEN = 500);

/// Skip the cache and ask the model again.
Property Refresh As %Boolean [ InitialExpression = 0 ];

}
