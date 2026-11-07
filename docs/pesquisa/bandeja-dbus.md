# Bandeja por D-Bus (SPEC-041)

Sondagem de 06/11/2026 no Ubuntu com GNOME em X11, com `tray_manager` 0.8.0 e `nativeapi` 0.5.10. O app rodou com dados temporários (`XDG_DATA_HOME`) e estados forçados. A leitura foi feita com `gdbus call` no StatusNotifierItem e em `com.canonical.dbusmenu.GetLayout`.

| O que foi conferido | Resultado |
|---|---|
| Troca de ícone em tempo real | Funciona. `IconPixmap` muda e `NewIcon` é emitido. A barra mostrou os estados em captura de tela |
| Troca de tooltip | Funciona, com `NewToolTip` |
| Troca de menu com ele fechado | Funciona. A versão do layout sobe e `LayoutUpdated` é emitido |
| Item desabilitado | Funciona: `enabled` é `false` |
| Separador | Funciona: `type` é `separator` |
| Rótulo com `_` | Vai cru. Pelo protocolo do DBusMenu, o `_` marca um atalho, por isso o app envia `__` |
| Tamanho na barra | O painel do GNOME reduz o PNG de 24 px. O selo continua visível, mas pequeno |

**Não conferido:** KDE, atualização com o menu aberto, clique real em um item do menu e rótulo com `__` renderizado no painel.
