import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../sessions/widgets/session_style.dart';
import '../../specs/spec_service.dart';
import '../spec_batch.dart';
import 'answer_spec_bar.dart';

/// "N specs nesta resposta" and the review list (SPEC-068 R1, R3–R6, R9).

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showAppToast(SnackBar(content: Text(msg)));
}

/// `1 requisito` / `3 requisitos`.
String requirementsLabel(int n) => '$n ${n == 1 ? 'requisito' : 'requisitos'}';

/// Opens the review list of [items] and creates the checked rows. Returns
/// the specs created (empty when cancelled).
Future<List<Spec>> showSpecBatch(
  BuildContext context,
  WidgetRef ref,
  Conversation c,
  List<SpecBatchItem> items, {
  int? answer,
}) async {
  final repo = ref.read(specsRepoProvider);
  final ws = await ref.read(workspacesRepoProvider).getById(c.workspaceId);
  if (ws == null) return const [];
  final specs = await repo.watchByWorkspace(ws.id).first;
  final next = await nextSpecNumber(repo, ws);
  final origin = answer == null ? null : (conversationId: c.id, answer: answer);
  if (!context.mounted) return const [];
  final entries = await showAppDialog<List<SpecBatchEntry>>(
    context: context,
    builder: (_) => SpecBatchDialog(
      entries: batchEntries(items, specs, origin),
      existing: {for (final s in specs) s.code},
      nextNumber: next,
    ),
  );
  if (entries == null || !context.mounted) return const [];
  try {
    // The numbers are planned again: another spec may have come meanwhile.
    final now = await repo.watchByWorkspace(ws.id).first;
    final plan = planBatch(
      entries,
      existing: {for (final s in now) s.code},
      nextNumber: await nextSpecNumber(repo, ws),
    );
    final created = await createSpecBatch(
      ref.read(specServiceProvider),
      repo,
      ws,
      entries,
      plan,
      origin: origin,
    );
    ref.invalidate(answerSpecTargetProvider((c, null)));
    if (context.mounted && created.isNotEmpty) {
      final codes = joinCodes([for (final s in created) s.code]);
      _snack(
        context,
        created.length == 1
            ? '$codes criada como rascunho na Bandeja do Quadro'
            : '$codes criadas como rascunho na Bandeja do Quadro',
      );
    }
    return created;
  } catch (e) {
    if (context.mounted) _snack(context, 'Falha ao criar as specs: $e');
    return const [];
  }
}

/// A code chip of the bar and of the list (`SPEC-A`, `SPEC-A → SPEC-021`).
class _CodeChip extends StatelessWidget {
  const _CodeChip(this.children, {this.prefix});

  final String? prefix;
  final List<InlineSpan> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppColors.borderHover),
    ),
    child: Text.rich(
      TextSpan(
        children: [
          if (prefix != null)
            TextSpan(
              text: '$prefix ',
              style: const TextStyle(fontFamily: AppFonts.sans),
            ),
          ...children,
        ],
      ),
      style: const TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 11,
        color: AppColors.text,
      ),
    ),
  );
}

const _amberMono = TextStyle(
  fontFamily: AppFonts.mono,
  color: AppColors.amber,
  fontWeight: FontWeight.w600,
);

/// "N specs nesta resposta" under an answer with two or more (R1).
class AnswerSpecsBar extends ConsumerWidget {
  const AnswerSpecsBar({
    super.key,
    required this.conversation,
    required this.items,
    this.answer,
  });

  final Conversation conversation;
  final List<SpecBatchItem> items;

  /// Index of the answer in the conversation (origin of the specs, R6).
  final int? answer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = conversation;
    final specs =
        ref.watch(specsProvider(c.workspaceId)).value ?? const <Spec>[];
    final info = ref.watch(answerSpecTargetProvider((c, null))).value;
    final origin = answer == null
        ? null
        : (conversationId: c.id, answer: answer!);
    final entries = batchEntries(items, specs, origin);
    final plan = info == null
        ? null
        : planBatch(
            entries,
            existing: {for (final s in specs) s.code},
            nextNumber: int.parse(info.nextCode.substring(5)),
          );
    final created = entries.where((e) => e.created != null).length;
    final String tail;
    if (plan == null) {
      tail = '';
    } else if (plan.toCreate.isEmpty) {
      tail = created == items.length ? '· já criadas' : '· nenhuma marcada';
    } else {
      tail = [
        '· ${plan.toCreate.length == 1 ? 'vira' : 'viram'} ${plan.range} ao criar',
        if (created > 0) '· $created já ${created == 1 ? 'criada' : 'criadas'}',
      ].join(' ');
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const ValueKey('answer-specs-bar'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaisedSolid,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderHover),
        ),
        child: Row(
          children: [
            const Icon(Icons.layers_outlined, size: 18, color: AppColors.amber),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${items.length} specs nesta resposta',
                    key: const ValueKey('answer-specs-title'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final i in items)
                        _CodeChip([TextSpan(text: i.label)]),
                      Text(
                        tail,
                        key: const ValueKey('answer-specs-subtitle'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SmallButton(
              key: const ValueKey('answer-specs-copy'),
              label: 'Copiar',
              height: 32,
              background: Colors.transparent,
              onTap: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: [for (final i in items) i.markdown].join('\n\n'),
                  ),
                );
                if (context.mounted) _snack(context, 'Specs copiadas');
              },
            ),
            const SizedBox(width: 8),
            SmallButton(
              key: const ValueKey('answer-specs-review'),
              label: plan != null && plan.toCreate.isEmpty
                  ? 'Revisar'
                  : 'Revisar e criar',
              icon: Icons.layers_outlined,
              height: 32,
              fontWeight: FontWeight.w600,
              color: AppColors.onAmber,
              border: AppColors.amber,
              background: AppColors.amber,
              onTap: info == null
                  ? null
                  : () => showSpecBatch(context, ref, c, items, answer: answer),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateIntent extends Intent {
  const _CreateIntent();
}

class _CreateAction extends Action<_CreateIntent> {
  _CreateAction(this.state);

  final _SpecBatchDialogState state;

  /// Enter on a button (Cancelar, Prévia, Marcar…) presses that button.
  @override
  bool isEnabled(_CreateIntent intent) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.findAncestorWidgetOfExactType<InkWell>() != null) {
      return false;
    }
    return state._editing == null && state._canCreate;
  }

  @override
  Object? invoke(_CreateIntent intent) {
    state._create();
    return null;
  }
}

/// "Criar specs da resposta" (R3): one row per spec, checked; the real
/// numbers, the warnings and the button that says how many.
class SpecBatchDialog extends ConsumerStatefulWidget {
  const SpecBatchDialog({
    super.key,
    required this.entries,
    required this.existing,
    required this.nextNumber,
  });

  final List<SpecBatchEntry> entries;
  final Set<String> existing;
  final int nextNumber;

  @override
  ConsumerState<SpecBatchDialog> createState() => _SpecBatchDialogState();
}

class _SpecBatchDialogState extends ConsumerState<SpecBatchDialog> {
  late List<SpecBatchEntry> _entries = widget.entries;
  int? _editing;
  final _titleField = TextEditingController();
  final _titleFocus = FocusNode();
  late final _createAction = _CreateAction(this);

  BatchPlan get _plan => planBatch(
    _entries,
    existing: widget.existing,
    nextNumber: widget.nextNumber,
  );

  bool get _canCreate {
    final p = _plan;
    return p.toCreate.isNotEmpty && !p.hasCycle;
  }

  @override
  void initState() {
    super.initState();
    _titleFocus.addListener(() {
      if (!_titleFocus.hasFocus && _editing != null) _commitTitle();
    });
  }

  @override
  void dispose() {
    _titleField.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _set(int index, SpecBatchEntry Function(SpecBatchEntry e) f) {
    setState(() {
      _entries = [for (final e in _entries) e.item.index == index ? f(e) : e];
    });
  }

  void _startEdit(SpecBatchEntry e) {
    setState(() {
      _editing = e.item.index;
      _titleField.text = e.effectiveTitle;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _titleFocus.requestFocus();
      _titleField.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _titleField.text.length,
      );
    });
  }

  void _commitTitle() {
    final row = _editing;
    if (row == null) return;
    final t = _titleField.text.trim();
    setState(() => _editing = null);
    if (t.isNotEmpty) _set(row, (e) => e.copyWith(title: t));
  }

  void _cancelEdit() {
    setState(() => _editing = null);
  }

  void _create() {
    if (!_canCreate) return;
    Navigator.pop(context, _entries);
  }

  SpecBatchEntry? _byAlias(String code) =>
      _entries.where((e) => e.item.alias == code).firstOrNull;

  Future<void> _preview(SpecBatchEntry e, BatchPlan plan) async {
    final code = plan.codes[e.item.index] ?? e.item.label;
    final text = batchSpecText(e, code, plan.deps[e.item.index] ?? const []);
    await showAppDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppColors.panelSolid,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$code · ${e.effectiveTitle}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fechar',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('spec-batch-preview'),
                  padding: const EdgeInsets.all(16),
                  child: MarkdownBody(
                    data: SpecDocument.parse(text).body,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final anyCreated = _entries.any((e) => e.created != null);
    final n = plan.toCreate.length;
    var focusedWarning = false;
    String footer = 'Entram como rascunho na Bandeja do Quadro';
    if (plan.existingDeps.isNotEmpty) {
      final d = plan.existingDeps.first;
      final row = _entries.firstWhere((e) => e.item.index == d.row);
      footer =
          'A ${row.item.label} depende da ${d.alias}, que já existe como '
          '${d.code}';
    }
    final cycle = plan.hasCycle;

    Widget row(SpecBatchEntry e) {
      final i = e.item.index;
      final created = e.created;
      final code = plan.codes[i];
      final warnings = plan.warnings[i] ?? const <BatchWarning>[];
      final selected = e.willCreate;
      final hasWarning = warnings.isNotEmpty;
      final deps = e.effectiveDeps;
      final titleStyle = TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: selected ? AppColors.text : AppColors.textSecondary,
      );
      final Widget title = _editing == i
          ? SizedBox(
              width: 280,
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
                },
                child: Actions(
                  actions: {
                    DismissIntent: CallbackAction<DismissIntent>(
                      onInvoke: (_) {
                        _cancelEdit();
                        return null;
                      },
                    ),
                  },
                  child: TextField(
                    key: ValueKey('spec-batch-title-field-$i'),
                    controller: _titleField,
                    focusNode: _titleFocus,
                    style: titleStyle,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                    ),
                    onSubmitted: (_) => _commitTitle(),
                  ),
                ),
              ),
            )
          : Semantics(
              button: created == null,
              label: created == null ? 'Editar título' : null,
              child: GestureDetector(
                key: ValueKey('spec-batch-title-$i'),
                onTap: created == null ? () => _startEdit(e) : null,
                child: Text(
                  e.effectiveTitle,
                  style: titleStyle.copyWith(
                    decoration: created == null
                        ? TextDecoration.underline
                        : null,
                    decorationStyle: TextDecorationStyle.dashed,
                    decorationColor: AppColors.borderHover,
                  ),
                ),
              ),
            );
      return Container(
        key: ValueKey('spec-batch-row-$i'),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceRaisedSolid : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected && hasWarning
                ? AppColors.amber
                : selected
                ? AppColors.border
                : Colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  key: ValueKey('spec-batch-check-$i'),
                  value: created == null && e.checked,
                  activeColor: AppColors.amber,
                  checkColor: AppColors.onAmber,
                  side: const BorderSide(color: AppColors.borderHover),
                  autofocus:
                      i == _entries.first.item.index && plan.warnings.isEmpty,
                  semanticLabel: created == null
                      ? '${e.item.label} ${e.effectiveTitle}'
                      : '${e.item.label} ${e.effectiveTitle}, já criada como '
                            '${created.code}',
                  onChanged: created != null
                      ? null
                      : (v) => _set(i, (x) => x.copyWith(checked: v ?? false)),
                ),
                Text(
                  e.item.label,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (created == null && code != null) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '→',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    code,
                    key: ValueKey('spec-batch-code-$i'),
                    style: _amberMono.copyWith(fontSize: 12),
                  ),
                ],
                const SizedBox(width: 10),
                Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: title),
                ),
                if (created != null) ...[
                  Container(
                    key: ValueKey('spec-batch-created-$i'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: SessionColors.runningToolBg,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: SessionColors.runningToolBorder,
                      ),
                    ),
                    child: Text(
                      '✓ já criada · ${created.code}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.teal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    key: ValueKey('spec-batch-open-$i'),
                    onPressed: () {
                      Navigator.pop(context);
                      openSpecInSpecs(ref, created);
                    },
                    child: const Text(
                      'Abrir',
                      style: TextStyle(fontSize: 12, color: AppColors.amber),
                    ),
                  ),
                ] else
                  TextButton.icon(
                    key: ValueKey('spec-batch-preview-$i'),
                    onPressed: () => _preview(e, plan),
                    icon: const Icon(
                      Icons.visibility_outlined,
                      size: 14,
                      color: AppColors.amber,
                    ),
                    label: const Text(
                      'Prévia',
                      style: TextStyle(fontSize: 12, color: AppColors.amber),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${requirementsLabel(e.item.requirements)}  ·',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (deps.isEmpty)
                    const Text(
                      'sem dependências',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  for (final d in deps)
                    _CodeChip(prefix: 'depende de', [
                      TextSpan(text: d, style: _amberMono),
                      if (_byAlias(d) case final t?
                          when plan.codes[t.item.index] != null &&
                              plan.codes[t.item.index] != d) ...[
                        const TextSpan(text: ' → '),
                        TextSpan(
                          text: plan.codes[t.item.index],
                          style: _amberMono,
                        ),
                      ],
                    ]),
                ],
              ),
            ),
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.only(left: 40, top: 8),
                child: Container(
                  key: ValueKey('spec-batch-warning-$i-${w.code}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: SessionColors.approvalBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: SessionColors.approvalBorder),
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 15,
                          color: AppColors.amber,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            w.message,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        if (w.kind == BatchWarningKind.unchecked)
                          Builder(
                            builder: (_) {
                              final first = !focusedWarning;
                              focusedWarning = true;
                              return TextButton(
                                key: ValueKey(
                                  'spec-batch-check-dep-$i-${w.code}',
                                ),
                                autofocus: first,
                                onPressed: () {
                                  final t = _byAlias(w.code);
                                  if (t != null) {
                                    _set(
                                      t.item.index,
                                      (x) => x.copyWith(checked: true),
                                    );
                                  }
                                },
                                child: Text(
                                  'Marcar a ${w.code}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.amber,
                                  ),
                                ),
                              );
                            },
                          ),
                        if (w.kind != BatchWarningKind.cycle ||
                            deps.contains(w.code))
                          Builder(
                            builder: (_) {
                              final first = !focusedWarning;
                              focusedWarning = true;
                              return TextButton(
                                key: ValueKey(
                                  'spec-batch-drop-dep-$i-${w.code}',
                                ),
                                autofocus: first,
                                onPressed: () => _set(
                                  i,
                                  (x) => x.copyWith(
                                    dependsOn: [
                                      for (final d in x.effectiveDeps)
                                        if (d != w.code) d,
                                    ],
                                  ),
                                ),
                                child: const Text(
                                  'Tirar a dependência',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.amber,
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): _CreateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): _CreateIntent(),
      },
      child: Actions(
        actions: {_CreateIntent: _createAction},
        child: Dialog(
          key: const ValueKey('spec-batch-dialog'),
          backgroundColor: AppColors.panelSolid,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 14, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.layers_outlined,
                          size: 18,
                          color: AppColors.amber,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: const Text(
                                'Criar specs da resposta',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              anyCreated
                                  ? 'Esta resposta já virou specs antes. Só o '
                                        'que é novo pode ser criado.'
                                  : 'Marque as que quer criar. Os códigos '
                                        'provisórios viram os próximos números '
                                        'livres, também no depende-de.',
                              key: const ValueKey('spec-batch-subtitle'),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('spec-batch-close'),
                        tooltip: 'Fechar',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: Semantics(
                    container: true,
                    label: 'Specs da resposta',
                    explicitChildNodes: true,
                    child: FocusTraversalGroup(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(12),
                        children: [for (final e in _entries) row(e)],
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.inbox_outlined,
                        size: 15,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          cycle
                              ? 'Há um ciclo de dependências: tire uma delas '
                                    'para criar.'
                              : footer,
                          key: const ValueKey('spec-batch-footer'),
                          style: TextStyle(
                            fontSize: 12,
                            color: cycle
                                ? AppColors.amber
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      SmallButton(
                        key: const ValueKey('spec-batch-cancel'),
                        label: 'Cancelar',
                        height: 34,
                        background: Colors.transparent,
                        onTap: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      SmallButton(
                        key: const ValueKey('spec-batch-create'),
                        label: n == 0
                            ? 'Nada novo para criar'
                            : n == 1
                            ? 'Criar 1 spec'
                            : 'Criar $n specs',
                        height: 34,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onAmber,
                        border: AppColors.amber,
                        background: AppColors.amber,
                        semanticLabel: cycle
                            ? 'Criar desligado: há um ciclo de dependências'
                            : null,
                        onTap: _canCreate ? _create : null,
                      ),
                    ],
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
