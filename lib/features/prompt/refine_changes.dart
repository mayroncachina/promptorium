import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/agent_event.dart' show PermissionRequest;
import '../../core/text/line_diff.dart';
import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/diff_view.dart';
import '../sessions/edit_diff.dart';
import '../sessions/session_manager.dart' show PendingApproval;
import '../sessions/timeline.dart';
import '../sessions/widgets/session_style.dart';
import '../specs/spec_file.dart' show specStatusLabel;
import '../specs/spec_service.dart' show specServiceProvider;
import '../specs/specs_screen.dart' show SpecPreview;
import 'conversation_manager.dart';
import 'refine_origin.dart';

// --- model (pure) ---------------------------------------------------------------

/// Edits of a refine conversation on the spec it came from (SPEC-026 R5).
class RefineProgress {
  RefineProgress({
    required this.workspace,
    required this.spec,
    required this.specPath,
    required this.baseText,
    required this.edits,
    required this.applied,
    required this.pending,
    required this.denied,
    required this.expectedText,
    required this.added,
    required this.removed,
  });

  final Workspace workspace;
  final Spec spec;

  /// Absolute path of the spec file.
  final String specPath;

  /// Spec text when the conversation started (R8); null for older ones.
  final String? baseText;

  /// What each edit card shows, by `tool_use_id` (R2, R11).
  final Map<String, EditInfo> edits;

  /// Edits applied to the spec, in order.
  final List<ToolItem> applied;

  /// Spec edits waiting for approval.
  final int pending;

  /// Spec edits denied (R4): not counted anywhere else.
  final int denied;

  /// Base text with the applied edits replayed (null when unknown).
  final String? expectedText;

  /// Lines added / removed by the applied edits since the start.
  final int added;
  final int removed;

  String get code => spec.code;

  /// Card of a pending approval (diff against the known spec text).
  EditInfo? approvalInfo(PermissionRequest r) {
    final id = r.toolUseId;
    if (id != null && edits[id] != null) return edits[id];
    if (!isEditTool(r.toolName)) return null;
    final path = editFilePath(r.input);
    final abs = path == null ? null : absolutePath(path, workspace.path);
    final onSpec = abs == specPath;
    final diff = editDiffOf(
      r.toolName,
      r.input,
      before: onSpec ? expectedText : null,
    );
    return EditInfo(
      diff: diff,
      target: onSpec ? _target(code, diff?.section) : null,
      outside: !onSpec,
    );
  }
}

String _target(String code, String? section) =>
    section == null ? code : '$code · $section';

/// Works out [RefineProgress] from the conversation [items].
RefineProgress refineProgressOf({
  required Workspace workspace,
  required Spec spec,
  required List<TimelineItem> items,
  String? baseText,
  List<PendingApproval> approvals = const [],
}) {
  final specPath = absolutePath(spec.path, workspace.path);
  final diffs = editDiffsOf(
    items,
    known: {specPath: ?baseText},
    root: workspace.path,
  );
  final edits = <String, EditInfo>{};
  final applied = <ToolItem>[];
  var denied = 0;
  for (final t in editToolsOf(items)) {
    final path = editFilePath(t.input);
    final onSpec =
        path != null && absolutePath(path, workspace.path) == specPath;
    final d = diffs[t.id];
    edits[t.id] = EditInfo(
      diff: d,
      target: onSpec ? _target(spec.code, d?.section) : null,
      outside: !onSpec,
    );
    if (!onSpec) continue;
    if (t.denied) {
      denied++;
    } else if (editApplied(t)) {
      applied.add(t);
    }
  }
  var pending = 0;
  for (final a in approvals) {
    final r = a.request;
    final p = editFilePath(r.input);
    if (isEditTool(r.toolName) &&
        p != null &&
        absolutePath(p, workspace.path) == specPath) {
      pending++;
    }
  }
  final expected = baseText == null
      ? null
      : textAfterEdits(items, specPath, base: baseText, root: workspace.path);
  var added = 0, removed = 0;
  if (baseText != null && expected != null) {
    for (final l in lineDiff(baseText, expected)) {
      if (l.op == DiffOp.add) added++;
      if (l.op == DiffOp.del) removed++;
    }
  } else {
    for (final t in applied) {
      added += diffs[t.id]?.added ?? 0;
      removed += diffs[t.id]?.removed ?? 0;
    }
  }
  return RefineProgress(
    workspace: workspace,
    spec: spec,
    specPath: specPath,
    baseText: baseText,
    edits: edits,
    applied: applied,
    pending: pending,
    denied: denied,
    expectedText: expected,
    added: added,
    removed: removed,
  );
}

/// Spec edits applied in the last turn (after the last user message).
int appliedInLastTurn(List<TimelineItem> items, RefineProgress p) {
  var start = 0;
  for (var i = items.length - 1; i >= 0; i--) {
    if (items[i] is UserItem) {
      start = i + 1;
      break;
    }
  }
  final ids = {for (final t in p.applied) t.id};
  return editToolsOf(items.sublist(start))
      .where((t) => ids.contains(t.id))
      .length;
}

/// `## ` sections of [text]: title → lines, in order.
Map<String, List<String>> _sections(String text) {
  final out = <String, List<String>>{};
  List<String>? cur;
  for (final l in text.split('\n')) {
    if (l.startsWith('## ')) {
      cur = out.putIfAbsent(l.substring(3).trim(), () => []);
    } else {
      cur?.add(l);
    }
  }
  return out;
}

final _req = RegExp(r'^- (R\d+) ·');
final _criterion = RegExp(r'^- \[[ xX]\] ');

String _count(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// What changed in one section: requirements and criteria touched, or the
/// line count.
String _sectionChange(List<String> before, List<String> after) {
  final parts = <String>[];
  Map<String, String> reqs(List<String> lines) => {
    for (final l in lines)
      if (_req.firstMatch(l) case final m?) m.group(1)!: l,
  };
  final rb = reqs(before), ra = reqs(after);
  for (final MapEntry(:key, :value) in ra.entries) {
    if (!rb.containsKey(key)) {
      parts.add('$key novo');
    } else if (rb[key] != value ||
        _reqBody(before, key) != _reqBody(after, key)) {
      parts.add('$key reescrito');
    }
  }
  for (final k in rb.keys) {
    if (!ra.containsKey(k)) parts.add('$k removido');
  }
  final cb = [
    for (final l in before)
      if (_criterion.hasMatch(l)) l,
  ];
  final ca = [
    for (final l in after)
      if (_criterion.hasMatch(l)) l,
  ];
  var add = 0, del = 0;
  for (final d in lineDiff(cb.join('\n'), ca.join('\n'))) {
    if (d.op == DiffOp.add && d.text.isNotEmpty) add++;
    if (d.op == DiffOp.del && d.text.isNotEmpty) del++;
  }
  final rewritten = add < del ? add : del;
  if (rewritten > 0) parts.add(_count(rewritten, 'reescrito', 'reescritos'));
  if (add - rewritten > 0) {
    parts.add(_count(add - rewritten, 'novo', 'novos'));
  }
  if (del - rewritten > 0) {
    parts.add(_count(del - rewritten, 'removido', 'removidos'));
  }
  if (parts.isNotEmpty) return parts.join(', ');
  var a = 0, d = 0;
  for (final l in lineDiff(before.join('\n'), after.join('\n'))) {
    if (l.op == DiffOp.add) a++;
    if (l.op == DiffOp.del) d++;
  }
  return '+$a −$d linhas';
}

/// Lines of requirement [id] (its line and the indented continuation).
String _reqBody(List<String> lines, String id) {
  final out = <String>[];
  var inside = false;
  for (final l in lines) {
    final m = _req.firstMatch(l);
    if (m != null) {
      inside = m.group(1) == id;
      if (inside) out.add(l);
    } else if (inside && l.startsWith('  ')) {
      out.add(l);
    } else {
      inside = false;
    }
  }
  return out.join('\n');
}

/// One line per changed section between [base] and [current] (R6).
List<({String section, String change})> refineSectionChanges(
  String base,
  String current,
) {
  final b = _sections(base), a = _sections(current);
  final out = <({String section, String change})>[];
  for (final MapEntry(:key, :value) in a.entries) {
    final old = b[key];
    if (old == null) {
      out.add((section: key, change: 'seção nova'));
    } else if (old.join('\n').trimRight() != value.join('\n').trimRight()) {
      out.add((section: key, change: _sectionChange(old, value)));
    }
  }
  for (final k in b.keys) {
    if (!a.containsKey(k)) out.add((section: k, change: 'seção removida'));
  }
  return out;
}

/// Section lines of the summary: by text when the base is known, by edit
/// otherwise (older conversations).
List<({String section, String change})> refineSummaryLines(RefineProgress p) {
  final base = p.baseText, now = p.expectedText;
  if (base != null && now != null) return refineSectionChanges(base, now);
  final by = <String, (int, int)>{};
  for (final t in p.applied) {
    final d = p.edits[t.id]?.diff;
    if (d == null) continue;
    final k = d.section ?? 'Sem seção';
    final (a, r) = by[k] ?? (0, 0);
    by[k] = (a + d.added, r + d.removed);
  }
  return [
    for (final MapEntry(:key, :value) in by.entries)
      (section: key, change: '+${value.$1} −${value.$2} linhas'),
  ];
}

String _editions(int n) => n == 1 ? '1 edição' : '$n edições';

// --- provider -------------------------------------------------------------------

/// Changes only when an edit appears or changes state (not on every delta).
String _editSignature(List<TimelineItem> items) => [
  for (final t in editToolsOf(items))
    '${t.id}:${t.done ? 1 : 0}${t.isError ? 1 : 0}${t.denied ? 1 : 0}',
].join(',');

/// [RefineProgress] of a refine conversation with a stored origin whose
/// spec exists in the active workspace (null otherwise).
final refineProgressProvider = Provider.autoDispose
    .family<RefineProgress?, int>((ref, id) {
      final ws = ref.watch(activeWorkspaceProvider);
      if (ws == null) return null;
      Conversation? conv;
      for (final c
          in ref.watch(conversationsProvider(ws.id)).value ??
              const <Conversation>[]) {
        if (c.id == id) conv = c;
      }
      if (conv == null) return null;
      final origin = refineOriginOf(conv);
      if (origin == null) return null;
      Spec? spec;
      for (final s in ref.watch(specsProvider(ws.id)).value ?? const <Spec>[]) {
        if (s.code == origin.specCode) spec = s;
      }
      if (spec == null) return null;
      ref.watch(
        conversationTimelineProvider(id).select((s) => _editSignature(s.items)),
      );
      final items = ref.read(conversationTimelineProvider(id)).items;
      final approvals = ref.watch(
        conversationManagerProvider.select((s) => s.approvalsOf(id)),
      );
      return refineProgressOf(
        workspace: ws,
        spec: spec,
        items: items,
        baseText: conv.refineBaseText,
        approvals: approvals,
      );
    });

// --- widgets --------------------------------------------------------------------

const _label = TextStyle(fontSize: 12, color: AppColors.textSecondary);
const _mono = TextStyle(
  fontFamily: AppFonts.mono,
  fontSize: 12,
  color: AppColors.text,
);

Widget _totals(int added, int removed, {Key? key}) => Semantics(
  key: key,
  label: '$added linhas adicionadas, $removed removidas',
  excludeSemantics: true,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('+$added', style: _mono.copyWith(color: AppColors.teal)),
      const SizedBox(width: 6),
      Text('−$removed', style: _mono.copyWith(color: AppColors.red)),
    ],
  ),
);

/// "Spec em refino" of the side panel (R5).
class RefineSpecPanel extends ConsumerWidget {
  const RefineSpecPanel({super.key, required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(refineProgressProvider(conversation.id));
    if (p == null) return const SizedBox.shrink();
    Widget row(String k, String v, {Key? key}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(k, style: _label)),
          Text(v, key: key, style: _mono),
        ],
      ),
    );
    final none = p.applied.isEmpty;
    final view = SmallButton(
      key: const ValueKey('refine-view-changes'),
      label: 'Ver alterações',
      icon: Icons.difference_outlined,
      expand: true,
      color: AppColors.textSecondary,
      onTap: none
          ? null
          : () => showRefineChangesDialog(context, ref, conversation),
    );
    return Column(
      key: const ValueKey('refine-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('SPEC EM REFINO', style: sectionTitleStyle),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p.code,
                      style: _mono.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                  Text(
                    specStatusLabel(p.spec.status),
                    key: const ValueKey('refine-panel-status'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                p.spec.title,
                style: const TextStyle(fontSize: 13, color: AppColors.text),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        row(
          'Aplicadas',
          p.applied.isEmpty ? '0' : _editions(p.applied.length),
          key: const ValueKey('refine-panel-applied'),
        ),
        row(
          'Aguardando você',
          p.pending == 0 ? 'nenhuma' : _editions(p.pending),
          key: const ValueKey('refine-panel-pending'),
        ),
        row(
          'Negadas',
          p.denied == 0 ? 'nenhuma' : _editions(p.denied),
          key: const ValueKey('refine-panel-denied'),
        ),
        row(
          'Linhas aplicadas',
          '+${p.added} −${p.removed}',
          key: const ValueKey('refine-panel-lines'),
        ),
        const SizedBox(height: 4),
        none
            ? Tooltip(message: 'Nenhuma edição aplicada ainda', child: view)
            : view,
        const SizedBox(height: 18),
      ],
    );
  }
}

/// "`<código>` atualizada" under the last answer of a turn with an applied
/// spec edit (R6).
class RefineSummaryCard extends ConsumerWidget {
  const RefineSummaryCard({
    super.key,
    required this.conversation,
    required this.progress,
  });

  final Conversation conversation;
  final RefineProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = progress;
    final lines = refineSummaryLines(p);
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          key: const ValueKey('refine-summary'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: SessionColors.runningToolBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.check, size: 16, color: AppColors.teal),
                  const SizedBox(width: 8),
                  Text(
                    '${p.code} atualizada',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.applied.length == 1
                          ? '1 edição aplicada'
                          : '${p.applied.length} edições aplicadas',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  _totals(p.added, p.removed),
                ],
              ),
              const SizedBox(height: 10),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 160,
                        child: Text(l.section, style: _label),
                      ),
                      Expanded(
                        child: Text(
                          l.change,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SmallButton(
                    key: const ValueKey('refine-summary-view'),
                    label: 'Ver alterações',
                    icon: Icons.difference_outlined,
                    height: 32,
                    onTap: () =>
                        showRefineChangesDialog(context, ref, conversation),
                  ),
                  AmberButton(
                    key: const ValueKey('refine-summary-back'),
                    label: 'Voltar à ${p.code}',
                    height: 32,
                    onTap: () => backToSpec(context, ref, conversation),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Alterações do refino em `<código>`" (R7, R8): diff between the base text
/// and the file now, or the edits one by one for older conversations.
Future<void> showRefineChangesDialog(
  BuildContext context,
  WidgetRef ref,
  Conversation c,
) async {
  final p = ref.read(refineProgressProvider(c.id));
  if (p == null) return;
  String? current;
  try {
    current = await ref.read(specServiceProvider).read(p.workspace, p.spec);
  } catch (_) {
    current = null;
  }
  if (!context.mounted) return;
  final back = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (_) => _RefineChangesDialog(
      conversation: c,
      progress: p,
      current: current ?? p.expectedText ?? '',
    ),
  );
  if (back == true && context.mounted) await backToSpec(context, ref, c);
}

class _RefineChangesDialog extends StatefulWidget {
  const _RefineChangesDialog({
    required this.conversation,
    required this.progress,
    required this.current,
  });

  final Conversation conversation;
  final RefineProgress progress;
  final String current;

  @override
  State<_RefineChangesDialog> createState() => _RefineChangesDialogState();
}

class _RefineChangesDialogState extends State<_RefineChangesDialog> {
  bool _rendered = false;

  late final EditDiff? _total = widget.progress.baseText == null
      ? null
      : editDiffOf('Write', {
          'content': widget.current,
        }, before: widget.progress.baseText);

  Widget _tab(String label, bool selected, VoidCallback onTap, Key key) =>
      Semantics(
        selected: selected,
        child: InkWell(
          key: key,
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? AppColors.amber : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.text : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      );

  Widget _edits() {
    final p = widget.progress;
    return ListView(
      key: const ValueKey('refine-edits-list'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (final t in p.applied)
          if (p.edits[t.id]?.diff case final d?) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Row(
                children: [
                  Text(t.name, style: _mono.copyWith(color: AppColors.amber)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(p.edits[t.id]?.target ?? p.code, style: _mono),
                  ),
                  _totals(d.added, d.removed),
                ],
              ),
            ),
            DiffView(rows: d.rows, collapseSame: 3),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final c = widget.conversation;
    final total = _total;
    final added = total?.added ?? p.added;
    final removed = total?.removed ?? p.removed;
    final expected = p.expectedText;
    final external =
        total != null && expected != null && expected != widget.current;
    final edits = _editions(p.applied.length);
    final subtitle = p.baseText == null
        ? 'Conversa sem o texto inicial da spec: as edições uma a uma, $edits'
        : 'Comparado com a spec no início da conversa '
              '(${formatClock(c.createdAt)}), $edits';
    return Dialog(
      key: const ValueKey('refine-changes-dialog'),
      backgroundColor: AppColors.panel,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: SessionColors.selectedBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Alterações do refino em ${p.code}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(subtitle, style: _label),
                      ],
                    ),
                  ),
                  _totals(
                    added,
                    removed,
                    key: const ValueKey('refine-changes-totals'),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),
            if (external)
              Container(
                key: const ValueKey('refine-external-warning'),
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: SessionColors.approvalBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: SessionColors.approvalBorder),
                ),
                child: const Text(
                  'A spec também foi alterada fora desta conversa',
                  style: TextStyle(fontSize: 12, color: AppColors.amber),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    _tab(
                      'Diferenças',
                      !_rendered,
                      () => setState(() => _rendered = false),
                      const ValueKey('refine-tab-diff'),
                    ),
                    _tab(
                      'Spec como ficou',
                      _rendered,
                      () => setState(() => _rendered = true),
                      const ValueKey('refine-tab-rendered'),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: _rendered
                    ? SpecPreview(
                        key: const ValueKey('refine-rendered'),
                        text: widget.current,
                      )
                    : total == null
                    ? _edits()
                    : DiffView(
                        key: const ValueKey('refine-total-diff'),
                        rows: total.rows,
                        collapseSame: 3,
                        scrollable: true,
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SmallButton(
                    key: const ValueKey('refine-changes-close'),
                    label: 'Fechar',
                    height: 34,
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Text(
                        'Esc',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    onTap: () => Navigator.pop(context, false),
                  ),
                  const SizedBox(width: 8),
                  AmberButton(
                    key: const ValueKey('refine-changes-back'),
                    label: 'Voltar à ${p.code}',
                    height: 34,
                    onTap: () => Navigator.pop(context, true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
