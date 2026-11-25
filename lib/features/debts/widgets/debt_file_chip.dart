import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../data/repos/debt_links_repo.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../sessions/session_changes.dart';
import '../../sessions/widgets/session_style.dart';
import '../debt_board.dart';
import '../piggyback.dart';
import 'debts_screen.dart' show openDebtsScreen;
import 'decision_panel.dart' show DebtTag;

/// The board of the workspace [workspaceId] (null while it loads or when
/// the workspace is unknown). The chips of R16 and the marks of R17 read it.
final workspaceDebtBoardProvider = Provider.family<DebtBoard?, int>((
  ref,
  workspaceId,
) {
  final list = ref.watch(workspacesProvider).value ?? const <Workspace>[];
  final w = list.where((w) => w.id == workspaceId).firstOrNull;
  if (w == null) return null;
  return ref.watch(debtBoardProvider(debtKeyOf(w)));
});

/// `1 débito neste arquivo` / `3 débitos neste arquivo`.
String debtFileLabel(int n) =>
    n == 1 ? '1 débito neste arquivo' : '$n débitos neste arquivo';

/// `2 débitos nos arquivos` (the card of the Quadro).
String debtFilesLabel(int n) =>
    n == 1 ? '1 débito nos arquivos' : '$n débitos nos arquivos';

/// The open debts of [board] cited by one of [paths], without repeats, in
/// the order of the board.
List<DebtRowView> debtsForPaths(DebtBoard board, Iterable<String> paths) {
  final ps = paths.toList();
  return [
    for (final d in board.openDebts)
      if (ps.any((p) => debtCitesPath(d.item, p))) d,
  ];
}

/// The debts the spec [specId] will pay: chosen in "Pagar" (R15) or
/// "pago de carona" confirmed (R17).
List<DebtRowView> debtsPaidBy(DebtBoard board, int specId) => [
  for (final d in board.debts)
    if (d.state != DebtRowState.paid &&
        (d.link?.paymentSpecId == specId ||
            (d.link?.piggybackSpecId == specId &&
                d.link?.piggybackState == DebtPiggybackState.confirmed)))
      d,
];

/// The "pago de carona?" marks of [specId] waiting for the person (R17).
List<DebtRowView> piggybacksToConfirm(DebtBoard board, int specId) => [
  for (final d in board.debts)
    if (d.link?.piggybackSpecId == specId && d.piggybackToConfirm) d,
];

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.onTap,
    this.color = AppColors.amber,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withValues(alpha: .6)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: color),
        ),
      ),
    ),
  );
}

/// The chip "N débitos neste arquivo" of a file in a diff (SPEC-112 R16):
/// the open debts whose "Onde" cites [path]. Nothing when none does.
class DebtFileChip extends ConsumerWidget {
  const DebtFileChip({
    super.key,
    required this.workspaceId,
    required this.path,
  });

  final int workspaceId;
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(workspaceDebtBoardProvider(workspaceId));
    final debts = board?.debtsForPath(path) ?? const <DebtRowView>[];
    if (debts.isEmpty) return const SizedBox.shrink();
    return _Chip(
      key: ValueKey('debt-file-chip-$path'),
      label: debtFileLabel(debts.length),
      onTap: () => showDebtListDialog(
        context,
        title: 'Débitos neste arquivo',
        subtitle: path,
        debts: debts,
      ),
    );
  }
}

/// The card of the Quadro (R16, R17): "N débitos nos arquivos" the spec
/// changed and the tag "pago de carona?". The changed files come from the
/// diff of the spec's last session ([sessionChangesProvider], read only
/// when the repository has open debts).
class SpecCardDebts extends ConsumerWidget {
  const SpecCardDebts({super.key, required this.spec, required this.sessionId});

  final Spec spec;
  final String? sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (spec.stage == SpecStage.done) return const SizedBox.shrink();
    final board = ref.watch(workspaceDebtBoardProvider(spec.workspaceId));
    if (board == null) return const SizedBox.shrink();
    final marks = piggybacksToConfirm(board, spec.id);
    var debts = const <DebtRowView>[];
    final id = sessionId;
    if (id != null && spec.worktreePath != null && board.openCount > 0) {
      final changes = ref.watch(sessionChangesProvider(id)).value;
      if (changes != null) {
        debts = debtsForPaths(board, [
          for (final e in changes.entries) e.path,
          for (final f in changes.files) f.path,
        ]);
      }
    }
    if (debts.isEmpty && marks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          if (debts.isNotEmpty)
            _Chip(
              key: ValueKey('debt-card-chip-${spec.code}'),
              label: debtFilesLabel(debts.length),
              onTap: () => showDebtListDialog(
                context,
                title: 'Débitos nos arquivos',
                subtitle: '${spec.code} · ${spec.title}',
                debts: debts,
              ),
            ),
          if (marks.isNotEmpty)
            _Chip(
              key: ValueKey('debt-card-piggyback-${spec.code}'),
              label: 'pago de carona?',
              color: AppColors.lilac,
              onTap: () => showAppDialog<void>(
                context: context,
                builder: (_) => _PiggybackDialog(spec: spec),
              ),
            ),
        ],
      ),
    );
  }
}

class _PiggybackDialog extends StatelessWidget {
  const _PiggybackDialog({required this.spec});

  final Spec spec;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppColors.panelSolid,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: PiggybackMarks(
            workspaceId: spec.workspaceId,
            specId: spec.id,
            specLabel: specLabel(spec),
          ),
        ),
      ),
    ),
  );
}

/// The list of [debts] (the chips of R16): ID, title, where and state, and
/// the way to the screen "Débitos e decisões".
Future<void> showDebtListDialog(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<DebtRowView> debts,
}) => showAppDialog<void>(
  context: context,
  builder: (_) =>
      _DebtListDialog(title: title, subtitle: subtitle, debts: debts),
);

class _DebtListDialog extends ConsumerWidget {
  const _DebtListDialog({
    required this.title,
    required this.subtitle,
    required this.debts,
  });

  final String title;
  final String? subtitle;
  final List<DebtRowView> debts;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Dialog(
    key: const ValueKey('debt-list-dialog'),
    backgroundColor: AppColors.panelSolid,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 10.5,
                letterSpacing: .8,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [for (final d in debts) _DebtLine(d)],
              ),
            ),
            const Divider(color: AppColors.border, height: 16),
            Row(
              children: [
                const Spacer(),
                SmallButton(
                  key: const ValueKey('debt-list-open-screen'),
                  label: 'Abrir Débitos e decisões',
                  onTap: () {
                    Navigator.of(context).pop();
                    openDebtsScreen(ref);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _DebtLine extends StatelessWidget {
  const _DebtLine(this.d);

  final DebtRowView d;

  @override
  Widget build(BuildContext context) => Padding(
    key: ValueKey('debt-list-${d.item.code}'),
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              d.item.code,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: AppColors.amber,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                d.item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            d.piggybackToConfirm
                ? const DebtTag('pago de carona?', color: AppColors.lilac)
                : DebtTag(d.state.label),
          ],
        ),
        if (d.item.where.trim().isNotEmpty)
          Text(
            d.item.where.replaceAll('`', ''),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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

/// The "pago de carona?" marks of [specId] (R17, mock 6): "Confirmar pago"
/// records `confirmado` (the merge strikes the row) and "Não foi pago"
/// `recusado`. Nothing changes in the file until the merge.
class PiggybackMarks extends ConsumerWidget {
  const PiggybackMarks({
    super.key,
    required this.workspaceId,
    required this.specId,
    this.specLabel,
  });

  final int workspaceId;
  final int specId;

  /// `spec 36`, for the note.
  final String? specLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(workspaceDebtBoardProvider(workspaceId));
    final marks = board == null
        ? const <DebtRowView>[]
        : piggybacksToConfirm(board, specId);
    if (marks.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final d in marks)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PiggybackCard(row: d, specLabel: specLabel),
          ),
      ],
    );
  }
}

class _PiggybackCard extends ConsumerWidget {
  const _PiggybackCard({required this.row, this.specLabel});

  final DebtRowView row;
  final String? specLabel;

  Future<void> _settle(
    BuildContext context,
    WidgetRef ref, {
    required bool confirmed,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final id = row.link?.id;
    if (id == null) return;
    try {
      await settlePiggyback(
        ref.read(debtLinksRepoProvider),
        id,
        confirmed: confirmed,
      );
    } catch (e) {
      messenger?.showAppToast(
        SnackBar(content: Text('Não deu para gravar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = row.item.code;
    final merge = specLabel == null
        ? 'no merge da spec'
        : 'no merge da $specLabel';
    return Container(
      key: ValueKey('piggyback-$code'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.lilac.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.lilac.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const DebtTag('pago de carona?', color: AppColors.lilac),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$code · ${row.item.title}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'O agente disse que pagou este débito. Nada muda até você '
            'confirmar. Confirmado, a linha é riscada $merge.',
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SmallButton(
                key: ValueKey('piggyback-refuse-$code'),
                label: 'Não foi pago',
                height: 26,
                fontSize: 11.5,
                onTap: () => _settle(context, ref, confirmed: false),
              ),
              const SizedBox(width: 8),
              SmallButton(
                key: ValueKey('piggyback-confirm-$code'),
                label: 'Confirmar pago',
                height: 26,
                fontSize: 11.5,
                color: AppColors.teal,
                border: AppColors.teal.withValues(alpha: .6),
                onTap: () => _settle(context, ref, confirmed: true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The Revisão of a spec (R15, R17): the "pago de carona?" marks to
/// confirm and the list of the debts the spec will pay.
class SpecReviewDebts extends ConsumerWidget {
  const SpecReviewDebts({super.key, required this.spec});

  final Spec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(workspaceDebtBoardProvider(spec.workspaceId));
    if (board == null) return const SizedBox.shrink();
    final marks = piggybacksToConfirm(board, spec.id);
    final paying = debtsPaidBy(board, spec.id);
    if (marks.isEmpty && paying.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('review-spec-debts'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PiggybackMarks(
            workspaceId: spec.workspaceId,
            specId: spec.id,
            specLabel: specLabel(spec),
          ),
          if (paying.isNotEmpty)
            Container(
              key: const ValueKey('review-spec-paying'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Esta spec vai pagar: ',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    TextSpan(
                      text: [
                        for (final d in paying)
                          '${d.item.code} ${d.item.title}',
                      ].join(' · '),
                      style: const TextStyle(color: AppColors.text),
                    ),
                    const TextSpan(
                      text: '. As linhas são riscadas no merge.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}
