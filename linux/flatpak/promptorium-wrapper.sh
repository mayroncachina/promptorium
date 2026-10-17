#!/bin/sh
# Dentro do sandbox, os programas do host (claude, git, gh, rg, bash) são
# chamados por flatpak-spawn --host: um diretório com atalhos vai à frente
# do PATH.
SHIMS="${XDG_RUNTIME_DIR:-/tmp}/promptorium-host-bin"
mkdir -p "$SHIMS"
for cmd in claude git gh rg bash setsid python3 xdg-open kill chmod; do
  printf '#!/bin/sh\nexec flatpak-spawn --host --watch-bus %s "$@"\n' "$cmd" > "$SHIMS/$cmd"
  chmod +x "$SHIMS/$cmd"
done
export PATH="$SHIMS:$PATH"
exec /app/lib/promptorium/promptorium "$@"
