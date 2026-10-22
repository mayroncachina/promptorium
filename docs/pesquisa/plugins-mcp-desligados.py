"""Sonda: desligar plugins e servidores MCP do usuário só nas execuções do app.

Uso: python3 plugins-mcp-desligados.py <claude> <plugin@marketplace> <servidor-mcp> [modelo]
Roda `claude -p --input-format stream-json` numa pasta temporária (longe dos
hooks do projeto) em três cenários e imprime, do `system/init`, os plugins,
as ferramentas MCP por servidor, os servidores MCP e os hooks SessionStart:
  base     — sem --settings;
  settings — --settings com enabledPlugins {plugin: false} e
             deniedMcpServers [{serverName: servidor}];
  strict   — --strict-mcp-config sem --mcp-config (para comparar).
"""
import collections, json, os, subprocess, sys, tempfile

cli, plugin, server = sys.argv[1], sys.argv[2], sys.argv[3]
model = sys.argv[4] if len(sys.argv) > 4 else "haiku"
tmp = tempfile.mkdtemp(prefix="sonda-plugins-")
settings = os.path.join(tmp, "settings.json")
json.dump({"enabledPlugins": {plugin: False},
           "deniedMcpServers": [{"serverName": server}]}, open(settings, "w"))


def run(extra):
    p = subprocess.Popen([cli, "-p", "--model", model,
        "--input-format", "stream-json", "--output-format", "stream-json",
        "--verbose", "--max-budget-usd", "0.05", *extra],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True, cwd=tmp)
    p.stdin.write(json.dumps({"type": "user", "message": {"role": "user",
        "content": "Responda só: ok"}}) + "\n")
    p.stdin.flush()
    init, hooks = None, []
    for line in p.stdout:
        m = json.loads(line)
        if m.get("type") == "system" and m.get("subtype") == "init":
            init = m
        if m.get("type") == "system" and m.get("subtype") == "hook_started":
            hooks.append(m.get("hook_name"))
        if m.get("type") == "result":
            break
    p.stdin.close()
    p.wait(timeout=60)
    tools = collections.Counter(
        t.split("__")[1] for t in init["tools"] if t.startswith("mcp__"))
    return {
        "versao": init.get("claude_code_version"),
        "plugins": [x["source"] for x in init.get("plugins", [])],
        "mcp_servers": {s["name"]: s["status"] for s in init.get("mcp_servers", [])},
        "ferramentas_mcp": dict(tools),
        "hooks_session_start": hooks,
    }


for nome, extra in [("base", []), ("settings", ["--settings", settings]),
                    ("strict", ["--strict-mcp-config"])]:
    print(f"== {nome}")
    print(json.dumps(run(extra), indent=1, ensure_ascii=False))
