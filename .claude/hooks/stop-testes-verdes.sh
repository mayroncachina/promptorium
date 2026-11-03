#!/usr/bin/env bash
# Hook Stop: o turno só termina com `flutter analyze` e `flutter test` verdes.
# Pula quando o código (HEAD + diff de lib/, test/ e pubspec.yaml) é o mesmo
# da última rodada verde; depois de 3 bloqueios seguidos, libera com um aviso.
# Não roda em worktrees e espera outro `flutter test` em andamento acabar.
set -u
cat >/dev/null # entrada do hook (não usada)
root=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0
# Worktree (sessão aberta pelo Promptorium): o gate do app já verifica.
[ "$(git rev-parse --absolute-git-dir)" = "$(git rev-parse --path-format=absolute --git-common-dir)" ] || exit 0
state=.dart_tool/claude-stop-hook
mkdir -p "$state"

fp=$({
  git rev-parse HEAD
  git diff HEAD -- lib test pubspec.yaml
  git ls-files -o --exclude-standard -- lib test | xargs -r -d '\n' sha1sum
} | sha1sum | cut -d' ' -f1)

if [ "$(cat "$state/green" 2>/dev/null)" = "$fp" ]; then
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
  echo "$fp" >"$state/green"
  rm -f "$state/tries"
  exit 0
fi

echo $((tries + 1)) >"$state/tries"
jq -n --arg step "$step" --arg n "$((tries + 1))" --arg out "$(grep -v -e '^\s*$' -e 'observação do repositório indisponível' "$log" | tail -n 150)" '{
  decision: "block",
  reason: ("`" + $step + "` falhou (bloqueio " + $n + " de 3). Corrija antes de encerrar o turno. Fim da saída:\n" + $out)
}'
exit 0
