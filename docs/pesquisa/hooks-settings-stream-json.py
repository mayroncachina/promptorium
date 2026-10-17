"""Sonda: hooks de um --settings temporário em `claude -p --input-format stream-json`.

Uso: python3 hooks-settings-stream-json.py <claude> [modelo]
Cria um repositório temporário, um settings.json com PreToolUse (Bash),
PostToolUse (Write|Edit), Stop (bloqueia uma vez) e SessionEnd, e pede ao
agente que tente um `git push --force`, escreva um arquivo e termine.
Imprime os eventos relevantes do stream e o que cada hook gravou.
"""
import json, os, subprocess, sys, tempfile, textwrap

cli = sys.argv[1]
model = sys.argv[2] if len(sys.argv) > 2 else "haiku"
tmp = tempfile.mkdtemp(prefix="sonda-hooks-")
repo = os.path.join(tmp, "repo"); os.makedirs(repo)
subprocess.run(["git", "init", "-q", repo], check=True)
log = os.path.join(tmp, "hooks.log")
hook = os.path.join(tmp, "hook.py")
open(hook, "w").write(textwrap.dedent(f"""\
    import json, sys
    ev = json.load(sys.stdin)
    name = ev.get("hook_event_name")
    with open({log!r}, "a") as f:
        f.write(json.dumps({{"evento": name, "chaves": sorted(ev.keys()),
                             "tool": ev.get("tool_name"),
                             "stop_hook_active": ev.get("stop_hook_active")}}) + "\\n")
    if name == "PreToolUse" and "push --force" in json.dumps(ev.get("tool_input")):
        print(json.dumps({{"hookSpecificOutput": {{"hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "Promptorium: git push --force é bloqueado."}}}}))
    elif name == "PostToolUse":
        print(json.dumps({{"hookSpecificOutput": {{"hookEventName": "PostToolUse",
            "additionalContext": "Promptorium: arquivo formatado."}}}}))
    elif name == "Stop" and not ev.get("stop_hook_active"):
        print(json.dumps({{"decision": "block",
            "reason": "Verificação do Promptorium falhou: rode `echo stop-hook-ok` com Bash e termine de novo."}}))
"""))
cmd = f"python3 {hook}"
settings = os.path.join(tmp, "settings.json")
json.dump({"hooks": {
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": cmd}]}],
    "PostToolUse": [{"matcher": "Write|Edit|MultiEdit", "hooks": [{"type": "command", "command": cmd}]}],
    "Stop": [{"hooks": [{"type": "command", "command": cmd}]}],
    "SessionEnd": [{"hooks": [{"type": "command", "command": cmd}]}],
}}, open(settings, "w"))

p = subprocess.Popen([cli, "-p", "--model", model, "--strict-mcp-config",
    "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
    "--permission-mode", "acceptEdits", "--permission-prompt-tool", "stdio",
    "--settings", settings, "--max-budget-usd", "0.30"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, cwd=repo)
prompt = ("Faça, nesta ordem: 1) use a ferramenta Bash para rodar exatamente "
          "`git push --force origin main`; 2) use a ferramenta Write para criar ola.txt "
          "com o texto oi; 3) termine respondendo FIM.")
p.stdin.write(json.dumps({"type": "user", "message": {"role": "user", "content": prompt}}) + "\n")
p.stdin.flush()
results = 0
for line in p.stdout:
    m = json.loads(line)
    t = m.get("type"); st = m.get("subtype")
    if t == "system" and st != "init":
        print("SYSTEM", st, line[:400].strip())
    elif t == "control_request":
        print("CONTROL", line[:300].strip())
        r = m["request"]
        p.stdin.write(json.dumps({"type": "control_response", "response": {"subtype": "success",
            "request_id": m["request_id"], "response": {"behavior": "allow", "updatedInput": r.get("input", {})}}}) + "\n")
        p.stdin.flush()
    elif t == "user":
        print("TOOL_RESULT", json.dumps(m["message"]["content"], ensure_ascii=False)[:400])
    elif t == "assistant":
        for b in m["message"]["content"]:
            if b.get("type") == "tool_use":
                print("TOOL_USE", b["name"], json.dumps(b["input"], ensure_ascii=False)[:200])
            elif b.get("type") == "text":
                print("TEXT", b["text"][:200])
    elif t == "result":
        results += 1
        print("RESULT", st, m.get("total_cost_usd"), str(m.get("result"))[:200])
        p.stdin.close()
p.wait()
print("EXIT", p.returncode)
print("--- hooks.log")
print(open(log).read() if os.path.exists(log) else "(vazio)")
