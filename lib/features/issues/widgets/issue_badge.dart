import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/gh_cli.dart' show cliRunnerProvider;
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_toast.dart';
import '../issue_availability.dart';

/// `14/11`.
String _day(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// What the badge of the issue of [spec] says (SPEC-074 R1, R9, R10, R12):
/// the visible text, the screen reader's and the tooltip. The states are
/// text, never only a color.
({String text, String semantics, String tooltip}) issueBadgeText(Spec spec) {
  final n = spec.issueNumber!;
  final pending = spec.issueCommentPending ? ' · comentário pendente' : '';
  return switch (spec.issueState) {
    IssueState.closed => (
      text: '#$n fechada$pending',
      semantics: 'Issue $n, fechada$pending',
      tooltip:
          'Fechada no GitHub'
          '${spec.issueClosedAt == null ? '' : ' em ${_day(spec.issueClosedAt!.toLocal())}'}'
          '${switch (spec.issueClosedBy) {
            null => '',
            'à mão' => ', à mão',
            final by => ', pelo $by',
          }}. A spec fica onde está.',
    ),
    IssueState.notFound => (
      text: '#$n não encontrada$pending',
      semantics: 'Issue $n, não encontrada$pending',
      tooltip: 'A issue #$n foi apagada ou transferida.',
    ),
    IssueState.open => (
      text: '#$n$pending',
      semantics: 'Issue $n, aberta$pending',
      tooltip: 'Abrir a issue #$n no GitHub',
    ),
    null => (
      text: '#$n$pending',
      semantics: 'Issue $n$pending',
      tooltip: 'Abrir a issue #$n no GitHub',
    ),
  };
}

/// Opens the issue [number] of the workspace of [workspaceId] in the
/// browser, in the repository of the Review's remote (R1). Without GitHub,
/// the reason shows in a notice.
Future<void> openIssue(
  BuildContext context,
  WidgetRef ref,
  int workspaceId,
  int number,
) async {
  final ws = await ref.read(workspacesRepoProvider).getById(workspaceId);
  if (ws == null) return;
  final a = await ref.read(issueAvailabilityProvider(ws.path).future);
  final url = a.issueUrl(number);
  if (url == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showAppToast(
      SnackBar(content: Text(a.reason ?? 'Não deu para abrir a issue.')),
    );
    return;
  }
  try {
    await ref.read(cliRunnerProvider)('xdg-open', [url]);
  } catch (e) {
    debugPrint('xdg-open $url: $e');
  }
}

/// The `#N` badge of a spec linked to an issue (R1): on the Bandeja, the
/// cards of the Quadro, the list and the header of Specs. A click opens
/// the issue; [onTap] replaces it (the menu of the Bandeja).
///
/// [compact] (the card of the Quadro): when the whole text does not fit,
/// the badge shows `#N` with an icon of the state instead of cutting it
/// ("#2 fecha…"); the whole text goes to the tooltip and to the screen
/// reader.
class IssueBadge extends ConsumerWidget {
  const IssueBadge({
    super.key,
    required this.spec,
    this.onTap,
    this.compact = false,
  });

  final Spec spec;
  final VoidCallback? onTap;
  final bool compact;

  static const _padding = EdgeInsets.symmetric(horizontal: 5, vertical: 1);

  static TextStyle _style(Color color) => TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    color: color,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = spec.issueNumber;
    if (n == null) return const SizedBox.shrink();
    final t = issueBadgeText(spec);
    final color = switch (spec.issueState) {
      IssueState.closed => AppColors.lilac,
      IssueState.notFound => AppColors.red,
      _ => CanvasColors.agent,
    };
    final style = _style(color);
    Widget badge(bool short) => Tooltip(
      message: short ? '${t.text}\n${t.tooltip}' : t.tooltip,
      child: InkWell(
        key: ValueKey('issue-badge-${spec.code}'),
        borderRadius: BorderRadius.circular(5),
        onTap:
            onTap ??
            () => unawaited(openIssue(context, ref, spec.workspaceId, n)),
        child: Container(
          padding: _padding,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: color.withValues(alpha: .55)),
          ),
          child: short
              ? Row(
                  key: ValueKey('issue-badge-short-${spec.code}'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('#$n', maxLines: 1, softWrap: false, style: style),
                    for (final icon in [
                      ?switch (spec.issueState) {
                        IssueState.closed => Icons.check_circle_outline,
                        IssueState.notFound => Icons.link_off,
                        _ => null,
                      },
                      if (spec.issueCommentPending) Icons.schedule,
                    ]) ...[
                      const SizedBox(width: 3),
                      Icon(icon, size: 11, color: color),
                    ],
                  ],
                )
              : Text(
                  t.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: t.semantics,
      excludeSemantics: true,
      child: !compact
          ? badge(false)
          : LayoutBuilder(
              builder: (context, box) {
                final painter = TextPainter(
                  text: TextSpan(text: t.text, style: style),
                  maxLines: 1,
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                final width = painter.width + _padding.horizontal + 2;
                painter.dispose();
                return badge(width > box.maxWidth);
              },
            ),
    );
  }
}
