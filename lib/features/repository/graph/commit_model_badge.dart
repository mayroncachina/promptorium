import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/agent_trailer.dart' show appTrailerModel;
import '../../../core/git/git_service.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/info_tip.dart';
import '../repository_info.dart';
import 'commit_log.dart';

/// The origins of the Grafo's commits (SPEC-045 R9, ligado na SPEC-046),
/// by repository root: the rows on screen ask for theirs with [want], and
/// every SHA asked in the same frame is read in one `git log --no-walk`
/// ([GitService.commitOriginsOf]) — never a git per row.
class CommitOriginBatch extends Notifier<Map<String, CommitOrigin>> {
  CommitOriginBatch(this.root);

  final String root;
  final _pending = <String>{};
  final _asked = <String>{};
  bool _scheduled = false;

  /// Git calls made (the tests check the batching).
  int reads = 0;

  @override
  Map<String, CommitOrigin> build() => const {};

  /// Reads [sha]'s origin with the others asked in this frame.
  void want(String sha) {
    if (!_asked.add(sha)) return;
    _pending.add(sha);
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() => unawaited(_flush()));
  }

  Future<void> _flush() async {
    _scheduled = false;
    if (_pending.isEmpty) return;
    final shas = _pending.toList();
    _pending.clear();
    try {
      reads++;
      final got = await ref
          .read(gitServiceFactoryProvider)(root)
          .commitOriginsOf(shas);
      if (!ref.mounted) return;
      state = {...state, for (final o in got) o.sha: o};
    } on GitException catch (e) {
      debugPrint('Grafo: origens não lidas — $e');
    }
  }
}

final commitOriginBatchProvider =
    NotifierProvider.family<
      CommitOriginBatch,
      Map<String, CommitOrigin>,
      String
    >(CommitOriginBatch.new);

/// Colour of a model's label (and of its dot).
Color modelColor(String model) {
  final m = model.toLowerCase();
  if (m == appTrailerModel) return const Color(0xFFC59BFF);
  if (m.contains('opus')) return const Color(0xFF8EC5FF);
  if (m.contains('sonnet')) return AppColors.amber;
  if (m.contains('haiku')) return AppColors.teal;
  return AppColors.textSecondary;
}

/// What goes beside the author of a marked commit (R9): `◆ sonnet`,
/// `◆ opus`, `◆ app`, with the origin and the exact trailer line in an
/// [InfoTip]. Nothing for an unmarked commit.
Widget? commitModelBadge(BuildContext context, CommitRow c) =>
    CommitModelBadge(commit: c);

class CommitModelBadge extends ConsumerWidget {
  const CommitModelBadge({super.key, required this.commit});

  final CommitRow commit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(activeWorkspaceProvider);
    if (ws == null) return const SizedBox.shrink();
    final root =
        ref.watch(repositoryInfoProvider(ws.path)).value?.path ?? ws.path;
    final sha = commit.sha;
    final origin = ref.watch(
      commitOriginBatchProvider(root).select((m) => m[sha]),
    );
    if (origin == null) {
      ref.read(commitOriginBatchProvider(root).notifier).want(sha);
      return const SizedBox.shrink();
    }
    return ModelLabel(origin: origin);
  }
}

/// The label of [origin] (nothing without a trailer).
class ModelLabel extends StatelessWidget {
  const ModelLabel({super.key, required this.origin});

  final CommitOrigin origin;

  @override
  Widget build(BuildContext context) {
    final o = origin;
    final model = o.model;
    if (model == null || o.trailer == null) return const SizedBox.shrink();
    final color = modelColor(model);
    final app = o.kind == CommitOriginKind.app;
    final step = o.origin;
    final bold = const TextStyle(fontWeight: FontWeight.w600);
    return InfoTip(
      key: ValueKey('graph-model-${o.sha}'),
      title: app ? 'Commit feito pelo app' : 'Commit feito por um agente',
      semanticLabel: app
          ? 'Commit do app${step == null ? '' : ', $step'}'
          : 'Commit do agente $model${step == null ? '' : ', $step'}',
      detail: TextSpan(
        children: app
            ? [
                const TextSpan(text: 'O próprio Promptorium commitou '),
                if (step != null) ...[
                  const TextSpan(text: 'numa etapa, '),
                  TextSpan(text: step, style: bold),
                  const TextSpan(text: '. '),
                ] else
                  const TextSpan(text: 'numa etapa. '),
                const TextSpan(text: 'Pode juntar edição sua e do agente.'),
              ]
            : [
                const TextSpan(text: 'Modelo '),
                TextSpan(
                  text: model,
                  style: bold.copyWith(color: color),
                ),
                if (step != null) ...[
                  const TextSpan(text: ', na etapa '),
                  TextSpan(text: step, style: bold),
                ],
                const TextSpan(text: '. O autor no git continua sendo você.'),
              ],
      ),
      code: InfoTipCode([o.trailer!]),
      footnote:
          'Linha que o app acrescenta aos commits das sessões (SPEC-048).',
      maxWidth: 360,
      child: Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          border: Border.all(color: color.withValues(alpha: .55)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.diamond, size: 9, color: color),
            const SizedBox(width: 4),
            Text(
              model,
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11,
                color: color,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
