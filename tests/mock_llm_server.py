"""Dependency-free mock LLM endpoint, Anthropic Messages API shape.

Exists so the tool-selection loop can be tested end to end without credentials or
token spend. It does not reason - it pattern-matches the coding system mentioned in
the prompt and returns the JSON tool choice a real model would return.

Run:  python3 mock_llm_server.py     (listens on 127.0.0.1:8766)
"""

import json
from http.server import BaseHTTPRequestHandler, HTTPServer


def choose(prompt):
    """Return the tool choice a model would produce for this prompt.

    Reads only the CONTEXT block. An earlier version matched against the whole
    prompt and always picked translate_icd, because the CATALOG text contains the
    word "ICD" in a tool description - the tell-tale of a selector keying off the
    wrong part of its input. A real model weighs the data it was given, not the
    vocabulary of the menu.
    """
    context = prompt.split("CONTEXT:", 1)[1].lower() if "CONTEXT:" in prompt else prompt.lower()

    if '"i10"' in context or "icd" in context:
        return {"tool": "translate_icd",
                "reason": "the observation carries an ICD-10 code (I10)"}
    if '"ln"' in context or "loinc" in context:
        return {"tool": "translate_loinc",
                "reason": "the observation carries a LOINC code (LN)"}
    return {"tool": "translate_code",
            "reason": "coding system not recognised, falling back to the generic tool"}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        req = json.loads(self.rfile.read(n) or "{}")

        # Anthropic Messages API request shape
        parts = []
        for m in req.get("messages", []):
            c = m.get("content")
            if isinstance(c, str):
                parts.append(c)
            elif isinstance(c, list):
                parts.extend(b.get("text", "") for b in c if isinstance(b, dict))
        if req.get("system"):
            parts.append(req["system"])
        prompt = "\n".join(parts)

        answer = choose(prompt)
        body = {
            "id": "msg_mock",
            "type": "message",
            "role": "assistant",
            "model": req.get("model", "mock-model"),
            "content": [{"type": "text", "text": json.dumps(answer)}],
            "stop_reason": "end_turn",
            "usage": {"input_tokens": len(prompt) // 4, "output_tokens": 20},
        }
        raw = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", 8766), Handler).serve_forever()
