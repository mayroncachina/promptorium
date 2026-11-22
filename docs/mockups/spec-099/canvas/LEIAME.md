# Canvas da SPEC-099 (cópia arquivada)

Cópia dos arquivos do projeto do canvas do Claude Design, baixada em 21/11/2026 de
<https://claude.ai/artifact/WKLCUqNSE1tVP6ReenDK2Z>.

O canvas sai do ar em **14/12/2026**. Esta pasta guarda a versão aprovada; os PNGs em
`docs/mockups/spec-099/` foram conferidos contra ela e mostram as mesmas telas.

## O que tem aqui

- `project/canvas.json`: título, posição, tamanho (1366×768) e ordem dos artboards.
- `project/*.dc.html`: um arquivo por artboard.
- `index.html`: a casca do tipo "Design" do claude.ai; não abre sozinha fora do artifact
  (os arquivos `artifact-type/*` do tipo não foram copiados).

| Arquivo | Artboard | PNG |
|---|---|---|
| `project/Main.dc.html` | Sessão com a cota esgotada | `../1-sessao-cota-esgotada.png` |
| `project/2-dialogo-passagem.dc.html` | Diálogo Continuar no Codex | `../2-dialogo-passagem.png` |
| `project/3-sessao-continuada.dc.html` | Sessão continuada no Codex | `../3-sessao-continuada.png` |
| `project/4-sem-ai-memory-e-estados.dc.html` | Sem ai-memory e estados | `../4-sem-ai-memory-e-estados.png` |

## Como abrir

Abra o `project/<artboard>.dc.html` direto no navegador (Chromium ou Firefox), com a janela em
1366×768. O HTML é estático: o `support.js` que ele referencia só existe dentro do artifact e
pode ser ignorado. As fontes (IBM Plex Sans e JetBrains Mono) vêm do Google Fonts; sem internet,
o texto cai na fonte padrão.
