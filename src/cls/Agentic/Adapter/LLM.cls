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
///
/// Part of: Production level feature — model-chosen tools. See README.
Class Agentic.Adapter.LLM Extends EnsLib.HTTP.OutboundAdapter
{

Parameter SETTINGS = "ConnectionName:LLM Connection:selector?context={Agentic.Adapter.ContextSearch/LLMConnections},ConnectionNamespace:LLM Connection,Provider:LLM,Model:LLM,MaxTokens:LLM,Temperature:LLM,AuthType:LLM,HeaderName:LLM,APIVersion:LLM";

/// Name of a connection already configured in AI Settings, e.g. bedrock-default.
///
/// When set, the provider, model, endpoint and API key are all taken from that
/// connection and the settings below are ignored. One place to change the model,
/// rotate the key, or switch provider — for every production that references it.
///
/// This is an optional, soft dependency: if the AI Settings classes are not present
/// the adapter falls back to the individual settings, so the module stays standalone.
Property ConnectionName As %String(MAXLEN = 100);

/// Namespace holding the AI Settings connection data, if it is not this one.
/// The connection classes may be mapped everywhere while their data is not.
Property ConnectionNamespace As %String;

/// Secret resolved from the connection. Held in memory for the life of the host
/// job, never persisted, never logged.
Property resolvedSecret As %String(MAXLEN = 4000) [ Internal, Private ];

/// Wire format to use: anthropic, bedrock, openai, or custom.
/// openai also covers Azure OpenAI and most OpenAI-compatible gateways.
/// bedrock uses the Amazon Bedrock Converse API, authenticated with a bearer token.
Property Provider As %String(VALUELIST = ",anthropic,bedrock,openai,custom") [ InitialExpression = "anthropic" ];

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
                ; each provider names its own key header; bedrock and openai both
                ; take a bearer token
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

/// Pull provider, model, endpoint and key from a connection configured in AI
/// Settings. Called once when the host starts.
Method OnInit() As %Status
{
    if ..ConnectionName = "" quit $$$OK
    quit ..resolveConnection()
}

Method resolveConnection() As %Status [ Internal ]
{
    set tSC = $$$OK
    try {
        if '##class(%Dictionary.CompiledClass).%ExistsId("AgenticInterop.Connections") {
            set tSC = $$$ERROR($$$GeneralError, "ConnectionName is set but AI Settings connections are not installed in this instance")
            quit
        }

        set tProvider = "", tModel = "", tRegion = "", tMax = ""
        new $namespace
        if ..ConnectionNamespace '= "" { set $namespace = ..ConnectionNamespace }

        set tRs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Provider,Model,Region,MaxTokens FROM AgenticInterop_Data.LLMConnection WHERE Name = ?", ..ConnectionName)
        if 'tRs.%Next() {
            set tSC = $$$ERROR($$$GeneralError, "connection '"_..ConnectionName_"' not found in namespace "_$namespace)
            quit
        }
        set tProvider = tRs.%Get("Provider")
        set tModel = tRs.%Get("Model")
        set tRegion = tRs.%Get("Region")
        set tMax = tRs.%Get("MaxTokens")

        ; the wallet is instance-wide, and stores the secret wrapped as JSON
        set tRaw = ##class(%Wallet.KeyValue).GetSecretValue("AgenticInteropConnections."_..ConnectionName)
        if tRaw = "" {
            set tSC = $$$ERROR($$$GeneralError, "connection '"_..ConnectionName_"' has no stored secret")
            quit
        }
        set ..resolvedSecret = ##class(%DynamicAbstractObject).%FromJSON(tRaw).value

        set ..Provider = tProvider
        set ..Model = tModel
        if (tMax '= "") && (+tMax > 0) && (+..MaxTokens = 0) { set ..MaxTokens = tMax }
        if ..AuthType = "" { set ..AuthType = "bearer" }
        if ..SSLConfig = "" { set ..SSLConfig = "default" }
        set ..HTTPPort = 443

        ; endpoint follows from the provider and region
        if tProvider = "bedrock" {
            set ..HTTPServer = "bedrock-runtime."_tRegion_".amazonaws.com"
            set ..URL = "/model/"_tModel_"/converse"
        } elseif tProvider = "anthropic" {
            set ..HTTPServer = "api.anthropic.com"
            set ..URL = "/v1/messages"
        } elseif tProvider = "openai" {
            set ..HTTPServer = "api.openai.com"
            set ..URL = "/v1/chat/completions"
        } else {
            set tSC = $$$ERROR($$$GeneralError, "connection provider '"_tProvider_"' has no known endpoint; set HTTPServer and URL manually")
            quit
        }

        $$$LOGINFO("LLM connection '"_..ConnectionName_"' resolved: "_tProvider_" "_tModel_" via "_..HTTPServer)
    }
    catch ex {
        set tSC = ex.AsStatus()
    }
    quit tSC
}

/// Resolve the credential's password, or the key from the named connection.
/// Never logged, never a setting.
Method secret() As %String [ Internal ]
{
    if ..resolvedSecret '= "" quit ..resolvedSecret
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

    if provider == "bedrock":
        # Amazon Bedrock Converse API. The model is named in the URL, not the body,
        # and content is a list of typed blocks rather than a bare string.
        body = {"messages": [{"role": "user", "content": [{"text": pUser}]}],
                "system": [{"text": pSystem}],
                "inferenceConfig": {"maxTokens": max_tokens,
                                    "temperature": temperature}}
    elif provider == "openai":
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
    # anthropic input_tokens/output_tokens, openai prompt_tokens/completion_tokens,
    # bedrock inputTokens/outputTokens
    self.LastInputTokens = int(usage.get("input_tokens") or usage.get("prompt_tokens")
                               or usage.get("inputTokens") or 0)
    self.LastOutputTokens = int(usage.get("output_tokens") or usage.get("completion_tokens")
                                or usage.get("outputTokens") or 0)

    if provider == "bedrock":
        blocks = ((msg.get("output") or {}).get("message") or {}).get("content") or []
        for b in blocks:
            if isinstance(b, dict) and b.get("text"):
                return b["text"]
        self.LastError = "no text in Bedrock response"
        return ""

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
