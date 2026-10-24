# Flatpak

Manifesto em [`linux/flatpak/dev.promptorium.promptorium.yml`](../linux/flatpak/dev.promptorium.promptorium.yml).
Ele empacota o bundle compilado pelo Flutter, sem recompilar dentro do SDK do Flatpak.

```bash
flutter build linux --release
flatpak install --user flathub org.freedesktop.Platform//24.08 org.freedesktop.Sdk//24.08
flatpak-builder --user --install --force-clean build-flatpak \
  linux/flatpak/dev.promptorium.promptorium.yml
flatpak run dev.promptorium.promptorium
```

## Como o app chega às ferramentas do host

O Promptorium roda `claude`, `git`, `gh`, `rg`, `bash` e os comandos do projeto (`testes:`, `lint:`,
`preparar:`…). Essas ferramentas não existem no runtime do Flatpak. Por isso o
[`promptorium-wrapper.sh`](../linux/flatpak/promptorium-wrapper.sh) cria atalhos que chamam cada uma com
`flatpak-spawn --host` e põe esses atalhos à frente do `PATH`. Isso exige
`--talk-name=org.freedesktop.Flatpak`, e o app tem acesso à home (`--filesystem=home`), porque precisa
dos repositórios, dos worktrees em `~/.promptorium` e do `~/.claude`.

## Ícone na bandeja (SPEC-020)

O `tray_manager` 0.8 publica o ícone como StatusNotifierItem direto pelo D-Bus (biblioteca
`libcnativeapi.so` do bundle, ligada a GTK 3, X11 e Xi, que já estão no `org.freedesktop.Platform`);
não usa `libayatana-appindicator3`, então o runtime não precisa de módulo extra. Basta
`--talk-name=org.kde.StatusNotifierWatcher`, que o manifesto já tem. Sem bandeja (GNOME sem a
extensão AppIndicator), o app só registra o aviso e segue sem ícone.

## Estado

O manifesto e o wrapper foram escritos, mas **não foram testados**: esta máquina não tem
`flatpak-builder`. O banco fica no diretório de dados do sandbox
(`~/.var/app/dev.promptorium.promptorium/data/promptorium`), e não em `~/.local/share/promptorium`.
