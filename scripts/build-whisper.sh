#!/usr/bin/env bash
# Compila o whisper-cli (SPEC-040 R8) e copia o binário para <destino>.
#   scripts/build-whisper.sh <destino>
# A versão é fixa. O binário é estático em relação ao whisper e ao ggml e
# precisa só do libgomp1 (declarado no .deb). GGML_NATIVE=OFF evita instruções
# da máquina de build, que não rodariam em outro computador.
set -euo pipefail

VERSION="v1.9.5"
DEST="${1:?uso: scripts/build-whisper.sh <destino>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${WHISPER_BUILD_DIR:-$ROOT/build/whisper.cpp-$VERSION}"

command -v cmake >/dev/null || { echo "cmake não encontrado." >&2; exit 1; }
if [[ ! -d "$SRC/.git" ]]; then
  git clone -q --depth 1 --branch "$VERSION" \
    https://github.com/ggml-org/whisper.cpp.git "$SRC"
fi
cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=OFF -DGGML_AVX=ON -DGGML_AVX2=ON \
  -DGGML_FMA=ON -DGGML_F16C=ON -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF >/dev/null
cmake --build "$SRC/build" --target whisper-cli -j"$(nproc)" >/dev/null
mkdir -p "$DEST"
install -m 0755 "$SRC/build/bin/whisper-cli" "$DEST/whisper-cli"
strip "$DEST/whisper-cli" 2>/dev/null || true
echo "whisper-cli $VERSION em $DEST"
