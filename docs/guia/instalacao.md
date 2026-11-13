# Instalação

O Promptorium roda no **Linux x64** (Ubuntu/Debian 22.04 ou mais novo). Ele precisa do **Claude Code CLI**, instalado à parte, e do `git`. O `gh` (GitHub CLI) é opcional e habilita PRs no Review.

## Requisito mínimo

| | Mínimo | Recomendado |
|---|---|---|
| Sistema | Linux x64, Ubuntu/Debian 22.04 ou mais novo | o mesmo |
| Vídeo | qualquer placa com driver OpenGL funcionando; sem placa, o Mesa desenha por software (llvmpipe) | placa integrada recente, como Intel Iris Xe, ou uma dedicada |
| Processador | 2 núcleos | 4 núcleos ou mais |
| Memória | 4 GB | 8 GB ou mais |
| Tela | janela de 1100×700 | 1440×900 ou maior |

O app ocupa cerca de 320 MB de memória (pico de 400 MB). Cada sessão aberta é um processo do Claude Code CLI, com 200 a 500 MB, e por isso a memória recomendada cresce com o número de sessões em paralelo (o padrão é até 12).

### Tema Vidro e desempenho

O tema Vidro desenha o fundo uma vez numa imagem e só desfoca atrás de diálogos. Medido com `scripts/medir_quadros.py` (percorre as 10 telas, com rolagem, paleta e atalhos), janela de 1440×900, build `--profile`. Os números são o p90 do tempo de raster de cada quadro; 16,7 ms é o limite para 60 quadros por segundo.

| Máquina | Visual opaco | Vidro | Vidro desligado |
|---|---|---|---|
| Intel Iris Xe (Raptor Lake) | 14,2 ms | 15,6 ms | — |
| Sem placa (llvmpipe), 2 núcleos de desempenho | 9,7 ms | 12,1 ms | 10,2 ms |
| Sem placa (llvmpipe), 12 núcleos híbridos | 44 ms | 55 ms | — |

Com placa de vídeo, o Vidro custa cerca de 1,5 ms por quadro e fica bem abaixo do limite. Sem placa, ele custa de 2 a 11 ms, conforme o processador. No caso dos 12 núcleos híbridos, a renderização por software espera os núcleos de eficiência e o app fica perto de 20 quadros por segundo com ou sem Vidro.

Desligue os efeitos em **Configurações › Aparência › Efeitos de vidro** (ou com `PROMPTORIUM_SEM_VIDRO=1`) quando:

- o desktop não tem aceleração gráfica (máquina virtual, sessão remota, driver de vídeo ausente);
- a rolagem ou os diálogos engasgam;
- a bateria importa mais que o visual.

Para medir a sua máquina, gere um build `--profile` e rode `scripts/medir_quadros.py percorrer saida.jsonl` (veja [Desenvolvimento](desenvolvimento.md)).

## Claude Code CLI

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

O app procura o `claude` no `PATH` e em `~/.local/bin/claude`. Sem ele, a splash mostra esta mesma instrução.

## Pacotes da release

Nas [Releases do GitHub](https://github.com/mayroncachina/promptorium/releases):

| Arquivo | Uso |
|---|---|
| `promptorium_<versão>_amd64.deb` | `sudo apt install ./promptorium_<versão>_amd64.deb`. Instala em `/opt/promptorium`, com o comando `promptorium`, atalho no menu e ícones. O apt instala o `git` e as bibliotecas (GTK, libnotify, X11); o `gh` é recomendado. |
| `promptorium-<versão>-linux-x64.tar.gz` | Portátil: extrair e rodar `./promptorium`, sem atalho no menu. |

## A partir do código

```bash
flutter build linux --release     # bundle em build/linux/x64/release/bundle
scripts/install.sh                # ou: scripts/install.sh --build
```

`scripts/install.sh` (sem sudo, pode ser rodado de novo) instala:

| O quê | Onde |
|---|---|
| Bundle | `~/.local/share/promptorium/app/` |
| Comando | `~/.local/bin/promptorium` |
| Atalho do menu | `~/.local/share/applications/promptorium.desktop` |
| Ícones | `~/.local/share/icons/hicolor/<N>x<N>/apps/promptorium.png` |

`scripts/uninstall.sh` remove só o que o install criou.

## Flatpak

Há um manifesto em `linux/flatpak/`, ainda não testado. Ver [flatpak.md](../flatpak.md).

## Atualizações

O app verifica uma vez por dia se há release nova e avisa. "Atualizar agora" (no cartão do Sobre, F1) baixa o pacote de github.com, confere o `.sha256` quando existe, instala e reinicia:

- cópia instalada pelo `.deb` em `/opt/promptorium`: instala o `.deb` com `pkexec`;
- outras cópias (`.tar.gz`, `install.sh`): extrai o `.tar.gz` por cima delas.

## Seus dados

O banco (`~/.local/share/promptorium/promptorium.sqlite`) fica fora da pasta do app. Instalar, atualizar ou remover o app não o apaga. Antes de cada migração do banco é feito um backup `.bak-v<N>`, que pode ser restaurado em Configurações › Banco e backups.

## Ícone na bandeja

O ícone usa o protocolo StatusNotifierItem (D-Bus). No GNOME, é preciso a extensão AppIndicator; sem bandeja, o app funciona normalmente, sem o ícone.
