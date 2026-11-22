#!/usr/bin/env python3
"""Codex falso para o E2E da SPEC-103: responde o App Server sem turno pago.

Modo em $FAKE_CODEX_MODE_FILE ("nativo" ou "posturno"). No nativo, o hooks/list
devolve os hooks do app como trusted e o turno roda o script do app como o
Codex faria (preToolUse antes do comando, postToolUse depois do apply_patch).
No pós-turno, eles vêm untrusted e o turno pede aprovação de comandos."""
import json, os, re, subprocess, sys, threading, time, uuid

REAL = "/home/mayron/.local/bin/codex"
HERE = os.path.dirname(os.path.abspath(__file__))
MODE_FILE = os.environ.get("FAKE_CODEX_MODE_FILE", os.path.join(HERE, "mode"))
LOG = os.path.join(HERE, "fake.log")


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
if args[:2] == ["app-server", "generate-json-schema"]:
    env = dict(os.environ, CODEX_HOME=os.path.join(HERE, "codexhome"))
    os.makedirs(env["CODEX_HOME"], exist_ok=True)
    os.execve(REAL, [REAL] + args, env)
if args[:1] != ["app-server"]:
    sys.stderr.write("fake codex: só app-server\n")
    sys.exit(2)

log("start", json.dumps(args))
hooks = {}  # eventName -> command
for i, a in enumerate(args):
    if a == "-c" and i + 1 < len(args):
        m = re.match(r"hooks\.(\w+)=", args[i + 1])
        if m:
            cm = re.search(r'command="((?:[^"\\]|\\.)*)"', args[i + 1])
            ev = m.group(1)[0].lower() + m.group(1)[1:]
            hooks[ev] = json.loads('"%s"' % cm.group(1))
mode = open(MODE_FILE).read().strip() if os.path.exists(MODE_FILE) else "posturno"
log("mode", mode, "hooks", list(hooks))

lock = threading.Lock()
pending = {}
state = {"thread": None, "cwd": os.getcwd(), "approval": "never", "n": 0}


def send(m):
    with lock:
        sys.stdout.write(json.dumps(m, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def note(method, params):
    send({"method": method, "params": dict(params, threadId=state["thread"])})


def ask(method, params):
    rid = 1000 + state["n"]
    state["n"] += 1
    ev = threading.Event()
    pending[rid] = [ev, None]
    send({"method": method, "id": rid, "params": dict(params, threadId=state["thread"])})
    ev.wait(600)
    return pending.pop(rid)[1]


def item(kind, it, turn):
    for m in ("item/started", "item/completed") if kind == "both" else (kind,):
        note(m, {"turnId": turn, "item": it})


def say(turn, text):
    i = "msg-" + uuid.uuid4().hex[:8]
    item("both", {"type": "agentMessage", "id": i, "text": text}, turn)


def run_hook(event, payload, turn):
    cmd = hooks.get(event)
    if not cmd:
        return 0, ""
    hid = "hook-" + uuid.uuid4().hex[:6]
    run = {"id": hid, "eventName": event, "handlerType": "command",
           "executionMode": "sync", "scope": "turn", "source": "sessionFlags",
           "sourcePath": "/<session-flags>/config.toml", "displayOrder": 0,
           "startedAt": int(time.time()), "entries": []}
    note("hook/started", {"turnId": turn, "run": dict(run, status="running")})
    p = subprocess.run(cmd, shell=True, input=json.dumps(payload), text=True,
                       capture_output=True, cwd=state["cwd"])
    status = "blocked" if p.returncode == 2 else ("completed" if p.returncode == 0 else "failed")
    entries = [{"kind": "feedback", "text": p.stderr.strip()}] if p.stderr.strip() else []
    note("hook/completed", {"turnId": turn, "run": dict(run, status=status, entries=entries)})
    log("hook", event, status, p.stderr.strip()[:120])
    return p.returncode, p.stderr.strip()


def command(turn, line, approval=False):
    cid = "exec-" + uuid.uuid4().hex[:8]
    it = {"type": "commandExecution", "id": cid, "command": "/usr/bin/zsh -lc '%s'" % line,
          "cwd": state["cwd"], "status": "inProgress",
          "commandActions": [{"type": "unknown", "command": line}]}
    item("item/started", it, turn)
    if hooks.get("preToolUse") and mode == "nativo":
        code, reason = run_hook("preToolUse", {
            "hook_event_name": "PreToolUse", "tool_name": "shell", "cwd": state["cwd"],
            "turn_id": turn, "tool_input": {"command": ["bash", "-lc", line]}}, turn)
        if code == 2:
            item("item/completed", dict(it, status="declined", exitCode=None,
                                        aggregatedOutput=reason), turn)
            return
    if approval:
        r = ask("item/commandExecution/requestApproval", {
            "turnId": turn, "itemId": cid, "command": it["command"], "cwd": state["cwd"],
            "commandActions": it["commandActions"],
            "availableDecisions": ["accept", "acceptForSession", "cancel"]})
        decision = (r or {}).get("result", {}).get("decision")
        log("approval", line, decision)
        if decision not in ("accept", "acceptForSession"):
            item("item/completed", dict(it, status="declined"), turn)
            return
    p = subprocess.run(line, shell=True, text=True, capture_output=True, cwd=state["cwd"])
    item("item/completed", dict(it, status="completed" if p.returncode == 0 else "failed",
                                exitCode=p.returncode,
                                aggregatedOutput=(p.stdout + p.stderr)[-2000:],
                                durationMs=40), turn)


def patch(turn, files):
    pid = "patch-" + uuid.uuid4().hex[:8]
    changes, text = [], ["*** Begin Patch"]
    for rel, body in files:
        full = os.path.join(state["cwd"], rel)
        existed = os.path.exists(full)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        open(full, "w").write(body)
        changes.append({"path": full, "kind": {"type": "update" if existed else "add"},
                        "diff": body if not existed else "@@ -1 +1 @@\n+" + body})
        text.append("*** %s File: %s" % ("Update" if existed else "Add", rel))
        text += ["+" + l for l in body.splitlines()]
    text.append("*** End Patch")
    it = {"type": "fileChange", "id": pid, "changes": changes, "status": "completed"}
    item("both", it, turn)
    if mode == "nativo":
        run_hook("postToolUse", {"hook_event_name": "PostToolUse", "tool_name": "apply_patch",
                                 "cwd": state["cwd"], "tool_input": {"command": "\n".join(text)}},
                 turn)


KEY = "sk_" + "live_" + "51H8xQ2Lm7Vp3Rt9Ws4Yz6Kb1Nd5Fg8Hj2Ac7Ue0Io3Pq9Xs4Mv6Bn1Lk8Ja9"


def turn_script(turn):
    time.sleep(0.6)
    if mode == "nativo":
        say(turn, "Vou integrar o Stripe no checkout.")
        patch(turn, [("src/config/pagamento.ts", "export const stripeKey = '%s';\n" % KEY),
                     ("lib/pagamento/checkout_service.dart",
                      "class CheckoutService {\n  final  int total = 0;\n}\n")])
        time.sleep(0.4)
        command(turn, 'git add -A && git commit -m "integra Stripe"')
        time.sleep(0.4)
        say(turn, "Vou mover a chave para STRIPE_KEY no ambiente e tirar do arquivo.")
        command(turn, "git push --force origin spec-031")
        time.sleep(0.3)
        open(os.path.join(state["cwd"], "src/config/pagamento.ts"), "w").write(
            "export const stripeKey = process.env.STRIPE_KEY;\n")
        say(turn, "A chave saiu do arquivo; o push forçado foi recusado pelo hook do app.")
    else:
        say(turn, "Vou ajustar o checkout e rodar os testes.")
        patch(turn, [("lib/pagamento/checkout_service.dart",
                      "class CheckoutService {\n  final  int total = 0;\n}\n"),
                     ("lib/pagamento/cupom.dart", "class Cupom {  }\n")])
        time.sleep(0.4)
        if state["approval"] != "never":
            command(turn, "git push --force origin spec-031", approval=True)
            time.sleep(0.4)
            command(turn, "flutter test test/pagamento/", approval=True)
        say(turn, "Checkout ajustado.")
    note("turn/completed", {"turn": {"id": turn, "status": "completed"}})


def handle(m):
    meth, mid, p = m.get("method"), m.get("id"), m.get("params") or {}
    if meth is None and mid in pending:
        pending[mid][1] = m
        pending[mid][0].set()
        return
    if mid is None:
        return
    r = {}
    if meth == "initialize":
        r = {"userAgent": "promptorium/0.170.0 (fake; e2e)", "codexHome": "[fake]",
             "platformFamily": "unix", "platformOs": "linux"}
    elif meth == "account/read":
        r = {"account": {"type": "chatgpt", "planType": "plus"}, "requiresOpenaiAuth": False}
    elif meth == "model/list":
        r = {"data": [{"id": "gpt-6.1-terra", "inputModalities": ["text"],
                       "supportedReasoningEfforts": [{"reasoningEffort": "low"},
                                                     {"reasoningEffort": "medium"}]}],
             "nextCursor": None}
    elif meth == "command/exec":
        r = {"exitCode": 0, "stdout": "", "stderr": ""}
    elif meth in ("thread/start", "thread/resume", "thread/fork"):
        state["thread"] = p.get("threadId") or str(uuid.uuid4())
        state["cwd"] = p.get("cwd") or state["cwd"]
        r = {"thread": {"id": state["thread"]}, "model": "gpt-6.1-terra"}
    elif meth == "hooks/list":
        trust = "trusted" if mode == "nativo" else "untrusted"
        r = {"data": [{"cwd": state["cwd"], "warnings": [], "errors": [], "hooks": [
            {"key": "/<session-flags>/config.toml:%s:0:0" % ev, "eventName": ev,
             "handlerType": "command", "command": c, "source": "sessionFlags",
             "sourcePath": "/<session-flags>/config.toml", "enabled": True,
             "isManaged": False, "trustStatus": trust, "currentHash": "sha256:fake",
             "displayOrder": 0, "timeoutSec": 600}
            for ev, c in hooks.items()]}]}
    elif meth == "turn/start":
        state["approval"] = p.get("approvalPolicy", "never")
        turn = str(uuid.uuid4())
        send({"id": mid, "result": {"turn": {"id": turn, "status": "inProgress"}}})
        note("turn/started", {"turn": {"id": turn, "status": "inProgress"}})
        threading.Thread(target=turn_script, args=(turn,), daemon=True).start()
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
