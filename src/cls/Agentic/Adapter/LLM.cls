/// Outbound adapter for a language model endpoint.
///
/// Deliberately the same shape as Agentic.Adapter.MCP: it extends
/// EnsLib.HTTP.OutboundAdapter, so TLS, credentials, OAuth 2 and proxy settings are
/// inherited rather than reimplemented, and every request goes through the platform's
/// HTTP machinery.
///
/// Provider-neutral. The wire format is chosen by the Provider setting, so the model
/// behind a production can be changed at deploy time without touching code.
///
/// This adapter exists for ONE job: asking a model which tool to call. It is not a
/// general chat client and deliberately has no streaming, no conversation history and
/// no tool-calling of its own.
Class Agentic.Adapter.LLM Extends EnsLib.HTTP.OutboundAdapter
{

Parameter SETTINGS = "Provider:LLM,Model:LLM,MaxTokens:LLM,Temperature:LLM,AuthType:LLM,HeaderName:LLM,APIVersion:LLM";

/// Wire format to use: anthropic, openai, or custom.
/// openai also covers Azure OpenAI and most OpenAI-compatible gateways.
Property Provider As %String(VALUELIST = ",anthropic,openai,custom") [ InitialExpression = "anthropic" ];

/// Model identifier, exactly as the provider expects it.
Property Model As %String(MAXLEN = 200);

Property MaxTokens As %Integer [ InitialExpression = 512 ];

/// Zero is the right default: choosing a tool should not be creative.
Property Temperature As %Numeric [ InitialExpression = 0 ];

/// How to present the credential: apikey (provider's own header), bearer, header, oauth2.
Property AuthType As %String(VALUELIST = ",none,apikey,bearer,header,oauth2") [ InitialExpression = "apikey" ];

/// Header name when AuthType is header.
Property HeaderName As %String [ InitialExpression = "X-API-Key" ];

/// Anthropic requires a version header. Ignored by other providers.
Property APIVersion As %String [ InitialExpression = "2023-06-01" ];

Property LastError As %String(MAXLEN = 2000) [ Internal ];

Property LastHttpCode As %String [ Internal ];

/// Prompt tokens reported by the provider, when it reports them.
Property LastInputTokens As %Integer [ Internal ];

Property LastOutputTokens As %Integer [ Internal ];

/// The only method that touches the wire. ObjectScript by necessity:
/// SendFormDataArray() uses Output parameters, which cannot appear in a
/// Language=python signature.
Method Send(pBody As %String) As %String [ Internal ]
{
    set ..LastError = "", ..LastHttpCode = ""
    set tBody = ""
    try {
        set tReq = ##class(%Net.HttpRequest).%New()
        set tReq.ContentType = "application/json"
        do tReq.SetHeader("Accept", "application/json")

        set tSecret = ..secret()
        if tSecret '= "" {
            if ..AuthType = "apikey" {
                ; each provider names its own key header
                if ..Provider = "anthropic" {
                    do tReq.SetHeader("x-api-key", tSecret)
                } else {
                    do tReq.SetHeader("Authorization", "Bearer "_tSecret)
                }
            } elseif ..AuthType = "bearer" {
                do tReq.SetHeader("Authorization", "Bearer "_tSecret)
            } elseif ..AuthType = "header" {
                do tReq.SetHeader(..HeaderName, tSecret)
            }
        }
        if (..Provider = "anthropic") && (..APIVersion '= "") {
            do tReq.SetHeader("anthropic-version", ..APIVersion)
        }

        do tReq.EntityBody.Write(pBody)
        set tSC = ..SendFormDataArray(.tResp, "POST", tReq)
        if $$$ISERR(tSC) {
            set ..LastError = $system.Status.GetErrorText(tSC)
            quit
        }
        if '$isobject(tResp) {
            set ..LastError = "no HTTP response"
            quit
        }
        set ..LastHttpCode = tResp.StatusCode
        if $isobject(tResp.Data) {
            while 'tResp.Data.AtEnd { set tBody = tBody_tResp.Data.Read(32000) }
        }
    }
    catch ex {
        set ..LastError = ex.DisplayString()
    }
    quit tBody
}

/// Resolve the configured credential's password. Never logged, never a setting.
Method secret() As %String [ Internal ]
{
    if ..Credentials = "" quit ""
    set tSC = ##class(Ens.Config.Credentials).GetCredentialsObj(.tCred, $classname(), "Ens.Config.Credentials", ..Credentials)
    if $$$ISERR(tSC) || '$isobject(tCred) quit ""
    quit tCred.Password
}

/// Send one system+user exchange and return the model's text reply.
/// Returns an empty string on failure, with LastError set.
Method Complete(pSystem As %String, pUser As %String) As %String [ Language = python ]
{
    import json

    provider = (self.Provider or "anthropic").lower()
    model = self.Model or ""
    max_tokens = int(self.MaxTokens or 512)
    temperature = float(self.Temperature or 0)

    if provider == "openai":
        body = {"model": model,
                "max_tokens": max_tokens,
                "temperature": temperature,
                "messages": [{"role": "system", "content": pSystem},
                             {"role": "user", "content": pUser}]}
    else:
        # anthropic shape, and the default for custom endpoints
        body = {"model": model,
                "max_tokens": max_tokens,
                "temperature": temperature,
                "system": pSystem,
                "messages": [{"role": "user", "content": pUser}]}

    raw = self.Send(json.dumps(body))
    if self.LastError:
        return ""
    if not raw:
        self.LastError = "empty response (HTTP %s)" % self.LastHttpCode
        return ""

    try:
        msg = json.loads(raw)
    except ValueError as e:
        self.LastError = "response is not JSON: %s" % e
        return ""

    if isinstance(msg, dict) and msg.get("error"):
        err = msg["error"]
        self.LastError = "provider error: %s" % (
            err.get("message") if isinstance(err, dict) else err)
        return ""

    return self.extractText(msg, provider)
}

/// Pull the assistant text and token usage out of a provider response.
Method extractText(msg, provider As %String) As %String [ Internal, Language = python ]
{
    usage = msg.get("usage") or {}
    # anthropic reports input_tokens/output_tokens, openai prompt_tokens/completion_tokens
    self.LastInputTokens = int(usage.get("input_tokens") or usage.get("prompt_tokens") or 0)
    self.LastOutputTokens = int(usage.get("output_tokens") or usage.get("completion_tokens") or 0)

    if provider == "openai":
        choices = msg.get("choices") or []
        if not choices:
            self.LastError = "no choices in response"
            return ""
        return (choices[0].get("message") or {}).get("content") or ""

    blocks = msg.get("content") or []
    for b in blocks:
        if isinstance(b, dict) and b.get("type") == "text":
            return b.get("text") or ""
    if blocks and isinstance(blocks[0], dict):
        return blocks[0].get("text") or ""
    self.LastError = "no text content in response"
    return ""
}

}
