import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/diff_parser.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_toast.dart';
import '../debt_actions.dart';
import '../debt_board.dart' show specLabel;
import '../origin_debts.dart';

/// What the comments of the Revisão need for "Virar débito" (SPEC-112 R8):
/// the spec reviewed, its workspace, whether it was merged and the diff
/// (for the function of "Onde"). Absent = no "Virar débito" (a PR without
/// spec).
class ReviewDebtScope extends InheritedWidget {
  const ReviewDebtScope({
    super.key,
    required this.spec,
    required this.workspaceId,
    required this.merged,
    this.files = const [],
    required super.child,
  });

  final Spec spec;
  final int workspaceId;

  /// After the merge the link stays: no "Desfazer".
  final bool merged;
  final List<DiffFile> files;

  static ReviewDebtScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReviewDebtScope>();

  @override
  bool updateShouldNotify(ReviewDebtScope old) =>
      old.spec != spec ||
      old.merged != merged ||
      old.workspaceId != workspaceId ||
      !identical(old.files, files);
}

/// "Virar débito" on [c] (R8): the form comes filled with the comment, the
/// file and the function; the row goes to the worktree of the spec (R18).
/// Once saved, the comment is resolved and carries the seal.
Future<void> turnReviewCommentIntoDebt(
  BuildContext context,
  WidgetRef ref,
  ReviewDebtScope scope,
  ReviewCommentRow c,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ws = (ref.read(workspacesProvider).value ?? const <Workspace>[])
      .where((w) => w.id == scope.workspaceId)
      .firstOrNull;
  if (ws == null) {
    messenger?.showAppToast(
      const SnackBar(content: Text('Workspace da spec não encontrado.')),
    );
    return;
  }
  final file = scope.files.where((f) => f.path == c.path).firstOrNull;
  final written = await openDebtForm(
    context,
    ref,
    repoRoot: ws.path,
    initial: reviewCommentDraft(
      c,
      specLabel: specLabel(scope.spec),
      function: enclosingFunction(file, c.line),
    ),
    writeRoot: scope.spec.worktreePath,
    link: DebtLinksCompanion(
      originSpecId: Value(scope.spec.id),
      originReviewCommentId: Value(c.id),
    ),
  );
  if (written == null) return;
  try {
    await ref.read(originDebtsProvider).settleReviewComment(written, c.id);
  } catch (e) {
    messenger?.showAppToast(
      SnackBar(content: Text('${written.code} gravado, mas o comentário: $e')),
    );
  }
}

/// "Desfazer" (R8, before the merge): the link goes, the row leaves the
/// file of the worktree when it is still as written, and the comment is
/// open again.
Future<void> undoReviewCommentDebt(
  BuildContext context,
  WidgetRef ref,
  ReviewDebtScope scope,
  ReviewCommentRow c,
  String code,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final r = await ref
        .read(originDebtsProvider)
        .undoReviewComment(c.id, writeRoot: scope.spec.worktreePath);
    messenger?.showAppToast(
      SnackBar(
        content: Text(switch (r) {
          ReviewDebtUndo.removed =>
            '$code desfeito: a linha saiu do arquivo e o comentário voltou a '
                'contar como aberto.',
          ReviewDebtUndo.rowChanged =>
            'A linha do $code mudou desde que foi gravada e ficou no arquivo. '
                'O comentário voltou a contar como aberto.',
          ReviewDebtUndo.rowMissing =>
            'O $code já não estava no arquivo. O comentário voltou a contar '
                'como aberto.',
        }),
      ),
    );
  } catch (e) {
    messenger?.showAppToast(
      SnackBar(content: Text('Não deu para desfazer: $e')),
    );
  }
}

/// The seal "→ DT-12" of a comment that became a debt (R8).
class CommentDebtSeal extends StatelessWidget {
  const CommentDebtSeal(this.code, {super.key});

  final String code;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.teal.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppColors.teal.withValues(alpha: .6)),
    ),
    child: Text(
      '→ $code',
      style: const TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 11,
        color: AppColors.teal,
      ),
    ),
  );
}
