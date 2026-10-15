#!/usr/bin/env bash
# Instala o Promptorium para o usuário atual (sem sudo).
#
#   scripts/install.sh            # usa o bundle release já gerado
#   scripts/install.sh --build    # roda `flutter build linux --release` antes
#
# O que é criado (e removido por scripts/uninstall.sh):
#   $DATA/promptorium/app/                       bundle release (binário + data/ + lib/)
#   ~/.local/bin/promptorium                     link para o binário
#   $DATA/applications/promptorium.desktop       atalho (Exec com caminho absoluto)
#   $DATA/icons/hicolor/<N>x<N>/apps/promptorium.png
#
# $DATA = ${XDG_DATA_HOME:-~/.local/share}. O banco do usuário
# ($DATA/promptorium/promptorium.sqlite) fica na pasta-mãe de app/ e NUNCA é
# tocado. Idempotente: rodar de novo substitui só o que está listado acima.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="$DATA/promptorium/app"
BIN_DIR="$HOME/.local/bin"
APPS_DIR="$DATA/applications"
ICONS_DIR="$DATA/icons/hicolor"
SIZES=(32 48 64 128 256 512)

if [[ "${1:-}" == "--build" ]]; then
  (cd "$ROOT" && flutter build linux --release)
fi

if [[ ! -x "$BUNDLE/promptorium" ]]; then
  echo "Bundle release não encontrado em $BUNDLE." >&2
  echo "Gere com: flutter build linux --release  (ou: $0 --build)" >&2
  exit 1
fi

# 1. Bundle → $DATA/promptorium/app (cópia em pasta temporária + troca, para
#    não deixar uma instalação pela metade). Só a subpasta app/ é substituída.
mkdir -p "$DATA/promptorium"
STAGE="$(mktemp -d "$DATA/promptorium/.app-install.XXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
cp -a "$BUNDLE/." "$STAGE/"
if [[ -d "$APP_DIR" ]]; then
  rm -rf -- "$APP_DIR"
fi
mv -- "$STAGE" "$APP_DIR"
trap - EXIT
echo "Bundle:   $APP_DIR"

# 2. Link no PATH do usuário.
mkdir -p "$BIN_DIR"
if [[ -e "$BIN_DIR/promptorium" && ! -L "$BIN_DIR/promptorium" ]]; then
  echo "Aviso: $BIN_DIR/promptorium existe e não é um link; não foi alterado." >&2
else
  ln -sfn "$APP_DIR/promptorium" "$BIN_DIR/promptorium"
  echo "Link:     $BIN_DIR/promptorium → $APP_DIR/promptorium"
fi

# 3. Ícones hicolor.
for n in "${SIZES[@]}"; do
  src="$ROOT/assets/icon/icon-$n.png"
  [[ -f "$src" ]] || continue
  dst="$ICONS_DIR/${n}x${n}/apps"
  mkdir -p "$dst"
  install -m 0644 "$src" "$dst/promptorium.png"
done
echo "Ícones:   $ICONS_DIR/<N>x<N>/apps/promptorium.png (N = ${SIZES[*]})"

# 4. Atalho .desktop com o caminho absoluto do binário.
mkdir -p "$APPS_DIR"
sed -e "s|^Exec=.*|Exec=$APP_DIR/promptorium|" \
    "$ROOT/linux/promptorium.desktop" > "$APPS_DIR/promptorium.desktop"
chmod 0644 "$APPS_DIR/promptorium.desktop"
echo "Atalho:   $APPS_DIR/promptorium.desktop"

# 5. Caches (se existirem; sem sudo).
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS_DIR" || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  # -t: ~/.local/share/icons/hicolor normalmente não tem index.theme.
  gtk-update-icon-cache -f -t -q "$ICONS_DIR" || true
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "Obs.: $BIN_DIR não está no PATH; o atalho do menu funciona mesmo assim." ;;
esac
echo "Promptorium instalado."
