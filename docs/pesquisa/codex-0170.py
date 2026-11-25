"""Sonda SPEC-093: Codex CLI 0.170 e o App Server.

Uso:
  python3 -I codex-0170.py --saida DIR [--codex codex] [--so a,b] [--pago]

Sem `--pago` só roda o que não abre turno (nada de cota): versão, ajuda,
features, schema, handshake, `account/rateLimits/read`, `hooks/list`,
`command/exec` no sandbox, `codex debug prompt-input` e a emulação do commit
em worktree com Landlock. Com `--pago` roda também os cenários com turno
(R5–R15), cada um com prompt de uma linha, o modelo mais barato e esforço
`low`. A lista de turnos gastos sai em DIR/turnos.json.

Garantias: o App Server roda só com `-c` (nunca `--trust`, nunca `codex login`),
em repositórios temporários dentro de DIR, e o `~/.codex/auth.json` nunca é
lido (só aparece por nome na lista de arquivos, sem conteúdo). Hash de
`~/.codex/config.toml` e de `~/.codex/rules/` antes e depois de cada bloco.

Cenários (--so): cli, schema, handshake, sandbox, instrucoes, hooks, landlock,
hooks_confianca, confianca, mcp,
e os pagos leitura, edicao, comando, worktree, ambiente, contexto, imagem,
interromper, hook_turno.

Cada transcrição JSON-RPC vai para DIR/fixtures/<cenario>.jsonl com uma linha
por mensagem: {"dir": "send"|"recv", "msg": {...}}, já sanitizada.
"""
import argparse, base64, ctypes, hashlib, json, os, queue, re, shutil, struct
import subprocess, sys, threading, time, zlib

HOME = os.path.expanduser("~")
USUARIO = os.path.basename(HOME)
CODEX_HOME = os.path.join(HOME, ".codex")
ap = argparse.ArgumentParser()
ap.add_argument("--saida", required=True)
ap.add_argument("--codex", default="codex")
ap.add_argument("--so", default="")
ap.add_argument("--pago", action="store_true")
ap.add_argument("--modelo", default="")
ap.add_argument("--landlock-exec", nargs=argparse.REMAINDER, help=argparse.SUPPRESS)
args = ap.parse_args()
OUT = os.path.abspath(args.saida)
SO = {s for s in args.so.split(",") if s}
PAGOS = ["leitura", "edicao", "comando", "worktree", "ambiente", "contexto",
         "imagem", "interromper", "hook_turno"]
TURNOS = []  # (cenario, turno, modelo, esforço, status)


def quer(nome):
    return not SO or nome in SO


# ---------------------------------------------------------------- sanitização

_SEGREDO = re.compile(r"^(?:access_?token|refresh_?token|id_?token|api_?key|"
                      r"authorization|email|accountId|account_id|userId|user_id|"
                      r"chatgptAccountId|organizationId|workspaceId|workspaceName|installationId|serverName)$", re.I)


def limpa_texto(s):
    s = s.replace(OUT, "<sonda>").replace(HOME, "~")
    s = re.sub(rf"\b{re.escape(USUARIO)}\b", "usuario", s)  # dono no `ls -la`
    s = re.sub(r"\bsk-[A-Za-z0-9_-]+", "[redigido]", s)
    s = re.sub(r"Bearer\s+\S+", "Bearer [redigido]", s, flags=re.I)
    s = re.sub(r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", "[jwt]", s)
    s = re.sub(r"[\w.+-]+@[\w-]+\.[\w.-]+", "[email]", s)
    return s


def limpa(v, chave=""):
    """Mesma ideia do `CodexRpc.redactJson`, mais caminhos e ids de conta."""
    if isinstance(v, dict):
        return {k: ("[redigido]" if _SEGREDO.match(k) and v[k] not in (None, "")
                    else limpa(x, k)) for k, x in v.items()}
    if isinstance(v, list):
        return [limpa(x, chave) for x in v]
    if isinstance(v, str):
        if v.startswith("data:image/"):
            return v[:40] + "…[base64 omitido]"
        return limpa_texto(v)
    return v


def grava(nome, conteudo):
    p = os.path.join(OUT, nome)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(conteudo if isinstance(conteudo, str)
                else json.dumps(conteudo, indent=2, ensure_ascii=False) + "\n")
    return p


def roda(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120, **kw)
    return r.returncode, limpa_texto(r.stdout), limpa_texto(r.stderr)


# ---------------------------------------------------------------- R4: arquivos do usuário

def foto(rotulo):
    h = {}
    for rel in ["config.toml"] + sorted("rules/" + f for f in os.listdir(
            os.path.join(CODEX_HOME, "rules"))):
        with open(os.path.join(CODEX_HOME, rel), "rb") as f:
            h[rel] = hashlib.sha256(f.read()).hexdigest()
    arvore = {}
    for raiz, dirs, arqs in os.walk(CODEX_HOME):
        for a in arqs:
            p = os.path.join(raiz, a)
            rel = os.path.relpath(p, CODEX_HOME)
            if rel == "auth.json":  # nunca ler; o stat também fica de fora
                continue
            try:
                st = os.stat(p)
            except OSError:
                continue
            arvore[rel] = (st.st_size, int(st.st_mtime))
    return {"rotulo": rotulo, "hash": h, "arvore": arvore}


def compara(a, b):
    novos = sorted(set(b["arvore"]) - set(a["arvore"]))
    sumidos = sorted(set(a["arvore"]) - set(b["arvore"]))
    mudados = sorted(k for k in set(a["arvore"]) & set(b["arvore"])
                     if a["arvore"][k] != b["arvore"][k])

    def grupo(lista):
        g = {}
        for k in lista:
            topo = k.split("/")[0]
            g[topo] = g.get(topo, 0) + 1
        return g
    return {"de": a["rotulo"], "para": b["rotulo"],
            "hash_igual": a["hash"] == b["hash"], "hash": b["hash"],
            "novos": grupo(novos), "mudados": grupo(mudados),
            "sumidos": grupo(sumidos)}


# ---------------------------------------------------------------- App Server

class AppServer:
    def __init__(self, cenario, cwd, extra=(), env=None):
        self.cenario = cenario
        self.trans = open(os.path.join(OUT, "fixtures", f"{cenario}.jsonl"), "w")
        self.argv = [args.codex, "app-server", "-c", "mcp_servers={}", *extra]
        e = dict(os.environ)
        e.update(env or {})
        self.p = subprocess.Popen(self.argv, cwd=cwd, env=e, text=True,
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE)
        self.q = queue.Queue()
        self.respostas = {}
        self.id = 0
        self.lock = threading.Lock()
        self.stderr = []
        threading.Thread(target=self._le, daemon=True).start()
        threading.Thread(target=lambda: self.stderr.extend(self.p.stderr),
                         daemon=True).start()

    def _log(self, d, m):
        self.trans.write(json.dumps({"dir": d, "msg": limpa(m)}, ensure_ascii=False) + "\n")
        self.trans.flush()

    def _le(self):
        for linha in self.p.stdout:
            try:
                m = json.loads(linha)
            except ValueError:
                continue
            self._log("recv", m)
            if "method" not in m and "id" in m:
                self.respostas[m["id"]] = m
            else:
                self.q.put(m)
        self.q.put(None)

    def envia(self, m):
        self._log("send", m)
        self.p.stdin.write(json.dumps(m) + "\n")
        self.p.stdin.flush()

    def pede(self, metodo, params=None, espera=60):
        with self.lock:
            self.id += 1
            i = self.id
        self.envia({"id": i, "method": metodo, "params": params or {}})
        fim = time.time() + espera
        while time.time() < fim:
            if i in self.respostas:
                r = self.respostas.pop(i)
                if "error" in r:
                    raise RuntimeError(f"{metodo}: {r['error']}")
                return r.get("result", {})
            time.sleep(0.02)
        raise TimeoutError(metodo)

    def abre(self):
        init = self.pede("initialize", {"clientInfo": {
            "name": "promptorium", "title": "Promptorium", "version": "0.22.0"}})
        self.envia({"method": "initialized", "params": {}})
        return init

    def eventos(self, ate, espera=180, responder=None):
        """Consome notificações até `ate(m)`; `responder(m)` trata pedidos."""
        vistos = []
        fim = time.time() + espera
        while time.time() < fim:
            try:
                m = self.q.get(timeout=1)
            except queue.Empty:
                continue
            if m is None:
                break
            vistos.append(m)
            if "id" in m and "method" in m:
                r = responder(m) if responder else {"decision": "decline"}
                self.envia({"id": m["id"], "result": r})
            if ate(m):
                break
        return vistos

    def fecha(self):
        try:
            self.p.stdin.close()
        except OSError:
            pass
        try:
            self.p.wait(5)
        except subprocess.TimeoutExpired:
            self.p.kill()
        self.trans.close()
        return limpa_texto("".join(self.stderr))[-4000:]


def repo_temp(nome, claude=None, worktree=False):
    base = os.path.join(OUT, "repos", nome)
    shutil.rmtree(base, ignore_errors=True)
    raiz = os.path.join(base, "repo")
    os.makedirs(raiz)
    g = ["git", "-C", raiz]
    subprocess.run(["git", "init", "-q", "-b", "main", raiz], check=True)
    subprocess.run(g + ["config", "user.email", "sonda@example.invalid"], check=True)
    subprocess.run(g + ["config", "user.name", "Sonda"], check=True)
    with open(os.path.join(raiz, "base.txt"), "w") as f:
        f.write("base\n")
    if claude:
        with open(os.path.join(raiz, "CLAUDE.md"), "w") as f:
            f.write(claude)
    subprocess.run(g + ["add", "."], check=True)
    subprocess.run(g + ["commit", "-qm", "inicio"], check=True)
    if not worktree:
        return raiz, raiz
    wt = os.path.join(base, "wt")
    subprocess.run(g + ["worktree", "add", "-q", "-b", "etapa", wt], check=True)
    return raiz, wt


def turno(srv, cenario, thread, texto, extra=None, responder=None, espera=240,
          durante=None):
    """Um turno pago: devolve (turn_id, notificações)."""
    pol, aprov = POLITICA.get(thread, ({"type": "readOnly"}, "never"))
    params = {"threadId": thread, "input": [{"type": "text", "text": texto}],
              "effort": "low", "sandboxPolicy": pol, "approvalPolicy": aprov,
              **(extra or {})}
    if isinstance(texto, list):
        params["input"] = texto
    r = srv.pede("turn/start", params)
    tid = r.get("turn", {}).get("id")
    vistos = []
    if durante:
        vistos += durante(srv, thread, tid)
    vistos += srv.eventos(lambda m: m.get("method") == "turn/completed",
                          espera=espera, responder=responder)
    fim = next((m for m in vistos if m.get("method") == "turn/completed"), None)
    status = fim["params"]["turn"]["status"] if fim else "sem turn/completed"
    TURNOS.append({"cenario": cenario, "turno": tid, "modelo": MODELO,
                   "esforco": "low", "status": status})
    grava("turnos.json", TURNOS)
    return tid, vistos


def itens(vistos, tipo=None, metodo="item/completed"):
    return [m["params"]["item"] for m in vistos if m.get("method") == metodo
            and (tipo is None or m["params"]["item"].get("type") == tipo)]


def resumo_itens(vistos):
    out = []
    for it in itens(vistos):
        t = it.get("type")
        if t == "commandExecution":
            out.append({"type": t, "command": it.get("command"), "status": it.get("status"),
                        "exitCode": it.get("exitCode"),
                        "aggregatedOutput": (it.get("aggregatedOutput") or "")[-600:]})
        elif t == "fileChange":
            out.append({"type": t, "status": it.get("status"), "changes": it.get("changes")})
        elif t == "agentMessage":
            out.append({"type": t, "text": it.get("text", "")[:600]})
        elif t not in ("userMessage", "reasoning"):
            out.append({"type": t})
    pedidos = [{"method": m["method"], "params": {k: v for k, v in m["params"].items()
                if k not in ("threadId", "turnId")}} for m in vistos
               if "id" in m and "method" in m]
    uso = [m["params"]["tokenUsage"] for m in vistos
           if m.get("method") == "thread/tokenUsage/updated"]
    fim = next((m["params"]["turn"] for m in vistos if m.get("method") == "turn/completed"), {})
    return limpa({"itens": out, "pedidos": pedidos, "uso": uso[-1:] if uso else [],
                  "turn": {k: fim.get(k) for k in ("status", "error", "durationMs")},
                  "metodos": sorted({m.get("method") for m in vistos if m.get("method")})})


RES = {}


def salva(nome, valor):
    RES[nome] = valor
    grava("resultados.json", RES)


# ---------------------------------------------------------------- T1 sem custo

def r1_cli():
    cli = {}
    for sub in ["", "exec", "resume", "fork", "review", "login", "mcp",
                "app-server", "sandbox"]:
        rc, so, se = roda([args.codex, *sub.split(), "--help"])
        grava(f"cli/help-{sub or 'codex'}.txt", so + se)
        cli[sub or "codex"] = rc
    rc, ver, _ = roda([args.codex, "--version"])
    rc, feats, _ = roda([args.codex, "features", "list"])
    grava("cli/features.txt", feats)
    estaveis = [l.split()[0] for l in feats.splitlines()
                if len(l.split()) >= 3 and l.split()[1] == "stable" and l.split()[-1] == "true"]
    _, ajuda, _ = roda([args.codex, "--help"])
    m = re.search(r"--ask-for-approval <APPROVAL_POLICY>(.*?)\n\s+--", ajuda, re.S)
    aprov = re.findall(r"^\s+- ([a-z-]+):", m.group(1), re.M) if m else []
    flags = {f: f in ajuda for f in ["--add-dir", "--ignore-user-config", "-c,",
                                     "--yolo", "--sandbox", "--ask-for-approval",
                                     "--image", "--profile"]}
    # O parser aceita? (--help não abre sessão; rc 2 = argumento recusado)
    parser = {" ".join(a): roda([args.codex, *a, "--help"])[0] for a in (
        ["-a", "untrusted"], ["resume", "x", "-a", "untrusted"], ["--yolo"],
        ["resume", "--yolo"], ["-a", "on-request"])}
    salva("cli", {"versao": ver.strip(), "help_rc": cli, "aprovacao_cli": aprov,
                  "parser_rc": parser,
                  "untrusted_na_cli": "untrusted" in aprov, "flags": flags,
                  "features_estaveis_uteis": [f for f in estaveis if f in (
                      "hooks", "shell_tool", "unified_exec", "view_image",
                      "guardian_approval", "goals", "plugins", "skill_search")],
                  "steer_feature": next((l for l in feats.splitlines()
                                         if l.startswith("steer ")), "")})


ADAPTADOR = {  # método → campos que o CodexRun lê ou envia (lib/core/codex)
    "initialize": ["clientInfo"],
    "account/read": ["requiresOpenaiAuth", "account"],
    "model/list": ["limit", "cursor", "data", "nextCursor", "id",
                   "supportedReasoningEfforts", "inputModalities"],
    "thread/start": ["cwd", "sandbox", "approvalPolicy", "model",
                     "developerInstructions", "config", "thread"],
    "thread/resume": ["threadId", "excludeTurns", "cwd", "sandbox", "approvalPolicy"],
    "thread/fork": ["threadId", "excludeTurns", "cwd", "sandbox", "approvalPolicy"],
    "turn/start": ["threadId", "approvalPolicy", "sandboxPolicy", "input",
                   "effort", "outputSchema", "turn"],
    "turn/interrupt": ["threadId", "turnId"],
    "turn/steer": ["threadId", "expectedTurnId", "input"],
    "item/commandExecution/requestApproval": ["itemId", "reason"],
    "item/fileChange/requestApproval": ["itemId", "reason"],
    "item/tool/requestUserInput": ["questions"],
    "thread/tokenUsage/updated": ["tokenUsage"],
    "turn/completed": ["turn"],
    "turn/started": ["turn"],
    "item/started": ["item"], "item/completed": ["item"],
    "item/agentMessage/delta": ["itemId", "delta"],
    "serverRequest/resolved": ["requestId"],
    "error": ["error", "willRetry"],
    "account/rateLimits/read": [], "thread/compact/start": ["threadId"],
}


def r2_schema():
    d = os.path.join(OUT, "schema")
    shutil.rmtree(d, ignore_errors=True)
    t0 = time.time()
    subprocess.run([args.codex, "app-server", "generate-json-schema", "--out", d],
                   check=True, capture_output=True)
    dur = time.time() - t0
    bundle = os.path.join(d, "codex_app_server_protocol.schemas.json")
    sha = hashlib.sha256(open(bundle, "rb").read()).hexdigest()

    def metodos(arq):
        j = json.load(open(os.path.join(d, arq)))
        out = {}
        for v in j.get("oneOf", []):
            e = v.get("properties", {}).get("method", {}).get("enum")
            if e:
                ref = v.get("properties", {}).get("params", {}).get("$ref", "")
                out[e[0]] = ref.split("/")[-1]
        return out
    cli, srv_req, notif = (metodos("ClientRequest.json"), metodos("ServerRequest.json"),
                           metodos("ServerNotification.json"))
    defs = json.load(open(os.path.join(d, "codex_app_server_protocol.v2.schemas.json")))["definitions"]
    todos = {**cli, **srv_req, **notif}
    tabela = {}
    for m, campos in ADAPTADOR.items():
        if m not in todos:
            tabela[m] = {"estado": "sumiu"}
            continue
        p = defs.get(todos[m], {})
        props = set(p.get("properties", {}))
        resp = todos[m].replace("Params", "Response")
        props |= set(defs.get(resp, {}).get("properties", {}))
        tabela[m] = {"estado": "existe", "params": todos[m],
                     "obrigatorios": p.get("required", []),
                     "campos_ausentes": [c for c in campos if props and c not in props
                                         and c not in ("data", "id", "nextCursor",
                                                       "supportedReasoningEfforts",
                                                       "inputModalities")]}
    salva("schema", {"sha256": sha, "segundos": round(dur, 3),
                     "contagem": {"client_requests": len(cli), "server_requests": len(srv_req),
                                  "notificacoes": len(notif)},
                     "adaptador": tabela,
                     "aprovacao_enum": defs["AskForApproval"]["oneOf"][0]["enum"],
                     "metodos_usados": sorted(ADAPTADOR)})
    grava("schema-metodos.json", {"client": sorted(cli), "serverRequests": sorted(srv_req),
                                  "notifications": sorted(notif)})


MODELO = None


def r3_handshake():
    global MODELO
    raiz, _ = repo_temp("handshake")
    srv = AppServer("handshake", raiz)
    try:
        init = srv.abre()
        conta = srv.pede("account/read", {})
        modelos, cursor = [], None
        while True:
            r = srv.pede("model/list", {"limit": 100, **({"cursor": cursor} if cursor else {})})
            modelos += r.get("data", [])
            cursor = r.get("nextCursor")
            if not cursor:
                break
        cota = srv.pede("account/rateLimits/read", {})
    finally:
        err = srv.fecha()
    vis = [m for m in modelos if not m.get("hidden")]
    # "Mais barato": o catálogo não traz preço; pega o de menor esforço padrão
    # entre os que anunciam `low`, preferindo nomes de linha leve.
    leve = ("mini", "luna", "nano", "spark", "lite")
    candidatos = [m for m in vis if any(e.get("reasoningEffort") == "low"
                                        for e in m.get("supportedReasoningEfforts", []))]
    candidatos.sort(key=lambda m: (not any(k in m["id"] for k in leve), m["id"]))
    MODELO = args.modelo or (candidatos[0]["id"] if candidatos else None)
    salva("handshake", limpa({
        "initialize": init,
        "account_read": {"requiresOpenaiAuth": conta.get("requiresOpenaiAuth"),
                         "account_tipo": (conta.get("account") or {}).get("type"),
                         "planType": (conta.get("account") or {}).get("planType"),
                         "chaves": sorted((conta.get("account") or {}).keys())},
        "modelos": [{"id": m["id"], "default": m.get("isDefault"), "hidden": m.get("hidden"),
                     "esforcos": [e["reasoningEffort"] for e in m.get("supportedReasoningEfforts", [])],
                     "esforco_padrao": m.get("defaultReasoningEffort"),
                     "modalidades": m.get("inputModalities")} for m in modelos],
        "modelo_escolhido": MODELO,
        "rateLimits": cota, "stderr": err[-800:]}))


def sandbox_exec():
    """command/exec: o mesmo sandbox dos turnos, sem modelo (R8/R9 sem custo)."""
    raiz, wt = repo_temp("sandbox", worktree=True)
    git_common = os.path.join(raiz, ".git")
    srv = AppServer("sandbox", wt, env={"PROMPTORIUM_AGENTE": "codex"})
    res = {}
    try:
        srv.abre()
        fora_tmp = {"excludeSlashTmp": True, "excludeTmpdirEnvVar": True}
        casos = {
            "readOnly_echo": ({"type": "readOnly"}, ["sh", "-c", "echo ok"]),
            "readOnly_escreve": ({"type": "readOnly"}, ["sh", "-c", "echo x > ro.txt"]),
            "workspaceWrite_escreve": ({"type": "workspaceWrite", **fora_tmp},
                                       ["sh", "-c", "echo x > ww.txt && echo gravou"]),
            "workspaceWrite_env": ({"type": "workspaceWrite", **fora_tmp},
                                   ["sh", "-c", "echo agente=$PROMPTORIUM_AGENTE"]),
            "worktree_commit_sem_roots": ({"type": "workspaceWrite", **fora_tmp},
                                          ["sh", "-c", "echo a > a.txt && git add a.txt && git commit -qm a && echo commitou"]),
            "worktree_commit_com_roots": ({"type": "workspaceWrite", **fora_tmp,
                                           "writableRoots": [git_common]},
                                          ["sh", "-c", "echo b > b.txt && git add b.txt && git commit -qm b && echo commitou"]),
            "dangerFullAccess_env": ({"type": "dangerFullAccess"},
                                     ["sh", "-c", "echo agente=$PROMPTORIUM_AGENTE"]),
        }
        for nome, (pol, cmd) in casos.items():
            try:
                r = srv.pede("command/exec", {"command": cmd, "cwd": wt,
                                              "sandboxPolicy": pol, "timeoutMs": 20000})
            except Exception as e:  # noqa: BLE001
                r = {"erro": str(e)}
            res[nome] = limpa(r)
    finally:
        res["stderr"] = srv.fecha()[-1500:]
    res["git_log_wt"] = roda(["git", "-C", wt, "log", "--oneline"])[1]
    salva("sandbox_exec", res)


def instrucoes():
    """R10 sem custo: o prompt que o modelo veria, com e sem o fallback."""
    raiz, wt = repo_temp("instrucoes", claude="# Regras\n\nA palavra-senha deste projeto é LARANJA-42.\n",
                         worktree=True)
    out = {}
    for rot, extra in [("com_fallback", ["-c", 'project_doc_fallback_filenames=["CLAUDE.md"]']),
                       ("sem_fallback", [])]:
        rc, so, se = roda([args.codex, "debug", "prompt-input", "-c", "mcp_servers={}",
                           *extra, "oi"], cwd=raiz)
        txt = so
        out[rot] = {"rc": rc, "le_claude_md": "LARANJA-42" in txt,
                    "bloco": (re.search(r"# AGENTS\.md instructions for [^\n]*", txt) or [None])[0]}
    perfis = {}
    git_common = os.path.join(raiz, ".git")
    for rot, extra in [("ww_sem_roots", []),
                       ("ww_com_roots", ["-c", f'sandbox_workspace_write.writable_roots=["{git_common}"]'])]:
        rc, so, se = roda([args.codex, "debug", "prompt-input", "-c", "mcp_servers={}",
                           "-c", 'sandbox_mode="workspace-write"',
                           "-c", "sandbox_workspace_write.exclude_slash_tmp=true",
                           "-c", "sandbox_workspace_write.exclude_tmpdir_env_var=true",
                           *extra, "oi"], cwd=wt)
        m = re.search(r"<filesystem>.*?</filesystem>", so, re.S)
        perfis[rot] = m.group(0) if m else so[-500:]
    out["perfil_sandbox"] = perfis
    # thread/start devolve instructionSources: dá para o app conferir sem turno.
    for rot, extra in [("thread_start_com_fallback", ["-c", 'project_doc_fallback_filenames=["CLAUDE.md"]']),
                       ("thread_start_sem_fallback", [])]:
        srv = AppServer(f"instrucoes-{rot}", raiz, extra=extra)
        try:
            srv.abre()
            r = srv.pede("thread/start", {"cwd": raiz, "sandbox": "read-only",
                                          "approvalPolicy": "never", "ephemeral": True})
            out[rot] = limpa({"instructionSources": r.get("instructionSources"),
                              "approvalPolicy": r.get("approvalPolicy"),
                              "sandbox": r.get("sandbox")})
        finally:
            srv.fecha()
    salva("instrucoes", out)


HOOK_PY = """import json, sys
ev = json.load(sys.stdin)
cmd = json.dumps(ev.get("tool_input", ev))
if "rm " in cmd:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "Promptorium: rm bloqueado"}}))
open(sys.argv[1], "a").write(json.dumps(ev)[:2000] + "\\n")
"""


def hook_args():
    d = os.path.join(OUT, "hook")
    os.makedirs(d, exist_ok=True)
    py = os.path.join(d, "nega_rm.py")
    open(py, "w").write(HOOK_PY)
    log = os.path.join(d, "eventos.log")
    cmd = f"python3 {py} {log}"
    return ["-c", f'hooks.PreToolUse=[{{matcher="*",hooks=[{{type="command",command="{cmd}"}}]}}]'], log


def hooks():
    """R15 sem custo: o hook injetado por -c aparece em hooks/list? Com que trust?"""
    raiz, _ = repo_temp("hooks")
    extra, _log = hook_args()
    out = {}
    for rot, ex in [("por_c", extra), ("sem_hook", [])]:
        srv = AppServer(f"hooks-{rot}", raiz, extra=ex)
        try:
            srv.abre()
            out[rot] = limpa(srv.pede("hooks/list", {"cwds": [raiz]}))
        except Exception as e:  # noqa: BLE001
            out[rot] = {"erro": limpa_texto(str(e))}
        finally:
            out[rot + "_stderr"] = srv.fecha()[-800:]
    salva("hooks", out)


def hooks_confianca():
    """R15: overrides por -c não marcam o hook como confiável."""
    raiz, _ = repo_temp("hooks")
    extra, _log = hook_args()
    srv = AppServer("hooks-por_c-tmp", raiz, extra=extra)
    try:
        srv.abre()
        h = srv.pede("hooks/list", {"cwds": [raiz]})["data"][0]["hooks"][0]
    finally:
        srv.fecha()
    out = {}
    for rot, ex in [("trusted_hash_por_c", ["-c", f'hooks.state."{h["key"]}".trusted_hash="{h["currentHash"]}"']),
                    ("bypass_hook_trust_por_c", ["-c", "bypass_hook_trust=true"])]:
        srv = AppServer(f"hooks-{rot}", raiz, extra=extra + ex)
        try:
            srv.abre()
            hs = srv.pede("hooks/list", {"cwds": [raiz]})["data"][0]["hooks"]
            out[rot] = [x.get("trustStatus") for x in hs]
        finally:
            srv.fecha()
    rc, so, se = roda([args.codex, "app-server", "--dangerously-bypass-hook-trust", "--help"])
    out["app_server_aceita_bypass_flag"] = rc == 0
    salva("hooks_confianca", out)


def confianca():
    """R4: quando o App Server grava `trust_level` no config.toml?

    Roda com um CODEX_HOME temporário e vazio (sem login: nenhum turno chega
    ao modelo), para não tocar no ~/.codex de quem usa.
    """
    base = os.path.join(OUT, "confianca")
    shutil.rmtree(base, ignore_errors=True)
    os.makedirs(base)
    casos = [
        ("thread_read_only", {"sandbox": "read-only", "approvalPolicy": "never"}, None),
        ("thread_workspace_write", {"sandbox": "workspace-write", "approvalPolicy": "on-request"}, None),
        ("thread_workspace_write_ephemeral", {"sandbox": "workspace-write",
                                              "approvalPolicy": "on-request", "ephemeral": True}, None),
        ("thread_danger_full_access", {"sandbox": "danger-full-access", "approvalPolicy": "never"}, None),
        ("thread_read_only_turno_workspace_write", {"sandbox": "read-only", "approvalPolicy": "never"},
         {"type": "workspaceWrite"}),
    ]
    out = {}
    for nome, tp, pol in casos:
        home = os.path.join(base, "home-" + nome)
        os.makedirs(home)
        r = os.path.join(base, nome)
        subprocess.run(["git", "init", "-q", r], check=True)
        srv = AppServer(f"confianca-{nome}", r, env={"CODEX_HOME": home})
        efetivo = None
        try:
            srv.abre()
            th = srv.pede("thread/start", {"cwd": r, **tp})["thread"]["id"]
            if pol:
                srv.pede("turn/start", {"threadId": th, "input": [{"type": "text", "text": "x"}],
                                        "sandboxPolicy": pol, "approvalPolicy": "on-request"})
                time.sleep(2)
                srv.pede("turn/interrupt", {"threadId": th, "turnId": srv.pede(
                    "thread/read", {"threadId": th, "includeTurns": True})["thread"]["turns"][-1]["id"]})
                efetivo = srv.pede("thread/resume", {"threadId": th})
                efetivo = {k: efetivo.get(k) for k in ("sandbox", "approvalPolicy")}
        except Exception as e:  # noqa: BLE001
            efetivo = {"erro": limpa_texto(str(e))}
        finally:
            srv.fecha()
        cfg = os.path.join(home, "config.toml")
        txt = open(cfg).read() if os.path.exists(cfg) else ""
        out[nome] = {"grava_trust": "trust_level" in txt, "config": limpa_texto(txt.strip()),
                     **({"efetivo_depois_do_turno": limpa(efetivo)} if pol else {})}
    salva("confianca", out)


def mcp_usuario():
    """`-c mcp_servers={}` desliga os MCP do usuário? (ephemeral, read-only)"""
    raiz, _ = repo_temp("mcp")
    nomes = []
    try:
        import tomllib  # noqa: F401  (3.11+)
    except ImportError:
        pass
    txt = open(os.path.join(CODEX_HOME, "config.toml")).read()
    nomes = sorted(set(re.findall(r"^\[mcp_servers\.([A-Za-z0-9_-]+)\]", txt, re.M)))
    casos = [("mcp_servers_vazio", []),
             ("enabled_false_por_servidor", [x for n in nomes for x in
                                             ("-c", f"mcp_servers.{n}.enabled=false")]),
             ("enabled_false_e_apps_off", [x for n in nomes for x in
                                           ("-c", f"mcp_servers.{n}.enabled=false")]
              + ["-c", "features.apps=false"])]
    out = {"servidores_do_usuario": len(nomes)}
    for rot, ex in casos:
        srv = AppServer(f"mcp-{rot}", raiz, extra=ex)
        try:
            srv.abre()
            srv.pede("thread/start", {"cwd": raiz, "sandbox": "read-only",
                                      "approvalPolicy": "never", "ephemeral": True})
            v = srv.eventos(lambda m: False, espera=7)
            out[rot] = sorted({"codex_apps" if m["params"]["name"] == "codex_apps" else "servidor do usuário"
                               for m in v if m.get("method") == "mcpServer/startupStatus/updated"})
        finally:
            srv.fecha()
    salva("mcp_usuario", out)


# ---------------------------------------------------------------- Landlock (emulação)

def landlock_exec(write_paths, argv):
    """Restringe a escrita do processo a `write_paths` (leitura livre) e roda argv.

    Emula o perfil `workspace-write` que o Codex mostra no prompt, para quando o
    bwrap do Codex não sobe (AppArmor). O kernel aplica a regra de verdade.
    """
    libc = ctypes.CDLL(None, use_errno=True)
    sc = libc.syscall
    abi = sc(444, None, 0, 1)  # LANDLOCK_CREATE_RULESET_VERSION
    if abi < 1:
        raise OSError("Landlock indisponível")
    leitura = (1 << 0) | (1 << 2) | (1 << 3)
    escrita = (1 << 1) | sum(1 << b for b in range(4, 13))
    if abi >= 2:
        escrita |= 1 << 13
    if abi >= 3:
        escrita |= 1 << 14
    tudo = leitura | escrita
    attr = struct.pack("QQQ", tudo, 0, 0)
    fd = sc(444, ctypes.c_char_p(attr), len(attr), 0)
    if fd < 0:
        raise OSError(ctypes.get_errno(), "landlock_create_ruleset")

    def regra(caminho, acesso):
        pfd = os.open(caminho, os.O_PATH | os.O_CLOEXEC)
        if os.path.isfile(caminho):
            acesso &= (1 << 0) | (1 << 1) | (1 << 2) | ((1 << 14) if abi >= 3 else 0)
        b = struct.pack("=Qi", acesso, pfd)
        if sc(445, fd, 1, ctypes.c_char_p(b), 0) != 0:
            raise OSError(ctypes.get_errno(), f"landlock_add_rule {caminho}")
        os.close(pfd)
    regra("/", leitura)
    for p in write_paths + ["/dev"]:
        regra(p, tudo)
    if libc.prctl(38, 1, 0, 0, 0) != 0:  # PR_SET_NO_NEW_PRIVS
        raise OSError("prctl")
    if sc(446, fd, 0) != 0:
        raise OSError(ctypes.get_errno(), "landlock_restrict_self")
    os.execvp(argv[0], argv)


def landlock():
    raiz, wt = repo_temp("landlock", worktree=True)
    common = os.path.join(raiz, ".git")
    marca = time.time()
    time.sleep(1.1)
    # Quais caminhos um commit no worktree grava (sem sandbox, num clone igual)?
    r2, wt2 = repo_temp("landlock-medida", worktree=True)
    time.sleep(1.1)
    t0 = time.time()
    subprocess.run(["sh", "-c", "echo m > m.txt && git add m.txt && git commit -qm m"],
                   cwd=wt2, check=True)
    gravados = []
    for base in (os.path.dirname(wt2),):
        for raiz_, ds, fs in os.walk(base):
            for f in fs + ds:
                p = os.path.join(raiz_, f)
                try:
                    if os.lstat(p).st_mtime >= t0 - 0.01:
                        gravados.append(limpa_texto(p))
                except OSError:
                    pass
    casos = {
        "so_cwd": [wt],
        "cwd_mais_git_common": [wt, common],
        "cwd_mais_subpastas_git": [wt, os.path.join(common, "worktrees", "wt"),
                                    os.path.join(common, "objects"),
                                    os.path.join(common, "refs"),
                                    os.path.join(common, "logs")],
    }
    out = {"gravados_por_commit_em_worktree": sorted(set(gravados))}
    for i, (nome, roots) in enumerate(casos.items()):
        cmd = f"echo {i} > c{i}.txt && git add c{i}.txt && git commit -qm c{i} && echo commitou"
        p = subprocess.run([sys.executable, "-I", os.path.abspath(__file__), "--saida", OUT,
                            "--landlock-exec", json.dumps(roots), "sh", "-c", cmd],
                           cwd=wt, capture_output=True, text=True, timeout=60)
        out[nome] = {"writable": [limpa_texto(r) for r in roots], "rc": p.returncode,
                     "saida": limpa_texto(p.stdout + p.stderr)[-600:]}
        subprocess.run(["git", "-C", wt, "reset", "-q"], check=False)
    out["git_log_wt"] = roda(["git", "-C", wt, "log", "--oneline"])[1]
    del marca
    salva("landlock", out)


# ---------------------------------------------------------------- T2 com custo

def aceita_sessao(m):
    if m["method"].endswith("requestApproval"):
        return {"decision": "acceptForSession"}
    return {"decision": "decline"}


POLITICA = {}  # thread → (sandboxPolicy, approvalPolicy) aplicados no turno
_TIPO = {"read-only": "readOnly", "workspace-write": "workspaceWrite",
         "danger-full-access": "dangerFullAccess"}


def nova_thread(srv, cwd, sandbox, aprov, **kw):
    """Abre a thread sempre em read-only e sobe o sandbox no `turn/start`.

    `thread/start` com `workspace-write` ou `danger-full-access` grava
    `trust_level = "trusted"` no ~/.codex/config.toml (achado da sondagem);
    pelo turno, não. A primeira rodada das fixtures ainda abria a thread com o
    sandbox pedido, e o config.toml foi restaurado depois (ver relatório).
    """
    r = srv.pede("thread/start", {"cwd": cwd, "sandbox": "read-only",
                                  "approvalPolicy": "never", "model": MODELO, **kw})
    th = r["thread"]["id"]
    POLITICA[th] = ({"type": _TIPO[sandbox]}, aprov)
    return th, limpa({k: r.get(k) for k in (
        "approvalPolicy", "sandbox", "model", "reasoningEffort", "instructionSources")})


def pago_leitura():
    raiz, _ = repo_temp("leitura")
    srv = AppServer("leitura", raiz)
    try:
        srv.abre()
        th, ini = nova_thread(srv, raiz, "read-only", "never")
        _, v = turno(srv, "leitura", th, "Crie o arquivo ola.txt com o texto oi. Não peça confirmação.")
        salva("pago_leitura", {"thread_start": ini, **resumo_itens(v),
                               "arquivo_criado": os.path.exists(os.path.join(raiz, "ola.txt"))})
    finally:
        srv.fecha()


def pago_edicao():
    raiz, _ = repo_temp("edicao")
    srv = AppServer("edicao", raiz)
    try:
        srv.abre()
        th, ini = nova_thread(srv, raiz, "workspace-write", "on-request")
        _, v = turno(srv, "edicao", th,
                     "Crie nota.txt com a linha um e depois altere base.txt para conter a linha dois. Use apply_patch.",
                     responder=aceita_sessao)
        salva("pago_edicao", {"thread_start": ini, **resumo_itens(v),
                              "nota": open(os.path.join(raiz, "nota.txt")).read()
                              if os.path.exists(os.path.join(raiz, "nota.txt")) else None,
                              "base": open(os.path.join(raiz, "base.txt")).read()})
    finally:
        srv.fecha()


def pago_comando():
    """R7 + R9: untrusted aceito? commandExecution e o ambiente no sandbox."""
    raiz, _ = repo_temp("comando")
    srv = AppServer("comando", raiz, env={"PROMPTORIUM_AGENTE": "codex"})
    try:
        srv.abre()
        try:
            th, ini = nova_thread(srv, raiz, "workspace-write", "untrusted")
        except RuntimeError as e:
            salva("pago_comando", {"untrusted": limpa_texto(str(e))})
            return
        aceitos = []

        def resp(m):
            aceitos.append(m["method"])
            return {"decision": "accept"}
        _, v = turno(srv, "comando", th,
                     "Rode, um por vez, estes comandos de shell: `ls`, `cat nao-existe.txt` e `echo agente=$PROMPTORIUM_AGENTE`. Depois diga a saída do último.",
                     responder=resp)
        salva("pago_comando", {"thread_start": ini, **resumo_itens(v), "aprovados": aceitos})
    finally:
        srv.fecha()


def pago_worktree():
    """R8: git commit dentro de um worktree.

    (a) `workspace-write` + `never` com o *git common dir* em `writableRoots`:
        o que o sandbox real faz neste host.
    (b) `workspace-write` + `on-request` sem `writableRoots`: se o sandbox
        bloquear, o modelo pede escalonamento e o app aprova (alternativa).
    """
    raiz, wt = repo_temp("worktree", worktree=True)
    common = os.path.join(raiz, ".git")
    fora_tmp = {"excludeSlashTmp": True, "excludeTmpdirEnvVar": True}
    out = {}
    for rot, aprov, pol in [
            ("com_roots_never", "never", {"type": "workspaceWrite", **fora_tmp,
                                          "writableRoots": [common]}),
            ("sem_roots_on_request", "on-request", {"type": "workspaceWrite", **fora_tmp})]:
        srv = AppServer(f"worktree-{rot}", wt)
        aprovados = []

        def resp(m):
            aprovados.append(limpa({"method": m["method"], "params": m["params"]}))
            return {"decision": "accept"}
        try:
            srv.abre()
            th, ini = nova_thread(srv, wt, "workspace-write", aprov)
            arq = f"{rot}.txt"
            _, v = turno(srv, f"worktree_{rot}", th,
                         f"Crie {arq} com a palavra ok e rode exatamente: git add {arq} && git commit -m {rot}. Se falhar, relate o erro sem tentar alternativas.",
                         extra={"sandboxPolicy": pol, "approvalPolicy": aprov},
                         responder=resp)
            out[rot] = {"thread_start": ini, **resumo_itens(v), "aprovacoes": aprovados,
                        "git_log": roda(["git", "-C", wt, "log", "--oneline"])[1]}
        finally:
            out[rot + "_stderr"] = srv.fecha()[-600:]
    salva("pago_worktree", out)


def pago_contexto():
    """R10 + R12 + R14: CLAUDE.md, outputSchema, tokenUsage e compactação."""
    raiz, _ = repo_temp("contexto", claude="# Regras\n\nA palavra-senha deste projeto é LARANJA-42.\n")
    srv = AppServer("contexto", raiz, extra=["-c", 'project_doc_fallback_filenames=["CLAUDE.md"]'])
    out = {}
    try:
        srv.abre()
        th, ini = nova_thread(srv, raiz, "read-only", "never")
        out["thread_start"] = ini
        _, v1 = turno(srv, "contexto_claude_md", th,
                      "Qual é a palavra-senha escrita nas instruções do projeto? Responda só ela, sem rodar comandos.")
        out["turno1"] = resumo_itens(v1)
        esquema = {"type": "object", "properties": {"ok": {"type": "boolean"}},
                   "required": ["ok"], "additionalProperties": False}
        _, v2 = turno(srv, "contexto_output_schema", th,
                      "Responda se 2+2=4, sem rodar comandos.", extra={"outputSchema": esquema})
        out["turno2_outputSchema"] = resumo_itens(v2)
        r = srv.pede("thread/compact/start", {"threadId": th})
        vc = srv.eventos(lambda m: m.get("method") in ("turn/completed",) or (
            m.get("method") == "item/completed"
            and m["params"]["item"].get("type") == "contextCompaction"), espera=180)
        vc += srv.eventos(lambda m: m.get("method") == "turn/completed", espera=20)
        TURNOS.append({"cenario": "contexto_compactar", "turno": "thread/compact/start",
                       "modelo": MODELO, "esforco": "-", "status": "ver eventos"})
        grava("turnos.json", TURNOS)
        out["compactar"] = {"resposta": r, **resumo_itens(vc)}
        lido = srv.pede("thread/read", {"threadId": th, "includeTurns": False})
        out["thread_read_chaves"] = sorted(lido.get("thread", {}).keys())
    finally:
        srv.fecha()
    salva("pago_contexto", out)


def png(cor, caminho):
    w = h = 16
    linha = b"\x00" + bytes(cor) * w
    raw = linha * h

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    dados = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
             + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
    open(caminho, "wb").write(dados)
    return dados


def pago_imagem():
    raiz, _ = repo_temp("imagem")
    verm = png((220, 20, 20), os.path.join(raiz, "a.png"))
    png((20, 20, 220), os.path.join(raiz, "b.png"))
    srv = AppServer("imagem", raiz)
    try:
        srv.abre()
        th, ini = nova_thread(srv, raiz, "read-only", "never")
        entrada = [{"type": "text", "text": "Diga só a cor dominante de cada imagem, na ordem (1, 2), sem rodar comandos."},
                   {"type": "image", "url": "data:image/png;base64," + base64.b64encode(verm).decode()},
                   {"type": "localImage", "path": os.path.join(raiz, "b.png")}]
        _, v = turno(srv, "imagem", th, entrada)
        salva("pago_imagem", {"thread_start": ini, **resumo_itens(v),
                              "esperado": "1 vermelho (data URL), 2 azul (localImage)"})
    finally:
        srv.fecha()


def pago_interromper():
    raiz, _ = repo_temp("interromper")
    srv = AppServer("interromper", raiz)
    out = {}
    try:
        srv.abre()
        th, ini = nova_thread(srv, raiz, "read-only", "never")

        def durante(s, thread, tid):
            vistos = s.eventos(lambda m: m.get("method") == "item/agentMessage/delta"
                               or m.get("method") == "turn/completed", espera=90)
            try:
                out["steer"] = s.pede("turn/steer", {"threadId": thread, "expectedTurnId": tid,
                                                     "input": [{"type": "text", "text": "Mude: escreva os números em inglês."}]})
            except Exception as e:  # noqa: BLE001
                out["steer"] = {"erro": limpa_texto(str(e))}
            vistos += s.eventos(lambda m: m.get("method") == "item/agentMessage/delta"
                                or m.get("method") == "turn/completed", espera=30)
            time.sleep(1.5)
            try:
                out["interrupt"] = s.pede("turn/interrupt", {"threadId": thread, "turnId": tid})
            except Exception as e:  # noqa: BLE001
                out["interrupt"] = {"erro": limpa_texto(str(e))}
            return vistos
        _, v = turno(srv, "interromper", th,
                     "Escreva os números de 1 a 300 por extenso, um por linha, sem rodar comandos.",
                     durante=durante)
        out.update({"thread_start": ini, **resumo_itens(v)})
    finally:
        srv.fecha()
    salva("pago_interromper", out)


def pago_hook_turno():
    raiz, _ = repo_temp("hook_turno")
    open(os.path.join(raiz, "apagar.txt"), "w").write("x\n")
    extra, log = hook_args()
    srv = AppServer("hook_turno", raiz, extra=extra)
    try:
        srv.abre()
        # danger-full-access: neste host o bwrap não sobe; sem sandbox o efeito
        # do hook fica visível (o arquivo some se o hook não bloquear).
        th, ini = nova_thread(srv, raiz, "danger-full-access", "never")
        _, v = turno(srv, "hook_turno", th, "Rode exatamente `rm apagar.txt` e relate o resultado; não tente alternativas.")
        salva("pago_hook_turno", {"thread_start": ini, **resumo_itens(v),
                                  "arquivo_existe": os.path.exists(os.path.join(raiz, "apagar.txt")),
                                  "hook_log": limpa_texto(open(log).read())[-1500:]
                                  if os.path.exists(log) else None})
    finally:
        srv.fecha()


# ---------------------------------------------------------------- main

def main():
    if args.landlock_exec:
        landlock_exec(json.loads(args.landlock_exec[0]), args.landlock_exec[1:])
        return
    global RES, TURNOS
    os.makedirs(os.path.join(OUT, "fixtures"), exist_ok=True)
    if os.path.exists(os.path.join(OUT, "resultados.json")):
        RES = json.load(open(os.path.join(OUT, "resultados.json")))
    if os.path.exists(os.path.join(OUT, "turnos.json")):
        TURNOS = json.load(open(os.path.join(OUT, "turnos.json")))
    fotos = RES.get("fotos", [])
    antes = foto("antes")
    gratis = [("cli", r1_cli), ("schema", r2_schema), ("handshake", r3_handshake),
              ("sandbox", sandbox_exec), ("instrucoes", instrucoes), ("hooks", hooks),
              ("landlock", landlock), ("hooks_confianca", hooks_confianca),
              ("confianca", confianca), ("mcp", mcp_usuario)]
    pagos = [("leitura", pago_leitura), ("edicao", pago_edicao), ("comando", pago_comando),
             ("worktree", pago_worktree), ("contexto", pago_contexto),
             ("imagem", pago_imagem), ("interromper", pago_interromper),
             ("hook_turno", pago_hook_turno)]
    global MODELO
    MODELO = args.modelo or RES.get("handshake", {}).get("modelo_escolhido")
    for nome, f in gratis + (pagos if args.pago else []):
        if not quer(nome):
            continue
        if nome in dict(pagos) and not MODELO:
            r3_handshake()
        print("==", nome, flush=True)
        try:
            f()
        except Exception as e:  # noqa: BLE001
            salva(f"erro_{nome}", limpa_texto(repr(e)))
            print("  erro:", e, flush=True)
    fotos.append(compara(antes, foto("depois " + ",".join(sorted(SO)) if SO else "depois")))
    salva("fotos", fotos)
    print(json.dumps(fotos[-1], indent=1))
    print("turnos pagos até agora:", len([t for t in TURNOS if t["turno"] != "thread/compact/start"]),
          "+ compactações:", len([t for t in TURNOS if t["turno"] == "thread/compact/start"]))


main()
