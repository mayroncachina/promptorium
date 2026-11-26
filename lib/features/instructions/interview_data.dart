import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The data of the interview of "Melhorar com IA" (SPEC-113 R13–R18) and of
/// the proposal it ends with (R19): what the AI answered in each round, what
/// the person chose, and the trechos the app applies (T6). Stored as JSON in
/// `instruction_interviews.data`.

/// A fact the code answers (R14): it never becomes a question.
@immutable
class InterviewFinding {
  const InterviewFinding({required this.text, required this.path});

  /// "Logger em".
  final String text;

  /// Where the AI read it (`lib/core/log.dart`, `ci.yml`).
  final String path;

  Map<String, Object?> toJson() => {'text': text, 'path': path};

  static InterviewFinding? fromJson(Object? j) {
    if (j is! Map) return null;
    final text = '${j['text'] ?? ''}'.trim();
    if (text.isEmpty) return null;
    return InterviewFinding(text: text, path: '${j['path'] ?? ''}'.trim());
  }
}

/// A decision of the person (R13): numbered, with the reason, the options
/// and the recommended answer.
@immutable
class InterviewQuestion {
  const InterviewQuestion({
    required this.id,
    required this.title,
    required this.text,
    required this.reason,
    required this.recommended,
    this.options = const [],
    this.requires = const [],
    this.onlyClaude = false,
    this.target = '',
  });

  /// `Q1`, `Q2`… unique in the interview.
  final String id;

  /// Short name for the side list ("Teste em tela nova").
  final String title;
  final String text;

  /// Why it is asked: what the AI saw ("8 das 11 telas têm teste…").
  final String reason;
  final List<String> options;
  final String recommended;

  /// Questions that must be answered before this one (R13).
  final List<String> requires;

  /// Only the Claude Code reads the rule (it goes to the `CLAUDE.md`).
  final bool onlyClaude;

  /// Where the answer lands: `AGENTS.md › Regras`.
  final String target;

  int get number => int.tryParse(id.substring(1)) ?? 0;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'text': text,
    'reason': reason,
    'options': options,
    'recommended': recommended,
    'requires': requires,
    'onlyClaude': onlyClaude,
    'target': target,
  };

  static InterviewQuestion? fromJson(Object? j) {
    if (j is! Map) return null;
    final text = '${j['text'] ?? ''}'.trim();
    if (text.isEmpty) return null;
    List<String> list(Object? v) => [
      if (v is List)
        for (final x in v)
          if ('$x'.trim().isNotEmpty) '$x'.trim(),
    ];
    final title = '${j['title'] ?? ''}'.trim();
    return InterviewQuestion(
      id: '${j['id'] ?? ''}'.trim().toUpperCase(),
      title: title.isEmpty ? text : title,
      text: text,
      reason: '${j['reason'] ?? ''}'.trim(),
      options: list(j['options']),
      recommended: '${j['recommended'] ?? ''}'.trim(),
      requires: list(j['requires']).map((e) => e.toUpperCase()).toList(),
      onlyClaude: j['onlyClaude'] == true,
      target: '${j['target'] ?? ''}'.trim(),
    );
  }

  InterviewQuestion withId(String id, List<String> requires) =>
      InterviewQuestion(
        id: id,
        title: title,
        text: text,
        reason: reason,
        options: options,
        recommended: recommended,
        requires: requires,
        onlyClaude: onlyClaude,
        target: target,
      );
}

/// How a question was answered (R15).
enum InterviewAnswerKind { option, text, recommended, skipped }

@immutable
class InterviewAnswer {
  const InterviewAnswer(this.kind, [this.value = '']);

  const InterviewAnswer.skipped() : this(InterviewAnswerKind.skipped);

  final InterviewAnswerKind kind;

  /// The option, the text or the recommended answer; empty when skipped.
  final String value;

  bool get skipped => kind == InterviewAnswerKind.skipped;

  /// A text answer still empty does not count.
  bool get complete => skipped || value.trim().isNotEmpty;

  Map<String, Object?> toJson() => {'kind': kind.name, 'value': value};

  static InterviewAnswer? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = InterviewAnswerKind.values
        .where((k) => k.name == j['kind'])
        .firstOrNull;
    if (kind == null) return null;
    return InterviewAnswer(kind, '${j['value'] ?? ''}');
  }

  /// The line the AI reads.
  String get spoken => switch (kind) {
    InterviewAnswerKind.skipped => 'pulada (não vira regra)',
    InterviewAnswerKind.recommended => 'aceita a recomendada: $value',
    InterviewAnswerKind.option => value,
    InterviewAnswerKind.text => value,
  };

  @override
  bool operator ==(Object other) =>
      other is InterviewAnswer && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// One round (R13): what the AI found, asked and drafted, and what the
/// person answered. [sent] = the answers went to the AI.
@immutable
class InterviewRound {
  const InterviewRound({
    required this.number,
    this.findings = const [],
    this.questions = const [],
    this.answers = const {},
    this.draft = '',
    this.sent = false,
  });

  final int number;
  final List<InterviewFinding> findings;
  final List<InterviewQuestion> questions;
  final Map<String, InterviewAnswer> answers;

  /// The draft of the instructions so far (Markdown).
  final String draft;
  final bool sent;

  /// Every question has a complete answer (answered or skipped).
  bool get complete => questions.every((q) => answers[q.id]?.complete ?? false);

  int get answered =>
      questions.where((q) => answers[q.id]?.complete ?? false).length;

  InterviewRound copyWith({
    Map<String, InterviewAnswer>? answers,
    bool? sent,
  }) => InterviewRound(
    number: number,
    findings: findings,
    questions: questions,
    answers: answers ?? this.answers,
    draft: draft,
    sent: sent ?? this.sent,
  );

  Map<String, Object?> toJson() => {
    'number': number,
    'findings': [for (final f in findings) f.toJson()],
    'questions': [for (final q in questions) q.toJson()],
    'answers': {for (final e in answers.entries) e.key: e.value.toJson()},
    'draft': draft,
    'sent': sent,
  };

  static InterviewRound fromJson(Map j) => InterviewRound(
    number: (j['number'] as num?)?.toInt() ?? 1,
    findings: [
      if (j['findings'] case final List l)
        for (final x in l) ?InterviewFinding.fromJson(x),
    ],
    questions: [
      if (j['questions'] case final List l)
        for (final x in l) ?InterviewQuestion.fromJson(x),
    ],
    answers: {
      if (j['answers'] case final Map m)
        for (final e in m.entries)
          '${e.key}': ?InterviewAnswer.fromJson(e.value),
    },
    draft: '${j['draft'] ?? ''}',
    sent: j['sent'] == true,
  );
}

/// Where the interview is.
enum InterviewStage {
  /// A round is open or on the way.
  asking,

  /// No questions left (R16): the summary waits for confirmation.
  summary,

  /// The proposal is ready ([InterviewData.proposal]).
  proposal,
}

/// The whole interview, as stored.
@immutable
class InterviewData {
  const InterviewData({
    this.rounds = const [],
    this.summary = '',
    this.stage = InterviewStage.asking,
    this.endedEarly = false,
    this.proposal,
  });

  final List<InterviewRound> rounds;

  /// What the AI understood (R16), shown before the proposal.
  final String summary;
  final InterviewStage stage;

  /// "Encerrar e ver a proposta": what stayed open does not become a rule.
  final bool endedEarly;
  final InstructionProposal? proposal;

  InterviewRound? get current => rounds.lastOrNull;

  /// The draft of the last round.
  String get draft => current?.draft ?? '';

  /// The draft of the round before (the lines new in [draft] stand out).
  String get previousDraft =>
      rounds.length < 2 ? '' : rounds[rounds.length - 2].draft;

  /// Every finding so far, without repeating a path + text.
  List<InterviewFinding> get findings {
    final seen = <String>{};
    return [
      for (final r in rounds)
        for (final f in r.findings)
          if (seen.add('${f.path}\n${f.text}')) f,
    ];
  }

  /// Every question asked, in order.
  List<InterviewQuestion> get questions => [
    for (final r in rounds) ...r.questions,
  ];

  /// The answers of every round.
  Map<String, InterviewAnswer> get answers => {
    for (final r in rounds) ...r.answers,
  };

  /// Answered (or skipped) questions, and the ones still open.
  int get answeredCount => answers.values.where((a) => a.complete).length;
  int get openCount => questions.length - answeredCount;

  /// The next free question number.
  int get nextNumber =>
      questions.fold<int>(0, (m, q) => q.number > m ? q.number : m) + 1;

  /// Nothing came back for the last answers (or for the first round): the
  /// round must run (again).
  bool get needsRun =>
      stage == InterviewStage.asking && (rounds.isEmpty || rounds.last.sent);

  InterviewData copyWith({
    List<InterviewRound>? rounds,
    String? summary,
    InterviewStage? stage,
    bool? endedEarly,
    InstructionProposal? proposal,
  }) => InterviewData(
    rounds: rounds ?? this.rounds,
    summary: summary ?? this.summary,
    stage: stage ?? this.stage,
    endedEarly: endedEarly ?? this.endedEarly,
    proposal: proposal ?? this.proposal,
  );

  /// [current] replaced by [round].
  InterviewData withCurrent(InterviewRound round) =>
      copyWith(rounds: [...rounds.take(rounds.length - 1), round]);

  Map<String, Object?> toJson() => {
    'v': 1,
    'rounds': [for (final r in rounds) r.toJson()],
    'summary': summary,
    'stage': stage.name,
    'endedEarly': endedEarly,
    if (proposal case final p?) 'proposal': p.toJson(),
  };

  String encode() => jsonEncode(toJson());

  static InterviewData decode(String text) {
    Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      j = null;
    }
    if (j is! Map) return const InterviewData();
    final stage = j['stage'];
    return InterviewData(
      rounds: [
        if (j['rounds'] case final List l)
          for (final x in l.whereType<Map>()) InterviewRound.fromJson(x),
      ],
      summary: '${j['summary'] ?? ''}',
      stage:
          InterviewStage.values.where((s) => s.name == stage).firstOrNull ??
          InterviewStage.asking,
      endedEarly: j['endedEarly'] == true,
      proposal: InstructionProposal.fromJson(j['proposal']),
    );
  }
}

// --- Proposta (R19) -------------------------------------------------------------

/// One trecho of the proposal (R19): where it goes, the text it replaces
/// and the new one, and the questions it came from. The AI never writes:
/// the app applies the accepted ones (T6).
@immutable
class InstructionProposalHunk {
  const InstructionProposalHunk({
    required this.file,
    required this.section,
    required this.oldText,
    required this.newText,
    this.questions = const [],
  });

  /// `AGENTS.md` or `CLAUDE.md`, relative to the project root.
  final String file;

  /// `Regras`, `Comandos`.
  final String section;

  /// The exact excerpt it replaces; empty = a new text at the end of the
  /// section (or of the file, when the section does not exist).
  final String oldText;
  final String newText;

  /// `Q4`, `Q5`.
  final List<String> questions;

  bool get isInsertion => oldText.isEmpty;

  Map<String, Object?> toJson() => {
    'file': file,
    'section': section,
    'oldText': oldText,
    'newText': newText,
    'questions': questions,
  };

  static InstructionProposalHunk? fromJson(Object? j) {
    if (j is! Map) return null;
    final file = '${j['file'] ?? ''}'.trim();
    final newText = '${j['newText'] ?? ''}';
    final oldText = '${j['oldText'] ?? ''}';
    if (file.isEmpty || (newText.isEmpty && oldText.isEmpty)) return null;
    return InstructionProposalHunk(
      file: file,
      section: '${j['section'] ?? ''}'.trim(),
      oldText: oldText,
      newText: newText,
      questions: [
        if (j['questions'] case final List l)
          for (final x in l)
            if ('$x'.trim().isNotEmpty) '$x'.trim().toUpperCase(),
      ],
    );
  }
}

/// What the interview proposes (R19), as the proposal screen (T6) reads it.
@immutable
class InstructionProposal {
  const InstructionProposal({
    required this.hunks,
    required this.provider,
    this.model,
    this.summary = '',
    this.endedEarly = false,
    this.questions = const {},
  });

  final List<InstructionProposalHunk> hunks;

  /// Who wrote it (the provider of the interview) and with which model.
  final String provider;
  final String? model;

  /// One sentence of what changes.
  final String summary;

  /// The interview ended before every question (R16).
  final bool endedEarly;

  /// Title of each question of origin (`Q4` → "Teste em tela nova"), so
  /// the screen names them without the interview.
  final Map<String, String> questions;

  Map<String, Object?> toJson() => {
    'hunks': [for (final h in hunks) h.toJson()],
    'provider': provider,
    'model': model,
    'summary': summary,
    'endedEarly': endedEarly,
    'questions': questions,
  };

  static InstructionProposal? fromJson(Object? j) {
    if (j is! Map) return null;
    return InstructionProposal(
      hunks: [
        if (j['hunks'] case final List l)
          for (final x in l) ?InstructionProposalHunk.fromJson(x),
      ],
      provider: '${j['provider'] ?? 'claude'}',
      model: j['model'] as String?,
      summary: '${j['summary'] ?? ''}',
      endedEarly: j['endedEarly'] == true,
      questions: {
        if (j['questions'] case final Map m)
          for (final e in m.entries) '${e.key}': '${e.value}',
      },
    );
  }
}
