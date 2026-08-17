import json, uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

SESSIONS = set()
TOOLS = [
    {"name": "translate_code",
     "description": "Translate a local code to a target terminology.",
     "inputSchema": {"type": "object",
                     "properties": {"code": {"type": "string"}, "system": {"type": "string"}},
                     "required": ["code"]}},
    {"name": "echo",
     "description": "Echo the input back.",
     "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}}},
]

def result(id_, payload):
    return {"jsonrpc": "2.0", "id": id_, "result": payload}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        req = json.loads(self.rfile.read(n) or "{}")
        method, id_ = req.get("method"), req.get("id")
        params = req.get("params") or {}
        sid = self.headers.get("Mcp-Session-Id")
        extra = {}

        if method == "initialize":
            sid = uuid.uuid4().hex
            SESSIONS.add(sid)
            extra["Mcp-Session-Id"] = sid
            body = result(id_, {"protocolVersion": "2025-06-18",
                                "capabilities": {"tools": {"listChanged": False}},
                                "serverInfo": {"name": "mock-mcp", "version": "0.1.0"}})
        elif method == "notifications/initialized":
            self.send_response(202); self.end_headers(); return
        elif method == "ping":
            body = result(id_, {})
        elif method == "tools/list":
            body = result(id_, {"tools": TOOLS})
        elif method == "tools/call":
            name = params.get("name")
            args = params.get("arguments") or {}
            if name == "translate_code":
                code = args.get("code", "")
                if code == "BOOM":
                    body = result(id_, {"isError": True,
                                        "content": [{"type": "text", "text": "unknown code"}]})
                else:
                    payload = {"code": "44054006", "display": "Diabetes mellitus type 2",
                               "system": "http://snomed.info/sct", "source": code}
                    body = result(id_, {"isError": False,
                                        "content": [{"type": "text", "text": json.dumps(payload)}],
                                        "structuredContent": payload})
            elif name == "echo":
                body = result(id_, {"isError": False,
                                    "content": [{"type": "text", "text": args.get("text", "")}]})
            else:
                body = {"jsonrpc": "2.0", "id": id_,
                        "error": {"code": -32602, "message": "unknown tool: %s" % name}}
        else:
            body = {"jsonrpc": "2.0", "id": id_,
                    "error": {"code": -32601, "message": "method not found"}}

        raw = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        for k, v in extra.items(): self.send_header(k, v)
        self.end_headers()
        self.wfile.write(raw)

HTTPServer(("127.0.0.1", 8765), H).serve_forever()
