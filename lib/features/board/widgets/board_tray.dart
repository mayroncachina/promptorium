import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../sessions/widgets/session_style.dart';
import '../../specs/spec_service.dart' show selectedSpecProvider;
import '../board_rules.dart';

/// The Bandeja of the Quadro (SPEC-068 R7, R8): specs that are not on the
/// Quadro yet, drafts and approved ones that wait, grouped by the
/// conversation they came from. Approved ones are taken to the Backlog.

/// The Bandeja is open (per workspace, remembered; R7).
class BoardTrayOpen extends Notifier<bool> {
  int? _workspaceId;

  @override
  bool build() {
    _workspaceId = ref.watch(activeWorkspaceProvider.select((w) => w?.id));
    final id = _workspaceId;
    if (id == null) return false;
    return ref
            .read(appSettingsProvider.notifier)
            .get(AppSettingKeys.boardTrayOpen(id)) ==
        '1';
  }

  Future<void> set(bool open) async {
    state = open;
    final id = _workspaceId;
    if (id == null) return;
    await ref
        .read(appSettingsProvider.notifier)
        .set(AppSettingKeys.boardTrayOpen(id), open ? '1' : '0');
  }

  Future<void> toggle() => set(!state);
}

final boardTrayOpenProvider = NotifierProvider<BoardTrayOpen, bool>(
  BoardTrayOpen.new,
);

/// One group of the Bandeja: the conversation (null = "Outras") and its
/// specs, in code order.
typedef TrayGroup = ({int? conversationId, List<Spec> specs});

/// The specs of the Bandeja grouped by the conversation of origin, the
/// conversations in order of their newest spec, "Outras" last (R7).
List<TrayGroup> trayGroups(Iterable<Spec> specs) {
  final by = <int?, List<Spec>>{};
  for (final s in specs.where(isInTray)) {
    by.putIfAbsent(s.originConversationId, () => []).add(s);
  }
  for (final l in by.values) {
    l.sort((a, b) => a.code.compareTo(b.code));
  }
  final keys = by.keys.whereType<int>().toList()
    ..sort((a, b) => b.compareTo(a));
  return [
    for (final k in keys) (conversationId: k, specs: by[k]!),
    if (by[null] case final other?) (conversationId: null, specs: other),
  ];
}

/// `SPEC-021 e SPEC-022 no Backlog` (R8).
String takenMessage(List<String> codes) {
  final list = codes.length <= 1
      ? codes.join()
      : '${codes.sublist(0, codes.length - 1).join(', ')} e ${codes.last}';
  return '$list no Backlog';
}

/// "Levar para o Backlog" (R8): the specs leave the Bandeja, with a notice
/// whose "Desfazer" puts them back.
Future<void> takeToBacklog(
  BuildContext context,
  WidgetRef ref,
  List<Spec> specs,
) async {
  if (specs.isEmpty) return;
  final repo = ref.read(specsRepoProvider);
  final ids = [for (final s in specs) s.id];
  await repo.setInTray(ids, false);
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showAppToast(
      SnackBar(
        key: const ValueKey('board-tray-taken'),
        content: Semantics(
          liveRegion: true,
          child: Text(takenMessage([for (final s in specs) s.code])),
        ),
        action: SnackBarAction(
          key: const ValueKey('board-tray-undo'),
          label: 'Desfazer',
          onPressed: () => unawaited(repo.setInTray(ids, true)),
        ),
      ),
    );
}

/// The button that replaces "N em rascunho fora do quadro" (R7, R9).
class BoardTrayButton extends ConsumerWidget {
  const BoardTrayButton({super.key, required this.count, this.compact = false});

  final int count;

  /// A narrow bar (filters folded): the icon and the count only; the name
  /// stays in the tooltip and for the screen reader.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(boardTrayOpenProvider);
    final label = count == 1
        ? 'Bandeja, 1 spec fora do quadro'
        : 'Bandeja, $count specs fora do quadro';
    return Semantics(
      container: true,
      button: true,
      toggled: open,
      label: '$label, ${open ? 'aberta' : 'fechada'}',
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          key: const ValueKey('board-tray-button'),
          color: open ? AppColors.amberTint : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: open ? AppColors.amber : AppColors.borderHover,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => ref.read(boardTrayOpenProvider.notifier).toggle(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 15,
                    color: open ? AppColors.amber : AppColors.textSecondary,
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 6),
                    Text(
                      'Bandeja',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: open ? AppColors.amber : AppColors.text,
                      ),
                    ),
                  ],
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.amber,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$count',
                        key: const ValueKey('board-tray-count'),
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onAmber,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The panel left of the Backlog (R7, R8).
class BoardTray extends ConsumerStatefulWidget {
  const BoardTray({super.key, required this.workspaceId, required this.specs});

  final int workspaceId;
  final List<Spec> specs;

  /// Width of the panel: the Quadro stays usable at 1100 px (R7).
  static const width = 300.0;

  @override
  ConsumerState<BoardTray> createState() => _BoardTrayState();
}

class _BoardTrayState extends ConsumerState<BoardTray> {
  final _checked = <int>{};

  void _open(Spec spec) {
    ref.read(selectedSpecProvider.notifier).select(spec.id);
    ref.read(navigationProvider.notifier).go(AppSection.specs);
  }

  @override
  Widget build(BuildContext context) {
    final groups = trayGroups(widget.specs);
    final conversations = {
      for (final c
          in ref.watch(conversationsProvider(widget.workspaceId)).value ??
              const <Conversation>[])
        c.id: c.title,
    };
    final inTray = {
      for (final g in groups)
        for (final s in g.specs) s.id: s,
    };
    // A spec that left (taken, run, edited) leaves the selection.
    _checked.removeWhere(
      (id) => inTray[id] == null || !canTakeFromTray(inTray[id]!),
    );
    final chosen = [
      for (final g in groups)
        for (final s in g.specs)
          if (_checked.contains(s.id)) s,
    ];
    final n = chosen.length;

    Widget card(Spec s) {
      final approved = s.status == SpecStatus.approved;
      final checked = _checked.contains(s.id);
      final detail = !approved
          ? 'aprove antes de levar'
          : s.dependsOn.isNotEmpty
          ? 'depende de ${s.dependsOn.join(', ')}'
          : '${s.requirements.length} '
                '${s.requirements.length == 1 ? 'requisito' : 'requisitos'}';
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          key: ValueKey('board-tray-spec-${s.code}'),
          color: checked ? AppColors.amberTint : AppColors.surfaceRaisedSolid,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: checked ? AppColors.amber : AppColors.border,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _open(s),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: approved
                        ? Checkbox(
                            key: ValueKey('board-tray-check-${s.code}'),
                            value: checked,
                            activeColor: AppColors.amber,
                            checkColor: AppColors.onAmber,
                            side: const BorderSide(
                              color: AppColors.borderHover,
                            ),
                            semanticLabel: '${s.code} ${s.title}, aprovada',
                            onChanged: (v) => setState(() {
                              v == true
                                  ? _checked.add(s.id)
                                  : _checked.remove(s.id);
                            }),
                          )
                        : Tooltip(
                            message: 'Aprove antes de levar',
                            child: Center(
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.border),
                                ),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.code,
                            style: const TextStyle(
                              fontFamily: AppFonts.mono,
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: approved
                                      ? SessionColors.runningToolBg
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: approved
                                        ? SessionColors.runningToolBorder
                                        : AppColors.borderHover,
                                  ),
                                ),
                                child: Text(
                                  approved ? 'Aprovada' : 'Rascunho',
                                  key: ValueKey('board-tray-state-${s.code}'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: approved
                                        ? AppColors.teal
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  detail,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget heading(TrayGroup g) {
      final id = g.conversationId;
      final title = id == null ? null : conversations[id];
      final text = id == null
          ? 'Outras · ${g.specs.length}'
          : 'Da conversa “${title ?? 'apagada'}” · ${g.specs.length}';
      return Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
        child: Row(
          children: [
            if (id != null) ...[
              const Icon(
                Icons.chat_bubble_outline,
                size: 12,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  text.toUpperCase(),
                  key: ValueKey('board-tray-group-${id ?? 'other'}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('board-tray'),
      width: BoardTray.width,
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.inbox_outlined,
                    size: 16,
                    color: AppColors.amber,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: const Text(
                          'Bandeja',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Rascunhos e aprovadas que ainda não estão no quadro.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('board-tray-close'),
                  tooltip: 'Fechar a Bandeja',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () =>
                      ref.read(boardTrayOpenProvider.notifier).set(false),
                ),
              ],
            ),
          ),
          Expanded(
            child: groups.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'Nada esperando. As specs novas entram aqui como '
                      'rascunho.',
                      key: ValueKey('board-tray-empty'),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    children: [
                      for (final g in groups) ...[
                        heading(g),
                        for (final s in g.specs) card(s),
                      ],
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  n == 0
                      ? 'Marque as aprovadas que quer levar.'
                      : '$n ${n == 1 ? 'aprovada marcada' : 'aprovadas marcadas'}'
                            ' · rascunhos se aprovam na spec',
                  key: const ValueKey('board-tray-footer'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                SmallButton(
                  key: const ValueKey('board-tray-take'),
                  label: n == 0
                      ? 'Levar para o Backlog'
                      : 'Levar $n para o Backlog',
                  icon: Icons.arrow_forward,
                  height: 36,
                  expand: true,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onAmber,
                  border: AppColors.amber,
                  background: AppColors.amber,
                  onTap: n == 0
                      ? null
                      : () async {
                          setState(_checked.clear);
                          await takeToBacklog(context, ref, chosen);
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
