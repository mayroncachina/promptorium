import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/shell/footer_stats.dart' show formatTokens;
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../session_changes.dart';
import '../session_manager.dart';
import '../timeline.dart';
import 'session_style.dart';

/// Right column: approvals of every session, details and changed files of the
/// selected one.
class SessionSidePanel extends ConsumerWidget {
  const SessionSidePanel({super.key, required this.session});

  final Session? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final approvals = ref.watch(sessionManagerProvider).approvals;
    final s = session;
    return ColoredBox(
      color: AppColors.panel,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'APROVAÇÕES PENDENTES · ${approvals.length}',
            style: sectionTitleStyle,
          ),
          const SizedBox(height: 10),
          if (approvals.isEmpty)
            const Text(
              'Nada aguardando.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          for (final a in approvals) ...[
            ApprovalCard(approval: a),
            const SizedBox(height: 8),
          ],
          if (s != null) ...[
            const SizedBox(height: 18),
            const Text('DETALHES', style: sectionTitleStyle),
            const SizedBox(height: 10),
            _Details(session: s),
            const SizedBox(height: 18),
            const Text('ARQUIVOS ALTERADOS', style: sectionTitleStyle),
            const SizedBox(height: 10),
            _ChangedFiles(sessionId: s.id),
          ],
        ],
      ),
    );
  }
}

String approvalVerb(String tool) => switch (tool) {
  'Bash' => 'quer executar',
  'Edit' || 'Write' || 'MultiEdit' || 'NotebookEdit' => 'quer editar',
  'Read' || 'Glob' || 'Grep' => 'quer ler',
  'WebFetch' || 'WebSearch' => 'quer acessar',
  _ => 'quer usar $tool',
};

/// "Sempre permitir …" text for the first `permission_suggestion`.
String? alwaysAllowLabel(List<Map<String, dynamic>> suggestions) {
  if (suggestions.isEmpty) return null;
  final s = suggestions.first;
  final where = switch (s['destination']) {
    'session' => ' nesta sessão',
    'localSettings' => ' neste projeto (local)',
    'projectSettings' => ' no projeto',
    'userSettings' => ' em todos os projetos',
    _ => '',
  };
  final rules = s['rules'];
  if (s['type'] == 'addRules' && rules is List && rules.isNotEmpty) {
    final names = [
      for (final r in rules)
        if (r is Map)
          r['ruleContent'] is String && (r['ruleContent'] as String).isNotEmpty
              ? '${r['toolName']}(${r['ruleContent']})'
              : '${r['toolName']}',
    ];
    return 'Sempre permitir ${names.join(', ')}$where';
  }
  if (s['type'] == 'setMode' && s['mode'] is String) {
    return 'Mudar para o modo ${s['mode']}$where';
  }
  return 'Sempre permitir$where';
}

/// One pending approval. Answers go to [SessionManager] unless [onApprove] /
/// [onDeny] are given (Prompt conversations reuse the card inline).
class ApprovalCard extends ConsumerStatefulWidget {
  const ApprovalCard({
    super.key,
    required this.approval,
    this.onApprove,
    this.onDeny,
    this.onOpen,
  });

  final PendingApproval approval;

  /// `always` = "Sempre permitir" (first permission suggestion).
  final Future<void> Function({required bool always})? onApprove;
  final Future<void> Function()? onDeny;

  /// Tap on the header (default: select the session).
  final VoidCallback? onOpen;

  @override
  ConsumerState<ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends ConsumerState<ApprovalCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function(SessionManager m) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(ref.read(sessionManagerProvider.notifier));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve({required bool always}) {
    final custom = widget.onApprove;
    final a = widget.approval;
    if (custom == null) {
      return _run((m) => m.approve(a.sessionId, a.requestId, always: always));
    }
    return _guard(() => custom(always: always));
  }

  Future<void> _deny() {
    final custom = widget.onDeny;
    final a = widget.approval;
    if (custom == null) return _run((m) => m.deny(a.sessionId, a.requestId));
    return _guard(custom);
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.approval;
    final r = a.request;
    final stats = editStats(r.toolName, r.input);
    final always = alwaysAllowLabel(r.permissionSuggestions);
    return Container(
      key: ValueKey('approval-${a.requestId}'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SessionColors.approvalBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SessionColors.approvalBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap:
                widget.onOpen ??
                () => ref
                    .read(selectedSessionProvider.notifier)
                    .select(a.sessionId),
            child: Text(
              '${a.sessionTitle} · ${approvalVerb(r.toolName)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.amber),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: toolTarget(r.toolName, r.input)),
                  if (stats != null)
                    TextSpan(
                      text: '  +${stats.$1}',
                      style: const TextStyle(color: AppColors.teal),
                    ),
                ],
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: AppColors.text,
              ),
            ),
          ),
          if (r.description != null && r.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.description!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SmallButton(
                  key: ValueKey('deny-${a.requestId}'),
                  label: 'Negar',
                  expand: true,
                  onTap: _busy ? null : _deny,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: AmberButton(
                  key: ValueKey('approve-${a.requestId}'),
                  label: 'Aprovar',
                  expand: true,
                  onTap: _busy ? null : () => _approve(always: false),
                ),
              ),
            ],
          ),
          if (always != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                key: ValueKey('always-${a.requestId}'),
                onTap: _busy ? null : () => _approve(always: true),
                child: Text(
                  always,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Spec / task of a session ("SPEC-001 Shell", or the task code).
final _sessionSpecProvider = FutureProvider.family<String?, int>((
  ref,
  taskId,
) async {
  final task = await ref.read(tasksRepoProvider).getById(taskId);
  if (task == null) return null;
  final spec = task.specId == null
      ? null
      : await ref.read(specsRepoProvider).getById(task.specId!);
  return spec == null
      ? '${task.code} ${task.title}'
      : '${spec.code} ${spec.title} · ${task.code}';
});

class _Details extends ConsumerStatefulWidget {
  const _Details({required this.session});

  final Session session;

  @override
  ConsumerState<_Details> createState() => _DetailsState();
}

class _DetailsState extends ConsumerState<_Details> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(_Details old) {
    super.didUpdateWidget(old);
    _syncTimer();
  }

  /// Ticks the duration once per second while the session runs.
  void _syncTimer() {
    final live = widget.session.endedAt == null;
    if (live && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!live) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final spec = s.taskId == null
        ? null
        : ref.watch(_sessionSpecProvider(s.taskId!)).value;
    final dur = (s.endedAt ?? DateTime.now()).difference(s.startedAt);
    final shortId = s.id.length > 12
        ? '${s.id.substring(0, 4)}…${s.id.substring(s.id.length - 4)}'
        : s.id;
    const label = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    const value = TextStyle(fontSize: 12, color: AppColors.text);
    const mono = TextStyle(
      fontSize: 12,
      fontFamily: AppFonts.mono,
      color: AppColors.text,
    );
    Widget row(String k, Widget v) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(k, style: label)),
          const SizedBox(width: 8),
          Expanded(child: v),
        ],
      ),
    );
    return Column(
      children: [
        row('Spec', Text(spec ?? '—', style: value)),
        row('Duração', Text(formatDuration(dur), style: mono)),
        row(
          'Tokens',
          Tooltip(
            message: 'entrada (com cache) ${s.tokensIn} · saída ${s.tokensOut}',
            child: Text(formatTokens(s.tokensIn + s.tokensOut), style: mono),
          ),
        ),
        row('Custo', Text(formatCost(s.costUsd), style: mono)),
        row(
          'Session ID',
          InkWell(
            key: const ValueKey('copy-session-id'),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: s.id));
              if (context.mounted) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(content: Text('Session ID copiado')),
                );
              }
            },
            child: Tooltip(
              message: 'Copiar ${s.id}',
              child: Text(
                '$shortId ⧉',
                style: mono.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChangedFiles extends ConsumerWidget {
  const _ChangedFiles({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final changes = ref.watch(sessionChangesProvider(sessionId));
    const mono = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 12,
      color: AppColors.text,
    );
    final body = changes.when(
      loading: () => const Text('…', style: mono),
      error: (e, _) => Text('$e', style: mono.copyWith(color: AppColors.red)),
      data: (c) {
        if (c.error != null) {
          return Text(
            c.error!,
            style: mono.copyWith(color: AppColors.red, fontSize: 11),
          );
        }
        if (c.entries.isEmpty) {
          return const Text(
            'Nenhuma alteração.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final e in c.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono,
                      ),
                    ),
                    ..._stats(c.numstat[e.path], e.isUntracked),
                  ],
                ),
              ),
          ],
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        body,
        const SizedBox(height: 10),
        InkWell(
          onTap: () =>
              ref.read(navigationProvider.notifier).go(AppSection.review),
          child: const Text(
            'Abrir no Review',
            style: TextStyle(fontSize: 12, color: AppColors.blue),
          ),
        ),
      ],
    );
  }

  static List<Widget> _stats((int, int)? n, bool untracked) {
    const mono = TextStyle(fontFamily: AppFonts.mono, fontSize: 12);
    if (untracked) {
      return [
        const SizedBox(width: 8),
        Text('novo', style: mono.copyWith(color: AppColors.teal)),
      ];
    }
    if (n == null) return const [];
    if (n.$1 < 0) {
      return [
        const SizedBox(width: 8),
        Text('bin', style: mono.copyWith(color: AppColors.textSecondary)),
      ];
    }
    return [
      if (n.$1 > 0) ...[
        const SizedBox(width: 8),
        Text('+${n.$1}', style: mono.copyWith(color: AppColors.teal)),
      ],
      if (n.$2 > 0) ...[
        const SizedBox(width: 8),
        Text('−${n.$2}', style: mono.copyWith(color: AppColors.red)),
      ],
    ];
  }
}
