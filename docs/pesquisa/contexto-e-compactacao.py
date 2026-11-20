"""Sonda SPEC-087: medição de contexto e compactação em -p stream-json.

Uso: python3 contexto-e-compactacao.py <claude> <cenario> [modelo] [sessão]
Cenários: basico, modelo, compact, resume <sessão>, fork <sessão>, auto, flag.
Grava cada linha recebida em out-<cenario>.jsonl (no diretório atual).
"""
import json, os, subprocess, sys, tempfile, threading, time, uuid

cli = sys.argv[1]
scen = sys.argv[2]
model = sys.argv[3] if len(sys.argv) > 3 else "haiku"
repo = os.environ.get("SONDA_REPO") or tempfile.mkdtemp(prefix="sonda-contexto-")
if not os.path.isdir(os.path.join(repo, ".git")):
    subprocess.run(["git", "init", "-q", repo], check=True)
    open(os.path.join(repo, "nota.txt"), "w").write("linha um\nlinha dois\nlinha três\n")
out = open(f"out-{scen}.jsonl", "a")


def start(extra):
    return subprocess.Popen([cli, "-p", "--model", model, "--strict-mcp-config",
        "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
        "--permission-prompt-tool", "stdio", "--permission-mode", "default",
        "--allowedTools", "Read", *extra],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, cwd=repo)


def send(p, obj):
    out.write(json.dumps({"__sent": obj}) + "\n")
    p.stdin.write(json.dumps(obj) + "\n"); p.stdin.flush()


def user(text):
    return {"type": "user", "message": {"role": "user", "content": text}}


def ctl(rid, req):
    return {"type": "control_request", "request_id": rid, "request": req}


def run(extra, steps, label):
    """steps: list of messages; a step is sent after each `result`."""
    print(f"== {label}")
    p = start(extra)
    queue = list(steps)
    send(p, queue.pop(0))
    sid = None
    for line in p.stdout:
        out.write(line)
        m = json.loads(line)
        t, st = m.get("type"), m.get("subtype")
        if t == "system":
            if st == "init":
                sid = m.get("session_id")
                print("INIT model=", m.get("model"), "sid=", sid,
                      "slash=", [c for c in m.get("slash_commands", []) if "compact" in c or "context" in c])
            else:
                keys = {k: m[k] for k in m if k not in ("uuid", "session_id", "type")}
                print("SYSTEM", st, json.dumps(keys)[:400])
        elif t == "assistant":
            u = m["message"].get("usage", {})
            print("ASSIST parent=", m.get("parent_tool_use_id"), "model=", m["message"].get("model"),
                  "usage=", {k: u.get(k) for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")})
        elif t == "control_response":
            print("CONTROL_RESPONSE", json.dumps(m)[:1500])
            if queue and isinstance(queue[0], dict) and queue[0].get("__after_ctl"):
                queue.pop(0); send(p, queue.pop(0)) if queue else None
        elif t == "control_request":
            send(p, {"type": "control_response", "response": {"subtype": "success",
                "request_id": m["request_id"], "response": {"behavior": "allow",
                "updatedInput": m["request"].get("input", {})}}})
        elif t == "user" and not isinstance(m["message"].get("content"), list):
            print("USER_ECO", str(m["message"]["content"])[:200])
        elif t == "result":
            print("RESULT", st, "num_turns=", m.get("num_turns"), "usage=", m.get("usage"),
                  "modelUsage=", json.dumps(m.get("modelUsage"))[:600], "result=", str(m.get("result"))[:120])
            if queue:
                nxt = queue.pop(0)
                while nxt.get("type") == "control_request":
                    send(p, nxt)
                    time.sleep(4)
                    nxt = queue.pop(0) if queue else None
                    if nxt is None: break
                if nxt is not None:
                    send(p, nxt)
                if not queue and nxt is None:
                    threading.Timer(15, lambda: p.stdin.close()).start()
            else:
                threading.Timer(8, lambda: p.stdin.close()).start()
    p.wait()
    print("SID", sid, "REPO", repo)
    return sid


if scen == "basico":
    run([], [
        user("Responda só: oi."),
        ctl("ctx-1", {"subtype": "get_context_usage", "detail": "summary"}),
        user("Leia nota.txt com a ferramenta Read e diga quantas linhas tem. Responda curto."),
        ctl("ctx-2", {"subtype": "get_context_usage", "detail": "summary"}),
        ctl("ctx-3", {"subtype": "get_context_usage", "detail": "full"}),
        user("Responda só: ok."),
    ], "1-3 primeira resposta, leitura, cache, get_context_usage")
elif scen == "modelo":
    run(["--autocompact", "200k"], [
        user("Responda só: oi."),
        ctl("m-1", {"subtype": "set_model", "model": "sonnet"}),
        user("Responda só: ok."),
        ctl("ctx-m", {"subtype": "get_context_usage", "detail": "summary"}),
        user("Responda só: fim."),
    ], "4 troca de modelo")
elif scen == "compact":
    run(["--autocompact", "200k"], [
        user("Responda só: oi."),
        ctl("ctx-c0", {"subtype": "get_context_usage", "detail": "summary"}),
        user("/compact foco: a palavra oi"),
        ctl("ctx-c", {"subtype": "get_context_usage", "detail": "summary"}),
        user("Responda só: ok."),
    ], "5 /compact em stream-json")
elif scen == "resume":
    sid = sys.argv[4]
    run(["--resume", sid, "--autocompact", "200k"], [
        ctl("ctx-r0", {"subtype": "get_context_usage", "detail": "summary"}),
        user("Responda só: retomado."),
    ], "6 retomada")
elif scen == "fork":
    sid = sys.argv[4]
    for i in (1, 2):
        run(["--resume", sid, "--fork-session", "--autocompact", "200k"], [
            user(f"Responda só: fork {i}."),
            ctl(f"ctx-f{i}", {"subtype": "get_context_usage", "detail": "summary"}),
            user("Responda só: ok."),
        ], f"7 fork {i}")
elif scen == "auto":
    import random
    random.seed(7)
    words = ["casa", "rio", "pedra", "vento", "folha", "nuvem", "trilha", "porta", "lago", "farol"]
    def bloco(n):
        return " ".join(f"{random.choice(words)}{random.randint(0, 9999)}" for _ in range(n))
    # --autocompact 100k: a sonda 5 mostrou limiar = janela − 33k (≈ 67k).
    run(["--autocompact", "100k"], [
        user("Guarde este texto, responda só: ok.\n" + bloco(9000)),
        ctl("ctx-a1", {"subtype": "get_context_usage", "detail": "summary"}),
        user("Mais texto, responda só: ok.\n" + bloco(9000)),
        ctl("ctx-a2", {"subtype": "get_context_usage", "detail": "summary"}),
        user("Mais texto, responda só: ok.\n" + bloco(9000)),
        ctl("ctx-a3", {"subtype": "get_context_usage", "detail": "summary"}),
        user("Responda só: fim."),
        ctl("ctx-a4", {"subtype": "get_context_usage", "detail": "summary"}),
    ], "8 compactação automática (--autocompact 100k)")
elif scen == "flag":
    # 9. apply_flag_settings muda o limiar com a sessão viva? (só control requests, sem turno)
    p = start(["--autocompact", "200k"])
    reqs = [ctl("c1", {"subtype": "get_context_usage", "detail": "summary"}),
            ctl("f1", {"subtype": "apply_flag_settings", "settings": {"autoCompactWindow": 300000}}),
            ctl("c2", {"subtype": "get_context_usage", "detail": "summary"})]
    send(p, reqs.pop(0))
    for line in p.stdout:
        out.write(line)
        m = json.loads(line)
        if m.get("type") == "control_response":
            r = m["response"].get("response") or {}
            print(m["response"]["request_id"], {k: r.get(k) for k in ("maxTokens", "autoCompactThreshold")})
            if reqs:
                send(p, reqs.pop(0))
            else:
                p.stdin.close()
    p.wait()
