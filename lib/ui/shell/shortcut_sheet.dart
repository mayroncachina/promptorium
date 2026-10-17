import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// One line of the shortcut sheet.
class ShortcutEntry {
  const ShortcutEntry(this.label, this.keys);

  final String label;

  /// `Ctrl+K`, `Ctrl+= · Ctrl+-`.
  final String keys;
}

class ShortcutGroup {
  const ShortcutGroup(this.title, this.entries);

  final String title;
  final List<ShortcutEntry> entries;
}

/// Every shortcut the app answers to, by area (UX v2, U2;
/// docs/mockups/v2/Atalhos.dc.html). Keep in sync with `shell_intents.dart`
/// and the `CallbackShortcuts` of each screen.
const shortcutGroups = [
  ShortcutGroup('Navegação', [
    ShortcutEntry('Início · Projeto · Specs · Quadro · Sessões', 'Ctrl+1 … 5'),
    ShortcutEntry('Review · Código · Prompt · Ferramentas', 'Ctrl+6 … 9'),
    ShortcutEntry('Paleta de comandos', 'Ctrl+K'),
    ShortcutEntry('Ir para arquivo (Código)', 'Ctrl+P'),
    ShortcutEntry('Busca global no worktree (Código)', 'Ctrl+Shift+F'),
    ShortcutEntry('Esta folha', 'Ctrl+/'),
  ]),
  ShortcutGroup('Para você e aprovações', [
    ShortcutEntry('Aprovar a pendência mais antiga', 'Ctrl+Shift+A'),
    ShortcutEntry('Negar a pendência mais antiga', 'Ctrl+Shift+D'),
    ShortcutEntry('Pendências na paleta', 'Ctrl+K, >'),
  ]),
  ShortcutGroup('Sessões e Prompt', [
    ShortcutEntry('Nova sessão', 'Ctrl+N'),
    ShortcutEntry('Enviar mensagem', 'Ctrl+Enter'),
    ShortcutEntry('Sessões lado a lado (abre / fecha o painel B)', 'Ctrl+\\'),
    ShortcutEntry('Mencionar arquivo · prompt salvo (Prompt)', '@ · /'),
  ]),
  ShortcutGroup('Paleta', [
    ShortcutEntry('Só ações e pendências', '>'),
    ShortcutEntry('Só specs', '#'),
    ShortcutEntry('Só sessões', ':'),
    ShortcutEntry('Navegar · executar', '↑↓ · Enter'),
  ]),
  ShortcutGroup('Editor (Specs e Código)', [
    ShortcutEntry('Salvar', 'Ctrl+S'),
    ShortcutEntry('Fechar aba (Código)', 'Ctrl+W'),
    ShortcutEntry('Buscar · Substituir', 'Ctrl+F · Ctrl+H'),
    ShortcutEntry('Zoom + / − / 100%', 'Ctrl+= · Ctrl+- · Ctrl+0'),
  ]),
];

/// Groups whose label or keys contain [query] (case-insensitive); empty
/// query = everything.
List<ShortcutGroup> filterShortcuts(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return shortcutGroups;
  return [
    for (final g in shortcutGroups)
      if (g.entries.any((e) => _matches(e, q)))
        ShortcutGroup(g.title, [
          for (final e in g.entries)
            if (_matches(e, q)) e,
        ]),
  ];
}

bool _matches(ShortcutEntry e, String q) =>
    e.label.toLowerCase().contains(q) || e.keys.toLowerCase().contains(q);

/// Folha de atalhos (Ctrl+/).
Future<void> showShortcutSheet(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => const ShortcutSheet(),
);

class ShortcutSheet extends StatefulWidget {
  const ShortcutSheet({super.key});

  @override
  State<ShortcutSheet> createState() => _ShortcutSheetState();
}

class _ShortcutSheetState extends State<ShortcutSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = filterShortcuts(_query.text);
    // The dialog route is outside AppShell's shortcuts: Ctrl+/ closes here.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.slash, control: true): () =>
            Navigator.of(context).maybePop(),
      },
      child: Dialog(
        key: const ValueKey('shortcut-sheet'),
        backgroundColor: AppColors.panel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: SessionColors.selectedBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                child: Row(
                  children: [
                    const Text(
                      'Atalhos de teclado',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Ctrl+/ abre e fecha',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      height: 30,
                      child: TextField(
                        key: const ValueKey('shortcut-sheet-filter'),
                        controller: _query,
                        autofocus: true,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Filtrar…',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Fechar',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: groups.isEmpty
                      ? const Text(
                          'Nenhum atalho com esse texto.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        )
                      : Wrap(
                          spacing: 28,
                          runSpacing: 20,
                          children: [
                            for (final g in groups)
                              SizedBox(width: 290, child: _group(g)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _group(ShortcutGroup g) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        g.title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 8),
      for (final e in g.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  e.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(4),
                    border: const Border(
                      top: BorderSide(color: SessionColors.selectedBorder),
                      left: BorderSide(color: SessionColors.selectedBorder),
                      right: BorderSide(color: SessionColors.selectedBorder),
                      bottom: BorderSide(
                        color: SessionColors.selectedBorder,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    e.keys,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
