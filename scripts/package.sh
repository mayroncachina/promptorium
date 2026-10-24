#!/usr/bin/env bash
# Empacota o bundle release do Linux em dist/:
#   dist/promptorium_<versão>_amd64.deb          instala em /opt/promptorium, com atalho e ícones
#   dist/promptorium-<versão>-linux-x64.tar.gz   bundle portátil (extrair e rodar)
#
#   flutter build linux --release [--build-name=<versão>]
#   scripts/package.sh 0.1.0
#
# O Claude Code não é pacote .deb (é instalado pelo instalador oficial ou npm),
# então o .deb declara só o que o apt resolve (git, GTK…) e avisa no
# pós-instalação quando o `claude` não está presente.
set -euo pipefail

VERSION="${1:?uso: scripts/package.sh <versão>  (ex.: 0.1.0)}"
VERSION="${VERSION#v}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.+~-][0-9A-Za-z.+~-]*)?$ ]]; then
  echo "Versão inválida: '$VERSION' (esperado 1.2.3)." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
OUT="$ROOT/dist"
NAME="promptorium"
ARCH="amd64"
SIZES=(32 48 64 128 256 512)

if [[ ! -x "$BUNDLE/$NAME" ]]; then
  echo "Bundle release não encontrado em $BUNDLE." >&2
  echo "Gere com: flutter build linux --release" >&2
  exit 1
fi
command -v dpkg-deb >/dev/null || { echo "dpkg-deb não encontrado." >&2; exit 1; }

mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT

# --- .deb -------------------------------------------------------------------
PKG="$WORK/deb"
mkdir -p "$PKG/DEBIAN" "$PKG/opt/$NAME" "$PKG/usr/bin" \
  "$PKG/usr/share/applications" "$PKG/usr/share/doc/$NAME"
cp -a "$BUNDLE/." "$PKG/opt/$NAME/"
ln -s "/opt/$NAME/$NAME" "$PKG/usr/bin/$NAME"
install -m 0644 "$ROOT/linux/$NAME.desktop" "$PKG/usr/share/applications/$NAME.desktop"
for n in "${SIZES[@]}"; do
  src="$ROOT/assets/icon/icon-$n.png"
  [[ -f "$src" ]] || continue
  mkdir -p "$PKG/usr/share/icons/hicolor/${n}x${n}/apps"
  install -m 0644 "$src" "$PKG/usr/share/icons/hicolor/${n}x${n}/apps/$NAME.png"
done
install -m 0644 "$ROOT/CHANGELOG.md" "$PKG/usr/share/doc/$NAME/changelog" 2>/dev/null || true
find "$PKG/opt" -type d -exec chmod 0755 {} +

SIZE_KB="$(du -sk "$PKG/opt" "$PKG/usr" | awk '{s+=$1} END {print s}')"
cat > "$PKG/DEBIAN/control" <<CONTROL
Package: $NAME
Version: $VERSION
Section: devel
Priority: optional
Architecture: $ARCH
Installed-Size: $SIZE_KB
Maintainer: Mayron Cachina <mayroncachina@users.noreply.github.com>
Homepage: https://github.com/mayroncachina/promptorium
Depends: libc6 (>= 2.35), libstdc++6, libgtk-3-0 (>= 3.22), libnotify4, libx11-6, libxi6, git
Recommends: gh
Description: IDE para o Claude Code CLI
 Gerencia sessões, specs, agentes, skills e servidores MCP do Claude Code,
 com Quadro de specs, Review de diffs e merge por worktree.
 .
 Requer o Claude Code CLI (comando "claude"), que não vem em pacote .deb:
 instale com "curl -fsSL https://claude.ai/install.sh | bash".
CONTROL

cat > "$PKG/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
  if ! command -v claude >/dev/null 2>&1 && ! ls /home/*/.local/bin/claude >/dev/null 2>&1; then
    echo "Promptorium: o Claude Code CLI (comando 'claude') não foi encontrado."
    echo "Instale, como o seu usuário (sem sudo):"
    echo "  curl -fsSL https://claude.ai/install.sh | bash"
  fi
fi
exit 0
POSTINST

cat > "$PKG/DEBIAN/postrm" <<'POSTRM'
#!/bin/sh
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
exit 0
POSTRM
chmod 0755 "$PKG/DEBIAN/postinst" "$PKG/DEBIAN/postrm"

DEB="$OUT/${NAME}_${VERSION}_${ARCH}.deb"
dpkg-deb --root-owner-group --build "$PKG" "$DEB" >/dev/null
echo "Deb:     $DEB"

# --- tar.gz portátil --------------------------------------------------------
TAR_DIR="$WORK/${NAME}-${VERSION}-linux-x64"
mkdir -p "$TAR_DIR"
cp -a "$BUNDLE/." "$TAR_DIR/"
cat > "$TAR_DIR/LEIA-ME.txt" <<README
Promptorium $VERSION (Linux x64)

Extraia em qualquer pasta e rode ./$NAME. Requer git e o Claude Code CLI:
  curl -fsSL https://claude.ai/install.sh | bash
Para atalho no menu e ícones, use o pacote .deb.
README
TAR="$OUT/${NAME}-${VERSION}-linux-x64.tar.gz"
tar -C "$WORK" -czf "$TAR" "$(basename "$TAR_DIR")"
echo "Tar.gz:  $TAR"
