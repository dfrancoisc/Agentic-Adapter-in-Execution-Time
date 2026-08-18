"""A real MCP server backed by a live terminology service.

Unlike mock_mcp_server.py, nothing here is invented. Every answer comes from
tx.fhir.org, the public HL7 FHIR terminology server, against real published
releases: SNOMED CT (Jan 2025), LOINC 2.82, ICD-10.

The use case is code validation and normalisation, which is what a public
terminology server does authoritatively:

    A sending system puts a code in OBX-5 with whatever description it happens to
    hold. Some of those descriptions are stale, abbreviated, or simply wrong, and
    some of the codes do not exist at all. This replaces the description with the
    official display text for that code, and flags codes the terminology server
    does not recognise.

Tools:
  lookup_icd10     official ICD-10 display for a code
  lookup_loinc     official LOINC display for a code
  lookup_snomed    official SNOMED CT display for a concept id

Each call is a real FHIR CodeSystem/$lookup against the published release.

A NOTE ON TRANSLATION, deliberately not implemented here:
tx.fhir.org exposes no ICD-10-to-SNOMED ConceptMap, and matching by display text
does not work — asking it to expand SNOMED for "type 2 diabetes mellitus" ranks
"Type-casting-machine operator" fifth and never returns concept 44054006 at all.
Cross-terminology mapping needs a real map (UMLS, a licensed SNOMED extension, or a
curated local ConceptMap), not string similarity. Shipping a fuzzy matcher here
would have produced confidently wrong clinical codes.

Run:  python3 terminology_mcp_server.py     (listens on 127.0.0.1:8767)

Requires outbound HTTPS to tx.fhir.org. No credentials, no API key.
"""

import json
import urllib.parse
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

TX = "https://tx.fhir.org/r4"

SYSTEMS = {
    "lookup_icd10": ("http://hl7.org/fhir/sid/icd-10", "ICD-10"),
    "lookup_loinc": ("http://loinc.org", "LOINC"),
    "lookup_snomed": ("http://snomed.info/sct", "SNOMED CT"),
}

TOOLS = [
    {"name": "lookup_icd10",
     "description": "Return the official ICD-10 display text for a diagnosis code, "
                    "and confirm the code exists in the published release.",
     "inputSchema": {"type": "object",
                     "properties": {"code": {"type": "string",
                                             "description": "ICD-10 code, e.g. E11.9"}},
                     "required": ["code"]}},
    {"name": "lookup_loinc",
     "description": "Return the official LOINC long common name for an observation "
                    "code, and confirm the code exists in the published release.",
     "inputSchema": {"type": "object",
                     "properties": {"code": {"type": "string",
                                             "description": "LOINC code, e.g. 2345-7"}},
                     "required": ["code"]}},
    {"name": "lookup_snomed",
     "description": "Return the preferred display for a SNOMED CT concept id.",
     "inputSchema": {"type": "object",
                     "properties": {"code": {"type": "string",
                                             "description": "SNOMED CT concept id"}},
                     "required": ["code"]}},
]


def fhir_lookup(system, code):
    """CodeSystem/$lookup against the real terminology server."""
    url = TX + "/CodeSystem/$lookup?" + urllib.parse.urlencode(
        {"system": system, "code": code})
    req = urllib.request.Request(url, headers={
        "Accept": "application/fhir+json",
        "User-Agent": "iris-agentic-adapter/1.0",
    })
    with urllib.request.urlopen(req, timeout=25) as r:
        return json.loads(r.read().decode())


def param(resource, name):
    for p in resource.get("parameter", []):
        if p.get("name") == name:
            for key in ("valueString", "valueCode"):
                if key in p:
                    return p[key]
    return None


def do_lookup(tool, code):
    system, label = SYSTEMS[tool]
    try:
        resource = fhir_lookup(system, code)
    except urllib.error.HTTPError as e:
        # the server answers 404/422 with an OperationOutcome for an unknown code -
        # a real data quality finding, not a transport failure
        return {"isError": True,
                "content": [{"type": "text",
                             "text": "%s does not recognise code %s" % (label, code)}]}
    except Exception as e:
        return {"isError": True,
                "content": [{"type": "text",
                             "text": "terminology server unreachable: %s" % e}]}

    display = param(resource, "display")
    if not display:
        return {"isError": True,
                "content": [{"type": "text",
                             "text": "no display for %s in %s" % (code, label)}]}

    payload = {"code": code,
               "display": display,
               "system": system,
               "terminology": label,
               "version": param(resource, "version") or ""}
    return {"isError": False,
            "content": [{"type": "text", "text": json.dumps(payload)}],
            "structuredContent": payload}


def ok(id_, payload):
    return {"jsonrpc": "2.0", "id": id_, "result": payload}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        req = json.loads(self.rfile.read(n) or "{}")
        method, id_ = req.get("method"), req.get("id")
        params = req.get("params") or {}
        extra = {}

        if method == "initialize":
            extra["Mcp-Session-Id"] = uuid.uuid4().hex
            body = ok(id_, {"protocolVersion": "2025-06-18",
                            "capabilities": {"tools": {"listChanged": False}},
                            "serverInfo": {"name": "tx-fhir-terminology-mcp",
                                           "version": "1.0.0"}})
        elif method == "notifications/initialized":
            self.send_response(202)
            self.end_headers()
            return
        elif method == "ping":
            body = ok(id_, {})
        elif method == "tools/list":
            body = ok(id_, {"tools": TOOLS})
        elif method == "tools/call":
            name = params.get("name")
            code = ((params.get("arguments") or {}).get("code") or "").strip()
            if name in SYSTEMS:
                body = ok(id_, do_lookup(name, code))
            else:
                body = {"jsonrpc": "2.0", "id": id_,
                        "error": {"code": -32602,
                                  "message": "unknown tool: %s" % name}}
        else:
            body = {"jsonrpc": "2.0", "id": id_,
                    "error": {"code": -32601, "message": "method not found"}}

        raw = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        for k, v in extra.items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(raw)


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", 8767), Handler).serve_forever()
