import 'package:flutter/foundation.dart';

import 'conflict_resolution.dart' show ResolutionState;
import 'review_logic.dart';

/// Pure rules of the queue as stacks (SPEC-032 R1–R3, R5, R8).

/// Specs of "Aguardando review" that depend on each other, from the base
/// (merged first) to the top. A spec with no mother nor children in the
/// queue is a stack of one ("Avulsas").
@immutable
class ReviewStack {
  const ReviewStack(this.items);

  final List<ReviewItem> items;

  bool get isStack => items.length > 1;
}

/// Item of [items] whose branch [item] was created from (its mother), or
/// null.
ReviewItem? motherOf(ReviewItem item, List<ReviewItem> items) {
  final base = item.session.baseBranch;
  if (base == null || base.isEmpty) return null;
  for (final o in items) {
    if (!identical(o, item) &&
        o.session.id != item.session.id &&
        o.session.branch == base) {
      return o;
    }
  }
  return null;
}

/// Orders the queue by dependency (R1) and groups the stacks (R2): stacks
/// first, then the loose specs, then items without a spec (tasks). Between
/// unrelated specs, [waves] (`dependencyWaves`) and then the spec code
/// decide; the base of each stack comes first.
List<ReviewStack> orderQueue(
  List<ReviewItem> items, {
  Map<int, int> waves = const {},
}) {
  final children = <String, List<ReviewItem>>{};
  final mother = <String, ReviewItem?>{};
  for (final i in items) {
    final m = motherOf(i, items);
    mother[i.session.id] = m;
    if (m != null) children.putIfAbsent(m.session.id, () => []).add(i);
  }
  final index = {for (final (n, i) in items.indexed) i.session.id: n};
  // Ties keep the order of the sessions (List.sort is not stable).
  int compare(ReviewItem a, ReviewItem b) {
    final sa = a.spec, sb = b.spec;
    int byIndex() => index[a.session.id]!.compareTo(index[b.session.id]!);
    if (sa == null || sb == null) {
      if (sa != null) return -1;
      if (sb != null) return 1;
      final t = a.session.startedAt.compareTo(b.session.startedAt);
      return t != 0 ? t : byIndex();
    }
    final w = (waves[sa.id] ?? 0).compareTo(waves[sb.id] ?? 0);
    if (w != 0) return w;
    final c = sa.code.compareTo(sb.code);
    return c != 0 ? c : byIndex();
  }

  for (final list in children.values) {
    list.sort(compare);
  }
  final seen = <String>{};
  List<ReviewItem> walk(ReviewItem root) {
    final out = <ReviewItem>[];
    void visit(ReviewItem i) {
      if (!seen.add(i.session.id)) return;
      out.add(i);
      for (final c in children[i.session.id] ?? const <ReviewItem>[]) {
        visit(c);
      }
    }

    visit(root);
    return out;
  }

  final roots = items.where((i) => mother[i.session.id] == null).toList()
    ..sort(compare);
  final groups = [for (final r in roots) ReviewStack(walk(r))];
  // A cycle (should not happen) has no root: it is broken by the code.
  final rest = items.where((i) => !seen.contains(i.session.id)).toList()
    ..sort(compare);
  for (final r in rest) {
    if (!seen.contains(r.session.id)) groups.add(ReviewStack(walk(r)));
  }
  int rank(ReviewStack s) => s.isStack
      ? 0
      : s.items.first.spec != null
      ? 1
      : 2;
  final ordered = [
    for (final k in [0, 1, 2]) ...groups.where((g) => rank(g) == k),
  ];
  return ordered;
}

/// Items of [stacks] in reading order.
List<ReviewItem> flatten(List<ReviewStack> stacks) => [
  for (final s in stacks) ...s.items,
];

/// Item to select after [merged] entered its base (R5): its first child,
/// else the next item of the order, else the previous one.
ReviewItem? nextAfterMerge(List<ReviewItem> items, String mergedSessionId) {
  final order = flatten(orderQueue(items));
  final index = order.indexWhere((i) => i.session.id == mergedSessionId);
  if (index < 0) return order.firstOrNull;
  final merged = order[index];
  final child = order
      .where((i) => motherOf(i, items)?.session.id == merged.session.id)
      .firstOrNull;
  if (child != null) return child;
  if (index + 1 < order.length) return order[index + 1];
  return index > 0 ? order[index - 1] : null;
}

/// Merge state of a queue item, shown with icon and text (R3).
enum MergeState {
  verificando('Verificando…'),
  pronto('Pronto para merge'),
  esperaMae('Espera'),
  conflito('Conflito'),
  conflitoBase('Conflito ao refazer a base'),
  baseDesatualizada('Base desatualizada'),
  revisando('Revisor revisando'),
  rebaseManual('Rebase em andamento'),
  pendencias('Pendências'),

  /// Conflict resolved by the agent, checked by the gate (SPEC-043 R2).
  resolvendo('Agente resolvendo o conflito…'),
  conferindo('Conferindo a resolução…'),
  resolvida('Conflito resolvido · gate aprovado'),
  reprovada('Resolução reprovada no gate'),
  resolucaoDesatualizada('A base mudou · resolver de novo');

  const MergeState(this.label);

  final String label;
}

/// State of an item and the detail of its text ("SPEC-029", the file).
@immutable
class MergeStatus {
  const MergeStatus(this.state, {this.detail});

  final MergeState state;

  /// Code of the mother ([MergeState.esperaMae]) or conflicting file(s).
  final String? detail;

  /// Short text of the card: "Espera SPEC-029", "Conflito em lib/a.dart".
  String get text => switch (state) {
    MergeState.esperaMae when detail != null => 'Espera $detail',
    MergeState.conflito when detail != null => 'Conflito em $detail',
    MergeState.rebaseManual when detail != null =>
      'Rebase em andamento · $detail',
    MergeState.conferindo when detail != null =>
      'Conferindo a resolução · $detail',
    MergeState.reprovada when detail != null =>
      'Resolução reprovada no gate · $detail',
    _ => state.label,
  };

  @override
  bool operator ==(Object other) =>
      other is MergeStatus && other.state == state && other.detail == detail;

  @override
  int get hashCode => Object.hash(state, detail);
}

/// Precedence of the states of an item (R3): the reviewer still reviewing,
/// then the mother not merged, a failed restack, a predicted conflict,
/// pendencies, and only then ready. [conflictFiles] null = not checked yet.
/// A conflict resolution (SPEC-043 R2) in progress, failed or outdated
/// comes first; an approved one replaces "ready". [resolutionDetail]: the
/// gate item running or the first that failed.
MergeStatus mergeStatusOf({
  ResolutionState? resolution,
  String? resolutionDetail,
  String? rebaseStep,
  bool reviewing = false,
  String? motherCode,
  bool restackConflict = false,
  bool staleBase = false,
  List<String>? conflictFiles,
  bool pending = false,
}) {
  switch (resolution) {
    case ResolutionState.resolvendo:
      return const MergeStatus(MergeState.resolvendo);
    case ResolutionState.conferindo:
      return MergeStatus(MergeState.conferindo, detail: resolutionDetail);
    case ResolutionState.reprovada when rebaseStep == null:
      return MergeStatus(MergeState.reprovada, detail: resolutionDetail);
    case ResolutionState.desatualizada when rebaseStep == null:
      return const MergeStatus(MergeState.resolucaoDesatualizada);
    default:
  }
  // A manual rebase in the worktree is the dominant fact (R17).
  if (rebaseStep != null) {
    return MergeStatus(MergeState.rebaseManual, detail: rebaseStep);
  }
  if (reviewing) return const MergeStatus(MergeState.revisando);
  if (motherCode != null) {
    return MergeStatus(MergeState.esperaMae, detail: motherCode);
  }
  if (restackConflict) return const MergeStatus(MergeState.conflitoBase);
  if (staleBase) return const MergeStatus(MergeState.baseDesatualizada);
  if (conflictFiles != null && conflictFiles.isNotEmpty) {
    final first = conflictFiles.first;
    return MergeStatus(
      MergeState.conflito,
      detail: conflictFiles.length == 1
          ? first
          : '$first +${conflictFiles.length - 1}',
    );
  }
  if (pending) return const MergeStatus(MergeState.pendencias);
  if (resolution == ResolutionState.aprovada) {
    return const MergeStatus(MergeState.resolvida);
  }
  if (conflictFiles == null) return const MergeStatus(MergeState.verificando);
  return const MergeStatus(MergeState.pronto);
}

/// The single primary action of the header for each state (R8).
enum PrimaryAction {
  fazerMerge('Fazer merge'),
  mergearPr('Mergear PR'),
  irParaMae('Ir para'),
  resolverConflito('Resolver conflito'),
  refazerBase('Refazer agora'),
  pedirAjustes('Pedir ajustes ao agente'),
  abrirEditor('Abrir no editor'),
  corrigirVerificar('Corrigir e verificar'),
  resolverDeNovo('Resolver de novo'),
  nenhuma('');

  const PrimaryAction(this.label);

  final String label;
}

/// Primary action of [status] (R8). While the forecast is still running the
/// merge stays the primary action (it will be enabled or not by readiness).
PrimaryAction primaryActionOf(MergeStatus status, {required bool hasPr}) =>
    switch (status.state) {
      MergeState.pronto ||
      MergeState.verificando ||
      MergeState.resolvendo ||
      MergeState.conferindo ||
      MergeState.resolvida =>
        hasPr ? PrimaryAction.mergearPr : PrimaryAction.fazerMerge,
      MergeState.reprovada => PrimaryAction.corrigirVerificar,
      MergeState.resolucaoDesatualizada => PrimaryAction.resolverDeNovo,
      MergeState.esperaMae => PrimaryAction.irParaMae,
      MergeState.conflito ||
      MergeState.conflitoBase => PrimaryAction.resolverConflito,
      MergeState.baseDesatualizada => PrimaryAction.refazerBase,
      MergeState.pendencias => PrimaryAction.pedirAjustes,
      MergeState.revisando => PrimaryAction.nenhuma,
      MergeState.rebaseManual => PrimaryAction.abrirEditor,
    };

/// Label of the primary action, with the mother's code for "Ir para".
String primaryLabel(PrimaryAction a, MergeStatus s) =>
    a == PrimaryAction.irParaMae ? 'Ir para ${s.detail ?? 'a mãe'}' : a.label;

/// Accessible label of a card (R14): "SPEC-031, 2 de 2 na pilha, espera
/// SPEC-029".
String queueSemanticLabel({
  required String title,
  int? position,
  int? stackSize,
  required MergeStatus status,
}) {
  final parts = [
    title,
    if (position != null && stackSize != null && stackSize > 1)
      '$position de $stackSize na pilha',
    status.text.substring(0, 1).toLowerCase() + status.text.substring(1),
  ];
  return parts.join(', ');
}
