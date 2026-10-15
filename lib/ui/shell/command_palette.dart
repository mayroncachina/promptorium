import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import 'navigation.dart';

/// A command shown in the palette.
class PaletteCommand {
  const PaletteCommand({required this.label, required this.run, this.shortcut});

  final String label;
  final String? shortcut;
  final VoidCallback run;
}

/// Stub command palette (Ctrl+K): filters a static list of commands.
/// TODO(Fase 5+): file search, sessions, specs, tasks.
Future<void> showCommandPalette(
  BuildContext context, {
  required void Function(AppSection) onNavigate,
}) {
  final commands = [
    for (final (i, s) in AppSection.values.indexed)
      PaletteCommand(
        label: 'Ir para ${s.label}',
        shortcut: i < AppSection.navItems.length ? 'Ctrl ${i + 1}' : null,
        run: () => onNavigate(s),
      ),
  ];
  return showDialog<void>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (context) => CommandPalette(commands: commands),
  );
}

class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key, required this.commands});

  final List<PaletteCommand> commands;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _query = TextEditingController();
  int _selected = 0;

  List<PaletteCommand> get _filtered {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return widget.commands;
    return widget.commands
        .where((c) => c.label.toLowerCase().contains(q))
        .toList();
  }

  void _run(PaletteCommand c) {
    Navigator.of(context).pop();
    c.run();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    if (_selected >= items.length) {
      _selected = items.isEmpty ? 0 : items.length - 1;
    }
    return Align(
      alignment: const Alignment(0, -0.6),
      child: Material(
        color: AppColors.panel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 520,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  setState(() {
                    if (items.isNotEmpty) {
                      _selected = (_selected + 1) % items.length;
                    }
                  }),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  setState(() {
                    if (items.isNotEmpty) {
                      _selected = (_selected - 1 + items.length) % items.length;
                    }
                  }),
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      AppIcon(
                        AppIcons.search,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _query,
                          autofocus: true,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.text,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Buscar ou executar comando…',
                            hintStyle: TextStyle(
                              color: AppColors.textSecondary,
                            ),
                            border: InputBorder.none,
                          ),
                          onChanged: (_) => setState(() => _selected = 0),
                          onSubmitted: (_) {
                            if (items.isNotEmpty) _run(items[_selected]);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: items.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Nenhum comando encontrado',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            final c = items[i];
                            final sel = i == _selected;
                            return InkWell(
                              onTap: () => _run(c),
                              child: Container(
                                height: 32,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? AppColors.amberTint
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        c.label,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: sel
                                              ? AppColors.amber
                                              : AppColors.text,
                                        ),
                                      ),
                                    ),
                                    if (c.shortcut != null)
                                      Text(
                                        c.shortcut!,
                                        style: const TextStyle(
                                          fontFamily: AppFonts.mono,
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
