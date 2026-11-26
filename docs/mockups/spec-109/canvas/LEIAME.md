# Canvas da SPEC-109 (cópia arquivada)

Cópia dos arquivos do projeto do canvas do Claude Design, baixada em 21/11/2026 de
<https://claude.ai/artifact/6eD6puW5gbjEXZqqXRD3tA>.

O canvas sai do ar em **14/12/2026**. Esta pasta guarda a versão aprovada; os PNGs em
`docs/mockups/spec-109/` foram conferidos contra ela e mostram as mesmas telas.

## O que tem aqui

- `project/canvas.json`: título, posição, tamanho (1366×768) e ordem dos artboards.
- `project/*.dc.html`: um arquivo por artboard.
- `index.html`: a casca do tipo "Design" do claude.ai; não abre sozinha fora do artifact
  (os arquivos `artifact-type/*` do tipo não foram copiados).

| Arquivo | Artboard | PNG |
|---|---|---|
| `project/Main.dc.html` | 0 · Antes | `../0-antes.png` |
| `project/Executar.dc.html` | 1 · Executar com provedor por etapa | `../1-executar-plano.png` |
| `project/Regras.dc.html` | 2 · Regras, reservas e desvio | `../2-regras.png` |
| `project/Desvio.dc.html` | 3 · Desvio por cota na linha do tempo | `../3-desvio-cota.png` |
| `project/Estados.dc.html` | 4 · Estados e Histórico | `../4-estados.png` |

Neste canvas cada artboard é uma imagem PNG do asset store do artifact, referenciada no HTML como `/_blob/<id>`. As cópias estão em `_blob/<id>.png` (idênticas, byte a byte, aos PNGs em `docs/mockups/spec-109/`). Para ver um artboard, abra o PNG correspondente ou, numa cópia do HTML, troque `/_blob/<id>` por `../_blob/<id>.png`.

## Como abrir

Abra o `project/<artboard>.dc.html` direto no navegador (Chromium ou Firefox), com a janela em
1366×768. O HTML é estático: o `support.js` que ele referencia só existe dentro do artifact e
pode ser ignorado. As fontes (IBM Plex Sans e JetBrains Mono) vêm do Google Fonts; sem internet,
o texto cai na fonte padrão.
