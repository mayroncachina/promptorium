import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../activities/widgets/robot_avatar.dart';
import '../../sessions/widgets/session_style.dart'
    show AmberButton, SmallButton;
import '../activity_journal.dart';
import '../resume_actions.dart';
import '../resume_state.dart';
import '../resume_summary.dart';

/// The card "Retomar de onde parei" (SPEC-080 R10, R11, R15): large on
/// opening the app, compact in the corner on coming back. Never modal.

/// Items shown per group before "+ N em Terminou" (R4).
const resumeGroupLimit = 6;

/// The compact card leaves by itself after this, with nothing waiting (R11).
const compactTimeout = Duration(seconds: 20);

IconData _iconOf(String tag) => switch (tag) {
  'RELEASE' => Icons.sell_outlined,
  'PR' || 'CI' => Icons.call_split,
  'DEV' => Icons.terminal,
  _ => Icons.smart_toy_outlined,
};

Color _markColor(JournalOutcome? m) => switch (m) {
  JournalOutcome.ok => AppColors.teal,
  JournalOutcome.failed => AppColors.red,
  JournalOutcome.attention => AppColors.amber,
  null => AppColors.textSecondary,
};

/// The robot of an item, with the result in its corner (or the icon).
class ResumeAvatar extends StatelessWidget {
  const ResumeAvatar({super.key, required this.item, this.size = 24});

  final ResumeItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final seed = item.seed;
    final mark = item.group == ResumeGroup.finished ? item.mark : null;
    return SizedBox(
      width: size + 6,
      height: size + 6,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(
            child: seed != null
                ? RobotAvatar(
                    seed: seed,
                    pose: item.pose,
                    size: size,
                    semanticLabel: RobotIdentity.of(seed).name,
                  )
                : Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Icon(
                      _iconOf(item.tag),
                      size: size * .6,
                      color: AppColors.teal,
                    ),
                  ),
          ),
          if (mark != null && seed != null)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: _markColor(mark),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.panelSolid, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppColors.border),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    ),
  );
}

/// One item: robot, badge, title, workspace, what happened, time, action.
class ResumeItemRow extends StatelessWidget {
  const ResumeItemRow({
    super.key,
    required this.item,
    required this.now,
    required this.onAction,
    this.selected = false,
    this.onHover,
  });

  final ResumeItem item;
  final DateTime now;
  final VoidCallback onAction;
  final bool selected;
  final VoidCallback? onHover;

  @override
  Widget build(BuildContext context) {
    final i = item;
    final mark = i.mark;
    final at = i.group == ResumeGroup.running ? null : i.at;
    return Semantics(
      button: true,
      selected: selected,
      label: resumeSemantics(i),
      excludeSemantics: true,
      onTap: onAction,
      child: MouseRegion(
        onEnter: (_) => onHover?.call(),
        child: Container(
          key: ValueKey('resume-item-${i.key}'),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.amber.withValues(alpha: .06) : null,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? AppColors.amber.withValues(alpha: .55)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              ResumeAvatar(item: i),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _Tag(i.tag),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            i.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        if (i.workspaceName != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            i.workspaceName!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (i.group == ResumeGroup.running)
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: const BoxDecoration(
                              color: AppColors.teal,
                              shape: BoxShape.circle,
                            ),
                          )
                        else if (mark != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: Text(
                              mark.mark,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _markColor(mark),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            i.line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: i.group == ResumeGroup.waiting
                                  ? AppColors.text
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (at != null) ...[
                const SizedBox(width: 10),
                Text(
                  resumeTime(at, now),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
              const SizedBox(width: 10),
              SizedBox(
                width: 116,
                child: selected
                    ? AmberButton(
                        key: ValueKey('resume-action-${i.key}'),
                        label: i.action.label,
                        onTap: onAction,
                        expand: true,
                      )
                    : SmallButton(
                        key: ValueKey('resume-action-${i.key}'),
                        label: i.action.label,
                        onTap: onAction,
                        expand: true,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The header of a group: `ESPERA POR VOCÊ  2`.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.group, this.count, {this.manual = false});

  final ResumeGroup group;
  final int count;

  /// "O que aconteceu": nobody was away, so "Terminou" is plain.
  final bool manual;

  String get _label => manual && group == ResumeGroup.finished
      ? 'Terminou nas últimas 24 h'
      : group.label;

  @override
  Widget build(BuildContext context) {
    final color = switch (group) {
      ResumeGroup.waiting => AppColors.amber,
      ResumeGroup.finished => AppColors.teal,
      ResumeGroup.running => AppColors.blue,
    };
    return Semantics(
      header: true,
      label: '$_label, $count',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
        child: Row(
          children: [
            Text(
              _label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `desde ontem 19:42 · 13 h · 3 workspaces · 2 esperam por você · …`
String resumeHeaderLine(
  ResumeState st,
  ResumeSummary s,
  DateTime now,
  int workspaces,
) {
  final since = st.since;
  final w = s.waiting.length, f = s.finished.length, r = s.running.length;
  return [
    if (st.origin == ResumeOrigin.manual)
      'nas últimas 24 h'
    else if (since != null)
      'desde ${resumeTime(since, now)}',
    if (st.origin != ResumeOrigin.manual && st.away != null)
      awayLabel(st.away!),
    if (workspaces > 1) '$workspaces workspaces',
    if (w > 0) '$w ${w == 1 ? 'espera' : 'esperam'} por você',
    if (f > 0) '$f ${f == 1 ? 'terminou' : 'terminaram'}',
    if (r > 0) '$r rodando',
  ].join(' · ');
}

class _Key extends StatelessWidget {
  const _Key(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppColors.border),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 10,
        color: AppColors.textSecondary,
      ),
    ),
  );
}

/// The large card (R10): over the screen, centered at the top, not modal.
class ResumeCard extends ConsumerStatefulWidget {
  const ResumeCard({
    super.key,
    required this.summary,
    required this.onRetryGithub,
  });

  final ResumeSummary summary;
  final VoidCallback onRetryGithub;

  @override
  ConsumerState<ResumeCard> createState() => _ResumeCardState();
}

class _ResumeCardState extends ConsumerState<ResumeCard> {
  final _focus = FocusNode(debugLabel: 'resume-card');
  final _expanded = <ResumeGroup>{};
  int _sel = 0;

  @override
  void initState() {
    super.initState();
    // R10: the keyboard goes to the first item.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  List<ResumeItem> _shown(ResumeSummary s) => [
    for (final g in ResumeGroup.values)
      ...(_expanded.contains(g) ? s.of(g) : s.of(g).take(resumeGroupLimit)),
  ];

  Future<void> _act(ResumeItem i) async {
    await runResumeAction(context, ref, i);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final items = _shown(widget.summary);
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      unawaited(ref.read(resumeProvider.notifier).close());
      return KeyEventResult.handled;
    }
    if (items.isEmpty) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.arrowDown) {
      setState(() => _sel = (_sel + 1).clamp(0, items.length - 1));
    } else if (k == LogicalKeyboardKey.arrowUp) {
      setState(() => _sel = (_sel - 1).clamp(0, items.length - 1));
    } else if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter) {
      unawaited(_act(items[_sel.clamp(0, items.length - 1)]));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(resumeProvider);
    final s = widget.summary;
    final now = DateTime.now();
    final workspaces = {for (final i in s.all) i.workspaceId}.length
        .clamp(0, 1 << 20);
    final items = _shown(s);
    final sel = items.isEmpty ? -1 : _sel.clamp(0, items.length - 1);
    final selKey = sel < 0 ? null : items[sel].key;
    final title = st.origin == ResumeOrigin.manual
        ? 'O que aconteceu'
        : 'Enquanto você esteve fora';

    Widget group(ResumeGroup g) {
      final all = s.of(g);
      if (all.isEmpty) return const SizedBox.shrink();
      final open = _expanded.contains(g);
      final shown = open ? all : all.take(resumeGroupLimit).toList();
      return Semantics(
        container: true,
        label: '${g.label}, ${all.length}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (g != ResumeGroup.waiting)
              const Divider(height: 8, color: AppColors.border),
            _GroupHeader(
              g,
              all.length,
              manual: st.origin == ResumeOrigin.manual,
            ),
            for (final i in shown)
              ResumeItemRow(
                item: i,
                now: now,
                selected: i.key == selKey,
                onHover: () => setState(() => _sel = items.indexOf(i)),
                onAction: () => _act(i),
              ),
            if (!open && all.length > resumeGroupLimit)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: ValueKey('resume-more-${g.name}'),
                  onPressed: () => setState(() => _expanded.add(g)),
                  child: Text(
                    '+ ${all.length - resumeGroupLimit} em ${g.short}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            if (g == ResumeGroup.running)
              for (final line in s.autopilot)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
                  child: Text(
                    line,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
          ],
        ),
      );
    }

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: title,
        child: Material(
          key: const ValueKey('resume-card'),
          color: AppColors.panelSolid,
          elevation: 18,
          shadowColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            resumeHeaderLine(st, s, now, workspaces),
                            key: const ValueKey('resume-header'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('resume-close'),
                      tooltip: 'Fechar',
                      iconSize: 16,
                      onPressed: () =>
                          ref.read(resumeProvider.notifier).close(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              if (st.githubFailed || st.checkingGithub)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 2),
                  child: Row(
                    children: [
                      Icon(
                        st.checkingGithub ? Icons.sync : Icons.cloud_off,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          st.checkingGithub
                              ? 'Conferindo o GitHub…'
                              : 'Não deu para conferir o GitHub agora.',
                          key: const ValueKey('resume-github'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      if (!st.checkingGithub)
                        TextButton(
                          key: const ValueKey('resume-github-retry'),
                          onPressed: widget.onRetryGithub,
                          child: const Text(
                            'Tentar de novo',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: s.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: Text(
                            'Nada terminou nem espera por você.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final g in ResumeGroup.values) group(g),
                          ],
                        ),
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 14, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: ExcludeSemantics(
                        child: Wrap(
                          spacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _Key('↑↓'),
                            Text(
                              'itens ·',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                            _Key('Enter'),
                            Text(
                              'ação ·',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                            _Key('Esc'),
                            Text(
                              'fechar',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SmallButton(
                      key: const ValueKey('resume-activities'),
                      label: 'Ver tudo na Atividades',
                      onTap: () {
                        unawaited(ref.read(resumeProvider.notifier).close());
                        ref
                            .read(navigationProvider.notifier)
                            .go(AppSection.activities);
                      },
                    ),
                    const SizedBox(width: 8),
                    AmberButton(
                      key: const ValueKey('resume-all-seen'),
                      label: '✓ Tudo visto',
                      onTap: () => ref.read(resumeProvider.notifier).allSeen(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The compact card in the corner (R11): `Voltou? Em 47 min:`.
class ResumeCompact extends ConsumerStatefulWidget {
  const ResumeCompact({super.key, required this.summary});

  final ResumeSummary summary;

  @override
  ConsumerState<ResumeCompact> createState() => _ResumeCompactState();
}

class _ResumeCompactState extends ConsumerState<ResumeCompact> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(ResumeCompact old) {
    super.didUpdateWidget(old);
    if (widget.summary.waiting.isNotEmpty) _timer?.cancel();
  }

  /// Leaves by itself after 20 s, only with nothing waiting (R11).
  void _arm() {
    _timer?.cancel();
    if (widget.summary.waiting.isNotEmpty) return;
    _timer = Timer(compactTimeout, () {
      if (!mounted) return;
      if (widget.summary.waiting.isNotEmpty) return;
      unawaited(ref.read(resumeProvider.notifier).close());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(resumeProvider);
    final s = widget.summary;
    final f = s.finished.length, w = s.waiting.length;
    final robots = [...s.waiting, ...s.finished].take(5).toList();
    final away = st.away == null ? '' : ' Em ${awayLabel(st.away!)}:';
    return MouseRegion(
      onEnter: (_) => _timer?.cancel(),
      onExit: (_) => _arm(),
      child: Semantics(
        container: true,
        label: 'Voltou?$away',
        child: Material(
          key: const ValueKey('resume-compact'),
          color: AppColors.panelSolid,
          elevation: 14,
          shadowColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Voltou?$away',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('resume-compact-close'),
                      tooltip: 'Fechar',
                      iconSize: 15,
                      onPressed: () =>
                          ref.read(resumeProvider.notifier).close(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 10,
                  children: [
                    if (f > 0)
                      Text(
                        '✓ $f ${f == 1 ? 'terminou' : 'terminaram'}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    if (w > 0)
                      Text(
                        '! $w ${w == 1 ? 'espera' : 'esperam'} por você',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.amber,
                        ),
                      ),
                    if (f == 0 && w == 0 && s.running.isNotEmpty)
                      Text(
                        '${s.running.length} rodando',
                        style: const TextStyle(fontSize: 13),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final i in robots) ResumeAvatar(item: i, size: 22),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: AmberButton(
                        key: const ValueKey('resume-compact-view'),
                        label: 'Ver',
                        onTap: () => ref.read(resumeProvider.notifier).expand(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  w > 0
                      ? 'Com algo esperando, o cartão fica até você fechar.'
                      : 'Some sozinho em 20 s.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
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
