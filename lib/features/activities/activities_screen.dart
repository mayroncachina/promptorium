import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../ui/shell/navigation.dart';
import '../../ui/theme/tokens.dart';
import '../sessions/widgets/session_style.dart' show AmberButton, SmallButton;
import '../resume/resume_state.dart' show resumeProvider;
import 'activities_state.dart';
import 'activity.dart';
import 'activity_actions.dart';
import 'automation_pause.dart';
import 'widgets/activity_panel.dart';
import 'widgets/activity_row.dart';
import 'widgets/quota_card.dart';

/// Atividades (SPEC-076 R15–R23): what is running now in every workspace.

/// The activity selected in the list (the Quadro's robot picks it, R23).
class ActivitiesSelection extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final activitiesSelectionProvider =
    NotifierProvider<ActivitiesSelection, String?>(ActivitiesSelection.new);

/// The tab of the list.
class ActivitiesTab extends Notifier<ActivityTab> {
  @override
  ActivityTab build() => ActivityTab.all;

  void select(ActivityTab t) => state = t;
}

final activitiesTabProvider = NotifierProvider<ActivitiesTab, ActivityTab>(
  ActivitiesTab.new,
);

/// "Agrupar por": Workspace (true) or Nenhum.
class ActivitiesGrouped extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool v) => state = v;
}

final activitiesGroupedProvider = NotifierProvider<ActivitiesGrouped, bool>(
  ActivitiesGrouped.new,
);

/// Opens the Atividades on [activityId] (the robot of a Quadro card, R23).
void openActivities(WidgetRef ref, String activityId) =>
    _openActivities(ref.read, activityId);

/// Same as [openActivities] from outside a widget.
void openActivitiesIn(ProviderContainer c, String activityId) =>
    _openActivities(c.read, activityId);

void _openActivities(
  T Function<T>(ProviderListenable<T>) read,
  String activityId,
) {
  read(activitiesSelectionProvider.notifier).select(activityId);
  read(activitiesTabProvider.notifier).select(ActivityTab.all);
  read(navigationProvider.notifier).go(AppSection.activities);
}

class ActivitiesScreen extends ConsumerStatefulWidget {
  const ActivitiesScreen({super.key});

  @override
  ConsumerState<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends ConsumerState<ActivitiesScreen> {
  Timer? _timer;
  final _listFocus = FocusNode(debugLabel: 'activities-list');

  @override
  void initState() {
    super.initState();
    // The times move and the dev servers have no change stream.
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      refreshActivities(ref);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _listFocus.dispose();
    super.dispose();
  }

  /// The rows in the order shown, for ↑/↓ (R21).
  List<Activity> _visible(ActivitiesSnapshot snap, ActivityTab tab) =>
      ref.read(activitiesGroupedProvider)
      ? [
          for (final g in groupActivities(
            snap.items,
            tab,
            order: snap.order,
            labels: snap.labels,
          ))
            ...g.items,
        ]
      : flatActivities(snap.items, tab);

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final snap = ref.read(activitiesSnapshotProvider);
    final rows = _visible(snap, ref.read(activitiesTabProvider));
    if (rows.isEmpty) return KeyEventResult.ignored;
    final sel = ref.read(activitiesSelectionProvider);
    var i = rows.indexWhere((a) => a.id == sel);
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      i = (i + 1).clamp(0, rows.length - 1);
    } else if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      i = i < 0 ? 0 : (i - 1).clamp(0, rows.length - 1);
    } else if (e.logicalKey == LogicalKeyboardKey.enter && i >= 0) {
      openActivity(ref, rows[i]);
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    ref.read(activitiesSelectionProvider.notifier).select(rows[i].id);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(activitiesSnapshotProvider);
    final tab = ref.watch(activitiesTabProvider);
    final grouped = ref.watch(activitiesGroupedProvider);
    final counts = activityTabCounts(snap.items);
    final selId = ref.watch(activitiesSelectionProvider);
    final visible = _visible(snap, tab);
    final selected =
        snap.items.where((a) => a.id == selId).firstOrNull ??
        visible.firstOrNull;
    final now = DateTime.now();

    return Row(
      key: const ValueKey('screen-activities'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(),
                const SizedBox(height: 14),
                _Tabs(tab: tab, counts: counts, grouped: grouped),
                const SizedBox(height: 10),
                Expanded(
                  child: Focus(
                    focusNode: _listFocus,
                    onKeyEvent: _onKey,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.panel,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: snap.items.isEmpty
                          ? const _Empty()
                          : _List(
                              snap: snap,
                              tab: tab,
                              grouped: grouped,
                              selectedId: selected?.id,
                              now: now,
                              onSelect: (a) {
                                _listFocus.requestFocus();
                                ref
                                    .read(activitiesSelectionProvider.notifier)
                                    .select(a.id);
                              },
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          width: 300,
          margin: const EdgeInsets.fromLTRB(0, 12, 16, 16),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: selected == null
              ? const Center(
                  child: Text(
                    'Selecione uma atividade.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                )
              : ActivityPanel(activity: selected, now: now),
        ),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paused = ref.watch(automationPausedProvider);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Atividades',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 2),
              Text(
                'Tudo o que está rodando agora, em todos os workspaces.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        const QuotaCard(),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Tooltip(
            message: paused
                ? 'O Autopilot e o Corrigir CI automático estão parados. '
                      'Retomar volta ao normal.'
                : 'Segura o Autopilot e o Corrigir CI automático. Os turnos '
                      'em andamento terminam.',
            child: paused
                ? AmberButton(
                    key: const ValueKey('activities-pause'),
                    label: 'Retomar automáticos',
                    height: 34,
                    onTap: () =>
                        ref.read(automationPausedProvider.notifier).set(false),
                  )
                : SmallButton(
                    key: const ValueKey('activities-pause'),
                    label: 'Pausar automáticos',
                    icon: Icons.pause,
                    height: 34,
                    onTap: () =>
                        ref.read(automationPausedProvider.notifier).set(true),
                  ),
          ),
        ),
      ],
    );
  }
}

class _Tabs extends ConsumerWidget {
  const _Tabs({required this.tab, required this.counts, required this.grouped});

  final ActivityTab tab;
  final Map<ActivityTab, int> counts;
  final bool grouped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Flexible(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in ActivityTab.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Semantics(
                      selected: t == tab,
                      button: true,
                      label: '${t.label}, ${counts[t] ?? 0}',
                      excludeSemantics: true,
                      child: InkWell(
                        key: ValueKey('activities-tab-${t.name}'),
                        borderRadius: BorderRadius.circular(7),
                        onTap: () =>
                            ref.read(activitiesTabProvider.notifier).select(t),
                        child: Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: t == tab ? AppColors.amberTint : null,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                t.label,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: t == tab
                                      ? AppColors.amber
                                      : AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${counts[t] ?? 0}',
                                key: ValueKey('activities-count-${t.name}'),
                                style: TextStyle(
                                  fontFamily: AppFonts.mono,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: t == tab
                                      ? AppColors.amber
                                      : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // SPEC-080 R13: the journal of the last 24 h, even without being away.
        SmallButton(
          key: const ValueKey('activities-what-happened'),
          label: 'O que aconteceu',
          icon: Icons.history,
          height: 28,
          onTap: () => ref.read(resumeProvider.notifier).showManual(),
        ),
        const SizedBox(width: 12),
        const Text(
          'Agrupar por',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<bool>(
          key: const ValueKey('activities-group-by'),
          tooltip: 'Agrupar por',
          color: AppColors.panelSolid,
          initialValue: grouped,
          onSelected: (v) =>
              ref.read(activitiesGroupedProvider.notifier).set(v),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: true,
              child: Text('Workspace', style: TextStyle(fontSize: 12)),
            ),
            PopupMenuItem(
              value: false,
              child: Text('Nenhum', style: TextStyle(fontSize: 12)),
            ),
          ],
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  grouped ? 'Workspace' : 'Nenhum',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.expand_more,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _List extends StatelessWidget {
  const _List({
    required this.snap,
    required this.tab,
    required this.grouped,
    required this.selectedId,
    required this.now,
    required this.onSelect,
  });

  final ActivitiesSnapshot snap;
  final ActivityTab tab;
  final bool grouped;
  final String? selectedId;
  final DateTime now;
  final void Function(Activity) onSelect;

  @override
  Widget build(BuildContext context) {
    Widget row(Activity a) => ActivityRow(
      key: ValueKey('activity-${a.id}'),
      activity: a,
      selected: a.id == selectedId,
      now: now,
      showWorkspace: !grouped,
      onTap: () => onSelect(a),
    );
    final children = <Widget>[];
    if (grouped) {
      for (final g in groupActivities(
        snap.items,
        tab,
        order: snap.order,
        labels: snap.labels,
      )) {
        children
          ..add(_GroupHeader(group: g))
          ..addAll(g.items.map(row));
      }
    } else {
      children.addAll(flatActivities(snap.items, tab).map(row));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ActivityHeaderRow(),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: children.isEmpty
              ? Center(
                  child: Text(
                    'Nada em "${tab.label}".',
                    key: const ValueKey('activities-tab-empty'),
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                )
              : ListView(
                  key: const ValueKey('activities-list'),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                  children: children,
                ),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final ActivityGroup group;

  @override
  Widget build(BuildContext context) {
    final n = group.needsYou;
    return Container(
      key: ValueKey('activities-group-${group.workspaceId}'),
      height: 28,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          const Icon(Icons.expand_more, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            group.name,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Text(
            [
              '${group.items.length}',
              if (n == 1) '1 precisa de você',
              if (n > 1) '$n precisam de você',
            ].join(' · '),
            style: TextStyle(
              fontSize: 11.5,
              color: n > 0 ? AppColors.amber : AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          if (group.label case final l?)
            Text(
              l,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

class _Empty extends ConsumerWidget {
  const _Empty();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Nada rodando agora.',
          key: ValueKey('activities-empty'),
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        const Text(
          'Quando um agente, um gate, um PR ou um servidor estiver rodando, '
          'ele aparece aqui.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        SmallButton(
          key: const ValueKey('activities-empty-board'),
          label: 'Abrir o Quadro',
          onTap: () =>
              ref.read(navigationProvider.notifier).go(AppSection.tasks),
        ),
      ],
    ),
  );
}
