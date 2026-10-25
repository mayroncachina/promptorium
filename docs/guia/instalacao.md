# Instalação

O Promptorium roda no **Linux x64** (Ubuntu/Debian 22.04 ou mais novo). Ele precisa do **Claude Code CLI**, instalado à parte, e do `git`. O `gh` (GitHub CLI) é opcional e habilita PRs no Review.

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

O app verifica uma vez por dia se há release nova e avisa. "Atualizar agora" (no Sobre, F1) baixa o pacote de github.com, confere o `.sha256` quando existe, instala e reinicia:

- cópia instalada pelo `.deb` em `/opt/promptorium`: instala o `.deb` com `pkexec`;
- outras cópias (`.tar.gz`, `install.sh`): extrai o `.tar.gz` por cima delas.

## Seus dados

O banco (`~/.local/share/promptorium/promptorium.sqlite`) fica fora da pasta do app. Instalar, atualizar ou remover o app não o apaga. Antes de cada migração do banco é feito um backup `.bak-v<N>`, que pode ser restaurado em Configurações › Banco e backups.

## Ícone na bandeja

O ícone usa o protocolo StatusNotifierItem (D-Bus). No GNOME, é preciso a extensão AppIndicator; sem bandeja, o app funciona normalmente, sem o ícone.
