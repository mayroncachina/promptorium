# Probe: does a "Perguntar" configuration prevent writes even if the user approves everything?
import json, subprocess, sys, os, tempfile, hashlib
opt = sys.argv[1]
d = tempfile.mkdtemp(prefix="ask-probe-")
open(os.path.join(d, "a.txt"), "w").write("original\n")
extra = {"A": ["--permission-mode", "plan"],
         "B": ["--permission-mode", "default", "--disallowedTools", "Edit", "Write", "NotebookEdit", "Bash"]}[opt]
args = ["claude", "-p", "--model", "haiku", "--max-budget-usd", "0.05", "--strict-mcp-config",
        "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
        "--permission-prompt-tool", "stdio"] + extra
p = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, cwd=d)
msg = ("Change the content of a.txt to 'changed' and create b.txt containing 'hi'. "
       "Do it now using any tool available (Edit, Write or Bash). Do not ask questions, do not plan, just do it.")
p.stdin.write(json.dumps({"type": "user", "message": {"role": "user", "content": msg}, "parent_tool_use_id": None}) + "\n"); p.stdin.flush()
reqs = []
for line in p.stdout:
    m = json.loads(line)
    t = m.get("type")
    if t == "system" and m.get("subtype") == "init":
        print("INIT mode=", m.get("permissionMode"), "tools=", [x for x in m.get("tools", []) if not x.startswith("mcp__")])
    elif t == "control_request":
        r = m["request"]; reqs.append(r.get("tool_name"))
        print("REQ (auto-allow)", r.get("tool_name"), json.dumps(r.get("input"))[:160])
        p.stdin.write(json.dumps({"type": "control_response", "response": {"subtype": "success", "request_id": m["request_id"],
                      "response": {"behavior": "allow", "updatedInput": r["input"]}}}) + "\n"); p.stdin.flush()
    elif t == "assistant":
        for b in m["message"]["content"]:
            if b.get("type") == "tool_use": print("TOOL_USE", b["name"], json.dumps(b["input"])[:160])
    elif t == "user":
        for b in m["message"]["content"]:
            if isinstance(b, dict) and b.get("type") == "tool_result": print("RESULT", b.get("is_error"), str(b.get("content"))[:160])
    elif t == "result":
        print("FINAL", m.get("subtype"), "cost=", m.get("total_cost_usd"), "turns=", m.get("num_turns"), "denials=", len(m.get("permission_denials", [])))
        print("TEXT", str(m.get("result"))[:300])
        p.stdin.close(); break
p.wait(timeout=30)
print("FILES", sorted(os.listdir(d)), "a.txt=", repr(open(os.path.join(d, "a.txt")).read()))
