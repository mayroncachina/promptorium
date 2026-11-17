import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hooks the app adds to every session through a temporary `--settings`
/// file (nothing goes to the user's `~/.claude/settings.json`). The hook is
/// a small Python 3 script written next to it; it reads the event on stdin
/// and answers like a user hook. What it did goes to `hooks.log` (JSON
/// lines), read by the app after each tool result (timeline cards).
///
/// Verified on CLI 2.1.302 (docs/pesquisa/hooks-settings-stream-json.md):
/// `PreToolUse` with `permissionDecision: deny` refuses the call and the
/// reason reaches the agent; `PostToolUse` and `SessionEnd` run; the user's
/// own hooks keep running.
enum ManagedHook {
  /// `PreToolUse` on Bash: refuses dangerous commands.
  block('Bloquear comandos perigosos', 'PreToolUse'),

  /// `PostToolUse` on Edit / Write / MultiEdit: runs `formatar:`.
  format('Formatar ao editar', 'PostToolUse'),

  /// `SessionEnd`: records why the session ended.
  end('Registrar fim da sessão', 'SessionEnd'),

  /// `PreToolUse` on Bash: the Vigia de segredos (SPEC-085 R1) checks what
  /// a `git commit`, `git push` or `gh pr create` would send.
  secrets('Vigia de segredos', 'PreToolUse');

  const ManagedHook(this.label, this.event);

  final String label;
  final String event;

  /// `app_settings` key: '0' = off (default on). The Vigia de segredos
  /// follows its own switch (Configurações › Vigia de segredos, R14).
  String get settingKey =>
      this == secrets ? secretsEnabledSettingKey : 'hooks.$name';

  String get description => switch (this) {
    block =>
      'Antes de cada comando Bash: recusa git push --force, rm -rf / ou ~, '
          'git worktree remove, git -C na raiz do repositório (sessões em '
          'worktree) e os bloquear-comandos do config.yml.',
    format =>
      'Depois de cada edição: roda o formatar: do config.yml com o arquivo '
          'editado.',
    end => 'Ao encerrar o processo: registra o motivo na timeline.',
    secrets =>
      'Antes de git commit, git push e gh pr create: procura chaves, tokens '
          'e arquivos .env no que vai sair e bloqueia o comando.',
  };
}

/// `app_settings` key of the Vigia de segredos (SPEC-085 R14): '0' = off.
const secretsEnabledSettingKey = 'secrets.enabled';

/// One rule of the `PreToolUse` hook: a regular expression searched in the
/// Bash command.
@immutable
class BlockRule {
  const BlockRule(this.name, this.pattern);

  final String name;
  final String pattern;

  Map<String, String> toJson() => {'nome': name, 're': pattern};
}

/// Built-in rules (see [ManagedHook.block]).
const builtinBlockRules = [
  BlockRule(
    'git push --force',
    r'\bgit\b[^;&|]*\bpush\b[^;&|]*(\s--force(?!-with-lease)\b|\s-f\b)',
  ),
  BlockRule(
    'rm -rf na raiz ou na home',
    r'\brm\s+-[A-Za-z]*\s+(/|~|\$HOME)/?\*?(\s|$|;|&)',
  ),
  BlockRule('git worktree remove', r'\bgit\b[^;&|]*\bworktree\s+remove\b'),
];

/// Extra rules of a session on a PR brought into the app (SPEC-050 R7):
/// `git push --force*`, `git push -f*` and `git push --force-with-lease*`
/// anywhere in the push, and a `+refspec` (a forced push too).
const prForcePushRules = [
  BlockRule(
    'git push --force* (PR trazido)',
    r'\bgit\b[^;&|]*\bpush\b[^;&|]*\s(--force\S*|-f\S*|-[A-Za-z]*f[A-Za-z]*)(\s|$|;|&|\|)',
  ),
  BlockRule(
    'git push +refspec (PR trazido)',
    r'\bgit\b[^;&|]*\bpush\b[^;&|]*\s\+\S',
  ),
];

/// `bloquear-comandos:` glob → [BlockRule]: `*` is anything; the pattern
/// may appear anywhere in the command.
BlockRule globRule(String glob) {
  final re = glob.split('*').map(RegExp.escape).join('.*');
  return BlockRule(glob, re);
}

/// Every rule of a session: built-in, the project's, [extra] and, for a session in a
/// worktree, `git -C <root>` / `cd <root>` (the main repository is not
/// touched from a worktree).
List<BlockRule> blockRules({
  List<String> projectGlobs = const [],
  String? root,
  String? cwd,
  List<BlockRule> extra = const [],
}) => [
  ...builtinBlockRules,
  for (final g in projectGlobs) globRule(g),
  ...extra,
  if (root != null && cwd != null && root != cwd) ...[
    BlockRule(
      'git -C na raiz do repositório',
      '\\bgit\\s+-C\\s+[\'"]?${RegExp.escape(root)}/?[\'"]?(\\s|\$)',
    ),
    BlockRule(
      'cd para a raiz do repositório',
      '\\bcd\\s+[\'"]?${RegExp.escape(root)}/?[\'"]?(\\s|\$|;|&)',
    ),
  ],
];

/// Whether [command] is refused by [rules] (same search as the script);
/// returns the rule's name.
String? blockedBy(String command, List<BlockRule> rules) {
  for (final r in rules) {
    if (RegExp(r.pattern).hasMatch(command)) return r.name;
  }
  return null;
}

/// What a hook did (a line of `hooks.log`).
@immutable
class HookActivity {
  const HookActivity({
    required this.hook,
    required this.text,
    required this.at,
    this.error = false,
    this.secrets,
    this.waived = const [],
    this.timedOut = false,
  });

  final ManagedHook hook;

  /// A commit, push or PR of the agent blocked by the Vigia de segredos
  /// (SPEC-085 R1, R7): the log line as it came (findings already masked).
  final Map<String, Object?>? secrets;

  /// Waivers that let a command through (R12: their last use is touched).
  final List<int> waived;

  /// The check took longer than its limit; the command went unchecked
  /// (R16).
  final bool timedOut;

  /// Timeline line ("Hook bloqueou `git push --force`").
  final String text;
  final DateTime at;
  final bool error;

  static HookActivity? fromLogLine(String line) {
    Object? j;
    try {
      j = jsonDecode(line);
    } on FormatException {
      return null;
    }
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['em'] ?? ''}') ?? DateTime.now();
    return switch (j['evento']) {
      'bloqueio' => HookActivity(
        hook: ManagedHook.block,
        text: 'Hook bloqueou `${j['comando']}` (${j['regra']})',
        at: at,
        error: true,
      ),
      'formatado' => HookActivity(
        hook: ManagedHook.format,
        text: j['ok'] == true
            ? 'Formatado: ${j['arquivo']}'
            : 'Falha ao formatar ${j['arquivo']}: ${j['saida'] ?? ''}'.trim(),
        at: at,
        error: j['ok'] != true,
      ),
      'fim' => HookActivity(
        hook: ManagedHook.end,
        text: 'Sessão encerrada (${j['motivo'] ?? '?'})',
        at: at,
      ),
      'segredo' => HookActivity(
        hook: ManagedHook.secrets,
        text: secretBlockTitle(
          '${j['acao'] ?? 'commit'}',
          (j['achados'] is List) ? (j['achados'] as List).length : 0,
        ),
        at: at,
        error: true,
        secrets: j.cast<String, Object?>(),
      ),
      'segredo_liberado' => HookActivity(
        hook: ManagedHook.secrets,
        text: 'Vigia de segredos: commit liberado por justificativa',
        at: at,
        waived: [
          if (j['ignorados'] case final List l)
            for (final e in l)
              if (e is num) e.toInt(),
        ],
      ),
      'segredo_tempo' => HookActivity(
        hook: ManagedHook.secrets,
        text: 'Vigia de segredos: tempo esgotado, commit não conferido',
        at: at,
        error: true,
        timedOut: true,
      ),
      _ => null,
    };
  }
}

/// "Vigia de segredos bloqueou o commit · 2 achados" (R7).
String secretBlockTitle(String action, int count) {
  final what = switch (action) {
    'push' => 'o push',
    'pr' => 'o PR',
    _ => 'o commit',
  };
  return 'Vigia de segredos bloqueou $what · $count '
      '${count == 1 ? 'achado' : 'achados'}';
}

/// The hook script (Python 3, standard library only).
const hookScript = r'''
import datetime, hashlib, json, math, os, re, shlex, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    cfg = json.load(open(os.path.join(HERE, "hooks-config.json"), encoding="utf-8"))
    ev = json.load(sys.stdin)
    name = ev.get("hook_event_name")

    def log(obj):
        obj["em"] = datetime.datetime.now().isoformat()
        with open(cfg["log"], "a", encoding="utf-8") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")

    tool_input = ev.get("tool_input") or {}
    if name == "PreToolUse" and ev.get("tool_name") == "Bash":
        cmd = tool_input.get("command") or ""
        for rule in cfg.get("bloquear", []):
            if re.search(rule["re"], cmd):
                log({"evento": "bloqueio", "comando": cmd, "regra": rule["nome"]})
                print(json.dumps({"hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason":
                        "Promptorium: comando bloqueado (%s). Não tente contornar; "
                        "se for necessário, peça ao usuário." % rule["nome"],
                }}))
                return
        reason = check_secrets(cfg, cmd, ev.get("cwd") or os.getcwd(), log)
        if reason:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }}, ensure_ascii=False))
            return
    elif name == "PostToolUse" and cfg.get("formatar") and \
            ev.get("tool_name") in ("Edit", "Write", "MultiEdit"):
        path = tool_input.get("file_path")
        if not path:
            return
        cmd = cfg["formatar"].replace("{arquivo}", shlex.quote(path))
        try:
            r = subprocess.run(cmd, shell=True, cwd=ev.get("cwd") or None,
                               capture_output=True, text=True, timeout=60)
            ok, out = r.returncode == 0, (r.stdout + r.stderr)[-2000:]
        except subprocess.TimeoutExpired:
            ok, out = False, "tempo esgotado (60 s)"
        rel = os.path.relpath(path, ev.get("cwd") or HERE)
        log({"evento": "formatado", "arquivo": rel, "ok": ok, "saida": out.strip()})
    elif name == "SessionEnd":
        log({"evento": "fim", "motivo": ev.get("reason")})


# --- Vigia de segredos (SPEC-085) -------------------------------------------
# Same algorithm as lib/core/secrets/secret_scanner.dart, over the same
# rules (secrets.json); test/core/secrets/secret_parity_test.dart compares
# both. The value of a finding never leaves scan_diff: only the mask and
# the salted fingerprint.

HUNK = re.compile(r"^@@ -\d+(,\d+)? \+(\d+)", re.ASCII)
ENV_KEY = re.compile(r"^\s*(export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=", re.ASCII)
HEX = re.compile(r"^[0-9a-fA-F]+$", re.ASCII)


def parse_diff(diff):
    files, cur, in_hunk, new_line = [], None, False, 0
    for raw in diff.split("\n"):
        if raw.startswith("diff --git "):
            cur = {"path": None, "binary": False, "deleted": False, "added": []}
            files.append(cur)
            in_hunk = False
            i = raw.rfind(" b/")
            if i >= 0:
                cur["path"] = raw[i + 3:]
            continue
        if cur is None:
            continue
        if raw.startswith("@@"):
            m = HUNK.match(raw)
            if m:
                new_line = int(m.group(2))
                in_hunk = True
            continue
        if in_hunk:
            if raw.startswith("+"):
                cur["added"].append((new_line, raw[1:]))
                new_line += 1
                continue
            if raw.startswith(" "):
                new_line += 1
                continue
            if raw.startswith("-") or raw.startswith("\\"):
                continue
            in_hunk = False
        if raw.startswith("+++ "):
            p = raw[4:]
            if p == "/dev/null":
                cur["deleted"] = True
            elif p.startswith("b/"):
                cur["path"] = p[2:]
        elif raw.startswith("deleted file mode"):
            cur["deleted"] = True
        elif raw.startswith("Binary files "):
            cur["binary"] = True
            if raw.endswith(" and /dev/null differ"):
                cur["deleted"] = True
    return files


def entropy(s):
    if not s:
        return 0.0
    counts = {}
    for c in s:
        counts[c] = counts.get(c, 0) + 1
    h = 0.0
    for c in counts.values():
        p = c / len(s)
        h -= p * (math.log(p) / math.log(2))
    return h


def thousands(n):
    return "{:,}".format(n).replace(",", ".")


def mask(value, rule, header=None):
    if rule.get("bloco"):
        return "%s •••• (%s caracteres)" % (
            header or "-----BEGIN PRIVATE KEY-----", thousands(len(value)))
    prefix = ""
    for p in rule.get("prefixos", []):
        if value.startswith(p):
            prefix = p
            break
    if not prefix and len(value) > 4:
        prefix = value[:2]
    return "%s••••••••(%d)" % (prefix, len(value))


def fingerprint(value, salt):
    return hashlib.sha256((salt + "\0" + value).encode("utf-8")).hexdigest()


def short_line(s):
    t = s.strip(" \t\r")
    return t if len(t) <= 160 else t[:160] + "…"


def scan_diff(diff, sc):
    rules = sc.get("regras", [])
    salt = sc.get("sal", "")
    partial = len(diff.encode("utf-8")) > sc.get("limite", 5242880)
    globs = [(re.compile(g["re"], re.ASCII), g["base"]) for g in sc.get("ignorar", [])]
    allow = sc.get("permitir", [])
    examples = sc.get("exemplos", [])
    waivers = sc.get("ignorados", [])
    compiled = {}
    for r in rules:
        if r.get("re"):
            fl = re.ASCII | (re.IGNORECASE if r.get("i") else 0)
            compiled[r["id"]] = re.compile(r["re"], fl)

    def ignored_path(path):
        base = path.split("/")[-1]
        return any(g.search(base if b else path) for g, b in globs)

    def waiver_of(rule, path, pr):
        for w in waivers:
            if w["alcance"] == "valor":
                if w["impressao"] and w["impressao"] == pr:
                    return w
            elif w["regra"] == rule and w["caminho"] == path:
                return w
        return None

    findings, seen, waived = [], set(), set()

    def add(f):
        key = (f["arquivo"], f["regra"], f["impressao"])
        if key not in seen:
            seen.add(key)
            findings.append(f)

    for f in parse_diff(diff):
        path = f["path"]
        if path is None or f["deleted"] or ignored_path(path):
            continue
        base = path.split("/")[-1]
        file_rule = None
        for r in rules:
            if r["tipo"] != "file":
                continue
            if not re.search(r["arquivo"], base, re.ASCII):
                continue
            if r.get("exceto") and re.search(r["exceto"], base, re.ASCII):
                continue
            if r.get("conteudo"):
                c = re.compile(r["conteudo"], re.ASCII)
                if not any(c.search(t) for _, t in f["added"]):
                    continue
            file_rule = r
            break
        if file_rule is not None:
            keys = []
            for _, t in f["added"]:
                m = ENV_KEY.search(t)
                if m and m.group(2) not in keys:
                    keys.append(m.group(2))
            n = len(f["added"])
            masked = ", ".join(keys) if keys else "•••• (%d %s)" % (
                n, "linha" if n == 1 else "linhas")
            pr = fingerprint("\n".join(t for _, t in f["added"]), salt)
            w = waiver_of(file_rule["id"], path, pr)
            if w is not None:
                waived.add(w["id"])
                continue
            add({"arquivo": path, "linha": None, "regra": file_rule["id"],
                 "nome": file_rule["nome"], "tipo": "file", "mascara": masked,
                 "impressao": pr, "linha_mascarada": None})
            continue
        if f["binary"]:
            continue
        added = f["added"]
        for i, (line_no, text) in enumerate(added):
            if any(a in text for a in allow):
                continue
            hits = []
            for r in rules:
                if r["tipo"] == "file":
                    continue
                if partial and not r.get("bloco"):
                    continue
                for m in compiled[r["id"]].finditer(text):
                    g = r.get("valor", 0)
                    value = m.group(g)
                    if not value:
                        continue
                    start = m.start() if g == 0 else m.start() + m.group(0).find(value)
                    end = start + len(value)
                    if any(start < h[1] and h[0] < end for h in hits):
                        continue
                    low = value.lower()
                    if any(e in low for e in examples):
                        continue
                    if r["tipo"] == "entropy":
                        lim = r["entropia"][1] if HEX.match(value) else r["entropia"][0]
                        if entropy(value) <= lim:
                            continue
                    full = value
                    if r.get("bloco"):
                        parts = [text[start:]]
                        for j in range(i + 1, len(added)):
                            n, t = added[j]
                            if n != added[j - 1][0] + 1:
                                break
                            parts.append(t)
                            if "-----END" in t:
                                break
                        full = "\n".join(parts)
                    pr = fingerprint(full, salt)
                    w = waiver_of(r["id"], path, pr)
                    if w is not None:
                        waived.add(w["id"])
                    hits.append((start, len(text) if r.get("bloco") else end, r,
                                 mask(full, r, m.group(0) if r.get("bloco") else None),
                                 pr, w is not None))
            if not hits:
                continue
            line = text
            for h in sorted(hits, key=lambda h: -h[0]):
                line = line[:h[0]] + h[3] + line[h[1]:]
            shown = short_line(line)
            for h in hits:
                if h[5]:
                    continue
                add({"arquivo": path, "linha": line_no, "regra": h[2]["id"],
                     "nome": h[2]["nome"], "tipo": h[2]["tipo"], "mascara": h[3],
                     "impressao": h[4], "linha_mascarada": shown})
    return {"achados": findings, "ignorados": sorted(waived), "parcial": partial}


def untracked_diff(path, data):
    head = "diff --git a/%s b/%s\nnew file mode 100644\n" % (path, path)
    if b"\0" in data[:8000]:
        return head + "Binary files /dev/null and b/%s differ\n" % path
    text = data.decode("utf-8", "replace")
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if not lines:
        return head + "--- /dev/null\n+++ b/%s\n" % path
    out = [head, "--- /dev/null\n+++ b/%s\n@@ -0,0 +1,%d @@\n" % (path, len(lines))]
    for l in lines:
        out.append("+" + l + "\n")
    return "".join(out)


EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
DIFF_ARGS = ["-c", "core.quotePath=false"]


def git_out(cwd, args, deadline):
    left = deadline - time.monotonic()
    if left <= 0:
        raise TimeoutError()
    r = subprocess.run(["git"] + DIFF_ARGS + ["-C", cwd] + args, capture_output=True,
                       timeout=left)
    return r.returncode, r.stdout


def commit_diff(cwd, limit, deadline):
    """Everything the command may put in the commit (R1): index and working
    tree against HEAD, plus the untracked files that are not ignored."""
    code, _ = git_out(cwd, ["rev-parse", "-q", "--verify", "HEAD"], deadline)
    base = "HEAD" if code == 0 else EMPTY_TREE
    _, out = git_out(cwd, ["diff", "--no-color", "--no-ext-diff", "--no-renames",
                           "-U0", base], deadline)
    _, staged = git_out(cwd, ["diff", "--no-color", "--no-ext-diff", "--no-renames",
                              "-U0", "--cached", base], deadline)
    parts = [out.decode("utf-8", "replace")]
    if staged != out:
        parts.append(staged.decode("utf-8", "replace"))
    _, names = git_out(cwd, ["ls-files", "--others", "--exclude-standard", "-z"], deadline)
    size = len(out)
    for name in names.decode("utf-8", "replace").split("\0"):
        if not name:
            continue
        p = os.path.join(cwd, name)
        try:
            if os.path.isdir(p) or os.path.islink(p):
                continue
            with open(p, "rb") as fh:
                data = fh.read(limit + 1)
        except OSError:
            continue
        size += len(data)
        parts.append(untracked_diff(name, data))
        if time.monotonic() > deadline:
            raise TimeoutError()
    return "\n".join(parts)


def push_diff(cwd, deadline):
    """Added lines of the commits not on any remote yet (R1)."""
    _, out = git_out(cwd, ["log", "-p", "--format=", "--no-color", "--no-ext-diff",
                           "--no-renames", "-U0", "--max-count=500", "HEAD",
                           "--not", "--remotes"], deadline)
    return out.decode("utf-8", "replace")


SPLIT = re.compile(r"&&|\|\||;|\||\n")


def git_actions(cmd, cwd):
    """(kind, dir) of each `git commit`, `git push` and `gh pr create` of a
    Bash command, following `cd` and `git -C` (R1)."""
    out = []
    here = cwd
    for seg in SPLIT.split(cmd):
        try:
            toks = shlex.split(seg)
        except ValueError:
            toks = seg.split()
        while toks and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", toks[0]):
            toks = toks[1:]
        if not toks:
            continue
        if toks[0] == "cd" and len(toks) > 1:
            here = os.path.normpath(os.path.join(here, os.path.expanduser(toks[1])))
            continue
        if toks[0] == "git":
            d = here
            i = 1
            while i < len(toks) and toks[i].startswith("-"):
                if toks[i] == "-C" and i + 1 < len(toks):
                    d = os.path.normpath(os.path.join(d, os.path.expanduser(toks[i + 1])))
                    i += 2
                elif toks[i] in ("-c", "--git-dir", "--work-tree") and i + 1 < len(toks):
                    i += 2
                else:
                    i += 1
            sub = toks[i] if i < len(toks) else ""
            if sub == "commit":
                out.append(("commit", d))
            elif sub == "push":
                out.append(("push", d))
        elif toks[0] == "gh" and len(toks) > 2 and toks[1] == "pr" and toks[2] == "create":
            out.append(("pr", here))
    return out


def check_secrets(cfg, cmd, cwd, log):
    path = cfg.get("segredos")
    if not path or not os.path.exists(path):
        return None
    actions = git_actions(cmd, cwd)
    if not actions:
        return None
    sc = json.load(open(path, encoding="utf-8"))
    if not sc.get("ligado", True):
        return None
    deadline = time.monotonic() + float(sc.get("tempo", 10))
    findings, waived, partial, kinds, done = [], set(), False, [], set()
    try:
        for kind, d in actions:
            what = "commit" if kind == "commit" else "push"
            if (what, d) in done:
                continue
            done.add((what, d))
            diff = commit_diff(d, sc.get("limite", 5242880), deadline) if what == "commit" \
                else push_diff(d, deadline)
            res = scan_diff(diff, sc)
            if sc.get("gitleaks"):
                res["achados"] = res["achados"] + run_gitleaks(sc, d, diff, deadline)
            if time.monotonic() > deadline:
                raise TimeoutError()
            waived.update(res["ignorados"])
            partial = partial or res["parcial"]
            if res["achados"]:
                kinds.append(kind)
                findings.extend(res["achados"])
    except (TimeoutError, subprocess.TimeoutExpired):
        log({"evento": "segredo_tempo"})
        return None
    if waived:
        log({"evento": "segredo_liberado", "ignorados": sorted(waived)})
    if not findings:
        return None
    kind = kinds[0]
    what = {"commit": "o commit", "push": "o push", "pr": "o PR"}[kind]
    log({"evento": "segredo", "acao": kind, "comando": mask_command(cmd, sc),
         "achados": findings, "parcial": partial})
    parts = []
    for f in findings[:5]:
        parts.append("arquivo %s" % f["arquivo"] if f["linha"] is None
                     else "%s em %s:%d" % (f["nome"], f["arquivo"], f["linha"]))
    more = "; +%d" % (len(findings) - 5) if len(findings) > 5 else ""
    n = len(findings)
    return ("Promptorium: o Vigia de segredos bloqueou %s: %d %s (%s%s). Não tente "
            "contornar nem mudar o comando; espere o usuário decidir." % (
                what, n, "achado" if n == 1 else "achados", "; ".join(parts), more))


def run_gitleaks(sc, d, diff, deadline):
    """gitleaks (always with --redact) on a copy of the changed files (R13);
    any error gives no findings: the app's own rules already ran."""
    import shutil, tempfile
    tmp = tempfile.mkdtemp(prefix="promptorium-gitleaks-")
    try:
        src = os.path.join(tmp, "src")
        for f in parse_diff(diff):
            if f["path"] is None or f["deleted"] or f["binary"]:
                continue
            p = os.path.join(d, f["path"])
            if not os.path.isfile(p):
                continue
            dst = os.path.join(src, f["path"])
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(p, dst)
        if not os.path.isdir(src):
            return []
        report = os.path.join(tmp, "report.json")
        left = max(0.1, deadline - time.monotonic())
        subprocess.run([sc["gitleaks"], "dir", "--redact", "--no-banner", "--exit-code",
                        "0", "--report-format", "json", "--report-path", report, src],
                       capture_output=True, timeout=left)
        out = []
        for e in json.load(open(report, encoding="utf-8")):
            path = e.get("File", "")
            if path.startswith(src + "/"):
                path = path[len(src) + 1:]
            rid = e.get("RuleID", "?")
            pr = fingerprint("gitleaks:%s:%s:%s" % (path, rid, e.get("StartLine")),
                             sc.get("sal", ""))
            if any((w["alcance"] == "valor" and w["impressao"] == pr) or
                   (w["alcance"] != "valor" and w["regra"] == "gitleaks:" + rid and
                    w["caminho"] == path) for w in sc.get("ignorados", [])):
                continue
            out.append({"arquivo": path, "linha": e.get("StartLine"),
                        "regra": "gitleaks:" + rid, "nome": rid + " (gitleaks)",
                        "tipo": "pattern", "mascara": "•••• (oculto pelo gitleaks)",
                        "impressao": pr, "linha_mascarada": None})
        return out
    except Exception:
        return []
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def mask_command(cmd, sc):
    res = scan_diff("diff --git a/cmd b/cmd\n+++ b/cmd\n@@ -0,0 +1,1 @@\n+" +
                    cmd.replace("\n", " ") + "\n", dict(sc, ignorados=[], ignorar=[]))
    for f in res["achados"]:
        if f["linha_mascarada"]:
            return f["linha_mascarada"]
    return cmd if len(cmd) <= 300 else cmd[:300] + "…"


if len(sys.argv) > 2 and sys.argv[1] == "--scan":
    # Tests (secret_parity_test.dart): the findings of a diff on stdin.
    _sc = json.load(open(sys.argv[2], encoding="utf-8"))
    _diff = sys.stdin.buffer.read().decode("utf-8", "replace")
    sys.stdout.write(json.dumps(scan_diff(_diff, _sc), ensure_ascii=False))
else:
    try:
        main()
    except Exception:
        # A broken hook must never stop the agent.
        pass
''';

/// Writes and removes the per-session hook files under [runBase]
/// (`~/.promptorium/run/<session>/`).
class ManagedHooks {
  ManagedHooks({required this.runBase, this.python = 'python3'});

  final String runBase;
  final String python;

  String dirOf(String sessionId) => '$runBase/$sessionId';
  String logOf(String sessionId) => '${dirOf(sessionId)}/hooks.log';

  /// Rules, ignored paths and waivers of the Vigia de segredos (SPEC-085):
  /// rewritten when a waiver is added, read by the hook on each command.
  String secretsOf(String sessionId) => '${dirOf(sessionId)}/secrets.json';

  /// Writes [secrets] ([secretRulesJson]) atomically; nothing when the
  /// session has no hook folder.
  Future<void> writeSecrets(
    String sessionId,
    Map<String, Object?> secrets,
  ) async {
    final dir = Directory(dirOf(sessionId));
    if (!await dir.exists()) return;
    final f = File(secretsOf(sessionId));
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(secrets), flush: true);
    await tmp.rename(f.path);
  }

  /// `settings.json` with one entry per enabled hook, all calling
  /// [command] (the script).
  static Map<String, Object?> settingsJson(
    String command,
    Set<ManagedHook> enabled,
  ) {
    List<Map<String, Object?>> entry(String? matcher) => [
      {
        'matcher': ?matcher,
        'hooks': [
          {'type': 'command', 'command': command, 'timeout': 90},
        ],
      },
    ];
    return {
      'hooks': {
        if (enabled.contains(ManagedHook.block) ||
            enabled.contains(ManagedHook.secrets))
          'PreToolUse': entry('Bash'),
        if (enabled.contains(ManagedHook.format))
          'PostToolUse': entry('Write|Edit|MultiEdit'),
        if (enabled.contains(ManagedHook.end)) 'SessionEnd': entry(null),
      },
    };
  }

  /// Writes the session's files; returns the `--settings` path, or null
  /// when no hook applies.
  /// [extra] goes into the same `settings.json` (the plugins and MCP
  /// servers turned off, SPEC-017 R2).
  Future<String?> prepare(
    String sessionId, {
    required Set<ManagedHook> enabled,
    required List<BlockRule> rules,
    String? formatCommand,
    Map<String, Object?>? secrets,
    Map<String, Object?> extra = const {},
  }) async {
    final on = {
      for (final h in enabled)
        if ((h != ManagedHook.format || formatCommand != null) &&
            (h != ManagedHook.secrets || secrets != null))
          h,
    };
    if (on.isEmpty && extra.isEmpty) return null;
    final dir = Directory(dirOf(sessionId));
    await dir.create(recursive: true);
    // A new process reads the log from the start: a log left by a process
    // that ended without its cleanup (the app was killed) would show its
    // blocks again (SPEC-085: a resolved block coming back).
    final oldLog = File(logOf(sessionId));
    if (await oldLog.exists()) await oldLog.delete();
    if (on.isEmpty) {
      final settings = File('${dir.path}/settings.json');
      await settings.writeAsString(jsonEncode(extra));
      return settings.path;
    }
    final script = File('${dir.path}/promptorium_hook.py');
    await script.writeAsString(hookScript);
    await File('${dir.path}/hooks-config.json').writeAsString(
      jsonEncode({
        'log': logOf(sessionId),
        'bloquear': [
          if (on.contains(ManagedHook.block))
            for (final r in rules) r.toJson(),
        ],
        'formatar': on.contains(ManagedHook.format) ? formatCommand : null,
        if (on.contains(ManagedHook.secrets)) 'segredos': secretsOf(sessionId),
      }),
    );
    if (on.contains(ManagedHook.secrets)) {
      await writeSecrets(sessionId, secrets!);
    }
    final settings = File('${dir.path}/settings.json');
    await settings.writeAsString(
      jsonEncode({
        ...settingsJson('$python ${_quote(script.path)}', on),
        ...extra,
      }),
    );
    return settings.path;
  }

  /// New lines of the session's log after byte [offset]; returns them and
  /// the new offset.
  Future<(List<HookActivity>, int)> readLog(
    String sessionId,
    int offset,
  ) async {
    final f = File(logOf(sessionId));
    if (!await f.exists()) return (const <HookActivity>[], offset);
    final len = await f.length();
    if (len <= offset) return (const <HookActivity>[], offset);
    final raf = await f.open();
    try {
      await raf.setPosition(offset);
      final bytes = await raf.read(len - offset);
      final text = utf8.decode(bytes, allowMalformed: true);
      final end = text.lastIndexOf('\n');
      if (end < 0) return (const <HookActivity>[], offset);
      final lines = text.substring(0, end).split('\n');
      return (
        [for (final l in lines) ?HookActivity.fromLogLine(l)],
        offset + utf8.encode(text.substring(0, end + 1)).length,
      );
    } finally {
      await raf.close();
    }
  }

  Future<void> cleanup(String sessionId) async {
    try {
      final d = Directory(dirOf(sessionId));
      if (await d.exists()) await d.delete(recursive: true);
    } catch (e) {
      debugPrint('hooks de $sessionId não removidos: $e');
    }
  }

  static String _quote(String s) => "'${s.replaceAll("'", r"'\''")}'";
}

/// Whether `python3` runs (the hook script needs it). Checked once.
Future<bool> pythonAvailable() => _python ??= () async {
  try {
    final r = await Process.run('python3', ['--version']);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}();
Future<bool>? _python;

/// The app's hooks; null = off (tests, or no `python3`). Tests that need
/// them override with a temporary [ManagedHooks.runBase].
final managedHooksProvider = Provider<ManagedHooks?>((ref) {
  if (Platform.environment['FLUTTER_TEST'] == 'true') return null;
  final home = Platform.environment['HOME'] ?? '';
  return ManagedHooks(runBase: '$home/.promptorium/run');
});

/// Whether the hook script can run; null = the app's hooks are off (tests).
final pythonAvailableProvider = FutureProvider<bool?>(
  (ref) async =>
      ref.watch(managedHooksProvider) == null ? null : await pythonAvailable(),
);

/// Last thing each hook did in this app session (Automações screen).
class HookActivityLog extends Notifier<Map<ManagedHook, HookActivity>> {
  @override
  Map<ManagedHook, HookActivity> build() => const {};

  void add(HookActivity a) => state = {...state, a.hook: a};
}

final hookActivityProvider =
    NotifierProvider<HookActivityLog, Map<ManagedHook, HookActivity>>(
      HookActivityLog.new,
    );
