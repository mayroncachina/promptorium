#!/usr/bin/env bash
# Remove o que scripts/install.sh criou. NUNCA remove os dados do usuário
# ($DATA/promptorium/promptorium.sqlite e demais arquivos fora de app/).
set -euo pipefail

DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="$DATA/promptorium/app"
BIN_LINK="$HOME/.local/bin/promptorium"
DESKTOP="$DATA/applications/promptorium.desktop"
ICONS_DIR="$DATA/icons/hicolor"
SIZES=(32 48 64 128 256 512)

# Link: só se for um link apontando para a nossa instalação.
if [[ -L "$BIN_LINK" && "$(readlink "$BIN_LINK")" == "$APP_DIR/promptorium" ]]; then
  rm -f -- "$BIN_LINK"
  echo "Removido: $BIN_LINK"
fi

# Atalho: só o que aponta para a nossa instalação.
if [[ -f "$DESKTOP" ]] && grep -qx "Exec=$APP_DIR/promptorium" "$DESKTOP"; then
  rm -f -- "$DESKTOP"
  echo "Removido: $DESKTOP"
fi

for n in "${SIZES[@]}"; do
  f="$ICONS_DIR/${n}x${n}/apps/promptorium.png"
  if [[ -f "$f" ]]; then
    rm -f -- "$f"
    echo "Removido: $f"
  fi
done

# Bundle: só a subpasta app/ (o banco fica em $DATA/promptorium/).
if [[ -d "$APP_DIR" ]]; then
  rm -rf -- "$APP_DIR"
  echo "Removido: $APP_DIR"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DATA/applications" 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1 && [[ -d "$ICONS_DIR" ]]; then
  gtk-update-icon-cache -f -t -q "$ICONS_DIR" || true
fi

echo "Promptorium desinstalado. Dados mantidos em $DATA/promptorium/."
