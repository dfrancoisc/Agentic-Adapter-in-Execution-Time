"""Dependency-free mock MCP server for exercising the adapter.

Exposes several terminology tools so tool SELECTION is a real decision:
  translate_icd    ICD-10 -> SNOMED
  translate_loinc  LOINC   -> SNOMED
  translate_code   generic, kept for the simple fixed-tool examples
  echo             used to prove AllowedTools blocks what it should

Run:  python3 mock_mcp_server.py     (listens on 127.0.0.1:8765)
"""

import json
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

SESSIONS = set()

TOOLS = [
    {"name": "translate_icd",
     "description": "Translate an ICD-10 diagnosis code to SNOMED CT.",
     "inputSchema": {"type": "object",
                     "properties": {"code": {"type": "string"},
                                    "text": {"type": "string"}},
                     "required": ["code"]}},
    {"name": "translate_loinc",
     "description": "Translate a LOINC observation code to SNOMED CT.",
     "inputSchema": {"type": "object",
                     "properties": {"code": {"type": "string"},
                                    "text": {"type": "string"}},
                     "required": ["code"]}},
    {"name": "translate_code",
     "description": "Translate a local code to a target terminology.",
     "inputSchema": {"type": "object",
                     "properties": {"code": {"type": "string"},
                                    "system": {"type": "string"}},
                     "required": ["code"]}},
    {"name": "echo",
     "description": "Echo the input back.",
     "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}}},
    {"name": "whoami",
     "description": "Report the Authorization header the caller sent. Exists so a "
                    "test can prove credentials actually reach the server.",
     "inputSchema": {"type": "object", "properties": {}}},
]

# code -> (snomed code, display)
ICD = {"E11.9": ("44054006", "Diabetes mellitus type 2"),
       "I10": ("59621000", "Essential hypertension")}
LOINC = {"2345-7": ("33747003", "Glucose measurement"),
         "4548-4": ("43396009", "Haemoglobin A1c measurement")}


def ok(id_, payload):
    return {"jsonrpc": "2.0", "id": id_, "result": payload}


def translated(code, table):
    if code == "BOOM" or code not in table:
        return {"isError": True,
                "content": [{"type": "text", "text": "unknown code: %s" % code}]}
    sctid, display = table[code]
    payload = {"code": sctid, "display": display,
               "system": "http://snomed.info/sct", "source": code}
    return {"isError": False,
            "content": [{"type": "text", "text": json.dumps(payload)}],
            "structuredContent": payload}


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
            sid = uuid.uuid4().hex
            SESSIONS.add(sid)
            extra["Mcp-Session-Id"] = sid
            body = ok(id_, {"protocolVersion": "2025-06-18",
                            "capabilities": {"tools": {"listChanged": False}},
                            "serverInfo": {"name": "mock-terminology-mcp",
                                           "version": "0.2.0"}})
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
            args = params.get("arguments") or {}
            code = args.get("code", "")
            if name == "translate_icd":
                body = ok(id_, translated(code, ICD))
            elif name == "translate_loinc":
                body = ok(id_, translated(code, LOINC))
            elif name == "translate_code":
                table = LOINC if code in LOINC else ICD
                body = ok(id_, translated(code, table))
            elif name == "whoami":
                auth = self.headers.get("Authorization") or "(none)"
                body = ok(id_, {"isError": False,
                                "content": [{"type": "text", "text": auth}],
                                "structuredContent": {"authorization": auth}})
            elif name == "echo":
                body = ok(id_, {"isError": False,
                                "content": [{"type": "text",
                                             "text": args.get("text", "")}]})
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
    HTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
