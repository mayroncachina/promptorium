# Canvas da SPEC-104 (cópia arquivada)

Cópia dos arquivos do projeto do canvas do Claude Design, baixada em 21/11/2026 de
<https://claude.ai/artifact/P8aC6uzvr8FT7gsvMHp6GU>.

O canvas sai do ar em **14/12/2026**. Esta pasta guarda a versão aprovada; os PNGs em
`docs/mockups/spec-104/` foram conferidos contra ela e mostram as mesmas telas.

## O que tem aqui

- `project/canvas.json`: título, posição, tamanho (1366×768) e ordem dos artboards.
- `project/*.dc.html`: um arquivo por artboard.
- `index.html`: a casca do tipo "Design" do claude.ai; não abre sozinha fora do artifact
  (os arquivos `artifact-type/*` do tipo não foram copiados).

| Arquivo | Artboard | PNG |
|---|---|---|
| `project/Main.dc.html` | 1 · Instruções por provedor | `../1-instrucoes.png` |
| `project/Skills.dc.html` | 2 · Skills nos dois provedores | `../2-skills.png` |
| `project/PlanoB.dc.html` | 3 · Plano B: AGENTS.md gerado | `../3-plano-b.png` |

## Como abrir

Abra o `project/<artboard>.dc.html` direto no navegador (Chromium ou Firefox), com a janela em
1366×768. O HTML é estático: o `support.js` que ele referencia só existe dentro do artifact e
pode ser ignorado. As fontes (IBM Plex Sans e JetBrains Mono) vêm do Google Fonts; sem internet,
o texto cai na fonte padrão.
