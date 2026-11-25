import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repos/debt_links_repo.dart';
import '../../data/repos/specs_repo.dart';
import '../../data/repos/workspaces_repo.dart';
import '../project/project_plan.dart' show PlanQuestion;
import '../specs/spec_draft.dart' show DraftQuestion;
import '../specs/spec_service.dart';
import 'debt_board.dart' show specLabel, specNumber;
import 'debt_detector.dart';
import 'debt_files.dart';
import 'debt_item.dart';
import 'debt_service.dart';
import 'debt_table.dart';

/// Reads the text of a spec file (null when it does not exist).
typedef SpecTextRead = Future<String?> Function(Workspace ws, Spec spec);

/// Writes the text of a spec file.
typedef SpecTextWrite = Future<void> Function(
  Workspace ws,
  Spec spec,
  String text,
);

/// What became of the spec answer after an item was written.
class InterviewWritten {
  const InterviewWritten(this.written, {required this.annotated});

  final DebtWritten written;

  /// The answer in the spec got "→ DT-NN" (false: the question was not
  /// found, or the spec file is gone).
  final bool annotated;
}

/// The debts and decisions born in the interview of a spec (SPEC-112 R6,
/// R7, R12, P2): the actions of each question, the suggestions of the
/// detector, the items of the mini-planejamento (before the spec has a
/// number) and the answer of a decision.
class DebtInterview {
  DebtInterview({
    required this.debts,
    required this.links,
    required this.specs,
    required this.workspaces,
    SpecTextRead? readSpec,
    SpecTextWrite? writeSpec,
  }) : _read = readSpec ?? _readFile,
       _write = writeSpec ?? _writeFile;

  final DebtService debts;
  final DebtLinksRepo links;
  final SpecsRepo specs;
  final WorkspacesRepo workspaces;
  final SpecTextRead _read;
  final SpecTextWrite _write;

  /// The spec file in the workspace, else in its worktree.
  static File _fileOf(Workspace ws, Spec spec) {
    final main = File('${ws.path}/${spec.path}');
    final wt = spec.worktreePath;
    if (main.existsSync() || wt == null) return main;
    final own = File('$wt/${spec.path}');
    return own.existsSync() ? own : main;
  }

  static Future<String?> _readFile(Workspace ws, Spec spec) async {
    final f = _fileOf(ws, spec);
    return await f.exists() ? f.readAsString() : null;
  }

  static Future<void> _writeFile(Workspace ws, Spec spec, String text) =>
      _fileOf(ws, spec).writeAsString(text);

  /// Reference of the draft of "Nova spec" of [workspaceId] in
  /// `debt_links.origin_session_id` (P2): there is one draft per workspace.
  static String draftRef(int workspaceId) => 'rascunho:$workspaceId';

  /// The worktree of [spec] while open: the row goes in its commit (R18).
  static String? writeRootOf(Spec spec) {
    final wt = spec.worktreePath;
    if (wt == null || spec.stage == SpecStage.done) return null;
    return Directory(wt).existsSync() ? wt : null;
  }

  /// `spec 33, P5`: the origin of a debt (R6).
  static String originOf(Spec spec, String questionId) =>
      '${specLabel(spec)}, $questionId';

  /// `[Spec 33](docs/specs/SPEC-033-….md) P5`: the "Origem" cell of a
  /// decision.
  static String decisionOriginOf(Spec spec, String questionId) {
    final label = specLabel(spec);
    final cap = '${label[0].toUpperCase()}${label.substring(1)}';
    return '[$cap](${spec.path}) $questionId';
  }

  /// "Simplificar agora → débito" (R6): the form filled with the question
  /// (the title), the simplified [answer] (the motive) and the suggestion
  /// (what resolves it).
  static DebtDraft debtDraftFor({
    required String question,
    String? answer,
    String? suggestion,
    required String origin,
  }) => DebtDraft(
    kind: DebtKind.debt,
    title: _plain(question),
    reason: _plain(answer ?? ''),
    toResolve: _plain(suggestion ?? ''),
    origin: origin,
  );

  /// "Decidir depois → DP" (R6): the question, and the suggestion as the
  /// recommendation.
  static DebtDraft decisionDraftFor({
    required String question,
    String? suggestion,
    required String origin,
  }) => DebtDraft(
    kind: DebtKind.decision,
    title: _plain(question),
    toResolve: _plain(suggestion ?? ''),
    origin: origin,
  );

  static String _plain(String s) =>
      s.replaceAll('**', '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String annotationFor(DebtKind kind, String code) =>
      kind == DebtKind.debt
      ? SpecDocument.debtAnnotation(code)
      : SpecDocument.decisionAnnotation(code);

  /// Writes "→ DT-NN" / "→ DP-NN" in the answer of [questionId] of [spec]
  /// (R6, R12); the question counts as answered. False when the question
  /// or the file is not there.
  Future<bool> annotate(
    Workspace ws,
    Spec spec,
    String questionId,
    String annotation, {
    String? answer,
  }) async {
    final text = await _read(ws, spec);
    if (text == null) return false;
    final out = SpecDocument.parse(text).withQuestionAnnotated(
      questionId,
      annotation,
      answer: answer,
      at: debts.now(),
    );
    if (out == null) return false;
    if (out != text) await _write(ws, spec, out);
    return true;
  }

  /// The link of an item born in question [questionId] of [spec].
  static DebtLinksCompanion linkOf(Spec spec, String questionId) =>
      DebtLinksCompanion(
        originSpecId: Value(spec.id),
        originQuestion: Value(questionId),
      );

  /// "Simplificar agora → débito" / "Decidir depois → DP" (R6): writes
  /// [draft] (in the worktree of the spec while it is open, R18) and the
  /// "→ DT-NN" in the answer. [answer] is the answer given, when any.
  Future<InterviewWritten> record(
    Workspace ws,
    Spec spec,
    String questionId,
    DebtDraft draft, {
    String? answer,
  }) async {
    final w = await debts.create(
      ws.path,
      draft,
      writeRoot: writeRootOf(spec),
      link: linkOf(spec, questionId),
    );
    final ok = await annotate(
      ws,
      spec,
      questionId,
      annotationFor(draft.kind, w.code),
      answer: answer,
    );
    return InterviewWritten(w, annotated: ok);
  }

  /// R7: when [answer] (the answer of [questionId] of [spec]) asks for a
  /// debt or a decision, a pending suggestion linked to the question;
  /// nothing is written in the file. A pending suggestion of the same
  /// question is updated, not repeated. Null when the answer asks for
  /// nothing.
  Future<int?> suggestFromAnswer(
    Workspace ws,
    Spec spec,
    OpenQuestion question,
    String answer,
  ) async {
    final intent = detectDebtIntent(answer);
    if (intent == null) return null;
    final origin = intent == DebtIntent.debt
        ? originOf(spec, question.id)
        : decisionOriginOf(spec, question.id);
    final draft = intent == DebtIntent.debt
        ? debtDraftFor(
            question: question.text,
            answer: answer,
            suggestion: question.suggestion,
            origin: origin,
          )
        : decisionDraftFor(
            question: question.text,
            suggestion: question.suggestion,
            origin: origin,
          );
    final body = {
      ...draft.toJson(),
      'pergunta': question.text,
      'resposta': answer,
    };
    final same = (await links.forRepo(ws.path)).where(
      (l) =>
          l.suggestionState == DebtSuggestionState.pending &&
          l.originSpecId == spec.id &&
          l.originQuestion == question.id,
    );
    if (same.isNotEmpty) {
      await links.updateSuggestion(same.first.id, intent.kind.dbName, body);
      return same.first.id;
    }
    return links.addSuggestion(
      repoRoot: ws.path,
      kind: intent.kind.dbName,
      source: DebtSuggestionSource.interview,
      body: body,
      link: linkOf(spec, question.id),
    );
  }

  /// Accepts a suggestion (R7, R11) and, when it came from a question of a
  /// spec, writes "→ DT-NN" in its answer.
  Future<DebtWritten> accept(
    int linkId, {
    DebtDraft? edited,
    String? writeRoot,
  }) async {
    final l = await links.byId(linkId);
    final w = await debts.accept(linkId, edited: edited, writeRoot: writeRoot);
    if (l?.originSpecId case final specId? when l?.originQuestion != null) {
      final spec = await specs.getById(specId);
      final ws = spec == null
          ? null
          : await workspaces.getById(spec.workspaceId);
      if (spec != null && ws != null) {
        try {
          final kind = DebtKind.fromDb(l!.kind);
          final answer = '${DebtLinksRepo.suggestionOf(l)['resposta'] ?? ''}';
          await annotate(
            ws,
            spec,
            l.originQuestion!,
            annotationFor(kind, w.code),
            answer: answer.trim().isEmpty ? null : answer,
          );
        } catch (_) {
          // The row is written; the answer is only a note.
        }
      }
    }
    return w;
  }

  // --- the mini-planejamento of "Nova spec" (P2) ----------------------------

  /// "Simplificar agora → débito" / "Decidir depois → DP" before the spec
  /// has a number (P2): a pending suggestion (`rascunho`) tied to the draft
  /// of [ws]; the row is written when the spec is created ([settleDraft]).
  Future<int> deferForDraft(
    Workspace ws,
    DraftQuestion question,
    int index,
    DebtDraft draft,
  ) async {
    final qid = 'P${index + 1}';
    // A second action on the same question replaces the first.
    for (final l in await draftLinks(ws)) {
      if (l.suggestionSource == DebtSuggestionSource.draft &&
          (DebtLinksRepo.suggestionOf(l)['pergunta'] == question.text ||
              l.originQuestion == qid)) {
        await links.delete(l.id);
      }
    }
    return links.addSuggestion(
      repoRoot: ws.path,
      kind: draft.kind.dbName,
      source: DebtSuggestionSource.draft,
      body: {...draft.toJson(), 'pergunta': question.text},
      link: DebtLinksCompanion(
        originSessionId: Value(draftRef(ws.id)),
        originQuestion: Value(qid),
      ),
    );
  }

  /// Pending links tied to the draft of [ws] (P2).
  Future<List<DebtLink>> draftLinks(Workspace ws) async => [
    for (final l in await links.forRepo(ws.path))
      if (l.originSessionId == draftRef(ws.id) &&
          l.suggestionState == DebtSuggestionState.pending)
        l,
  ];

  /// R7 in the mini-planejamento: the answers of [reply] to the planner's
  /// [questions] ("5 - deixa simulado por hora e cria um débito") that ask
  /// for a debt or a decision become pending suggestions tied to the draft.
  /// Returns how many.
  Future<int> suggestFromDraftReply(
    Workspace ws,
    List<PlanQuestion> questions,
    String reply,
  ) async {
    if (questions.isEmpty) return 0;
    var n = 0;
    for (final a in splitNumberedAnswers(reply)) {
      final intent = detectDebtIntent(a.text);
      if (intent == null) continue;
      final i = a.number == null
          ? (questions.length == 1 ? 0 : null)
          : a.number! - 1;
      if (i == null || i < 0 || i >= questions.length) continue;
      final q = _plain(questions[i].text);
      final draft = intent == DebtIntent.debt
          ? debtDraftFor(question: q, answer: a.text, origin: '')
          : decisionDraftFor(question: q, origin: '');
      await links.addSuggestion(
        repoRoot: ws.path,
        kind: intent.kind.dbName,
        source: DebtSuggestionSource.interview,
        body: {...draft.toJson(), 'pergunta': q, 'resposta': a.text},
        link: DebtLinksCompanion(originSessionId: Value(draftRef(ws.id))),
      );
      n++;
    }
    return n;
  }

  /// The spec of the draft was created (P2): the items of "Simplificar
  /// agora"/"Decidir depois" are written with "(spec N, P5)" and the ID
  /// goes in the answer; the suggestions of the detector are tied to the
  /// spec and stay pending.
  Future<List<InterviewWritten>> settleDraft(Workspace ws, Spec spec) async {
    final out = <InterviewWritten>[];
    final text = await _read(ws, spec);
    final questions = text == null
        ? const <OpenQuestion>[]
        : SpecDocument.parse(text).openQuestions;
    String? questionIdOf(DebtLink l) {
      final asked = _plain(
        '${DebtLinksRepo.suggestionOf(l)['pergunta'] ?? ''}',
      );
      final byText = questions
          .where((q) => _plain(q.text) == asked)
          .firstOrNull;
      if (byText != null) return byText.id;
      return questions.any((q) => q.id == l.originQuestion)
          ? l.originQuestion
          : null;
    }

    for (final l in await draftLinks(ws)) {
      final qid = questionIdOf(l);
      final kind = DebtKind.fromDb(l.kind);
      final draft = DebtDraft.fromJson(
        DebtLinksRepo.suggestionOf(l),
        kind: kind,
      );
      final origin = qid == null
          ? specLabel(spec)
          : kind == DebtKind.debt
          ? originOf(spec, qid)
          : decisionOriginOf(spec, qid);
      await links.update(
        l.id,
        DebtLinksCompanion(
          originSpecId: Value(spec.id),
          originQuestion: Value(qid),
          originSessionId: const Value(null),
        ),
      );
      if (l.suggestionSource != DebtSuggestionSource.draft) {
        await links.updateSuggestion(l.id, l.kind, {
          ...DebtLinksRepo.suggestionOf(l),
          'origem': origin,
        });
        continue;
      }
      final w = await debts.accept(
        l.id,
        edited: draft.copyWith(origin: origin),
        writeRoot: writeRootOf(spec),
      );
      final ok =
          qid != null &&
          await annotate(ws, spec, qid, annotationFor(kind, w.code));
      out.add(InterviewWritten(w, annotated: ok));
    }
    return out;
  }

  /// The draft of [ws] was discarded (P2): its suggestions go with it.
  Future<void> discardDraft(Workspace ws) async {
    for (final l in await draftLinks(ws)) {
      await links.delete(l.id);
    }
  }

  // --- answering a decision (R12) -------------------------------------------

  /// The line "Decidido" of [decision] answered with [answer].
  List<String> decidedCells(DecisionItem decision, String answer) =>
      decision.decidedCells(_oneLine(answer), date: debts.today);

  /// "Q7 → DP-09: Recusar no envio…": what goes to the spec (R12).
  static String specPreview(DecisionItem d, String answer) =>
      '${d.originQuestion ?? '?'} '
      '${SpecDocument.decisionAnnotation(d.code, answer: answer)}';

  static String _oneLine(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// "Salvar decisão" (R12): fills "Decisão" with "**Decidido (AAAA-MM-DD):**
  /// …" in the file at [root] (the main checkout or the worktree where the
  /// row is) and, with [toSpec], takes the answer to the origin spec: the
  /// question gets `→ DP-04: <resposta>` and counts as answered. Returns the
  /// decision as written and whether the spec got the answer.
  Future<({DecisionItem decision, bool annotated})> answerDecision(
    String repoRoot,
    DecisionItem decision,
    String answer, {
    String? root,
    bool toSpec = true,
    Workspace? ws,
    Spec? spec,
  }) async {
    final rel = DebtFiles.relPath(debts.configOf(repoRoot), DebtKind.decision);
    final doc = await DebtFiles.apply(
      root ?? repoRoot,
      rel,
      DebtKind.decision,
      ReplaceDebtRow(
        decision.code,
        decidedCells(decision, answer),
        expectedRaw: decision.raw.isEmpty ? null : decision.raw,
      ),
    );
    final written = doc.decisions.firstWhere((d) => d.code == decision.code);
    var annotated = false;
    final qid = decision.originQuestion;
    if (toSpec && qid != null) {
      final target = spec ?? await originSpecOf(repoRoot, decision);
      final w =
          ws ??
          (target == null
              ? null
              : await workspaces.getById(target.workspaceId));
      if (target != null && w != null) {
        annotated = await annotate(
          w,
          target,
          qid,
          SpecDocument.decisionAnnotation(decision.code, answer: answer),
        );
      }
    }
    return (decision: written, annotated: annotated);
  }

  /// The spec a decision came from: the link, else the spec number of
  /// "Origem".
  Future<Spec?> originSpecOf(String repoRoot, DecisionItem d) async {
    final l = await links.byCode(repoRoot, d.code);
    if (l?.originSpecId case final id?) return specs.getById(id);
    final n = d.originSpecNumber;
    if (n == null) return null;
    final ws = await workspaces.getByPath(repoRoot);
    if (ws == null) return null;
    final all = await specs.watchByWorkspace(ws.id).first;
    for (final s in all) {
      if (specNumber(s.code) == n && !s.code.toUpperCase().startsWith('VIBE')) {
        return s;
      }
    }
    return null;
  }

  /// "Virar débito" of a decision (R12): the origin is "DP-04" (with the
  /// spec when the decision has one).
  static DebtDraft debtDraftFromDecision(DecisionItem d, {String? leftover}) {
    final n = d.originSpecNumber;
    return DebtDraft(
      kind: DebtKind.debt,
      title: _plain(leftover ?? ''),
      reason: '',
      origin: n == null ? d.code : 'spec $n, ${d.code}',
    );
  }

  /// The link of a debt born from the decision [decisionCode].
  static DebtLinksCompanion linkOfDecision(String decisionCode) =>
      DebtLinksCompanion(originDecision: Value(decisionCode));

  /// "gerou o DT-10" in the decision [decisionCode] of the file at [root]
  /// (R12): the other end of the link.
  Future<void> markGenerated(
    String repoRoot,
    String decisionCode,
    String debtCode, {
    String? root,
  }) async {
    final rel = DebtFiles.relPath(debts.configOf(repoRoot), DebtKind.decision);
    final at = root ?? repoRoot;
    final doc = await DebtFiles.read(at, rel, DebtKind.decision);
    final d = doc.decisions.where((x) => x.code == decisionCode).firstOrNull;
    if (d == null) throw StateError('$decisionCode não está em $rel.');
    if (d.decision.toLowerCase().contains(
      'gerou o ${debtCode.toLowerCase()}',
    )) {
      return;
    }
    await DebtFiles.apply(
      at,
      rel,
      DebtKind.decision,
      ReplaceDebtRow(d.code, d.withGenerated(debtCode), expectedRaw: d.raw),
    );
  }

  /// "Virar débito" without the form (tests, MCP): writes [draft] linked to
  /// [decisionCode] and "gerou o DT-NN" in the decision.
  Future<DebtWritten> debtFromDecision(
    String repoRoot,
    String decisionCode,
    DebtDraft draft, {
    String? writeRoot,
    String? decisionRoot,
  }) async {
    final w = await debts.create(
      repoRoot,
      draft,
      writeRoot: writeRoot,
      link: linkOfDecision(decisionCode),
    );
    await markGenerated(repoRoot, decisionCode, w.code, root: decisionRoot);
    return w;
  }
}

final debtInterviewProvider = Provider(
  (ref) => DebtInterview(
    debts: ref.watch(debtServiceProvider),
    links: ref.watch(debtLinksRepoProvider),
    specs: ref.watch(specsRepoProvider),
    workspaces: ref.watch(workspacesRepoProvider),
    readSpec: (ws, spec) => ref.read(specServiceProvider).read(ws, spec),
    writeSpec: (ws, spec, text) async {
      await ref.read(specServiceProvider).save(ws, spec, text);
    },
  ),
);

/// The pending items of the draft of "Nova spec" (P2), by workspace.
final draftDebtLinksProvider = StreamProvider.autoDispose
    .family<List<DebtLink>, ({int workspaceId, String root})>(
      (ref, key) => ref
          .watch(debtLinksRepoProvider)
          .watchRepo(key.root)
          .map(
            (all) => [
              for (final l in all)
                if (l.originSessionId ==
                        DebtInterview.draftRef(key.workspaceId) &&
                    l.suggestionState == DebtSuggestionState.pending)
                  l,
            ],
          ),
    );
