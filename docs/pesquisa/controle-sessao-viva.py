"""Sondas: set_permission_mode com a sessão viva, mensagem no meio do turno e
--tools como lista de permitidos.

Uso: python3 controle-sessao-viva.py <claude> [modelo]
"""
import json, os, subprocess, sys, tempfile, threading, time

cli = sys.argv[1]
model = sys.argv[2] if len(sys.argv) > 2 else "haiku"
repo = tempfile.mkdtemp(prefix="sonda-controle-")
subprocess.run(["git", "init", "-q", repo], check=True)


def start(extra):
    return subprocess.Popen([cli, "-p", "--model", model, "--strict-mcp-config",
        "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
        "--permission-prompt-tool", "stdio", "--max-budget-usd", "0.20", *extra],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, cwd=repo)


def send(p, obj):
    p.stdin.write(json.dumps(obj) + "\n"); p.stdin.flush()


def user(text):
    return {"type": "user", "message": {"role": "user", "content": text}}


print("== 1. set_permission_mode (default → acceptEdits) com a sessão viva")
p = start(["--permission-mode", "default"])
send(p, {"type": "control_request", "request_id": "pm-1",
         "request": {"subtype": "set_permission_mode", "mode": "acceptEdits"}})
send(p, user("Use a ferramenta Write para criar a.txt com o texto a. Depois responda OK."))
for line in p.stdout:
    m = json.loads(line)
    t = m.get("type")
    if t == "control_response":
        print("CONTROL_RESPONSE", line.strip()[:300])
    elif t == "control_request":
        print("PEDIU PERMISSÃO (modo não mudou):", m["request"].get("tool_name"))
        send(p, {"type": "control_response", "response": {"subtype": "success",
            "request_id": m["request_id"], "response": {"behavior": "allow",
            "updatedInput": m["request"].get("input", {})}}})
    elif t == "system" and m.get("subtype") == "init":
        print("INIT permissionMode=", m.get("permissionMode"))
    elif t == "result":
        print("RESULT", m.get("subtype"), str(m.get("result"))[:100]); p.stdin.close()
p.wait()

print("== 2. mensagem do usuário no meio do turno")
p = start(["--permission-mode", "acceptEdits", "--allowedTools", "Bash(sleep *)"])
send(p, user("Rode com Bash exatamente `sleep 6` e depois responda PRIMEIRA."))
sent = False; results = 0
for line in p.stdout:
    m = json.loads(line)
    t = m.get("type")
    if t == "assistant":
        for b in m["message"]["content"]:
            if b.get("type") == "tool_use" and not sent:
                time.sleep(1)
                send(p, user("Aviso do Promptorium: inclua também a palavra BANANA na resposta."))
                sent = True
                print("ENVIADA no meio do turno, durante", b["name"])
            elif b.get("type") == "text":
                print("TEXT", b["text"][:150])
    elif t == "user" and not isinstance(m["message"]["content"], list):
        print("USER_ECO", str(m["message"]["content"])[:120])
    elif t == "control_request":
        send(p, {"type": "control_response", "response": {"subtype": "success",
            "request_id": m["request_id"], "response": {"behavior": "allow",
            "updatedInput": m["request"].get("input", {})}}})
    elif t == "result":
        results += 1
        print("RESULT", results, m.get("subtype"), str(m.get("result"))[:150])
        if results >= 2 or "BANANA" in str(m.get("result")):
            p.stdin.close()
        else:
            threading.Timer(20, lambda: p.stdin.close()).start()
p.wait()

print("== 3. --tools Read,Glob,Grep (lista de permitidos)")
p = start(["--permission-mode", "default", "--tools", "Read,Glob,Grep"])
send(p, user("Liste as ferramentas que você tem disponíveis (só os nomes) e tente rodar `ls` com Bash."))
for line in p.stdout:
    m = json.loads(line)
    t = m.get("type")
    if t == "system" and m.get("subtype") == "init":
        print("INIT tools=", m.get("tools"))
    elif t == "control_request":
        print("PEDIU PERMISSÃO:", m["request"].get("tool_name"))
        send(p, {"type": "control_response", "response": {"subtype": "success",
            "request_id": m["request_id"], "response": {"behavior": "deny", "message": "não"}}})
    elif t == "result":
        print("RESULT", m.get("subtype"), str(m.get("result"))[:200]); p.stdin.close()
p.wait()
