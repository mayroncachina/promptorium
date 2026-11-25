#!/usr/bin/env python3
"""Codex falso do E2E da SPEC-107: App Server sem turno pago.

Turnos com leituras por comando (commandActions), MCP, subagente, uso pelo
`last` e janela de 400 mil; o turno 2 é redirecionado pelo serviço, o turno 3
compacta sozinho e o thread/compact/start roda como turno."""
import json, os, sys, threading, time, uuid

HERE = os.path.dirname(os.path.abspath(__file__))
LOG = os.path.join(HERE, "..", "fake.log")


def log(*a):
    with open(LOG, "a") as f:
        f.write(time.strftime("%H:%M:%S ") + " ".join(str(x) for x in a) + "\n")


args = sys.argv[1:]
if args[:1] == ["--version"]:
    print("codex-cli 0.170.0")
    sys.exit(0)
if args[:2] == ["login", "status"]:
    print("Logged in using ChatGPT (fake)")
    sys.exit(0)
if args[:2] == ["app-server", "--help"]:
    print("Run the app server (fake)")
    sys.exit(0)
if args[:1] != ["app-server"]:
    sys.stderr.write("fake codex: só app-server\n")
    sys.exit(2)

log("start", json.dumps(args))
lock = threading.Lock()
state = {"thread": None, "cwd": os.getcwd(), "turns": 0, "model": "gpt-6.2-sol",
         "total": 0}


def send(m):
    with lock:
        sys.stdout.write(json.dumps(m, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def note(method, params, thread=None):
    send({"method": method, "params": dict(params, threadId=thread or state["thread"])})


def item(kind, it, turn):
    for m in ("item/started", "item/completed") if kind == "both" else (kind,):
        note(m, {"turnId": turn, "item": it})


def usage(turn, total, cached=0, output=1800, input_zero=False, thread=None):
    state["total"] += total
    inp = 0 if input_zero else total - output
    last = {"totalTokens": total, "inputTokens": inp,
            "cachedInputTokens": 0 if input_zero else min(cached, inp),
            "cacheWriteInputTokens": 0,
            "outputTokens": 0 if input_zero else output, "reasoningOutputTokens": 0}
    note("thread/tokenUsage/updated", {"turnId": turn, "tokenUsage": {
        "total": dict(last, totalTokens=state["total"]), "last": last,
        "modelContextWindow": 400000}}, thread=thread)


def say(turn, text):
    item("both", {"type": "agentMessage", "id": "msg-" + uuid.uuid4().hex[:8],
                  "text": text}, turn)


def cmd(turn, line, actions):
    cid = "exec-" + uuid.uuid4().hex[:8]
    it = {"type": "commandExecution", "id": cid, "command": "/usr/bin/zsh -lc '%s'" % line,
          "cwd": state["cwd"], "status": "inProgress", "commandActions": actions}
    item("item/started", it, turn)
    time.sleep(0.15)
    item("item/completed", dict(it, status="completed", exitCode=0,
                                aggregatedOutput="ok\n", durationMs=120), turn)


def turn_script(turn, n):
    time.sleep(0.4)
    cache = os.path.join(state["cwd"], "lib/features/catalog/cache.dart")
    if n == 2:
        note("model/rerouted", {"turnId": turn, "fromModel": "gpt-6.2-sol",
                                "toModel": "gpt-6.1-terra",
                                "reason": "highRiskCyberActivity"})
        state["model"] = "gpt-6.1-terra"
    cmd(turn, "sed -n 1,120p lib/features/catalog/cache.dart",
        [{"type": "read", "command": "sed -n 1,120p lib/features/catalog/cache.dart",
          "name": "cache.dart", "path": cache}])
    if state.get("manual"):
        usage(turn, 58000, cached=40000)
    else:
        usage(turn, [0, 118000, 196000, 288000, 214000, 241000][min(n, 5)] - 20000, cached=150000)
    cmd(turn, 'rg "expiresAt" lib/',
        [{"type": "search", "command": 'rg "expiresAt" lib/', "query": "expiresAt",
          "path": "lib/"}])
    if n == 1:
        cmd(turn, "ls test/catalog", [{"type": "listFiles", "command": "ls test/catalog",
                                       "path": "test/catalog/"}])
        mid = "mcp-" + uuid.uuid4().hex[:6]
        item("both", {"type": "mcpToolCall", "id": mid, "server": "github",
                      "tool": "search_issues", "arguments": {"q": "cache"},
                      "status": "completed", "result": {"content": []}}, turn)
        sub = "7f2e9a10-" + uuid.uuid4().hex[:6]
        item("both", {"type": "collabAgentToolCall", "id": "agent-" + uuid.uuid4().hex[:6],
                      "tool": "spawnAgent", "prompt": "explore o catálogo",
                      "receiverThreadIds": [sub], "senderThreadId": state["thread"],
                      "status": "completed"}, turn)
        # The subagent's own usage: another thread, never the main reading.
        usage(turn, 99000, thread=sub)
    if n == 3:
        cid = "compact-" + uuid.uuid4().hex[:6]
        item("item/started", {"type": "contextCompaction", "id": cid}, turn)
        time.sleep(0.5)
        usage(turn, 52000, input_zero=True)
        item("item/completed", {"type": "contextCompaction", "id": cid}, turn)
        usage(turn, 60000, cached=40000)
    elif state.get("manual"):
        usage(turn, 64000, cached=40000)
    else:
        usage(turn, [0, 118000, 196000, 288000, 214000, 241000][min(n, 5)], cached=180000)
    say(turn, "O cache agora expira pelo `expiresAt` do servidor e os testes do catálogo passam.")
    note("turn/completed", {"turn": {"id": turn, "status": "completed"}})


def compact_script(turn):
    state["manual"] = True
    time.sleep(0.3)
    note("turn/started", {"turn": {"id": turn, "status": "inProgress"}})
    cid = "compact-" + uuid.uuid4().hex[:6]
    item("item/started", {"type": "contextCompaction", "id": cid}, turn)
    time.sleep(1.2)
    usage(turn, 46000, input_zero=True)
    item("item/completed", {"type": "contextCompaction", "id": cid}, turn)
    note("turn/completed", {"turn": {"id": turn, "status": "completed"}})


def handle(m):
    meth, mid, p = m.get("method"), m.get("id"), m.get("params") or {}
    if mid is None:
        return
    r = {}
    if meth == "initialize":
        r = {"userAgent": "promptorium/0.170.0 (fake; e2e)", "codexHome": "[fake]",
             "platformFamily": "unix", "platformOs": "linux"}
    elif meth == "account/read":
        r = {"account": {"type": "chatgpt", "planType": "plus"}, "requiresOpenaiAuth": False}
    elif meth == "account/rateLimits/read":
        r = {"rateLimits": {"limitId": "codex",
                            "primary": {"usedPercent": 41, "windowDurationMins": 300,
                                        "resetsAt": int(time.time()) + 7800},
                            "secondary": {"usedPercent": 22, "windowDurationMins": 10080,
                                          "resetsAt": int(time.time()) + 360000},
                            "planType": "plus"}}
    elif meth == "model/list":
        r = {"data": [{"id": mdl, "inputModalities": ["text"],
                       "supportedReasoningEfforts": [{"reasoningEffort": "low"},
                                                     {"reasoningEffort": "medium"}]}
                      for mdl in ("gpt-6.2-sol", "gpt-6.1-terra")],
             "nextCursor": None}
    elif meth == "config/read":
        r = {"config": {"model_auto_compact_token_limit_scope": "total"}}
    elif meth == "command/exec":
        r = {"exitCode": 0, "stdout": "", "stderr": ""}
    elif meth in ("thread/start", "thread/resume", "thread/fork"):
        state["thread"] = (p.get("threadId") if meth == "thread/resume" else None) or str(uuid.uuid4())
        state["cwd"] = p.get("cwd") or state["cwd"]
        log("thread", meth, json.dumps(p.get("config")))
        r = {"thread": {"id": state["thread"]}, "model": state["model"],
             "instructionSources": [os.path.join(state["cwd"], "AGENTS.md"),
                                    os.path.join(state["cwd"], "packages/api/CLAUDE.md")],
             "approvalPolicy": "never", "sandbox": {"type": "readOnly"}}
    elif meth == "hooks/list":
        r = {"data": [{"cwd": state["cwd"], "warnings": [], "errors": [], "hooks": []}]}
    elif meth == "turn/start":
        state["turns"] += 1
        turn = str(uuid.uuid4())
        send({"id": mid, "result": {"turn": {"id": turn, "status": "inProgress"}}})
        note("turn/started", {"turn": {"id": turn, "status": "inProgress"}})
        threading.Thread(target=turn_script, args=(turn, state["turns"]), daemon=True).start()
        return
    elif meth == "thread/compact/start":
        log("compact/start", json.dumps(p))
        send({"id": mid, "result": {}})
        threading.Thread(target=compact_script, args=(str(uuid.uuid4()),), daemon=True).start()
        return
    send({"id": mid, "result": r})


for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        msg = json.loads(line)
    except ValueError:
        continue
    log("recv", (msg.get("method") or "answer"), msg.get("id"))
    threading.Thread(target=handle, args=(msg,), daemon=True).start()
