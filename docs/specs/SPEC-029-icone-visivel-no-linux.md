---
id: SPEC-029
status: rascunho
depende-de: SPEC-020
---

# Ícone visível nas barras do Linux

## Objetivo

No Linux, o ícone do Promptorium aparece como um quadrado preto na barra. Isso acontece no dock do Ubuntu e na barra superior, onde fica a bandeja (SPEC-020).

**O que já foi conferido (Ubuntu 24.04, GNOME Shell 46, X11):**

- A janela publica o ícone certo. `_NET_WM_ICON` tem 256×256, o mesmo `assets/icon/icon-256.png` que `linux/runner/my_application.cc:66` carrega.
- O atalho está associado à janela. `WM_CLASS` e `_GTK_APPLICATION_ID` são `dev.promptorium.promptorium`, iguais ao `StartupWMClass` de `promptorium.desktop`. Os PNGs estão em `~/.local/share/icons/hicolor/<N>x<N>/apps/promptorium.png`.
- **A causa é o desenho do ícone.** A arte é um quadrado de cantos arredondados quase preto (`#08090E`, luminância média de 30 em 255) que ocupa a imagem inteira. O frasco colorido ocupa só o centro.
  - No dock (32–48 px, fundo cinza-escuro translúcido) e na barra superior (16–24 px, fundo preto), o quadrado se confunde com o fundo. O frasco fica pequeno demais para ser visto, e o que se nota é um quadrado preto.
  - A bandeja usa a mesma arte, em `assets/icon/icon-64.png` (SPEC-020, Decisões: "sem variante monocromática nesta versão").
- Os tamanhos pequenos que os painéis pedem (16, 22 e 24 px) não existem. O sistema reduz o de 32 px, e o frasco perde ainda mais detalhe.
- A versão instalada em `~/.local/share/promptorium/app` é de 22/10, anterior à SPEC-020. Por isso ela ainda não mostra o ícone na bandeja.

Esta spec cria uma variante do ícone sem o quadrado escuro, para os tamanhos pequenos e para fundos escuros e claros, e passa a usá-la no dock, na bandeja e na janela.

Capturas em `docs/mockups/spec-029/` (1 a 3: o esboço gerado da arte atual; 4: a marca final, redesenhada em SVG):

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-bandeja-barra-superior.png` | Hoje e proposta em 16, 22, 24 e 32 px sobre o preto da barra superior | R1, R3 |
| `2-dock.png` | Hoje e proposta em 32, 36, 48 e 64 px sobre o dock | R1, R4 |
| `3-painel-claro.png` | Hoje e proposta sobre um painel claro (tema claro do Ubuntu, KDE) | R1 |
| `4-marca-final.png` | A marca final de 16 a 64 px sobre o preto da barra, o dock e um painel claro | R1, R2 |

## Requisitos

- R1 · O projeto deve ter uma variante do ícone, a "marca", que é o frasco sem o quadrado de fundo:
  - fundo transparente;
  - um contorno ou cor que a separe tanto de um fundo escuro (`#000000`, `#282828`) quanto de um claro (`#F6F6F6`), com contraste mínimo de 3:1 da forma principal contra os dois;
  - arquivos em `assets/icon/mark/mark-<N>.png` para N = 16, 22, 24, 32, 48, 64, 128, 256 e 512, mais o original vetorial `assets/icon/mark/mark.svg`.
- R2 · Nos tamanhos de 16 a 24 px, a marca deve ser desenhada para o tamanho, não só reduzida. Os detalhes finos (bolhas, o `>_` dentro do frasco) podem sair, desde que a silhueta do frasco continue reconhecível.
- R3 · A bandeja (`TrayService`, SPEC-020) deve usar a marca no lugar de `assets/icon/icon-64.png`, no tamanho que o painel pede, com 22 ou 24 px como base e 32 ou 48 px para telas com escala.
- R4 · Os ícones instalados no tema `hicolor` como `promptorium` devem usar a marca. Isso vale para `scripts/install.sh`, `scripts/package.sh` (.deb) e o manifesto Flatpak, que usa `dev.promptorium.promptorium`.
  - Os tamanhos instalados passam a incluir 16, 22 e 24 px.
  - O SVG vai em `hicolor/scalable/apps`.
  - O cache de ícones continua sendo atualizado depois da instalação (`gtk-update-icon-cache`).
- R5 · A janela deve publicar a marca em mais de um tamanho (`gtk_window_set_icon_list` com 32, 48, 64, 128 e 256 px), não só `icon-256.png`. Assim, o painel que lê `_NET_WM_ICON` também recebe a marca, mesmo sem achar o `.desktop`.
- R6 · Quando a marca não puder ser carregada, a janela e a bandeja devem voltar ao ícone atual (`icon-<N>.png`) e registrar um aviso no log, sem travar a inicialização (mesmo padrão da SPEC-020 R7).
- R7 · O ícone quadrado atual continua sendo usado onde não há fundo de painel: README, página do release e o ícone de 512 px da loja Flathub (se houver).

## Fora do escopo

- Redesenhar a marca do Promptorium (cores, frasco, nome).
- Ícones do macOS e do Windows.
- Ícone simbólico monocromático, que segue a cor do tema (ver Decisões, P3).
- Badge ou estado no ícone da bandeja.

## Design

### O que já existe

- `assets/icon/icon-{32,48,64,128,256,512}.png`: o quadrado escuro com o frasco.
- `linux/runner/my_application.cc:57-67`: `gtk_window_set_icon_from_file` com `data/flutter_assets/assets/icon/icon-256.png`, ao lado do executável.
- `lib/core/tray_service.dart` e `lib/core/tray_backend_native.dart`: a bandeja via `tray_manager` 0.8 (StatusNotifierItem). O ícone vai como `IconPixmap` (ARGB32), carregado de `ImageAsset.fromAsset('assets/icon/icon-64.png')`. A conversão em `cnativeapi-0.5.2/.../tray_icon_linux.cpp:211` respeita o canal alfa, então um PNG transparente chega transparente ao painel.
- `scripts/install.sh` (`SIZES=(32 48 64 128 256 512)`), `scripts/package.sh` (mesma lista, em `/usr/share/icons/hicolor`) e `linux/flatpak/dev.promptorium.promptorium.yml` (só 256 e 512 px).
- `linux/promptorium.desktop`: `Icon=promptorium`, `StartupWMClass=dev.promptorium.promptorium`.

### R1–R2 · Arte

- A marca parte do frasco da arte atual. O esboço em `docs/mockups/spec-029/` foi gerado automaticamente, removendo os pixels do fundo, e serve só para mostrar o efeito.
- A arte final é desenhada em SVG (P4). Os PNGs saem dela por um script, `scripts/icons.sh`, que usa `rsvg-convert`. Os tamanhos de 16 a 24 px têm um SVG próprio, simplificado (R2).

### R3 · Bandeja

- `TrayService.start()` passa a receber `assets/icon/mark/mark-24.png`. Se o backend não aceitar o asset, tenta `icon-64.png` e registra o aviso (R6).
- `pubspec.yaml`: `assets/icon/mark/` entra na lista de assets.

### R4 · Instalação

- `install.sh` e `package.sh`: `SIZES=(16 22 24 32 48 64 128 256 512)`, com a origem em `assets/icon/mark/mark-$n.png`, mais `mark.svg` em `scalable/apps/promptorium.svg`.
- Flatpak: os mesmos tamanhos, com o nome `dev.promptorium.promptorium`.
- `uninstall.sh` remove os novos tamanhos e o SVG.

### R5–R6 · Janela

- `my_application.cc`: monta uma `GList` de `GdkPixbuf` com `gdk_pixbuf_new_from_file` para cada `mark-<N>.png` e chama `gtk_window_set_icon_list`. Se nenhum carregar, volta ao `icon-256.png` com `g_warning`.

### Testes

- `test/assets/icon_mark_test.dart`: para cada N do R1, o arquivo existe, tem N×N, os quatro cantos são transparentes e a forma principal atinge 3:1 contra `#000000` e `#F6F6F6` (média dos pixels opacos).
- `test/core/tray_service_test.dart`: a bandeja recebe `mark-24.png`, e cai em `icon-64.png` quando a marca falha (R3, R6).
- `test/core/install_icons_test.dart`: roda `install.sh --icons-only` com `XDG_DATA_HOME` temporário; os tamanhos do R4 e o SVG são instalados, e `uninstall.sh` os remove.

## Critérios de aceite

- [ ] Os PNGs da marca existem nos tamanhos do R1, com fundo transparente e contraste de 3:1 em fundo escuro e claro [R1] verificar: flutter test test/assets/icon_mark_test.dart
- [ ] A marca de 16 a 24 px é reconhecível como frasco (verificação manual com as capturas de `docs/mockups/spec-029/`) [R2] verificar: manual (comparar a marca de 16, 22 e 24 px sobre preto e sobre #F6F6F6)
- [ ] A bandeja usa `mark-24.png` e volta a `icon-64.png` se a marca falhar [R3] [R6] verificar: flutter test test/core/tray_service_test.dart
- [ ] No Ubuntu, o ícone da bandeja na barra superior mostra o frasco, não um quadrado preto (verificação manual) [R3] verificar: manual (abrir o app instalado e olhar a barra superior)
- [ ] `install.sh` instala os tamanhos 16 a 512 e o SVG em `hicolor`, e atualiza o cache [R4] verificar: flutter test test/core/install_icons_test.dart
- [ ] No dock do Ubuntu, o ícone do Promptorium mostra o frasco, não um quadrado preto (verificação manual) [R4] verificar: manual (fixar o app no dock e comparar com 2-dock.png)
- [ ] A janela publica a marca em vários tamanhos em `_NET_WM_ICON` [R5] verificar: manual (xprop -id <janela> _NET_WM_ICON lista 32 a 256 px)
- [ ] README e release continuam com o ícone quadrado [R7] verificar: manual (README.md e o workflow de release apontam para icon-*.png)
- [ ] A análise estática passa sem avisos novos [R1] [R3] [R6] verificar: flutter analyze

## Decisões

- (P1) A spec cobre o dock e a barra superior (bandeja): a causa é a mesma.
- (P2) A marca sem fundo é usada em todos os tamanhos do Linux (16 a 512 px e o SVG), porque o dock e a grade de apps também têm fundo escuro. O quadrado fica só no README e no release (R7).
- (P3) Sem ícone simbólico monocromático nesta versão; a marca colorida com contorno escuro resolve e o simbólico fica para uma spec futura.
- (P4) A marca foi redesenhada em SVG a partir do frasco (`assets/icon/mark/mark.svg`), com um desenho próprio para 16–24 px (`mark-small.svg`: só a silhueta do frasco e o líquido, sem molécula, bolhas nem `>_`).
- Contraste (R1): contorno âmbar `#F5A23A` com um contorno externo escuro `#14100A`. A média dos pixels opacos fica entre 4,2:1 e 4,4:1 contra `#000000` e entre 4,4:1 e 4,7:1 contra `#F6F6F6` em todos os tamanhos.
- `scripts/icons.sh` usa `rsvg-convert` quando existe e cai no Inkscape senão; os PNGs desta branch foram gerados com o Inkscape (não havia `rsvg-convert` na máquina).
- Bandeja (R3, R6): o backend lança `TrayIconUnavailable` quando o asset não carrega. Só nesse caso o `TrayService` tenta `icon-64.png` com um backend novo e registra "marca indisponível"; outras falhas (sem D-Bus etc.) continuam como na SPEC-020 R7. A bandeja usa só `mark-24.png`: o `tray_manager` aceita uma imagem só, e o painel a escala em telas com escala.
- Instalação (R4): `install.sh --icons-only` instala só os ícones e atualiza o cache, sem exigir o bundle; é o que o teste (`test/core/install_icons_test.dart`, com `XDG_DATA_HOME` temporário) usa. O critério de aceite do R4 passou a usar esse teste, porque `install.sh` sem argumentos exige o bundle release.
- Flatpak: a pasta `assets/icon/mark` entra como fonte `dir`, e um laço instala os 9 tamanhos e o SVG como `dev.promptorium.promptorium`.
- `mark-small.svg` também entra no bundle (a pasta `assets/icon/mark/` é declarada inteira no `pubspec.yaml`); são poucos bytes.
