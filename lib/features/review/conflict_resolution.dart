import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_service.dart';
import '../../core/git/worktree_setup.dart';
import '../../core/process/shell_runner.dart';
import '../../data/providers.dart';
import '../board/step_gate.dart';
import '../board/test_count.dart';
import '../project/project_config.dart';
import '../sessions/app_notifier.dart';
import '../sessions/session_manager.dart';
import '../specs/spec_service.dart';
import '../tasks/task_actions.dart';
import 'restack.dart';
import 'review_service.dart';

/// Conflict resolved by the agent, checked by the gate (SPEC-043).

/// Where a resolution is (R2).
enum ResolutionState {
  resolvendo('Agente resolvendo o conflito…'),
  conferindo('Conferindo a resolução…'),
  aprovada('Conflito resolvido · gate aprovado'),
  reprovada('Resolução reprovada no gate'),
  desatualizada('A base mudou · resolver de novo');

  const ResolutionState(this.label);

  final String label;

  /// The agent or the gate is still working on it.
  bool get active => this == resolvendo || this == conferindo;
}

/// Who started a resolution (R9).
abstract final class ResolutionOrigin {
  static const person = 'pessoa';
  static const automatic = 'automatico';
}

/// `author` of the resolution rows in the spec's review history (R9).
const resolutionAuthor = 'resolucao';

/// App setting with the resolution of a session (like the restack marks).
String resolutionKey(String sessionId) => 'review.resolucao.$sessionId';

/// Ref with the tip of the branch before the resolution (R3).
String beforeResolutionRef(String key) =>
    'refs/promptorium/$key/antes-da-resolucao';

/// One resolution of a session's conflict: state, files, the SHA before
/// it, the SHA the gate checked and the gate's report.
@immutable
class ConflictResolution {
  const ConflictResolution({
    required this.state,
    required this.workspaceId,
    this.files = const [],
    this.origin = ResolutionOrigin.person,
    this.base = 'main',
    this.beforeSha,
    this.baseSha,
    this.checkedSha,
    this.report,
    this.running,
    this.plan = const [],
    this.answer,
    this.gates = 0,
    this.autoFixUsed = false,
    this.restackMark,
    this.approvedCount,
    this.approvedAt,
    this.startedAt,
  });

  final ResolutionState state;
  final int workspaceId;

  /// Files that were in conflict.
  final List<String> files;

  /// [ResolutionOrigin.person] or [ResolutionOrigin.automatic].
  final String origin;

  /// Name of the base branch.
  final String base;

  /// Tip of the branch before the resolution (also in
  /// [beforeResolutionRef]).
  final String? beforeSha;

  /// Tip of the base the resolution must contain: when it started, then the
  /// one the last gate checked (R7).
  final String? baseSha;

  /// HEAD of the worktree the last gate checked.
  final String? checkedSha;

  /// Last gate (partial while [ResolutionState.conferindo]).
  final GateReport? report;

  /// Item of the gate running now.
  final String? running;

  /// Items the gate runs, in order ([StepGate.resolutionPlan]).
  final List<String> plan;

  /// The agent's last answer (for `## Como resolvi`, R4).
  final String? answer;

  /// Gates run so far.
  final int gates;

  /// The automatic mode already sent its single "Corrigir e verificar".
  final bool autoFixUsed;

  /// Restack mark cleared when the resolution started (restored on undo).
  final String? restackMark;

  /// Test count of the last approved gate of a resolution of this session.
  final TestCount? approvedCount;
  final DateTime? approvedAt;
  final DateTime? startedAt;

  bool get automatic => origin == ResolutionOrigin.automatic;

  /// First failed item of [report] (R2: "· testes").
  GateCheck? get firstFailure => report?.failures.firstOrNull;

  /// Text of the card and the header (R2).
  String get text => switch (state) {
    ResolutionState.conferindo when running != null =>
      'Conferindo a resolução · ${gateItemLabel(running!)}',
    ResolutionState.reprovada when firstFailure != null =>
      'Resolução reprovada no gate · ${firstFailure!.label}',
    _ => state.label,
  };

  ConflictResolution copyWith({
    ResolutionState? state,
    List<String>? files,
    String? origin,
    String? Function()? baseSha,
    String? Function()? checkedSha,
    GateReport? Function()? report,
    String? Function()? running,
    List<String>? plan,
    String? Function()? answer,
    int? gates,
    bool? autoFixUsed,
    TestCount? Function()? approvedCount,
    DateTime? Function()? approvedAt,
  }) => ConflictResolution(
    state: state ?? this.state,
    workspaceId: workspaceId,
    files: files ?? this.files,
    origin: origin ?? this.origin,
    base: base,
    beforeSha: beforeSha,
    baseSha: baseSha == null ? this.baseSha : baseSha(),
    checkedSha: checkedSha == null ? this.checkedSha : checkedSha(),
    report: report == null ? this.report : report(),
    running: running == null ? this.running : running(),
    plan: plan ?? this.plan,
    answer: answer == null ? this.answer : answer(),
    gates: gates ?? this.gates,
    autoFixUsed: autoFixUsed ?? this.autoFixUsed,
    restackMark: restackMark,
    approvedCount: approvedCount == null ? this.approvedCount : approvedCount(),
    approvedAt: approvedAt == null ? this.approvedAt : approvedAt(),
    startedAt: startedAt,
  );

  String encode() => jsonEncode({
    'estado': state.name,
    'workspace': workspaceId,
    'arquivos': files,
    'origem': origin,
    'base': base,
    'antes': ?beforeSha,
    'ponta-base': ?baseSha,
    'conferido': ?checkedSha,
    if (report != null) 'gate': report!.encode(),
    'rodando': ?running,
    'plano': plan,
    'resposta': ?answer,
    'gates': gates,
    'correcao-automatica': autoFixUsed,
    'marca-restack': ?restackMark,
    if (approvedCount != null) 'contagem-aprovada': approvedCount!.toJson(),
    if (approvedAt != null) 'aprovada-em': approvedAt!.toIso8601String(),
    if (startedAt != null) 'inicio': startedAt!.toIso8601String(),
  });

  static ConflictResolution? decode(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    try {
      final j = jsonDecode(text);
      if (j is! Map) return null;
      final state = ResolutionState.values
          .where((s) => s.name == j['estado'])
          .firstOrNull;
      if (state == null) return null;
      String? str(String k) => j[k] is String ? j[k] as String : null;
      return ConflictResolution(
        state: state,
        workspaceId: (j['workspace'] as num?)?.toInt() ?? 0,
        files: [for (final f in (j['arquivos'] as List? ?? const [])) '$f'],
        origin: str('origem') ?? ResolutionOrigin.person,
        base: str('base') ?? 'main',
        beforeSha: str('antes'),
        baseSha: str('ponta-base'),
        checkedSha: str('conferido'),
        report: GateReport.decode(str('gate')),
        running: str('rodando'),
        plan: [for (final p in (j['plano'] as List? ?? const [])) '$p'],
        answer: str('resposta'),
        gates: (j['gates'] as num?)?.toInt() ?? 0,
        autoFixUsed: j['correcao-automatica'] == true,
        restackMark: str('marca-restack'),
        approvedCount: TestCount.fromJson(j['contagem-aprovada']),
        approvedAt: DateTime.tryParse(str('aprovada-em') ?? ''),
        startedAt: DateTime.tryParse(str('inicio') ?? ''),
      );
    } on FormatException {
      return null;
    }
  }
}

/// Label of a gate item by name, before it has a [GateCheck].
String gateItemLabel(String name) => GateCheck(name: name, ok: true).label;

/// The resolution of [sessionId] (null = none), read from the app settings.
final conflictResolutionProvider = Provider.family<ConflictResolution?, String>(
  (ref, sessionId) => ConflictResolution.decode(
    ref.watch(appSettingsProvider.select((m) => m[resolutionKey(sessionId)])),
  ),
);

/// `## Como resolvi` of the agent's answer (R4, R8).
@immutable
class HowResolved {
  const HowResolved(this.files, this.section);

  /// Path → what was kept of each side.
  final Map<String, String> files;

  /// The section as written.
  final String section;

  /// Explanation of [path]: the exact path, else a line whose path ends
  /// like it (the agent may write only the file name).
  String? explain(String path) {
    if (files[path] case final e?) return e;
    final name = path.split('/').last;
    for (final MapEntry(:key, :value) in files.entries) {
      if (path.endsWith('/$key') || key.endsWith('/$path')) return value;
    }
    for (final MapEntry(:key, :value) in files.entries) {
      if (key.split('/').last == name) return value;
    }
    return null;
  }
}

/// Reads the last `## Como resolvi` of [text]: one `caminho: explicação` per
/// line, until the next heading. Null when the section is missing.
HowResolved? parseHowResolved(String? text) {
  if (text == null) return null;
  final lines = text.split('\n');
  final head = RegExp(
    r'^#{1,6}\s*como\s+resolvi\s*:?\s*$',
    caseSensitive: false,
  );
  final start = lines.lastIndexWhere((l) => head.hasMatch(l.trim()));
  if (start < 0) return null;
  final body = <String>[];
  for (final l in lines.skip(start + 1)) {
    if (RegExp(r'^#{1,6}\s').hasMatch(l.trim())) break;
    body.add(l);
  }
  final files = <String, String>{};
  for (final raw in body) {
    var l = raw.trim().replaceFirst(RegExp(r'^[-*+]\s+'), '');
    if (l.isEmpty) continue;
    final m = RegExp(r'^`?([^`:\s][^`:]*?)`?\s*:\s+(.+)$').firstMatch(l);
    if (m == null) continue;
    l = m.group(2)!.trim();
    files[m.group(1)!.trim()] = l;
  }
  return HowResolved(files, body.join('\n').trim());
}

/// One stretch the resolution decided: both sides of the conflict and the
/// final version (R4).
@immutable
class ResolutionHunk {
  const ResolutionHunk({
    required this.path,
    required this.line,
    required this.base,
    required this.spec,
    required this.result,
  });

  final String path;

  /// First line of the stretch in the resolved file.
  final int line;
  final List<String> base, spec, result;

  int get endLine => line + (result.isEmpty ? 0 : result.length - 1);
}

final _open = RegExp(r'^<{7}(?: |$)');
final _mid = RegExp(r'^={7}$');
final _close = RegExp(r'^>{7}(?: |$)');
final _ancestor = RegExp(r'^\|{7}(?: |$)');

/// Stretches of a diff from the automatic merge (with markers) to the
/// resolved file: `git show --remerge-diff` or `git diff` from the tree
/// of `git merge-tree` to the resolved commit. Removed lines between markers are the two sides; the added
/// lines after them, the result. [firstIsBase]: the first side of the
/// markers is the base (merge-tree of base and spec) or the spec (a merge
/// of the base into the spec's branch).
List<ResolutionHunk> parseResolutionDiff(
  String diff, {
  required bool firstIsBase,
}) {
  final out = <ResolutionHunk>[];
  String? path;
  var newLine = 0;
  // The block being read (side 0 first, 1 ancestor, 2 second) and the one
  // whose result is being collected.
  List<String>? first, second;
  var side = -1;
  int? blockLine;
  _Block? current;
  final prelude = <String>[];

  void finish() {
    if (current != null) {
      out.add(current!.build());
      current = null;
    }
  }

  for (final l in diff.split('\n')) {
    if (l.startsWith('diff --git ')) {
      finish();
      final b = l.lastIndexOf(' b/');
      path = b < 0 ? null : l.substring(b + 3);
      side = -1;
      prelude.clear();
      continue;
    }
    if (l.startsWith('+++ ')) {
      if (l.startsWith('+++ b/')) path = l.substring(6);
      continue;
    }
    if (l.startsWith('--- ')) continue;
    final hunk = RegExp(r'^@@+ [^@]*\+(\d+)(?:,\d+)? @@').firstMatch(l);
    if (hunk != null) {
      finish();
      newLine = int.parse(hunk.group(1)!);
      side = -1;
      prelude.clear();
      continue;
    }
    if (l.isEmpty) continue;
    final mark = l.isEmpty ? ' ' : l[0];
    final body = l.isEmpty ? '' : l.substring(1);
    if (mark == '-') {
      if (_open.hasMatch(body)) {
        finish();
        first = [];
        second = [];
        side = 0;
        blockLine = newLine;
      } else if (side >= 0 && _ancestor.hasMatch(body) && side == 0) {
        side = 1;
      } else if (side >= 0 && side < 2 && _mid.hasMatch(body)) {
        side = 2;
      } else if (side == 2 && _close.hasMatch(body)) {
        current = _Block(
          path: path ?? '',
          line: blockLine ?? newLine,
          base: firstIsBase ? first! : second!,
          spec: firstIsBase ? second! : first!,
          result: [...prelude],
        );
        prelude.clear();
        side = -1;
      } else if (side == 0) {
        first!.add(body);
      } else if (side == 2) {
        second!.add(body);
      }
    } else if (mark == '+') {
      if (side >= 0) {
        // Added in the middle of a block: part of its result.
        prelude.add(body);
      } else if (current != null) {
        current!.result.add(body);
      } else {
        prelude.add(body);
      }
      newLine++;
    } else if (mark == ' ') {
      finish();
      if (side < 0) prelude.clear();
      newLine++;
    }
  }
  finish();
  return out;
}

class _Block {
  _Block({
    required this.path,
    required this.line,
    required this.base,
    required this.spec,
    required this.result,
  });

  final String path;
  final int line;
  final List<String> base, spec, result;

  ResolutionHunk build() => ResolutionHunk(
    path: path,
    line: line,
    base: base,
    spec: spec,
    result: result,
  );
}

/// "O que a resolução decidiu" (R4).
@immutable
class ResolutionDecisions {
  const ResolutionDecisions({
    this.hunks = const [],
    this.how,
    this.answer,
    this.raw,
    this.notice,
  });

  final List<ResolutionHunk> hunks;

  /// `## Como resolvi`; null = missing (the whole [answer] is shown).
  final HowResolved? how;
  final String? answer;

  /// `git show --cc` when the git has no `--remerge-diff` (shown as is).
  final String? raw;
  final String? notice;

  /// The agent's explanation of [path] (or the whole answer).
  String? explain(String path) =>
      how?.explain(path) ?? (how == null ? answer : null);
}

/// The criteria's `verificar:` of [specText], without the manual ones (R1).
List<String> resolutionVerifyCommands(String specText) => {
  for (final c in parseCriteria(specText))
    if (c.verify != null &&
        !c.verify!.trim().toLowerCase().startsWith('manual'))
      c.verify!.trim(),
}.toList();

/// Item of "Pronto para merge?" for [r] (R5, R7): null = approved on the
/// current tip; else (state word, detail). [head] is the worktree's HEAD
/// now; [baseTip] the tip of the base now and [containsBase] whether the
/// checked commit contains it.
(String, String)? resolutionProblem(
  ConflictResolution r, {
  String? head,
  String? baseTip,
  bool containsBase = true,
}) {
  String short(String? sha) =>
      sha == null ? '?' : sha.substring(0, sha.length.clamp(0, 7));
  switch (r.state) {
    case ResolutionState.resolvendo:
      return ('em andamento', 'O agente ainda está resolvendo o conflito.');
    case ResolutionState.conferindo:
      return (
        'em andamento',
        'O gate está conferindo a resolução'
            '${r.running == null ? '' : ' (${gateItemLabel(r.running!)})'}.',
      );
    case ResolutionState.reprovada:
      return (
        'reprovada',
        'O gate reprovou a resolução'
            '${r.firstFailure == null ? '' : ' em ${r.firstFailure!.label}'}.',
      );
    case ResolutionState.desatualizada:
      return (
        'desatualizada',
        'A ${r.base} mudou enquanto o agente resolvia ou o gate rodava. O '
            'commit conferido, ${short(r.checkedSha)}, não contém a ponta '
            'atual da ${r.base}, ${short(baseTip ?? r.baseSha)}.',
      );
    case ResolutionState.aprovada:
      if (!containsBase) {
        return (
          'desatualizada',
          'A ${r.base} andou depois do gate. O commit conferido, '
              '${short(r.checkedSha)}, não contém a ponta atual da ${r.base}, '
              '${short(baseTip)}.',
        );
      }
      if (head != null && r.checkedSha != null && head != r.checkedSha) {
        return (
          'desatualizada',
          'A branch ganhou commits depois do gate (conferido '
              '${short(r.checkedSha)}, ponta ${short(head)}): confira de novo.',
        );
      }
      return null;
  }
}

/// Message of "Corrigir e verificar" (R3): the failures of [report].
String resolutionFixMessage(GateReport report, String base) {
  final b = StringBuffer()
    ..writeln(
      'A verificação do Promptorium reprovou a resolução do conflito com '
      '$base: ${report.summary}. O merge continua bloqueado.',
    );
  for (final c in report.failures) {
    b
      ..writeln()
      ..writeln(
        c.command == null
            ? '### ${c.label}'
            : '### ${c.label} (`${c.command}`)',
      )
      ..writeln('```')
      ..writeln(tailLines(c.output, 40))
      ..writeln('```');
  }
  b
    ..writeln()
    ..writeln(
      'Corrija no worktree, mantendo o que as duas versões precisam, e faça '
      'commit. $howResolvedInstruction',
    );
  return b.toString().trimRight();
}

/// Runs the gate on the agent's resolutions and the three ways out of a
/// failed one (SPEC-043 R1, R3, R6, R7, R9).
class ConflictResolver {
  ConflictResolver(this._ref);

  final Ref _ref;
  final _checking = <String>{};
  bool _autoBusy = false;

  AppSettingsController get _settings =>
      _ref.read(appSettingsProvider.notifier);

  GitService _git(String root) => _ref.read(gitServiceFactoryProvider)(root);

  ConflictResolution? get(String sessionId) =>
      ConflictResolution.decode(_settings.get(resolutionKey(sessionId)));

  Future<void> _save(String sessionId, ConflictResolution r) =>
      _settings.set(resolutionKey(sessionId), r.encode());

  Future<({Session session, Workspace ws, Spec? spec})?> _context(
    String sessionId,
  ) async {
    final s = await _ref.read(sessionsRepoProvider).getById(sessionId);
    if (s == null) return null;
    final ws = await _ref.read(workspacesRepoProvider).getById(s.workspaceId);
    if (ws == null) return null;
    final spec = s.specId == null
        ? null
        : await _ref.read(specsRepoProvider).getById(s.specId!);
    return (session: s, ws: ws, spec: spec);
  }

  static String keyOf(Session s, Spec? spec) => spec?.code ?? s.id;

  /// Before the conflict message goes to the agent: saves the tip of the
  /// branch in `antes-da-resolucao` and marks the session "resolvendo".
  Future<ConflictResolution> begin({
    required Session session,
    required Workspace ws,
    required Spec? spec,
    required String base,
    required List<String> files,
    String origin = ResolutionOrigin.person,
    String? restackMark,
  }) async {
    final main = _git(ws.path);
    final before =
        await main.resolveRef('refs/heads/${session.branch}') ??
        await _git(session.worktreePath).headSha();
    if (before != null) {
      await main.updateRef(beforeResolutionRef(keyOf(session, spec)), before);
    }
    final previous = get(session.id);
    final r = ConflictResolution(
      state: ResolutionState.resolvendo,
      workspaceId: ws.id,
      files: files,
      origin: origin,
      base: base,
      beforeSha: before,
      baseSha: await main.resolveRef('refs/heads/$base'),
      restackMark: restackMark,
      approvedCount: previous?.approvedCount,
      approvedAt: previous?.approvedAt,
      startedAt: DateTime.now(),
    );
    await _save(session.id, r);
    await _history(
      spec,
      'Resolução de conflito começada por '
      '${r.automatic ? 'resolução automática' : 'você'}'
      '${files.isEmpty ? '' : ' · arquivos em conflito: ${files.join(', ')}'}',
      verdict: 'inicio',
      sha: before,
    );
    return r;
  }

  /// The message could not be sent: no resolution after all.
  Future<void> cancel(String sessionId) =>
      _settings.remove(resolutionKey(sessionId));

  /// End of a turn of [sessionId] (from [SessionManager]): a resolution
  /// waiting for the agent goes to the gate, outside the session's queue.
  Future<void> onResult(String sessionId, String? answer) async {
    final r = get(sessionId);
    if (r == null || r.state != ResolutionState.resolvendo) return;
    await _save(sessionId, r.copyWith(answer: () => answer ?? r.answer));
    unawaited(Future<void>.microtask(() => check(sessionId)));
  }

  /// Test count to compare with (SPEC-023 R2): the most recent approved
  /// gate of the spec, among its steps and this session's resolutions.
  Future<TestCount?> _baseline(Spec? spec, ConflictResolution r) async {
    TestCount? best = r.approvedCount;
    var at = r.approvedAt ?? DateTime(1970);
    if (spec == null) return best;
    for (final row in await _ref.read(specStepsRepoProvider).bySpec(spec.id)) {
      final g = GateReport.decode(row.gateReport);
      if (g == null || !g.ok || g.testCount == null) continue;
      if (best == null || g.at.isAfter(at)) {
        best = g.testCount;
        at = g.at;
      }
    }
    return best;
  }

  /// Why a rebase or merge still stopped in [wt] keeps the gate from
  /// checking (null = none).
  static Future<String?> _stopped(GitService wt) async {
    for (final (path, what) in [
      ('rebase-merge', 'um rebase'),
      ('rebase-apply', 'um rebase'),
      ('MERGE_HEAD', 'um merge'),
    ]) {
      try {
        var p = (await wt.git(['rev-parse', '--git-path', path])).trim();
        if (!p.startsWith('/')) p = '${wt.repoRoot}/$p';
        if (FileSystemEntity.typeSync(p) != FileSystemEntityType.notFound) {
          return 'Ainda há $what em andamento no worktree: termine-o e faça '
              'commit antes de conferir.';
        }
      } on GitException {
        /* not a repository: the tree check says it */
      }
    }
    return null;
  }

  /// The gate of R1 on [sessionId]'s worktree; the result decides the
  /// state (R7: a base that moved makes it outdated). Null = nothing to
  /// check (or already checking).
  Future<ConflictResolution?> check(String sessionId) async {
    if (!_checking.add(sessionId)) return null;
    try {
      var r = get(sessionId);
      final c = await _context(sessionId);
      if (r == null || c == null) return null;
      final config = ProjectConfig.loadSync(c.ws.path);
      final main = _git(c.ws.path), wt = _git(c.session.worktreePath);
      final base = await _ref
          .read(reviewServiceProvider)
          .baseBranchOf(c.session, c.ws);
      final tip = await main.resolveRef('refs/heads/$base') ?? base;
      final text = c.spec == null
          ? null
          : await _ref.read(specServiceProvider).read(c.ws, c.spec!);
      final verify = text == null
          ? const <String>[]
          : resolutionVerifyCommands(text);
      final plan = StepGate.resolutionPlan(config, verifyCount: verify.length);
      final head = await wt.headSha();
      r = r.copyWith(
        state: ResolutionState.conferindo,
        running: () => plan.first,
        plan: plan,
        report: () => null,
      );
      await _save(sessionId, r);
      final stopped = await _stopped(wt);
      final GateReport report;
      if (stopped != null) {
        report = GateReport(
          at: DateTime.now(),
          attempt: r.gates,
          checks: [GateCheck(name: 'arvore', ok: false, output: stopped)],
        );
      } else {
        final progress = r;
        report = await StepGate(git: wt, shell: _ref.read(shellRunnerProvider))
            .runResolution(
              files: r.files,
              baseSha: tip,
              config: config,
              extraCommands: verify,
              baseline: await _baseline(c.spec, r),
              attempt: r.gates,
              environment: worktreeEnvironment(
                root: c.ws.path,
                worktree: c.session.worktreePath,
                specCode: c.spec?.code,
              ),
              onProgress: (name, done) => unawaited(
                _save(
                  sessionId,
                  progress.copyWith(
                    running: () => name,
                    report: () => GateReport(
                      checks: [...done],
                      at: DateTime.now(),
                      attempt: progress.gates,
                    ),
                  ),
                ),
              ),
            );
      }
      final tipNow = await main.resolveRef('refs/heads/$base') ?? base;
      final baseFailed = report.failures.firstOrNull?.name == 'base';
      final ResolutionState state;
      if (tipNow != tip ||
          (baseFailed && r.baseSha != null && tip != r.baseSha)) {
        state = ResolutionState.desatualizada;
      } else if (report.ok) {
        state = ResolutionState.aprovada;
      } else {
        state = ResolutionState.reprovada;
      }
      final count = report.testCount;
      r = r.copyWith(
        state: state,
        report: () => report,
        running: () => null,
        checkedSha: () => head,
        baseSha: () =>
            state == ResolutionState.desatualizada ? r!.baseSha : tip,
        gates: r.gates + 1,
        approvedCount: state == ResolutionState.aprovada && count != null
            ? () => count
            : null,
        approvedAt: state == ResolutionState.aprovada && count != null
            ? () => report.at
            : null,
      );
      await _save(sessionId, r);
      final short = head == null
          ? ''
          : head.substring(0, head.length.clamp(0, 7));
      await _history(
        c.spec,
        switch (state) {
          ResolutionState.aprovada => 'Gate da resolução aprovado em $short',
          ResolutionState.desatualizada =>
            'Gate da resolução: a $base mudou durante a resolução '
                '(desatualizada)',
          _ => 'Gate da resolução reprovado: ${report.summary}',
        },
        verdict: state.name,
        sha: head,
      );
      final autoFix =
          state == ResolutionState.reprovada && r.automatic && !r.autoFixUsed;
      if (r.automatic) {
        final who = c.spec?.code ?? sessionTitle(c.session);
        unawaited(
          _ref.read(appNotifierProvider).show(
            'Resolução automática',
            switch (state) {
              ResolutionState.aprovada =>
                '$who: conflito resolvido e gate aprovado. O merge '
                    'continua com você.',
              ResolutionState.desatualizada =>
                '$who: a $base mudou durante a resolução. Resolva de novo.',
              _ when autoFix =>
                '$who: o gate reprovou a resolução (${report.summary}). '
                    'O agente vai corrigir uma vez.',
              _ =>
                '$who: o gate reprovou a resolução de novo '
                    '(${report.summary}). As próximas correções são com você.',
            },
          ),
        );
      }
      if (autoFix) {
        unawaited(Future<void>.microtask(() => fix(sessionId, auto: true)));
      }
      return r;
    } finally {
      _checking.remove(sessionId);
    }
  }

  /// "Corrigir e verificar" (R3): the gate's report goes to the session;
  /// the gate runs again when it finishes.
  Future<void> fix(String sessionId, {bool auto = false}) async {
    final r = get(sessionId);
    final c = await _context(sessionId);
    if (r == null || c == null || r.report == null) return;
    await _save(
      sessionId,
      r.copyWith(
        state: ResolutionState.resolvendo,
        running: () => null,
        autoFixUsed: auto ? true : null,
      ),
    );
    try {
      await _ref
          .read(sessionManagerProvider.notifier)
          .send(sessionId, resolutionFixMessage(r.report!, r.base));
    } on SessionException catch (e) {
      await _save(sessionId, r);
      throw ReviewException('$e');
    }
    await _history(
      c.spec,
      '${auto ? 'Resolução automática' : 'Você'} pediu "Corrigir e verificar"',
      verdict: 'corrigir',
    );
    if (c.session.taskId != null) {
      await _ref
          .read(taskActionsProvider)
          .move(c.session.taskId!, TaskStatus.running);
    }
  }

  /// "Desfazer a resolução" (R3): the branch goes back to the SHA saved in
  /// `antes-da-resolucao`. Refused (nothing changes) with uncommitted
  /// changes, an operation stopped in the worktree or a live session.
  Future<String> undo(String sessionId) async {
    final c = await _context(sessionId);
    if (c == null) throw const ReviewException('Sessão não encontrada.');
    final key = keyOf(c.session, c.spec);
    final main = _git(c.ws.path), wt = _git(c.session.worktreePath);
    final before = await main.resolveRef(beforeResolutionRef(key));
    if (before == null) {
      throw const ReviewException(
        'O SHA de antes da resolução não foi guardado: nada a desfazer.',
      );
    }
    if (!c.session.status.isTerminal) {
      throw const ReviewException(
        'O agente ainda está trabalhando na spec: espere a sessão terminar '
        'antes de desfazer a resolução.',
      );
    }
    final dirty = (await wt.status()).where((e) => !e.isUntracked).toList();
    if (dirty.isNotEmpty) {
      throw ReviewException(
        'O worktree tem ${dirty.length} alteração(ões) não commitada(s). '
        'Desfazer a resolução apagaria esse trabalho, então nada foi feito: '
        'faça commit ou descarte as alterações e tente de novo.',
      );
    }
    if (await _stopped(wt) case final why?) {
      throw ReviewException(why);
    }
    await wt.git(['reset', '-q', '--hard', before]);
    try {
      await main.git(['update-ref', '-d', beforeResolutionRef(key)]);
    } on GitException {
      /* stays as a checkpoint */
    }
    final r = get(sessionId);
    if (r?.restackMark case final mark?) {
      await _settings.set(restackMarkKey(sessionId), mark);
    }
    await _settings.remove(resolutionKey(sessionId));
    await _history(
      c.spec,
      'Resolução desfeita: a branch voltou para '
      '${before.substring(0, 7)}',
      verdict: 'desfeita',
      sha: before,
    );
    return before;
  }

  /// "Resolver eu mesmo" (R3): undoes the resolution and starts the manual
  /// rebase of SPEC-032 R17, stopped on the conflicts.
  Future<RebaseStatus> resolveMyself(String sessionId) async {
    if (get(sessionId) != null) await undo(sessionId);
    return _ref.read(reviewServiceProvider).startRebase(sessionId);
  }

  /// An approved resolution whose base moved (R7), found by "Pronto para
  /// merge?": the card shows it as outdated.
  Future<void> markOutdated(String sessionId) async {
    final r = get(sessionId);
    if (r == null || r.state != ResolutionState.aprovada) return;
    await _save(sessionId, r.copyWith(state: ResolutionState.desatualizada));
  }

  /// R6: with `review: resolver-conflitos: automatico`, a conflict of
  /// [sessionId] (predicted with the base or from a restack) starts the
  /// resolution by itself: one spec at a time in the workspace, never
  /// with a live session, never twice for a resolution the person still
  /// has to look at. Returns whether it started.
  Future<bool> autoStart(String sessionId) async {
    if (_autoBusy) return false;
    _autoBusy = true;
    try {
      final c = await _context(sessionId);
      if (c == null) return false;
      if (!ProjectConfig.loadSync(c.ws.path).autoResolveConflicts) return false;
      final s = c.session;
      if (!s.status.isTerminal ||
          s.status == SessionStatus.merged ||
          s.mergeCommit != null ||
          !ReviewService.hasWorktree(s, c.ws)) {
        return false;
      }
      final own = get(sessionId);
      if (own != null && own.state != ResolutionState.aprovada) return false;
      for (final MapEntry(:key, :value)
          in _ref.read(appSettingsProvider).entries) {
        if (!key.startsWith('review.resolucao.')) continue;
        final other = ConflictResolution.decode(value);
        if (other != null &&
            other.workspaceId == c.ws.id &&
            other.state.active) {
          return false;
        }
      }
      final files = await _ref
          .read(reviewServiceProvider)
          .resolveConflict(sessionId, origin: ResolutionOrigin.automatic);
      final who = c.spec?.code ?? sessionTitle(s);
      unawaited(
        _ref
            .read(appNotifierProvider)
            .show(
              'Resolução automática',
              '$who tem conflito${files.isEmpty ? '' : ' em ${files.join(', ')}'}. '
                  'O agente começou a resolver. Nada é mergeado sem você.',
            ),
      );
      return true;
    } catch (e) {
      debugPrint('resolução automática de $sessionId não começou — $e');
      return false;
    } finally {
      _autoBusy = false;
    }
  }

  /// "O que a resolução decidiu" (R4): `git show --remerge-diff` when the
  /// checked commit is the agent's merge; else (a rebase, or fixes after
  /// the merge) the diff from `git merge-tree <base> <antes>` to it.
  Future<ResolutionDecisions> decisions(String sessionId) async {
    final r = get(sessionId);
    final c = await _context(sessionId);
    if (r == null || c == null) return const ResolutionDecisions();
    final how = parseHowResolved(r.answer);
    final sha = r.checkedSha ?? await _git(c.session.worktreePath).headSha();
    if (sha == null) return ResolutionDecisions(how: how, answer: r.answer);
    final main = _git(c.ws.path);
    var parents = 0;
    try {
      parents =
          (await main.git(['rev-list', '--parents', '-n', '1', sha]))
              .trim()
              .split(' ')
              .length -
          1;
    } on GitException {
      /* unknown commit */
    }
    if (parents > 1) {
      try {
        final diff = await main.git([
          'show',
          '--remerge-diff',
          '--format=',
          sha,
        ]);
        return ResolutionDecisions(
          hunks: parseResolutionDiff(diff, firstIsBase: false),
          how: how,
          answer: r.answer,
        );
      } on GitException catch (e) {
        if (!e.stderr.contains('remerge')) rethrow;
        final raw = await main.git(['show', '--cc', '--format=', sha]);
        return ResolutionDecisions(
          how: how,
          answer: r.answer,
          raw: raw,
          notice:
              'Este git não tem `--remerge-diff` (git 2.36 ou mais novo): '
              'mostrando `git show --cc`, sem separar os dois lados.',
        );
      }
    }
    final before = r.beforeSha, base = r.baseSha;
    if (before == null || base == null) {
      return ResolutionDecisions(how: how, answer: r.answer);
    }
    String tree;
    try {
      tree = (await main.git(['merge-tree', '--write-tree', base, before]))
          .split('\n')
          .first
          .trim();
    } on GitException catch (e) {
      if (e.exitCode != 1) rethrow;
      tree = e.stdout.split('\n').first.trim();
    }
    final diff = await main.git(['diff', tree, sha, '--', ...r.files]);
    return ResolutionDecisions(
      hunks: parseResolutionDiff(diff, firstIsBase: true),
      how: how,
      answer: r.answer,
    );
  }

  /// A row of the spec's review history (R9): resolved, so never an open
  /// comment, and in round 0, so never a review round.
  Future<void> _history(
    Spec? spec,
    String body, {
    required String verdict,
    String? sha,
  }) async {
    if (spec == null) return;
    try {
      await _ref.read(reviewCommentsRepoProvider).insertAll([
        ReviewCommentsCompanion.insert(
          specId: spec.id,
          round: 0,
          author: resolutionAuthor,
          body: body,
          verdict: Value(verdict),
          commitSha: Value(sha),
          resolved: const Value(true),
        ),
      ]);
    } catch (e) {
      debugPrint('histórico da resolução não gravado — $e');
    }
  }

  /// [_history] for the merge made over a resolution blocker (R5).
  Future<void> recordOverride(String sessionId, String reason) async {
    final c = await _context(sessionId);
    final r = get(sessionId);
    if (c == null || r == null) return;
    await _history(
      c.spec,
      'Mergeada mesmo assim com a resolução ${r.state.name}: $reason',
      verdict: 'mesmo-assim',
      sha: r.checkedSha,
    );
  }
}

final conflictResolverProvider = Provider<ConflictResolver>(
  ConflictResolver.new,
);

/// "O que a resolução decidiu" of a session (never an error state).
final resolutionDecisionsProvider =
    FutureProvider.family<ResolutionDecisions, String>((ref, sessionId) async {
      final r = ref.watch(
        conflictResolutionProvider(sessionId).select((r) => r?.checkedSha),
      );
      if (r == null) return const ResolutionDecisions();
      try {
        return await ref.read(conflictResolverProvider).decisions(sessionId);
      } catch (e) {
        return ResolutionDecisions(
          notice: 'Não foi possível ler a resolução: $e',
        );
      }
    });
