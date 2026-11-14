"""Sonda: MCP do app por HTTP local, com token por execução (SPEC-052).

Uso: python3 mcp-do-app.py <claude> [servidor-do-usuario-a-negar] [modelo]

Sobe um servidor MCP mínimo ("Streamable HTTP", só respostas JSON) em
127.0.0.1:<porta livre>, que exige `Authorization: Bearer <token>` e expõe
`ler` (leitura) e `criar` (escrita). Cada chamada fica no log do servidor.
Roda `claude -p` como o app roda (stream-json + --permission-prompt-tool
stdio), numa pasta temporária, nos cenários:

  base    — --allowedTools mcp__promptorium__ler; `criar` é negado pelo stdio;
            com --settings negando o servidor do usuário (se informado);
  token   — token errado no --mcp-config (o servidor responde 401);
  bypass  — --dangerously-skip-permissions: `criar` roda sem can_use_tool?
  resume  — --resume da sessão do cenário base com outro arquivo/token;
  perguntar — como o modo Perguntar do app: --tools só de leitura (sem
            ToolSearch) e --strict-mcp-config; `ler` em --allowedTools;
  planejar — como o modo Planejar: --permission-mode plan; `criar` chega
            por can_use_tool e é aprovado?

A variável SONDA_CENARIOS (ex.: "perguntar") roda só os cenários listados.
"""
import json, os, subprocess, sys, tempfile, threading, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

cli = sys.argv[1]
denied = sys.argv[2] if len(sys.argv) > 2 else None
model = sys.argv[3] if len(sys.argv) > 3 else "haiku"
tmp = tempfile.mkdtemp(prefix="sonda-mcp-app-")
TOKENS = set()
LOG = []
TOOLS = [
    {"name": "ler", "description": "Lê o quadro (só leitura).",
     "inputSchema": {"type": "object", "properties": {}},
     "annotations": {"readOnlyHint": os.environ.get("SONDA_READONLY") == "1"}},
    {"name": "criar", "description": "Cria uma spec rascunho.",
     "inputSchema": {"type": "object", "properties": {
         "titulo": {"type": "string"}}, "required": ["titulo"]}},
]


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body=None, headers=()):
        self.send_response(code)
        for k, v in headers:
            self.send_header(k, v)
        data = json.dumps(body).encode() if body is not None else b""
        if body is not None:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        LOG.append(("GET", self.headers.get("Authorization")))
        self._send(405)

    def do_DELETE(self):
        self._send(405)

    def do_POST(self):
        auth = self.headers.get("Authorization", "")
        n = int(self.headers.get("Content-Length", "0"))
        req = json.loads(self.rfile.read(n) or b"{}")
        method = req.get("method")
        tok = auth[7:] if auth.startswith("Bearer ") else None
        LOG.append(("POST", method, tok))
        if tok not in TOKENS:
            return self._send(401, {"error": "token"},
                              [("WWW-Authenticate", "Bearer")])
        rid = req.get("id")
        if rid is None:  # notificação
            return self._send(202)
        if method == "initialize":
            res = {"protocolVersion": req["params"]["protocolVersion"],
                   "capabilities": {"tools": {}},
                   "serverInfo": {"name": "promptorium", "version": "0"}}
        elif method == "tools/list":
            res = {"tools": TOOLS}
        elif method == "tools/call":
            name = req["params"]["name"]
            LOG.append(("CALL", name, req["params"].get("arguments")))
            res = {"content": [{"type": "text", "text": f"{name}: ok"}]}
        else:
            return self._send(200, {"jsonrpc": "2.0", "id": rid, "error": {
                "code": -32601, "message": "método"}})
        self._send(200, {"jsonrpc": "2.0", "id": rid, "result": res})


srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
port = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()


def config(token):
    path = os.path.join(tmp, f"mcp-{token[:8]}.json")
    json.dump({"mcpServers": {"promptorium": {
        "type": "http", "url": f"http://127.0.0.1:{port}/mcp",
        "headers": {"Authorization": f"Bearer {token}"}}}}, open(path, "w"))
    os.chmod(path, 0o600)
    return path


PROMPT = ("Chame a ferramenta mcp__promptorium__ler. Depois chame "
          "mcp__promptorium__criar com titulo 'Sonda'. Não faça mais nada "
          "e responda numa linha o que cada uma devolveu.")


def run(extra, prompt=PROMPT, deny_criar=True):
    LOG.clear()
    p = subprocess.Popen([cli, "-p", "--model", model,
        "--input-format", "stream-json", "--output-format", "stream-json",
        "--verbose", "--permission-prompt-tool", "stdio",
        "--max-budget-usd", "0.10", *extra],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, text=True, cwd=tmp)
    p.stdin.write(json.dumps({"type": "user", "message": {
        "role": "user", "content": prompt}}) + "\n")
    p.stdin.flush()
    out = {"init": None, "can_use_tool": [], "tool_results": [], "sid": None}
    for line in p.stdout:
        m = json.loads(line)
        t = m.get("type")
        if t == "system" and m.get("subtype") == "init":
            out["sid"] = m.get("session_id")
            out["init"] = {
                "versao": m.get("claude_code_version"),
                "mcp_servers": [s for s in m.get("mcp_servers", [])
                                if s.get("name") in ("promptorium", denied)],
                "ferramentas": [x for x in m.get("tools", [])
                                if x.startswith("mcp__promptorium")],
            }
        elif t == "control_request":
            r = m["request"]
            out["can_use_tool"].append({
                "tool": r.get("tool_name"), "input": r.get("input"),
                "sugestoes": r.get("permission_suggestions")})
            if deny_criar and r.get("tool_name", "").endswith("criar"):
                resp = {"behavior": "deny", "message": "A pessoa negou."}
            else:
                resp = {"behavior": "allow", "updatedInput": r.get("input")}
            p.stdin.write(json.dumps({"type": "control_response", "response": {
                "subtype": "success", "request_id": m["request_id"],
                "response": resp}}) + "\n")
            p.stdin.flush()
        elif t == "user":
            for c in m["message"].get("content", []):
                if isinstance(c, dict) and c.get("type") == "tool_result":
                    out["tool_results"].append(str(c.get("content"))[:160])
        elif t == "result":
            out["resultado"] = str(m.get("result"))[:200]
            break
    p.stdin.close()
    p.wait(timeout=60)
    out["log_servidor"] = [x for x in LOG if x[0] == "CALL"]
    out["metodos"] = sorted({x[1] for x in LOG if x[0] == "POST"})
    out["gets"] = len([x for x in LOG if x[0] == "GET"])
    return out


def show(nome, r):
    print(f"== {nome}")
    print(json.dumps(r, indent=1, ensure_ascii=False))


SO = os.environ.get("SONDA_CENARIOS", "").split(",")
quer = lambda n: SO == [""] or n in SO
tok = uuid.uuid4().hex
TOKENS.add(tok)
base = None
if quer("base") or quer("resume"):
    extra = ["--mcp-config", config(tok), "--allowedTools", "mcp__promptorium__ler"]
    if denied:
        settings = os.path.join(tmp, "settings.json")
        json.dump({"deniedMcpServers": [{"serverName": denied}]}, open(settings, "w"))
        extra += ["--settings", settings]
    base = run(extra)
    show("base", base)

if quer("token"):
    show("token", run(["--mcp-config", config(uuid.uuid4().hex)],
                      prompt="Liste as ferramentas mcp__promptorium que você tem."
                      " Responda numa linha."))

tok2 = uuid.uuid4().hex
TOKENS.add(tok2)
if quer("bypass"):
    show("bypass", run(["--mcp-config", config(tok2),
                        "--dangerously-skip-permissions"]))

if quer("resume"):
    TOKENS.discard(tok)  # revogado: só o token novo vale
    tok3 = uuid.uuid4().hex
    TOKENS.add(tok3)
    show("resume", run(["--resume", base["sid"], "--mcp-config", config(tok3),
                        "--allowedTools", "mcp__promptorium__ler"],
                       prompt="Chame mcp__promptorium__ler de novo e diga o que "
                       "devolveu, numa linha."))

if quer("perguntar"):
    tok4 = uuid.uuid4().hex
    TOKENS.add(tok4)
    show("perguntar", run([
        "--permission-mode", "default",
        "--mcp-config", config(tok4), "--strict-mcp-config",
        "--tools", "Read,Glob,Grep,WebFetch,WebSearch,TodoWrite",
        "--allowedTools", "mcp__promptorium__ler",
        "--disallowedTools", "Edit", "Write", "Bash", "mcp__promptorium__criar"]))

if quer("planejar"):
    tok5 = uuid.uuid4().hex
    TOKENS.add(tok5)
    show("planejar", run([
        "--permission-mode", "plan", "--mcp-config", config(tok5),
        "--allowedTools", "mcp__promptorium__ler"], deny_criar=False))
srv.shutdown()
