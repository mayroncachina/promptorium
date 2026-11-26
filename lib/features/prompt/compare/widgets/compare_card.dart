import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/claude/claude_args.dart' show ClaudePermissionMode;
import '../../../../core/claude/claude_cli.dart';
import '../../../../core/codex/codex_cli.dart';
import '../../../../core/codex/codex_command.dart';
import '../../../../core/system/worktree_launcher.dart';
import '../../../../ui/providers/provider_logos.dart';

import '../../../../ui/theme/tokens.dart';
import '../../../../ui/widgets/app_toast.dart';
import '../../../sessions/timeline.dart';
import '../../../sessions/widgets/timeline_view.dart';
import '../compare_run.dart';
import '../compare_weight.dart';
import 'compare_bar.dart';

String _quote(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// The command that opens the session of [side] in a terminal (SPEC-108
/// R9): `claude --resume <id>`, or `codex resume <thread>` read only. Null
/// without a session.
String? compareTerminalCommand(
  CompareSide side, {
  required String claude,
  required String codex,
}) {
  final id = side.sessionId;
  if (!side.started || id == null || id.isEmpty) return null;
  return side.provider == 'codex'
      ? [
          codex,
          ...codexCommandArgs(
            threadId: id,
            model: side.model,
            permissionMode: ClaudePermissionMode.plan,
          ),
        ].map(_quote).join(' ')
      : [claude, '--resume', id].map(_quote).join(' ');
}

/// The folded comparison in the conversation (R11): the side chosen, the
/// metrics of both and "Ver a resposta" of the other, read only.
class CompareCard extends ConsumerStatefulWidget {
  const CompareCard({super.key, required this.item, this.root});

  final CompareItem item;
  final String? root;

  @override
  ConsumerState<CompareCard> createState() => _CompareCardState();
}

class _CompareCardState extends ConsumerState<CompareCard> {
  bool _open = false;
  List<TimelineItem>? _otherItems;

  /// "Abrir no terminal": the app only opens it and does not follow.
  Future<void> _openTerminal(String command) async {
    final root = widget.root;
    if (root == null) return;
    final used = await ref
        .read(worktreeLauncherProvider)
        .terminal(root, command);
    if (!mounted || used != null) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showAppToast(
        SnackBar(content: Text('Nenhum terminal encontrado. Rode: $command')),
      );
  }

  @override
  Widget build(BuildContext context) {
    // Before SPEC-108 the event had no provider and Comparar only ran on
    // the Claude Code.
    final run = CompareRun.fromJson(widget.item.data, conversationId: 0);
    final chosen = run?.chosenSide;
    final other = run?.otherSide;
    if (run == null || chosen == null || other == null) {
      return Text(
        widget.item.text,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      );
    }
    const head = TextStyle(fontSize: 11, color: AppColors.textSecondary);
    const cell = TextStyle(
      fontSize: 12,
      fontFamily: AppFonts.mono,
      color: AppColors.text,
    );
    TableRow row(CompareSide s) {
      final m = s.metrics;
      final w = s.weight;
      return TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                CompareLetter(s.letter, size: 18),
                const SizedBox(width: 8),
                if (run.crossProvider) ...[
                  ProviderChip(s.provider, dense: true),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: s.modelLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.text,
                          ),
                        ),
                        if (s.letter != run.chosen)
                          const TextSpan(
                            text: '  (não escolhida)',
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Text(m == null ? '—' : compareDuration(m.durationMs), style: cell),
          Text(m == null ? '—' : compareTokensLine(m), style: cell),
          Text(w == null ? '—' : compareWeightLabel(w.five), style: cell),
          Text(w == null ? '—' : compareWeightLabel(w.week), style: cell),
        ],
      );
    }

    final cross = run.crossProvider;
    final command = widget.root == null
        ? null
        : compareTerminalCommand(
            other,
            claude: ref.read(claudeExecutableProvider),
            codex: other.provider == 'codex'
                ? ref.read(codexExecutableProvider)
                : 'codex',
          );
    final windows = run.readingOf(chosen.provider);
    String head1(int? minutes, String fallback) {
      final w = minutes == null ? fallback : compareWindowLabel(minutes);
      return '${w[0].toUpperCase()}${w.substring(1)}';
    }

    final otherItems = _otherItems ??= [
      for (final i in other.timeline().items)
        if (i is! NoticeItem) i,
    ];
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Semantics(
          container: true,
          label: widget.item.text,
          child: Container(
            key: const ValueKey('compare-card'),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.view_column_outlined,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Comparação',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '· escolhida ${chosen.letter} · '
                        '${cross ? chosen.fullLabel : chosen.label}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: compareSideColor(chosen.letter),
                        ),
                      ),
                    ),
                    if (command != null)
                      TextButton(
                        key: const ValueKey('compare-card-terminal'),
                        onPressed: () => _openTerminal(command),
                        child: Tooltip(
                          message:
                              'A sessão do lado ${other.letter}, fora do '
                              'app: $command',
                          child: const Text(
                            'Abrir no terminal',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    TextButton.icon(
                      key: const ValueKey('compare-card-toggle'),
                      onPressed: () => setState(() => _open = !_open),
                      icon: Icon(
                        _open ? Icons.expand_less : Icons.chevron_right,
                        size: 16,
                      ),
                      label: Text(
                        _open
                            ? 'Recolher'
                            : 'Ver a resposta do ${other.letter}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                Table(
                  columnWidths: {
                    0: FlexColumnWidth(cross ? 3.2 : 2.2),
                    1: const FlexColumnWidth(1.2),
                    2: const FlexColumnWidth(2),
                    3: const FlexColumnWidth(1.2),
                    4: const FlexColumnWidth(1),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      children: [
                        const SizedBox(),
                        const Text('Tempo', style: head),
                        const Text('Tokens', style: head),
                        Text(
                          head1(windows?.fiveMinutes, 'janela de 5 h'),
                          style: head,
                        ),
                        Text(
                          head1(windows?.weekMinutes, 'semana'),
                          style: head,
                        ),
                      ],
                    ),
                    for (final s in run.sides) row(s),
                  ],
                ),
                if (_open) ...[
                  const SizedBox(height: 8),
                  Container(
                    key: const ValueKey('compare-card-answer'),
                    constraints: const BoxConstraints(maxHeight: 420),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: otherItems.isEmpty
                        ? const Text(
                            'Sem resposta guardada.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          )
                        : ReadingCommands(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final i in otherItems)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: TimelineItemView(
                                        item: i,
                                        root: widget.root,
                                        assistantName:
                                            '${other.fullLabel} · não '
                                            'escolhida',
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
