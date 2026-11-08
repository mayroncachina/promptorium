import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../review/review_service.dart' show selectedReviewProvider;
import '../../sessions/widgets/session_style.dart';
import '../releases/releases_tab.dart' show GhStatusLabel, formatBytes, plural;
import '../repository_info.dart';
import '../repository_screen.dart';
import 'hygiene_cleaner.dart';
import 'hygiene_scan.dart';
import 'hygiene_state.dart';

/// The Higiene tab (SPEC-047; docs/mockups/spec-047/1-higiene.png).
final higieneTab = RepositoryTab(
  id: 'higiene',
  label: 'Higiene',
  builder: (context, repo) => HigieneTab(repo: repo),
  count: (ref, repo) =>
      ref.watch(hygieneProvider(repo).select((s) => s.report?.total)),
  headerTrailing: (context, repo) => GhStatusLabel(repo: repo),
);

/// Rows shown per group before "Mostrar as outras N".
const _preview = 5;

const _months = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

/// `7 nov` (this year) or `7 nov 2025`.
String shortDate(DateTime? d, {DateTime? now}) {
  if (d == null) return '';
  final l = d.toLocal();
  final year = (now ?? DateTime.now()).year;
  return '${l.day} ${_months[l.month - 1]}${l.year == year ? '' : ' ${l.year}'}';
}

/// `Analisado agora` / `Analisado há 3 min` / `Analisado há 2 h`.
String scannedAgo(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'Analisado agora';
  if (d.inHours < 1) return 'Analisado há ${d.inMinutes} min';
  return 'Analisado há ${d.inHours} h';
}

/// The summary line under the header.
String hygieneSummaryLine(HygieneReport r, DateTime now) {
  final parts = [
    plural(r.merged.length, 'branch mergeada', 'branches mergeadas'),
    plural(r.worktrees.length, 'worktree', 'worktrees'),
    '${plural(r.behind.length, 'branch atrás', 'branches atrás')} da '
        '${r.defaultBranch}',
    'refs de ${plural(r.refs.length, 'spec', 'specs')}',
  ];
  final gh = r.ghAvailable
      ? ''
      : ' · sem gh, as mergeadas por squash não aparecem';
  return '${scannedAgo(r.scannedAt, now)} · ${parts.join(', ')}$gh';
}

/// What the toast says after a cleanup (R7).
String cleanupMessage(CleanupOutcome o) {
  final what = [
    if (o.worktrees.isNotEmpty)
      plural(o.worktrees.length, 'worktree', 'worktrees'),
    if (o.branches.isNotEmpty) plural(o.branches.length, 'branch', 'branches'),
  ];
  final parts = <String>[
    if (what.isNotEmpty)
      '${what.join(' e ')} ${o.worktrees.length + o.branches.length == 1 ? 'removido' : 'removidos'}',
    if (o.remoteBranches.isNotEmpty)
      plural(o.remoteBranches.length, 'remota apagada', 'remotas apagadas'),
    if (o.refs.isNotEmpty)
      'refs de ${plural(o.refs.length, 'spec', 'specs')} apagadas',
    if (o.freedBytes > 0) '${formatBytes(o.freedBytes)} livres',
    if (o.errors.isNotEmpty)
      '${plural(o.errors.length, 'item recusado', 'itens recusados')} pelo git',
  ];
  return parts.isEmpty ? 'Nada foi removido.' : parts.join(' · ');
}

class HigieneTab extends ConsumerStatefulWidget {
  const HigieneTab({super.key, required this.repo});

  final RepositoryInfo repo;

  @override
  ConsumerState<HigieneTab> createState() => _HigieneTabState();
}

class _HigieneTabState extends ConsumerState<HigieneTab> {
  bool _allMerged = false;
  bool _allWorktrees = false;

  HygieneController get _ctl => ref.read(hygieneProvider(widget.repo).notifier);

  @override
  void initState() {
    super.initState();
    // R1: the scan runs when the tab opens.
    Future.microtask(() {
      if (mounted) _ctl.scan();
    });
  }

  Future<void> _clean(HygieneState s) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final deleteRemote = await showCleanupDialog(
      context,
      state: s,
      onGitHub: widget.repo.githubSlug != null,
    );
    if (deleteRemote == null || !mounted) return;
    final outcome = await _ctl.clean(deleteRemote: deleteRemote);
    if (outcome == null) return;
    _toast(messenger, outcome);
  }

  Future<void> _cleanRefs(List<RefGroup> groups) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final outcome = await _ctl.cleanRefs(groups);
    if (outcome == null) return;
    _toast(messenger, outcome);
  }

  void _toast(ScaffoldMessengerState? messenger, CleanupOutcome outcome) {
    final ctl = _ctl;
    messenger?.hideCurrentSnackBar();
    messenger?.showAppToast(
      SnackBar(
        key: const ValueKey('hygiene-toast'),
        behavior: SnackBarBehavior.floating,
        width: 460,
        duration: outcome.undoable
            ? HygieneCleaner.undoWindow
            : const Duration(seconds: 6),
        content: CleanupToast(
          outcome: outcome,
          onUndo: outcome.undoable
              ? () async {
                  messenger.hideCurrentSnackBar();
                  try {
                    final u = await ctl.undo();
                    if (u == null) return;
                    messenger.showAppToast(
                      SnackBar(
                        key: const ValueKey('hygiene-undone'),
                        content: Text(
                          u.errors.isEmpty
                              ? 'Desfeito: ${[if (u.branches.isNotEmpty) plural(u.branches.length, 'branch', 'branches'), if (u.worktrees.isNotEmpty) plural(u.worktrees.length, 'worktree', 'worktrees')].join(' e ')} de volta.'
                              : 'Desfeito em parte: ${u.errors.join('; ')}',
                        ),
                      ),
                    );
                  } on UndoExpiredException catch (e) {
                    messenger.showAppToast(SnackBar(content: Text('$e')));
                  }
                }
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(hygieneProvider(widget.repo));
    final r = s.report;
    if (r == null) {
      return Center(
        child: s.error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Não foi possível analisar o repositório: ${s.error}',
                    key: const ValueKey('hygiene-error'),
                    style: const TextStyle(color: AppColors.red, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  SmallButton(label: 'Tentar de novo', onTap: _ctl.scan),
                ],
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Analisando branches e worktrees…',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
      );
    }
    final count = s.selectionCount;
    return SingleChildScrollView(
      key: const ValueKey('hygiene-body'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  hygieneSummaryLine(r, DateTime.now()),
                  key: const ValueKey('hygiene-summary'),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (s.error != null) ...[
                Flexible(
                  child: Text(
                    s.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.red),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              SmallButton(
                key: const ValueKey('hygiene-rescan'),
                label: s.scanning ? 'Analisando…' : 'Analisar de novo',
                height: 40,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                onTap: s.scanning || s.cleaning ? null : _ctl.scan,
              ),
              const SizedBox(width: 12),
              AmberButton(
                key: const ValueKey('hygiene-clean'),
                label: 'Limpar selecionados ($count)',
                height: 40,
                fontSize: 14,
                busy: s.cleaning,
                onTap: count == 0 || s.cleaning || s.scanning
                    ? null
                    : () => _clean(s),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, c) {
              final left = [
                _MergedCard(
                  state: s,
                  expanded: _allMerged,
                  onExpand: () => setState(() => _allMerged = true),
                  ctl: _ctl,
                ),
                const SizedBox(height: 16),
                _WorktreesCard(
                  state: s,
                  expanded: _allWorktrees,
                  onExpand: () => setState(() => _allWorktrees = true),
                  ctl: _ctl,
                ),
              ];
              final right = [
                _BehindCard(report: r),
                const SizedBox(height: 16),
                _RefsCard(
                  report: r,
                  errors: s.errors,
                  busy: s.cleaning,
                  onClean: _cleanRefs,
                ),
              ];
              if (c.maxWidth < 900) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [...left, const SizedBox(height: 16), ...right],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 86,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: left,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 46,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: right,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// --- cards ----------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({super.key, required this.header, required this.children});

  final Widget header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: header,
        ),
        for (final c in children) ...[
          const Divider(height: 1, thickness: 1, color: AppColors.border),
          c,
        ],
      ],
    ),
  );
}

/// `Branches mergeadas · 64`.
class _CardTitle extends StatelessWidget {
  const _CardTitle(this.title, this.count);

  final String title;
  final String count;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        TextSpan(
          text: ' · $count',
          style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

class _Box extends StatelessWidget {
  const _Box({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  /// Null = some (tristate header).
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 28,
    child: Checkbox(
      value: value,
      tristate: value == null,
      semanticLabel: semanticLabel,
      activeColor: AppColors.amber,
      checkColor: AppColors.onAmber,
      side: BorderSide(
        color: onChanged == null ? AppColors.border : AppColors.textSecondary,
        width: 1.5,
      ),
      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
    ),
  );
}

class _ShowMore extends StatelessWidget {
  const _ShowMore({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.blue),
        ),
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
    ),
  );
}

bool? _tri(int on, int total) => on == 0
    ? false
    : on == total
    ? true
    : null;

const _mono = TextStyle(fontFamily: AppFonts.mono, fontSize: 13);

class _MergedCard extends StatelessWidget {
  const _MergedCard({
    required this.state,
    required this.expanded,
    required this.onExpand,
    required this.ctl,
  });

  final HygieneState state;
  final bool expanded;
  final VoidCallback onExpand;
  final HygieneController ctl;

  @override
  Widget build(BuildContext context) {
    final all = state.report!.merged;
    final selectable = [
      for (final b in all)
        if (state.branchSelectable(b)) b.id,
    ];
    final on = selectable.where(state.selected.contains).length;
    final rows = expanded ? all : all.take(_preview).toList();
    final hasRemote = all.any((b) => b.remoteRef != null);
    return _Card(
      key: const ValueKey('hygiene-merged'),
      header: Row(
        children: [
          _Box(
            key: const ValueKey('hygiene-merged-all'),
            value: _tri(on, selectable.length),
            semanticLabel: 'Selecionar todas as branches mergeadas',
            onChanged: selectable.isEmpty
                ? null
                : (v) => ctl.toggleAll(selectable, on < selectable.length),
          ),
          const SizedBox(width: 10),
          Expanded(child: _CardTitle('Branches mergeadas', '${all.length}')),
          if (hasRemote)
            const Text(
              'também no remoto',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
        ],
      ),
      children: [
        if (all.isEmpty) const _Empty('Nenhuma branch mergeada para limpar.'),
        for (final b in rows)
          _MergedRow(branch: b, state: state, ctl: ctl, hasRemote: hasRemote),
        if (!expanded && all.length > _preview)
          _ShowMore(
            key: const ValueKey('hygiene-merged-more'),
            label: 'Mostrar as outras ${all.length - _preview}',
            onTap: onExpand,
          ),
      ],
    );
  }
}

class _MergedRow extends StatelessWidget {
  const _MergedRow({
    required this.branch,
    required this.state,
    required this.ctl,
    required this.hasRemote,
  });

  final MergedBranch branch;
  final HygieneState state;
  final HygieneController ctl;
  final bool hasRemote;

  @override
  Widget build(BuildContext context) {
    final b = branch;
    final ok = state.branchSelectable(b);
    final error = state.errors[b.id] ?? state.errors['remote:${b.name}'];
    final meta = !ok
        ? b.protection!.reason
        : [
            ?b.spec,
            if (b.bySquash)
              'mergeada por squash'
            else if (b.pr != null)
              'PR #${b.pr}',
          ].join(' · ');
    final dim = ok ? 1.0 : 0.5;
    return Padding(
      key: ValueKey('hygiene-branch-${b.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _Box(
            key: ValueKey('hygiene-branch-box-${b.name}'),
            value: ok && state.selected.contains(b.id),
            semanticLabel: 'Apagar ${b.name}',
            onChanged: ok ? (v) => ctl.toggle(b.id, v) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 5,
            child: Opacity(
              opacity: dim,
              child: Text(
                b.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _mono,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Tooltip(
              message: error ?? '',
              child: Text(
                error == null ? meta : 'git recusou: $error',
                key: ValueKey('hygiene-branch-meta-${b.name}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: error != null
                      ? AppColors.red
                      : ok
                      ? AppColors.textSecondary
                      : AppColors.amber.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 72,
            child: Opacity(
              opacity: dim,
              child: Text(
                shortDate(b.date),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          if (hasRemote)
            SizedBox(
              width: 56,
              child: b.remoteRef == null
                  ? null
                  : Center(
                      child: _Box(
                        key: ValueKey('hygiene-remote-box-${b.name}'),
                        value: ok && state.remote.contains(b.name),
                        semanticLabel: 'Apagar também ${b.remoteRef}',
                        onChanged: ok
                            ? (v) => ctl.toggleRemote(b.name, v)
                            : null,
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

class _WorktreesCard extends StatelessWidget {
  const _WorktreesCard({
    required this.state,
    required this.expanded,
    required this.onExpand,
    required this.ctl,
  });

  final HygieneState state;
  final bool expanded;
  final VoidCallback onExpand;
  final HygieneController ctl;

  @override
  Widget build(BuildContext context) {
    final r = state.report!;
    final all = r.worktrees;
    final selectable = [
      for (final w in all)
        if (w.protection == null) w.id,
    ];
    final on = selectable.where(state.selected.contains).length;
    final rows = expanded ? all : all.take(_preview).toList();
    final size = r.worktreeBytes;
    return _Card(
      key: const ValueKey('hygiene-worktrees'),
      header: Row(
        children: [
          _Box(
            key: const ValueKey('hygiene-worktrees-all'),
            value: _tri(on, selectable.length),
            semanticLabel: 'Selecionar todos os worktrees',
            onChanged: selectable.isEmpty
                ? null
                : (v) {
                    final turnOn = on < selectable.length;
                    for (final id in selectable) {
                      ctl.toggle(id, turnOn);
                    }
                  },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _CardTitle(
              'Worktrees',
              size > 0
                  ? '${all.length} · ${formatBytes(size)}'
                  : '${all.length}',
            ),
          ),
        ],
      ),
      children: [
        if (all.isEmpty) const _Empty('Nenhum worktree para limpar.'),
        for (final w in rows) _WorktreeRow(item: w, state: state, ctl: ctl),
        if (!expanded && all.length > _preview)
          _ShowMore(
            key: const ValueKey('hygiene-worktrees-more'),
            label: 'Mostrar os outros ${all.length - _preview}',
            onTap: onExpand,
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color, {super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
    ),
  );
}

class _WorktreeRow extends StatelessWidget {
  const _WorktreeRow({
    required this.item,
    required this.state,
    required this.ctl,
  });

  final WorktreeItem item;
  final HygieneState state;
  final HygieneController ctl;

  @override
  Widget build(BuildContext context) {
    final w = item;
    final ok = w.protection == null;
    final error = state.errors[w.id];
    final days = w.lastCommit == null
        ? null
        : DateTime.now().difference(w.lastCommit!).inDays;
    final (label, color) = !ok
        ? (w.protection!.reason, AppColors.red)
        : switch (w.kind) {
            WorktreeKind.orphan => (
              'órfão: a pasta não existe',
              AppColors.lilac,
            ),
            WorktreeKind.closed => ('de spec fechada', AppColors.blue),
            WorktreeKind.stale => ('parado há $days dias', AppColors.amber),
          };
    return Padding(
      key: ValueKey('hygiene-worktree-${w.path}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Opacity(
        opacity: ok ? 1 : 0.5,
        child: Row(
          children: [
            _Box(
              value: ok && state.selected.contains(w.id),
              semanticLabel: 'Remover ${w.path}',
              onChanged: ok ? (v) => ctl.toggle(w.id, v) : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tildePath(w.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _mono,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    error != null
                        ? 'git recusou: $error'
                        : w.branch ?? 'HEAD destacado',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: error != null ? null : AppFonts.mono,
                      fontSize: 12,
                      color: error != null
                          ? AppColors.red
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _Pill(label, color, key: ValueKey('hygiene-pill-${w.path}')),
            SizedBox(
              width: 82,
              child: Text(
                formatBytes(w.sizeBytes),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BehindCard extends ConsumerWidget {
  const _BehindCard({required this.report});

  final HygieneReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = report.behind;
    return _Card(
      key: const ValueKey('hygiene-behind'),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle('Atrás da ${report.defaultBranch}', '${rows.length}'),
          const SizedBox(height: 2),
          const Text(
            'Só informa. Atualizar a base é no Review.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
      children: [
        if (rows.isEmpty)
          _Empty('Nenhuma branch aberta atrás da ${report.defaultBranch}.'),
        for (final b in rows)
          Padding(
            key: ValueKey('hygiene-behind-${b.name}'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        b.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _mono,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${b.behind} atrás · ${b.ahead} à frente',
                      style: TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 12,
                        color: (b.conflict?.files.isNotEmpty ?? false)
                            ? AppColors.amber
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (b.conflict case final c?) ...[
                  if (c.error != null)
                    Text(
                      'Conflito não verificado: ${c.error}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    )
                  else if (c.files.isEmpty)
                    const Text(
                      'Sem conflito previsto',
                      style: TextStyle(fontSize: 13, color: AppColors.teal),
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 15,
                          color: AppColors.red,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Conflito previsto em ${c.files.join(', ')}',
                            key: ValueKey('hygiene-conflict-${b.name}'),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
                if (b.sessionId != null &&
                    (b.conflict?.files.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IntrinsicWidth(
                      child: SmallButton(
                        key: ValueKey('hygiene-review-${b.name}'),
                        label: 'Abrir no Review',
                        height: 34,
                        fontSize: 13,
                        onTap: () {
                          ref
                              .read(selectedReviewProvider.notifier)
                              .select(b.sessionId);
                          ref
                              .read(navigationProvider.notifier)
                              .go(AppSection.review);
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _RefsCard extends StatelessWidget {
  const _RefsCard({
    required this.report,
    required this.errors,
    required this.busy,
    required this.onClean,
  });

  final HygieneReport report;
  final Map<String, String> errors;
  final bool busy;
  final void Function(List<RefGroup>) onClean;

  @override
  Widget build(BuildContext context) {
    final groups = report.refs;
    return _Card(
      key: const ValueKey('hygiene-refs'),
      header: Row(
        children: [
          Expanded(
            child: _CardTitle(
              'Refs internas',
              plural(groups.length, 'spec', 'specs'),
            ),
          ),
          if (groups.isNotEmpty)
            SmallButton(
              key: const ValueKey('hygiene-refs-all'),
              label: 'Limpar todas',
              height: 34,
              fontSize: 13,
              onTap: busy ? null : () => onClean(groups),
            ),
        ],
      ),
      children: [
        if (groups.isEmpty) const _Empty('Nenhuma ref de spec fechada.'),
        for (final g in groups)
          Padding(
            key: ValueKey('hygiene-ref-${g.key}'),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 94,
                  child: Text(
                    g.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    errors['refs:${g.key}'] ??
                        '${plural(g.refs.length, 'ref', 'refs')} · '
                            '${g.deleted
                                ? 'apagada'
                                : g.mergedAt == null
                                ? 'mergeada'
                                : 'mergeada em ${shortDate(g.mergedAt)}'}',
                    style: TextStyle(
                      fontSize: 13,
                      color: errors.containsKey('refs:${g.key}')
                          ? AppColors.red
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                InkWell(
                  key: ValueKey('hygiene-ref-clean-${g.key}'),
                  onTap: busy ? null : () => onClean([g]),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      'Limpar',
                      style: TextStyle(fontSize: 13, color: AppColors.blue),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Text(
            'refs/promptorium/<spec>/ guarda os pontos de volta das etapas. '
            'Specs mergeadas não precisam mais deles. Não voltam com o '
            'Desfazer.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

// --- confirmation and toast ---------------------------------------------------

/// "Limpar N itens?" (docs/mockups/spec-047/2-limpar.png). Returns whether
/// to delete on the remote too, or null when cancelled.
Future<bool?> showCleanupDialog(
  BuildContext context, {
  required HygieneState state,
  bool onGitHub = true,
}) {
  final worktrees = state.selectedWorktrees;
  final branches = state.selectedBranches;
  final remote = state.selectedRemote;
  final n = state.selectionCount;
  final bytes = worktrees.fold(0, (a, w) => a + (w.sizeBytes ?? 0));
  final where = onGitHub ? 'no GitHub' : 'no remoto';
  var deleteRemote = false;
  const label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: AppColors.textSecondary,
  );
  return showAppDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Dialog(
        key: const ValueKey('hygiene-confirm'),
        backgroundColor: AppColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Limpar ${plural(n, 'item', 'itens')}?',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${bytes > 0 ? 'Libera ${formatBytes(bytes)}. ' : ''}Nada '
                  'com alterações não commitadas ou sessão viva entra aqui.',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (worktrees.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text('WORKTREES · ${worktrees.length}', style: label),
                  const SizedBox(height: 6),
                  for (final w in worktrees)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              tildePath(w.path),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: AppFonts.mono,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            formatBytes(w.sizeBytes),
                            style: const TextStyle(
                              fontFamily: AppFonts.mono,
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (branches.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'BRANCHES LOCAIS · ${branches.length} · git branch -d',
                    style: label,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    branches.map((b) => b.name).join(', '),
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ],
                if (remote.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.red.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Box(
                          key: const ValueKey('hygiene-confirm-remote'),
                          value: deleteRemote,
                          semanticLabel: 'Apagar também $where',
                          onChanged: (v) => setState(() => deleteRemote = v),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text.rich(
                              TextSpan(
                                style: const TextStyle(fontSize: 13),
                                children: [
                                  TextSpan(
                                    text: 'Apagar também $where',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  TextSpan(
                                    text:
                                        ' ${remote.length == 1 ? 'a branch remota' : 'as ${remote.length} branches remotas'} '
                                        '(${remote.map((b) => b.remoteRef).join(', ')}). '
                                        'Afeta quem usa o repositório e não volta '
                                        'com o Desfazer.',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Por 15 s, "Desfazer" recria as branches locais nos mesmos '
                  'commits e os worktrees. Se o git recusar apagar uma '
                  'branch, ela fica na lista com o motivo e não é forçada.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SmallButton(
                      key: const ValueKey('hygiene-confirm-cancel'),
                      label: 'Cancelar',
                      height: 40,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    AmberButton(
                      key: const ValueKey('hygiene-confirm-ok'),
                      label: 'Limpar ${plural(n, 'item', 'itens')}',
                      height: 40,
                      fontSize: 14,
                      onTap: () => Navigator.of(context).pop(deleteRemote),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// What the cleanup removed and "Desfazer · 12 s" (R7).
class CleanupToast extends StatefulWidget {
  const CleanupToast({super.key, required this.outcome, this.onUndo});

  final CleanupOutcome outcome;
  final VoidCallback? onUndo;

  @override
  State<CleanupToast> createState() => _CleanupToastState();
}

class _CleanupToastState extends State<CleanupToast> {
  Timer? _timer;
  late int _left = HygieneCleaner.undoWindow.inSeconds;

  @override
  void initState() {
    super.initState();
    if (widget.onUndo != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() => _left = (_left - 1).clamp(0, 99));
        if (_left == 0) t.cancel();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        widget.outcome.errors.isEmpty ? Icons.check : Icons.info_outline,
        size: 18,
        color: widget.outcome.errors.isEmpty ? AppColors.teal : AppColors.amber,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          cleanupMessage(widget.outcome),
          key: const ValueKey('hygiene-toast-text'),
          style: const TextStyle(fontSize: 13),
        ),
      ),
      if (widget.onUndo != null && _left > 0) ...[
        const SizedBox(width: 12),
        SmallButton(
          key: const ValueKey('hygiene-undo'),
          label: 'Desfazer · $_left s',
          height: 34,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          onTap: widget.onUndo,
        ),
      ],
    ],
  );
}

// --- Início card (R8) ------------------------------------------------------------

/// "Repositório com 31 itens para limpar" on the Início, above
/// [hygieneCardThreshold], until dismissed for 30 days.
class HygieneHomeCard extends ConsumerWidget {
  const HygieneHomeCard({super.key, required this.workspacePath, this.now});

  final String workspacePath;

  /// Clock of the dismissal (tests).
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryInfoProvider(workspacePath)).value;
    if (repo == null) return const SizedBox.shrink();
    final count = ref.watch(hygieneSummaryProvider(repo.path)).value;
    final settings = ref.watch(appSettingsProvider);
    final at = (now ?? DateTime.now)();
    if (count == null ||
        count <= hygieneCardThreshold ||
        hygieneDismissed(settings, repo.path, at)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Material(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: const ValueKey('home-hygiene'),
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            ref.read(repositoryTabProvider.notifier).select('higiene');
            ref.read(navigationProvider.notifier).go(AppSection.repository);
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.cleaning_services_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Repositório com $count itens para limpar',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const Text(
                  'Abrir Higiene',
                  style: TextStyle(fontSize: 13, color: AppColors.blue),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const ValueKey('home-hygiene-dismiss'),
                  tooltip: 'Dispensar por 30 dias',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  color: AppColors.textSecondary,
                  icon: const Icon(Icons.close),
                  onPressed: () => ref
                      .read(appSettingsProvider.notifier)
                      .set(
                        hygieneDismissKey(repo.path),
                        at.add(hygieneDismissal).toIso8601String(),
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
