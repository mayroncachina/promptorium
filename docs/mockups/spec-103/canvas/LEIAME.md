# Canvas da SPEC-103 (cópia arquivada)

Cópia dos arquivos do projeto do canvas do Claude Design, baixada em 21/11/2026 de
<https://claude.ai/artifact/L8QfgVnHyijyB5Zfvuih4S>.

O canvas sai do ar em **14/12/2026**. Esta pasta guarda a versão aprovada; os PNGs em
`docs/mockups/spec-103/` foram conferidos contra ela e mostram as mesmas telas.

## O que tem aqui

- `project/canvas.json`: título, posição, tamanho (1366×768) e ordem dos artboards.
- `project/*.dc.html`: um arquivo por artboard.
- `index.html`: a casca do tipo "Design" do claude.ai; não abre sozinha fora do artifact
  (os arquivos `artifact-type/*` do tipo não foram copiados).

| Arquivo | Artboard | PNG |
|---|---|---|
| `project/Main.dc.html` | 0 · Antes · hooks só no Claude | `../0-antes.png` |
| `project/1-automacoes.dc.html` | 1 · Automações por provedor | `../1-automacoes.png` |
| `project/2-sessao-codex.dc.html` | 2 · Sessão Codex com hooks nativos | `../2-sessao-codex.png` |
| `project/3-pos-turno.dc.html` | 3 · Hooks só pós-turno | `../3-pos-turno.png` |

## Como abrir

Abra o `project/<artboard>.dc.html` direto no navegador (Chromium ou Firefox), com a janela em
1366×768. O HTML é estático: o `support.js` que ele referencia só existe dentro do artifact e
pode ser ignorado. As fontes (IBM Plex Sans e JetBrains Mono) vêm do Google Fonts; sem internet,
o texto cai na fonte padrão.
