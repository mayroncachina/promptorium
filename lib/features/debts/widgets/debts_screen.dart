import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../sessions/widgets/session_style.dart';
import '../debt_actions.dart';
import '../debt_board.dart';
import '../debt_service.dart';
import '../debt_table.dart';
import 'debt_suggestions_strip.dart';
import 'decision_panel.dart';
import 'pay_debts_dialog.dart';

/// "Débitos e decisões" (SPEC-112 R13): the debts and the pending
/// decisions of the repository, read from the files.

/// The tab on show.
class DebtsTab extends Notifier<DebtKind> {
  @override
  DebtKind build() => DebtKind.debt;

  void select(DebtKind k) => state = k;
}

final debtsTabProvider = NotifierProvider<DebtsTab, DebtKind>(DebtsTab.new);

/// Pagos (true) / Abertos; Decididas (true) / Pendentes. Opens in Abertos
/// and Pendentes (R13).
class _Toggle extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) => state = v;
}

final debtsShowPaidProvider = NotifierProvider<_Toggle, bool>(_Toggle.new);
final decisionsShowDecidedProvider = NotifierProvider<_Toggle, bool>(
  _Toggle.new,
);

/// The debts ticked for "Pagar" (codes).
class DebtsSelection extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String code) => state = state.contains(code)
      ? ({...state}..remove(code))
      : {...state, code};

  void clear() => state = const {};
}

final debtsSelectionProvider = NotifierProvider<DebtsSelection, Set<String>>(
  DebtsSelection.new,
);

/// The decision open on the right.
class _SelectedDecision extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? code) => state = code;
}

final selectedDecisionProvider = NotifierProvider<_SelectedDecision, String?>(
  _SelectedDecision.new,
);

/// The workspace on show (null = the active one).
class _DebtsWorkspace extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int? id) => state = id;
}

final debtsWorkspaceProvider = NotifierProvider<_DebtsWorkspace, int?>(
  _DebtsWorkspace.new,
);

/// The workspace the screen shows.
final debtsScreenWorkspaceProvider = Provider<Workspace?>((ref) {
  final id = ref.watch(debtsWorkspaceProvider);
  final active = ref.watch(activeWorkspaceProvider);
  if (id == null) return active;
  final list = ref.watch(workspacesProvider).value ?? const <Workspace>[];
  return list.where((w) => w.id == id).firstOrNull ?? active;
});

/// Opens the screen (the Quadro chip, R14; a file chip, R16).
void openDebtsScreen(WidgetRef ref, {DebtKind tab = DebtKind.debt}) {
  ref.read(debtsTabProvider.notifier).select(tab);
  ref.read(navigationProvider.notifier).go(AppSection.debts);
}

/// "Novo débito" / "Nova decisão" (R10): the same form, without origin.
Future<void> newDebtByHand(
  BuildContext context,
  WidgetRef ref, [
  DebtKind? kind,
]) async {
  final w = ref.read(debtsScreenWorkspaceProvider);
  if (w == null) return;
  await openDebtForm(
    context,
    ref,
    repoRoot: w.path,
    initial: DebtDraft(kind: kind ?? ref.read(debtsTabProvider), title: ''),
  );
}

class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(debtsScreenWorkspaceProvider);
    if (w == null) {
      return const Center(
        child: Text(
          'Abra um workspace para ver os débitos e as decisões.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    final board = ref.watch(debtBoardProvider(debtKeyOf(w)));
    final tab = ref.watch(debtsTabProvider);
    return Padding(
      key: const ValueKey('screen-debts'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(workspace: w, board: board, tab: tab),
            _Tabs(board: board, tab: tab),
            const Divider(height: 1),
            if (board != null && board.snapshot.hasLegacy)
              _LegacyStrip(workspace: w, board: board),
            Expanded(
              child: board == null
                  ? const Center(child: CircularProgressIndicator())
                  : tab == DebtKind.debt
                  ? _DebtsTab(board: board, workspace: w)
                  : _DecisionsTab(board: board, workspace: w),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.workspace,
    required this.board,
    required this.tab,
  });

  final Workspace workspace;
  final DebtBoard? board;
  final DebtKind tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = board?.snapshot.config;
    final file = cfg == null
        ? ''
        : tab == DebtKind.debt
        ? cfg.debtsPath
        : cfg.decisionsPath;
    final list = ref.watch(workspacesProvider).value ?? const <Workspace>[];
    final now = TimeOfDay.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 6),
      child: Row(
        children: [
          const Text(
            'Débitos e decisões',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 10),
          if (file.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.borderHover),
              ),
              child: Text(
                file,
                key: const ValueKey('debts-file'),
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'lido às ${now.hour.toString().padLeft(2, '0')}:'
              '${now.minute.toString().padLeft(2, '0')} · relido ao mudar',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          const Spacer(),
          if (list.length > 1) ...[
            PopupMenuButton<int>(
              key: const ValueKey('debts-repo'),
              tooltip: 'Repositório',
              color: AppColors.panelSolid,
              initialValue: workspace.id,
              onSelected: (id) {
                ref.read(debtsWorkspaceProvider.notifier).select(id);
                ref.read(debtsSelectionProvider.notifier).clear();
              },
              itemBuilder: (_) => [
                for (final x in list)
                  PopupMenuItem(
                    value: x.id,
                    child: Text(x.name, style: const TextStyle(fontSize: 12)),
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
                    Text(workspace.name, style: const TextStyle(fontSize: 12)),
                    const Icon(Icons.expand_more, size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          SmallButton(
            key: const ValueKey('debts-new-decision'),
            label: 'Nova decisão',
            height: 28,
            onTap: () => newDebtByHand(context, ref, DebtKind.decision),
          ),
          const SizedBox(width: 8),
          SmallButton(
            key: const ValueKey('debts-new-debt'),
            label: 'Novo débito',
            height: 28,
            color: AppColors.teal,
            border: ReviewColors.acceptBorder,
            onTap: () => newDebtByHand(context, ref, DebtKind.debt),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends ConsumerWidget {
  const _Tabs({required this.board, required this.tab});

  final DebtBoard? board;
  final DebtKind tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget item(DebtKind k, String label, int n) {
      final on = k == tab;
      return InkWell(
        key: ValueKey('debts-tab-${k.dbName}'),
        onTap: () => ref.read(debtsTabProvider.notifier).select(k),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: on ? AppColors.amber : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: on ? AppColors.text : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 7),
              _Count(n, on: on, key: ValueKey('debts-tab-count-${k.dbName}')),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Row(
        children: [
          item(DebtKind.debt, 'Débitos', board?.openDebts.length ?? 0),
          const SizedBox(width: 6),
          item(DebtKind.decision, 'Decisões', board?.pending.length ?? 0),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.n, {super.key, this.on = false});

  final int n;
  final bool on;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0.5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      border: Border.all(
        color: on ? AppColors.amber.withValues(alpha: .6) : AppColors.border,
      ),
    ),
    child: Text(
      '$n',
      style: TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 11,
        color: on ? AppColors.amber : AppColors.textSecondary,
      ),
    ),
  );
}

/// R2: the old files of docs/ found; nothing changes without a choice.
class _LegacyStrip extends ConsumerWidget {
  const _LegacyStrip({required this.workspace, required this.board});

  final Workspace workspace;
  final DebtBoard board;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = board.snapshot;
    final files = [?s.legacyDebts, ?s.legacyDecisions];
    final service = ref.read(debtServiceProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    Future<void> run(Future<void> Function() f, String done) async {
      try {
        await f();
        messenger?.showAppToast(SnackBar(content: Text(done)));
      } catch (e) {
        messenger?.showAppToast(SnackBar(content: Text('Falhou: $e')));
      }
    }

    return Container(
      key: const ValueKey('debts-legacy'),
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: SessionColors.approvalBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SessionColors.approvalBorder),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.description_outlined,
            size: 16,
            color: AppColors.amber,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Encontrei ${files.join(' e ')}. O app usa '
              '${s.config.debtsPath} e ${s.config.decisionsPath}, na raiz.',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          SmallButton(
            key: const ValueKey('debts-legacy-use'),
            label: 'Usar estes arquivos',
            height: 26,
            onTap: () => run(
              () => service.useLegacy(workspace.path),
              'Caminho gravado em .promptorium/config.yml.',
            ),
          ),
          const SizedBox(width: 6),
          SmallButton(
            key: const ValueKey('debts-legacy-move'),
            label: 'Mover para a raiz',
            height: 26,
            onTap: () => run(
              () => service.moveLegacy(workspace.path),
              'Arquivos movidos com git mv; os links foram consertados.',
            ),
          ),
        ],
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.left,
    required this.right,
    required this.rightOn,
    required this.onChanged,
    required this.keyPrefix,
  });

  final String left, right;
  final bool rightOn;
  final ValueChanged<bool> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool value) {
      final on = value == rightOn;
      return InkWell(
        key: ValueKey('$keyPrefix-${value ? 'right' : 'left'}'),
        borderRadius: BorderRadius.circular(6),
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: on ? AppColors.amberTint : null,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: on ? SessionColors.approvalBorder : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: on ? AppColors.amber : AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [seg(left, false), seg(right, true)],
        ),
      ),
    );
  }
}

class _DebtsTab extends ConsumerWidget {
  const _DebtsTab({required this.board, required this.workspace});

  final DebtBoard board;
  final Workspace workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paid = ref.watch(debtsShowPaidProvider);
    final rows = paid ? board.paidDebts : board.openDebts;
    final selected = ref.watch(debtsSelectionProvider);
    final inSpec = [
      for (final d in board.debts)
        if (d.state == DebtRowState.inSpec) d,
    ];
    final odd = board.unrecognized(DebtKind.debt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
          child: Row(
            children: [
              _Segmented(
                keyPrefix: 'debts-filter',
                left: 'Abertos · ${board.openDebts.length}',
                right: 'Pagos · ${board.paidDebts.length}',
                rightOn: paid,
                onChanged: (v) {
                  ref.read(debtsShowPaidProvider.notifier).set(v);
                  ref.read(debtsSelectionProvider.notifier).clear();
                },
              ),
              const SizedBox(width: 10),
              if (inSpec.isNotEmpty)
                Flexible(
                  child: Text(
                    '+ ${inSpec.length} na '
                    '${{for (final d in inSpec) specLabel(d.inSpec!)}.join(', ')}'
                    ', ainda não mesclada',
                    key: const ValueKey('debts-in-spec-note'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              if (board.orphans.isNotEmpty) ...[
                const SizedBox(width: 10),
                Tooltip(
                  message:
                      'Vínculos do app cujo ID não está mais no arquivo. O app '
                      'não recria a linha: o arquivo vale.',
                  child: Text(
                    '${board.orphans.length} '
                    '${board.orphans.length == 1 ? 'vínculo órfão' : 'vínculos órfãos'}: '
                    '${board.orphans.map((l) => l.code).join(', ')}',
                    key: const ValueKey('debts-orphans'),
                    style: const TextStyle(fontSize: 12, color: AppColors.red),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!paid)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: DebtSuggestionsStrip(
              board: board,
              workspaceId: workspace.id,
            ),
          ),
        const _TableHeader(),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    paid
                        ? 'Nenhum débito pago ainda.'
                        : board.snapshot.debtsExists
                        ? 'Nenhum débito aberto.'
                        : 'Ainda não há ${board.snapshot.config.debtsPath}. '
                              'O primeiro débito cria o arquivo.',
                    key: const ValueKey('debts-empty'),
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) => _DebtRow(
                    row: rows[i],
                    selected: selected.contains(rows[i].item.code),
                  ),
                ),
        ),
        _Footer(
          board: board,
          rows: rows,
          unrecognized: odd,
          workspace: workspace,
        ),
      ],
    );
  }
}

const _colId = 76.0;
const _colWhere = 270.0;
const _colOrigin = 130.0;
const _colState = 180.0;

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 10.5,
      letterSpacing: .8,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: const Row(
        children: [
          SizedBox(width: 34),
          SizedBox(
            width: _colId,
            child: Text('ID', style: style),
          ),
          Expanded(child: Text('O QUÊ', style: style)),
          SizedBox(
            width: _colWhere,
            child: Text('ONDE', style: style),
          ),
          SizedBox(
            width: _colOrigin,
            child: Text('ORIGEM', style: style),
          ),
          SizedBox(
            width: _colState,
            child: Text('ESTADO', style: style),
          ),
        ],
      ),
    );
  }
}

class _DebtRow extends ConsumerWidget {
  const _DebtRow({required this.row, required this.selected});

  final DebtRowView row;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = row.item;
    final canSelect = row.state == DebtRowState.open;
    final dim = row.state == DebtRowState.inSpec;
    final (stateLabel, stateColor) = switch (row.state) {
      DebtRowState.open => ('aberto', null),
      DebtRowState.paying => (
        'em pagamento${row.paymentSpec == null ? '' : ' · ${specLabel(row.paymentSpec!)}'}',
        AppColors.amber,
      ),
      DebtRowState.paid => (
        d.resolvedBy == null ? 'pago' : 'pago · ${d.resolvedBy}',
        CanvasColors.done,
      ),
      DebtRowState.inSpec => (
        'na ${row.inSpec == null ? 'spec' : specLabel(row.inSpec!)}',
        AppColors.lilac,
      ),
    };
    return Container(
      key: ValueKey('debt-row-${d.code}'),
      constraints: const BoxConstraints(minHeight: 38),
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      decoration: BoxDecoration(
        color: selected ? AppColors.amberTint.withValues(alpha: .6) : null,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: canSelect
                ? Checkbox(
                    key: ValueKey('debt-check-${d.code}'),
                    value: selected,
                    visualDensity: VisualDensity.compact,
                    activeColor: AppColors.amber,
                    checkColor: AppColors.onAmber,
                    onChanged: (_) => ref
                        .read(debtsSelectionProvider.notifier)
                        .toggle(d.code),
                  )
                : null,
          ),
          SizedBox(
            width: _colId,
            child: Text(
              d.code,
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12.5,
                decoration: d.paid ? TextDecoration.lineThrough : null,
                color: dim ? AppColors.textMuted : AppColors.text,
              ),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: d.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: d.paid ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (d.reason.isNotEmpty)
                    TextSpan(
                      text: ' · ${_plain(d.reason)}',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          SizedBox(
            width: _colWhere,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                d.whereRefs.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          SizedBox(
            width: _colOrigin,
            child: Align(
              alignment: Alignment.centerLeft,
              child: DebtTag(row.origin),
            ),
          ),
          SizedBox(
            width: _colState,
            child: Align(
              alignment: Alignment.centerLeft,
              child: DebtTag(
                stateLabel,
                color: stateColor,
                filled: stateColor != null,
                key: ValueKey('debt-state-${d.code}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The text of a cell without the Markdown marks.
String _plain(String v) => v
    .replaceAll(RegExp(r'\*\*|~~|`'), '')
    .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1)!);

class _Footer extends ConsumerWidget {
  const _Footer({
    required this.board,
    required this.rows,
    required this.unrecognized,
    required this.workspace,
  });

  final DebtBoard board;
  final List<DebtRowView> rows;
  final List<UnrecognizedLine> unrecognized;
  final Workspace workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sel = ref.watch(debtsSelectionProvider);
    // Only open debts are paid (R15).
    final picked = [
      for (final r in rows)
        if (sel.contains(r.item.code) && r.state == DebtRowState.open) r.item,
    ];
    final codes = [for (final d in picked) d.code];
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 14, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (codes.isNotEmpty) ...[
            Text(
              '${codes.length} ${codes.length == 1 ? 'selecionado' : 'selecionados'}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Text(
              codes.join(', '),
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 16),
          ],
          if (unrecognized.isNotEmpty) UnrecognizedLink(lines: unrecognized),
          const Spacer(),
          if (codes.isNotEmpty) ...[
            SmallButton(
              key: const ValueKey('debts-clear'),
              label: 'Limpar',
              onTap: () => ref.read(debtsSelectionProvider.notifier).clear(),
            ),
            const SizedBox(width: 8),
            AmberButton(
              key: const ValueKey('debts-pay'),
              label: 'Pagar · ${codes.length}',
              onTap: () async {
                final spec = await openPayDebtsDialog(
                  context,
                  ref,
                  ws: workspace,
                  items: picked,
                  file: board.snapshot.config.debtsPath,
                );
                if (spec != null) {
                  ref.read(debtsSelectionProvider.notifier).clear();
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// "N linhas não reconhecidas no arquivo · ver" (R5): the raw text, never
/// rewritten.
class UnrecognizedLink extends StatelessWidget {
  const UnrecognizedLink({super.key, required this.lines});

  final List<UnrecognizedLine> lines;

  @override
  Widget build(BuildContext context) {
    final n = lines.length;
    return InkWell(
      key: const ValueKey('debts-unrecognized'),
      onTap: () => showAppDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.panelSolid,
          title: Text(
            '$n ${n == 1 ? 'linha não reconhecida' : 'linhas não reconhecidas'}',
            style: const TextStyle(fontSize: 15),
          ),
          content: SizedBox(
            width: 620,
            child: SelectableText(
              [for (final l in lines) 'linha ${l.line + 1}: ${l.text}']
                  .join('\n'),
              style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
      child: Text(
        '$n ${n == 1 ? 'linha não reconhecida' : 'linhas não reconhecidas'} '
        'no arquivo · ver',
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
    );
  }
}

class _DecisionsTab extends ConsumerWidget {
  const _DecisionsTab({required this.board, required this.workspace});

  final DebtBoard board;
  final Workspace workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decided = ref.watch(decisionsShowDecidedProvider);
    final rows = decided ? board.decided : board.pending;
    final selCode = ref.watch(selectedDecisionProvider);
    final sel =
        board.decisions.where((d) => d.item.code == selCode).firstOrNull ??
        rows.firstOrNull;
    final recent = board.decided.reversed.take(3).toList();
    final odd = board.unrecognized(DebtKind.decision);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 380,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _Segmented(
                    keyPrefix: 'decisions-filter',
                    left: 'Pendentes · ${board.pending.length}',
                    right: 'Decididas · ${board.decided.length}',
                    rightOn: decided,
                    onChanged: (v) =>
                        ref.read(decisionsShowDecidedProvider.notifier).set(v),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: rows.isEmpty
                      ? Center(
                          child: Text(
                            decided
                                ? 'Nenhuma decisão tomada ainda.'
                                : 'Nenhuma decisão pendente.',
                            key: const ValueKey('decisions-empty'),
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final r in rows)
                              _DecisionCard(
                                row: r,
                                selected: r.item.code == sel?.item.code,
                              ),
                          ],
                        ),
                ),
                if (odd.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  UnrecognizedLink(lines: odd),
                ],
                if (!decided && recent.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'DECIDIDAS HÁ POUCO',
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final r in recent)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '${r.item.code} · ${r.item.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: sel == null
              ? const Center(
                  child: Text(
                    'Selecione uma decisão.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                )
              : DecisionPanel(
                  row: sel,
                  board: board,
                  workspaceId: workspace.id,
                ),
        ),
      ],
    );
  }
}

class _DecisionCard extends ConsumerWidget {
  const _DecisionCard({required this.row, required this.selected});

  final DecisionRowView row;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = row.item;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: ValueKey('decision-card-${d.code}'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => ref.read(selectedDecisionProvider.notifier).select(d.code),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: selected ? SessionColors.selectedBg : null,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? SessionColors.selectedBorder
                  : Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    d.code,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 12,
                      color: AppColors.amber,
                    ),
                  ),
                  const SizedBox(width: 8),
                  DebtTag(
                    d.decided
                        ? 'decidida'
                        : row.inSpec != null
                        ? 'na ${specLabel(row.inSpec!)}'
                        : 'pendente',
                    color: d.decided
                        ? CanvasColors.done
                        : row.inSpec != null
                        ? AppColors.lilac
                        : AppColors.amber,
                  ),
                  const Spacer(),
                  Text(
                    d.since,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                d.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                row.origin,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
