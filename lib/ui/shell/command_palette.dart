import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../features/board/autopilot.dart';
import '../../features/board/board_rules.dart';
import '../../features/board/spec_runner.dart';
import '../../features/code/worktree_files.dart' show fuzzyScore;
import '../../features/home/home_inbox.dart';
import '../../features/prompt/conversation_manager.dart';
import '../../features/review/review_service.dart' show selectedReviewProvider;
import '../../features/sessions/new_session_dialog.dart';
import '../../features/sessions/session_manager.dart';
import '../../features/specs/new_spec_dialog.dart';
import '../../features/specs/spec_service.dart' show selectedSpecProvider;

import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import 'navigation.dart';
import 'about_dialog.dart';
import 'shortcut_sheet.dart';

/// A command shown in the palette.
class PaletteCommand {
  const PaletteCommand({
    required this.label,
    required this.run,
    this.shortcut,
    this.group = 'Telas',
    this.detail,
  });

  final String label;
  final String? shortcut;

  /// `Pendentes`, `Ações`, `Telas`, `Specs`, `Sessões` (section of the
  /// list; see [paletteGroups]).
  final String group;

  /// Grey text after the label (what the action is about).
  final String? detail;
  final VoidCallback run;
}

/// Sections of the palette, in display order.
const paletteGroups = [
  'Recentes',
  'Pendentes',
  'Ações',
  'Telas',
  'Specs',
  'Sessões',
];

/// Prefix of the query that restricts the list to some groups (UX v2):
/// `>` actions and pending items, `#` specs, `:` sessions.
const palettePrefixes = {
  '>': ['Pendentes', 'Ações'],
  '#': ['Specs'],
  ':': ['Sessões'],
};

/// `(groups, text)` of a query: `>apr` → (`[Pendentes, Ações]`, `apr`);
/// no prefix → (null, query).
(List<String>?, String) parsePaletteQuery(String query) {
  final q = query.trimLeft();
  if (q.isNotEmpty && palettePrefixes.containsKey(q[0])) {
    return (palettePrefixes[q[0]], q.substring(1).trim());
  }
  return (null, query.trim());
}

/// Commands of the palette, best match first ([fuzzyScore], the same
/// search as "Ir para arquivo"). Empty query = the list as given. A prefix
/// (`>`, `#`, `:`) keeps only its groups.
List<PaletteCommand> filterCommands(List<PaletteCommand> all, String query) {
  final (groups, text) = parsePaletteQuery(query);
  final scoped = groups == null
      ? all
      : [
          for (final c in all)
            if (groups.contains(c.group)) c,
        ];
  if (text.isEmpty) return scoped;
  final scored = <(PaletteCommand, int)>[];
  for (final c in scoped) {
    final s = fuzzyScore(
      c.detail == null ? c.label : '${c.label} ${c.detail}',
      text,
    );
    if (s != null) scored.add((c, s));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final (c, _) in scored) c];
}

/// Everything Ctrl+K reaches (F10, UX v2): the pending items of Início
/// (approve / deny / answer / review / resume), actions (autopilot, new
/// session / spec), screens, the specs of the workspace (open, run) and its
/// sessions. Recent commands come first ([recentPaletteLabels]).
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
  final conversations = ref.read(conversationManagerProvider.notifier);
  final messenger = ScaffoldMessenger.maybeOf(context);
  void toast(String msg) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
  final byCode = specsByCode(specs);
  void openSession(String id) {
    ref.read(selectedSessionProvider.notifier).select(id);
    onNavigate(AppSection.sessions);
  }

  final pending = <PaletteCommand>[];
  for (final g in ref.read(inboxProvider)) {
    for (final it in g.items) {
      final a = it.approval;
      final id = it.sessionId;
      switch (g.kind) {
        case InboxKind.approval:
          if (a == null) continue;
          final conv = it.conversationId;
          pending.add(
            PaletteCommand(
              label: a.request.toolName == 'AskUserQuestion'
                  ? 'Responder'
                  : 'Aprovar',
              detail: '${it.ref} · ${it.detail}',
              group: 'Pendentes',
              run: () {
                // A question needs the user's choice: just go to it.
                if (a.request.toolName == 'AskUserQuestion') {
                  if (conv != null) {
                    ref
                        .read(selectedConversationProvider.notifier)
                        .select(conv);
                    onNavigate(AppSection.prompt);
                  } else {
                    ref
                        .read(selectedSessionProvider.notifier)
                        .select(a.sessionId);
                    onNavigate(AppSection.sessions);
                  }
                  return;
                }
                conv != null
                    ? conversations.approve(conv, a.requestId)
                    : manager.approve(a.sessionId, a.requestId);
              },
            ),
          );
          pending.add(
            PaletteCommand(
              label: 'Negar',
              detail: '${it.ref} · ${it.detail}',
              group: 'Pendentes',
              run: () => conv != null
                  ? conversations.deny(conv, a.requestId)
                  : manager.deny(a.sessionId, a.requestId),
            ),
          );
        case InboxKind.needsAnswer:
          if (id == null) continue;
          pending.add(
            PaletteCommand(
              label: 'Responder',
              detail: '${it.ref} · ${it.title}',
              group: 'Pendentes',
              run: () => openSession(id),
            ),
          );
        case InboxKind.review || InboxKind.prProblem:
          pending.add(
            PaletteCommand(
              label: 'Abrir review',
              detail: '${it.ref} · ${it.title}',
              group: 'Pendentes',
              run: () {
                if (id != null) {
                  ref.read(selectedReviewProvider.notifier).select(id);
                }
                onNavigate(AppSection.review);
              },
            ),
          );
        case InboxKind.interrupted:
          if (id == null) continue;
          pending.add(
            PaletteCommand(
              label: 'Retomar',
              detail: '${it.ref} · ${it.detail}',
              group: 'Pendentes',
              run: () async {
                try {
                  await manager.send(id, 'Continue de onde parou.');
                  openSession(id);
                } catch (e) {
                  toast('$e');
                }
              },
            ),
          );
      }
    }
  }

  return [
    ...pending,
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
    PaletteCommand(
      label: 'Atalhos de teclado',
      shortcut: 'Ctrl /',
      group: 'Ações',
      run: () => showShortcutSheet(context),
    ),
    PaletteCommand(
      label: 'Sobre',
      shortcut: 'F1',
      group: 'Ações',
      run: () => showAboutPromptorium(context),
    ),
    for (final s in specs)
      if (s.status != SpecStatus.archived &&
          isOnBoard(s) &&
          s.stage != SpecStage.done &&
          s.stage != SpecStage.review &&
          specBlockers(s, byCode, reviewUnblocks: true).isEmpty)
        PaletteCommand(
          label: 'Executar ${s.code}',
          detail: s.title,
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
    for (final s in specs)
      if (s.status != SpecStatus.archived)
        PaletteCommand(
          label: '${s.code} · ${s.title}',
          group: 'Specs',
          run: () {
            ref.read(selectedSpecProvider.notifier).select(s.id);
            onNavigate(AppSection.specs);
          },
        ),
    for (final x in sessions.take(50))
      PaletteCommand(
        label: sessionTitle(x),
        detail: x.branch,
        group: 'Sessões',
        run: () => openSession(x.id),
      ),
  ];
}

/// Labels of the last commands run (newest first).
List<String> recentPaletteLabels(AppSettingsController settings) => [
  for (final l in (settings.get(AppSettingKeys.paletteRecent) ?? '').split(
    '\n',
  ))
    if (l.isNotEmpty) l,
];

/// Remembers [label] as the most recent command (8 kept).
Future<void> rememberPaletteLabel(
  AppSettingsController settings,
  String label,
) {
  final list = [
    label,
    ...recentPaletteLabels(settings).where((l) => l != label),
  ];
  return settings.set(AppSettingKeys.paletteRecent, list.take(8).join('\n'));
}

/// [commands] with a "Recentes" copy of the ones run before (same label), in
/// the order they were run. Only a label that names one command counts, and
/// never a pending item: "Aprovar" / "Negar" / "Retomar" repeat per request
/// and a recent one would answer whichever request comes first.
List<PaletteCommand> withRecents(
  List<PaletteCommand> commands,
  List<String> recents,
) {
  final byLabel = <String, PaletteCommand>{};
  final repeated = <String>{};
  for (final c in commands) {
    if (c.group == 'Pendentes') continue;
    if (byLabel.containsKey(c.label)) repeated.add(c.label);
    byLabel.putIfAbsent(c.label, () => c);
  }
  repeated.forEach(byLabel.remove);
  return [
    for (final l in recents)
      if (byLabel[l] case final c?)
        PaletteCommand(
          label: c.label,
          detail: c.detail,
          shortcut: c.shortcut,
          group: 'Recentes',
          run: c.run,
        ),
    ...commands,
  ];
}

/// Command palette (Ctrl+K).
Future<void> showCommandPalette(
  BuildContext context, {
  required WidgetRef ref,
  required void Function(AppSection) onNavigate,
}) {
  final settings = ref.read(appSettingsProvider.notifier);
  final commands = withRecents(
    paletteCommands(context, ref, onNavigate: onNavigate),
    recentPaletteLabels(settings),
  );
  return showDialog<void>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (_) => CommandPalette(
      commands: commands,
      onRun: (c) => rememberPaletteLabel(settings, c.label),
      // The shell's context: the palette is gone when the sheet opens.
      onShortcuts: () => showShortcutSheet(context),
    ),
  );
}

class CommandPalette extends StatefulWidget {
  const CommandPalette({
    super.key,
    required this.commands,
    this.onRun,
    this.onShortcuts,
  });

  final List<PaletteCommand> commands;

  /// Called with the command before it runs (recents).
  final void Function(PaletteCommand)? onRun;

  /// "Todos os atalhos" of the footer, called after the palette closes.
  final VoidCallback? onShortcuts;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _query = TextEditingController();
  int _selected = 0;

  List<PaletteCommand> get _filtered {
    final list = filterCommands(widget.commands, _query.text);
    // Recents only while nothing is typed; with a query every command
    // appears once (its own group).
    final (_, text) = parsePaletteQuery(_query.text);
    return text.isEmpty
        ? list
        : [
            for (final c in list)
              if (c.group != 'Recentes') c,
          ];
  }

  void _run(PaletteCommand c) {
    widget.onRun?.call(c);
    Navigator.of(context).pop();
    c.run();
  }

  void _setPrefix(String? prefix) {
    final (_, text) = parsePaletteQuery(_query.text);
    _query.text = '${prefix ?? ''}$text';
    _query.selection = TextSelection.collapsed(offset: _query.text.length);
    setState(() => _selected = 0);
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
    final (activeGroups, _) = parsePaletteQuery(_query.text);
    final activePrefix = activeGroups == null
        ? null
        : palettePrefixes.entries
              .firstWhere((e) => e.value == activeGroups)
              .key;
    // Rows: a header before the first command of each group.
    final rows = <Object>[];
    String? lastGroup;
    for (final c in items) {
      if (c.group != lastGroup) {
        rows.add(c.group);
        lastGroup = c.group;
      }
      rows.add(c);
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
          width: 640,
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Wrap(
                    runSpacing: 4,
                    children: [
                      _chip('Tudo', null, activePrefix),
                      for (final e in palettePrefixes.entries)
                        _chip(
                          '${e.key} ${e.value.join(' e ')}',
                          e.key,
                          activePrefix,
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
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
                          itemCount: rows.length,
                          itemBuilder: (context, i) {
                            final r = rows[i];
                            if (r is String) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  4,
                                ),
                                child: Text(
                                  r.toUpperCase(),
                                  key: ValueKey('palette-group-$r'),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.8,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              );
                            }
                            final c = r as PaletteCommand;
                            final sel = items.indexOf(c) == _selected;
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
                                      child: Text.rich(
                                        TextSpan(
                                          text: c.label,
                                          children: [
                                            if (c.detail != null)
                                              TextSpan(
                                                text: '  ${c.detail}',
                                                style: const TextStyle(
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                              ),
                                          ],
                                        ),
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
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '↑↓ navegar · Enter executar · Esc fechar',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const ValueKey('palette-shortcuts'),
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onShortcuts?.call();
                        },
                        child: const Text(
                          'Todos os atalhos · Ctrl+/',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, String? prefix, String? active) {
    final on = prefix == active;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        key: ValueKey('palette-chip-${prefix ?? 'all'}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _setPrefix(prefix),
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.amberTint : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? AppColors.amber : AppColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: on ? AppColors.amber : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
