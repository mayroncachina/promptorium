#!/usr/bin/env bash
# Hook Stop: o turno só termina com `flutter analyze` e `flutter test` verdes.
# Pula quando o conteúdo de lib/, test/ e pubspec.yaml é igual ao de uma das
# últimas rodadas verdes: commits só de docs, troca de branch ou pull que não
# mexem no código não rodam a suíte de novo. Depois de 3 bloqueios seguidos,
# libera com um aviso.
# Não roda em worktrees e espera outro `flutter test` em andamento acabar.
set -u
cat >/dev/null # entrada do hook (não usada)
root=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0
# Worktree (sessão aberta pelo Promptorium): o gate do app já verifica.
[ "$(git rev-parse --absolute-git-dir)" = "$(git rev-parse --path-format=absolute --git-common-dir)" ] || exit 0
state=.dart_tool/claude-stop-hook
mkdir -p "$state"

# Impressão do conteúdo, não do commit: as árvores de lib/ e test/ e o blob do
# pubspec.yaml no HEAD, mais o que mudou no diretório de trabalho.
fp=$({
  git rev-parse HEAD:lib HEAD:test HEAD:pubspec.yaml 2>/dev/null
  git diff HEAD -- lib test pubspec.yaml
  git ls-files -o --exclude-standard -- lib test | xargs -r -d '\n' sha1sum
} | sha1sum | cut -d' ' -f1)

# Últimas impressões verdes (até 50), uma por linha.
greens="$state/greens"
if grep -qxF "$fp" "$greens" 2>/dev/null; then
  rm -f "$state/tries"
  exit 0
fi

tries=$(cat "$state/tries" 2>/dev/null || echo 0)
if [ "$tries" -ge 3 ]; then
  rm -f "$state/tries"
  jq -n '{systemMessage: "Hook Stop: análise ou testes ainda vermelhos depois de 3 tentativas; turno liberado."}'
  exit 0
fi

# Outro `flutter test` rodando (o gate do app, outra sessão): espera ele
# acabar, até 4 min, para as duas suítes não disputarem a CPU e falharem
# por tempo.
for _ in $(seq 120); do
  pgrep -f 'flutter_tools\.snapshot test' >/dev/null || break
  sleep 2
done

log=$(mktemp)
trap 'rm -f "$log"' EXIT
if ! flutter analyze >"$log" 2>&1; then
  step="flutter analyze"
elif ! flutter test --reporter failures-only >"$log" 2>&1; then
  step="flutter test"
else
  { grep -vxF "$fp" "$greens" 2>/dev/null; echo "$fp"; } | tail -n 50 >"$greens.tmp"
  mv "$greens.tmp" "$greens"
  rm -f "$state/tries"
  exit 0
fi

echo $((tries + 1)) >"$state/tries"
jq -n --arg step "$step" --arg n "$((tries + 1))" --arg out "$(grep -v -e '^\s*$' -e 'observação do repositório indisponível' "$log" | tail -n 150)" '{
  decision: "block",
  reason: ("`" + $step + "` falhou (bloqueio " + $n + " de 3). Corrija antes de encerrar o turno. Fim da saída:\n" + $out)
}'
exit 0
