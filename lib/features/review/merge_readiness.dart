/// Pure classification shared by the header, panel and merge controls.
enum ReadinessLevel { ok, aviso, bloqueio, naoVerificado }

enum ReadinessOrigin { servico, tela }

class ReadinessItem {
  const ReadinessItem(
    this.id,
    this.label,
    this.level,
    this.detail, {
    this.blocking = false,
    this.origin = ReadinessOrigin.servico,
    this.action,
    this.targets = const [],
  });
  final String id, label, detail;
  final ReadinessLevel level;
  final bool blocking;
  final ReadinessOrigin origin;
  final String? action;

  /// What the action opens (the failing steps of `verificacoes`).
  final List<String> targets;
  ReadinessLevel get effective => level == ReadinessLevel.naoVerificado
      ? (blocking ? ReadinessLevel.bloqueio : ReadinessLevel.aviso)
      : level;
}

class MergeReadiness {
  const MergeReadiness(this.items);
  final List<ReadinessItem> items;
  List<ReadinessItem> get blockers =>
      items.where((i) => i.effective == ReadinessLevel.bloqueio).toList();
  List<ReadinessItem> get warnings =>
      items.where((i) => i.effective == ReadinessLevel.aviso).toList();
  bool get canOverride =>
      blockers.isNotEmpty &&
      blockers.every(
        (i) => i.id == 'criterios' && i.level != ReadinessLevel.naoVerificado,
      );
  ReadinessLevel get level => blockers.isNotEmpty
      ? ReadinessLevel.bloqueio
      : warnings.isNotEmpty
      ? ReadinessLevel.aviso
      : ReadinessLevel.ok;
  String get summary => blockers.isNotEmpty
      ? 'Bloqueado · ${blockers.length} bloqueios · ${warnings.length} avisos'
      : warnings.isNotEmpty
      ? 'Com avisos · ${warnings.length}'
      : 'Pronto para merge';
}

class ReadinessInputs {
  const ReadinessInputs({
    this.hasSpec = false,
    this.reviewing = false,
    this.reviewerFailed = false,
    this.pendingCriteria = const [],
    this.failedGates = const [],
    this.prProblem,
    this.openComments = 0,
    this.stackedOn,
    this.rootProblem,
    this.worktreeProblem,
    this.uncommitted = 0,
    this.unknown = const {},
  });
  final bool hasSpec, reviewing;

  /// The automatic reviewer failed and handed the spec to the user.
  final bool reviewerFailed;
  final List<String> pendingCriteria, failedGates;
  final String? prProblem, stackedOn, rootProblem, worktreeProblem;
  final int openComments, uncommitted;
  final Map<String, String> unknown;
}

MergeReadiness evaluateReadiness(ReadinessInputs f) {
  ReadinessItem item(
    String id,
    String label,
    String? problem, {
    bool blocking = false,
    String? action,
    ReadinessOrigin origin = ReadinessOrigin.servico,
    List<String> targets = const [],
  }) => ReadinessItem(
    id,
    label,
    f.unknown.containsKey(id)
        ? ReadinessLevel.naoVerificado
        : problem == null
        ? ReadinessLevel.ok
        : blocking
        ? ReadinessLevel.bloqueio
        : ReadinessLevel.aviso,
    f.unknown[id] ?? problem ?? 'OK',
    blocking: blocking,
    origin: origin,
    action: action,
    targets: targets,
  );
  final reviewer = item(
    'revisor',
    'Revisor automático',
    f.reviewing ? 'O revisor automático ainda está revisando' : null,
    blocking: true,
    origin: ReadinessOrigin.tela,
    action: 'Pular revisor',
  );
  return MergeReadiness([
    if (f.hasSpec) ...[
      if (reviewer.level == ReadinessLevel.ok && f.reviewerFailed)
        const ReadinessItem(
          'revisor',
          'Revisor automático',
          ReadinessLevel.aviso,
          'O revisor automático falhou e passou para você',
          blocking: true,
          origin: ReadinessOrigin.tela,
        )
      else
        reviewer,
      item(
        'criterios',
        'Critérios de aceite',
        f.pendingCriteria.isEmpty
            ? null
            : '${f.pendingCriteria.length} critérios sem marcar',
        blocking: true,
        action: 'Marcar critérios',
      ),
      item(
        'verificacoes',
        'Verificações das etapas',
        f.failedGates.isEmpty ? null : 'Falharam: ${f.failedGates.join(', ')}',
        action: 'Abrir etapa',
        targets: f.failedGates,
      ),
      item(
        'comentarios',
        'Comentários abertos',
        f.openComments == 0 ? null : '${f.openComments} comentários abertos',
        action: 'Ver comentários',
      ),
    ],
    item('pr', 'PR', f.prProblem, action: 'Verificar PR'),
    item(
      'empilhada',
      'Spec empilhada',
      f.stackedOn == null ? null : 'Faça o merge de ${f.stackedOn} primeiro',
      blocking: true,
      action: 'Abrir dependência',
    ),
    item('raiz', 'Repositório principal', f.rootProblem, blocking: true),
    item(
      'worktree',
      'Worktree',
      f.worktreeProblem ??
          (f.uncommitted > 0
              ? '${f.uncommitted} alterações serão commitadas'
              : null),
      blocking: f.worktreeProblem != null || f.unknown.containsKey('worktree'),
    ),
  ]);
}
