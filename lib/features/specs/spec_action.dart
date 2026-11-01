import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Actions of the Specs screen that lock the spec while they run
/// (SPEC-025 R1).
enum SpecActionKind {
  design(
    headerId: 'design',
    running: 'Gerando design…',
    lockLabel: 'Bloqueada: gerando o design',
    failure: 'Não foi possível gerar o design.',
    long: true,
  ),
  approve(
    headerId: 'approve',
    running: 'Aprovando…',
    lockLabel: 'Somente leitura enquanto aprova',
    failure: 'Não foi possível aprovar a spec.',
  ),
  clone(
    headerId: 'clone',
    running: 'Clonando…',
    lockLabel: 'Somente leitura enquanto clona',
    failure: 'Não foi possível clonar a spec.',
  ),
  refine(
    headerId: 'refine',
    running: 'Abrindo conversa…',
    lockLabel: 'Somente leitura enquanto abre a conversa',
    failure: 'Não foi possível abrir a conversa.',
  ),
  screens(
    headerId: 'generate',
    running: 'Gerando telas…',
    lockLabel: 'Bloqueada: gerando as telas',
    failure: 'Não foi possível gerar as telas.',
    long: true,
  ),

  /// "Aplicar respostas" with "Atualizar requisitos e critérios" (SPEC-028
  /// R10): the Claude rewrites the spec text, shown as a diff before saving.
  answers(
    headerId: 'answers',
    running: 'Aplicando respostas…',
    lockLabel: 'Bloqueada: aplicando as respostas',
    failure: 'Não foi possível aplicar as respostas.',
    long: true,
  );

  const SpecActionKind({
    required this.headerId,
    required this.running,
    required this.lockLabel,
    required this.failure,
    this.long = false,
  });

  /// [SpecAction.id] of the header button that started it.
  final String headerId;

  /// Gerund label of the button while it runs (R2).
  final String running;

  /// Text of the tabs line while it runs (R6).
  final String lockLabel;

  /// Title of the failure alert (R8).
  final String failure;

  /// Long actions show the status strip and ask before leaving (R3, R7).
  final bool long;

  /// Title of the status strip (R3).
  String title(String code) => switch (this) {
    screens => 'Gerando as telas de $code…',
    answers => 'Atualizando requisitos de $code com as respostas…',
    _ => 'Gerando o design de $code…',
  };

  /// What is still running, in the leave dialog (R7).
  String get stillRunning => switch (this) {
    screens => 'As telas ainda estão sendo geradas.',
    answers => 'As respostas ainda estão sendo aplicadas.',
    _ => 'O design ainda está sendo gerado.',
  };
}

/// Thrown by an action that was cancelled (R5).
class SpecActionCancelled implements Exception {
  const SpecActionCancelled();

  @override
  String toString() => 'Geração cancelada.';
}

/// The action in progress (R1): which one, on which spec, since when, and
/// how to cancel it.
class SpecActionState {
  SpecActionState({
    required this.kind,
    required this.specId,
    required this.specCode,
    DateTime? startedAt,
    this.fromKeyboard = false,
  }) : startedAt = startedAt ?? DateTime.now();

  final SpecActionKind kind;
  final int specId;
  final String specCode;
  final DateTime startedAt;

  /// Started from the keyboard: the strip takes the focus (R11).
  final bool fromKeyboard;

  /// Completed by "Cancelar geração" / Esc (R5); passed to the agent run as
  /// `cancelled`.
  final cancel = Completer<void>();

  bool get cancelled => cancel.isCompleted;

  Future<void> get cancelledFuture => cancel.future;
}

/// The action in progress of the Specs screen; null = none (replaces the
/// old `_busy`).
class SpecActionController extends Notifier<SpecActionState?> {
  @override
  SpecActionState? build() => null;

  /// The action in progress (null = none).
  SpecActionState? get current => state;

  /// Starts [kind] on the spec; null when another action is running (R2:
  /// one at a time).
  SpecActionState? start(
    SpecActionKind kind, {
    required int specId,
    required String specCode,
    bool fromKeyboard = false,
  }) {
    if (state != null) return null;
    final a = SpecActionState(
      kind: kind,
      specId: specId,
      specCode: specCode,
      fromKeyboard: fromKeyboard,
    );
    state = a;
    return a;
  }

  /// Ends [a] (no-op when another action took its place).
  void finish(SpecActionState a) {
    if (identical(state, a)) state = null;
  }

  /// "Cancelar geração" (R5): the runner sees `cancelled` and stops.
  void cancel() {
    final a = state;
    if (a != null && !a.cancel.isCompleted) a.cancel.complete();
  }
}

final specActionProvider =
    NotifierProvider<SpecActionController, SpecActionState?>(
      SpecActionController.new,
    );

/// Whether [specId] can be changed now: not started (`stage == backlog`,
/// [stageLocked] false) and no action running on it (R1).
bool specLocked({
  required int specId,
  required bool stageLocked,
  SpecActionState? action,
}) => stageLocked || action?.specId == specId;

/// "1 min 12 s" (R3).
String formatElapsed(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${s ~/ 60} min ${s % 60} s';
}

/// First line of an error, without the exception class name (R8).
String errorCause(Object e) {
  var text = '$e'.trim();
  for (final prefix in ['Exception: ', 'PlannerException: ']) {
    if (text.startsWith(prefix)) text = text.substring(prefix.length);
  }
  final line = text.split('\n').first.trim();
  if (line.isEmpty) return 'Erro desconhecido.';
  return RegExp(r'[.!?…]$').hasMatch(line) ? line : '$line.';
}
