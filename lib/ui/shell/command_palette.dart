import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../features/board/autopilot.dart';
import '../../features/board/board_rules.dart';
import '../../features/board/spec_runner.dart';
import '../../features/code/worktree_files.dart' show fuzzyScore;
import '../../features/sessions/new_session_dialog.dart';
import '../../features/sessions/session_manager.dart';
import '../../features/specs/new_spec_dialog.dart';
import '../../features/specs/spec_service.dart' show selectedSpecProvider;

import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import 'navigation.dart';

/// A command shown in the palette.
class PaletteCommand {
  const PaletteCommand({
    required this.label,
    required this.run,
    this.shortcut,
    this.group = 'Telas',
  });

  final String label;
  final String? shortcut;

  /// `Telas`, `Ações`, `Specs`, `Sessões` (shown on the right).
  final String group;
  final VoidCallback run;
}

/// Commands of the palette, best match first ([fuzzyScore], the same
/// search as "Ir para arquivo"). Empty query = the list as given.
List<PaletteCommand> filterCommands(List<PaletteCommand> all, String query) {
  if (query.trim().isEmpty) return all;
  final scored = <(PaletteCommand, int)>[];
  for (final c in all) {
    final s = fuzzyScore(c.label, query);
    if (s != null) scored.add((c, s));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final (c, _) in scored) c];
}

/// Everything Ctrl+K reaches (F10): screens, actions (pending approval,
/// autopilot, new session / spec), the specs of the workspace (open, run)
/// and its sessions.
List<PaletteCommand> paletteCommands(
  BuildContext context,
  WidgetRef ref, {
  required void Function(AppSection) onNavigate,
}) {
  final ws = ref.read(activeWorkspaceProvider);
  final specs = ws == null
      ? const <Spec>[]
      : ref.read(specsProvider(ws.id)).value ?? const <Spec>[];
  final sessions = ws == null
      ? const <Session>[]
      : ref.read(sessionsProvider(ws.id)).value ?? const <Session>[];
  final manager = ref.read(sessionManagerProvider.notifier);
  final approvals = ref.read(sessionManagerProvider).approvals;
  final messenger = ScaffoldMessenger.maybeOf(context);
  void toast(String msg) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
  final byCode = specsByCode(specs);
  return [
    for (final s in [
      ...AppSection.navItems,
      AppSection.skills,
      AppSection.mcp,
      AppSection.settings,
    ])
      PaletteCommand(
        label: 'Ir para ${s == AppSection.agents ? 'Agentes' : s.label}',
        shortcut: s.shortcutLabel,
        run: () => onNavigate(s),
      ),
    if (approvals.isNotEmpty)
      PaletteCommand(
        label:
            'Aprovar pendente: ${approvals.first.request.displayName ?? approvals.first.request.toolName} '
            '(${approvals.first.sessionTitle})',
        group: 'Ações',
        run: () => manager.approve(
          approvals.first.sessionId,
          approvals.first.requestId,
        ),
      ),
    if (ws != null)
      ref.read(autopilotProvider).contains(ws.id)
          ? PaletteCommand(
              label: 'Parar Autopilot',
              group: 'Ações',
              run: () => ref.read(autopilotProvider.notifier).stop(ws.id),
            )
          : PaletteCommand(
              label: 'Ligar Autopilot (Executar tudo)',
              group: 'Ações',
              run: () => ref.read(autopilotProvider.notifier).start(ws.id),
            ),
    PaletteCommand(
      label: 'Nova sessão',
      shortcut: 'Ctrl N',
      group: 'Ações',
      run: () {
        onNavigate(AppSection.sessions);
        showNewSessionDialog(context);
      },
    ),
    PaletteCommand(
      label: 'Nova spec',
      group: 'Ações',
      run: () => showNewSpecDialog(context),
    ),
    for (final s in specs)
      if (s.status != SpecStatus.archived) ...[
        PaletteCommand(
          label: '${s.code} · ${s.title}',
          group: 'Specs',
          run: () {
            ref.read(selectedSpecProvider.notifier).select(s.id);
            onNavigate(AppSection.specs);
          },
        ),
        if (isOnBoard(s) &&
            s.stage != SpecStage.done &&
            s.stage != SpecStage.review &&
            specBlockers(s, byCode, reviewUnblocks: true).isEmpty)
          PaletteCommand(
            label: 'Executar ${s.code}',
            group: 'Ações',
            run: () async {
              try {
                await ref
                    .read(specRunnerProvider)
                    .runNext(s.id, reviewUnblocks: true);
                onNavigate(AppSection.tasks);
              } catch (e) {
                toast('$e');
              }
            },
          ),
      ],
    for (final x in sessions.take(50))
      PaletteCommand(
        label: sessionTitle(x),
        group: 'Sessões',
        run: () {
          ref.read(selectedSessionProvider.notifier).select(x.id);
          onNavigate(AppSection.sessions);
        },
      ),
  ];
}

/// Command palette (Ctrl+K).
Future<void> showCommandPalette(
  BuildContext context, {
  required WidgetRef ref,
  required void Function(AppSection) onNavigate,
}) {
  final commands = paletteCommands(context, ref, onNavigate: onNavigate);
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

  List<PaletteCommand> get _filtered =>
      filterCommands(widget.commands, _query.text);

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
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: sel
                                              ? AppColors.amber
                                              : AppColors.text,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      c.group,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                    if (c.shortcut != null) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        c.shortcut!,
                                        style: const TextStyle(
                                          fontFamily: AppFonts.mono,
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
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
