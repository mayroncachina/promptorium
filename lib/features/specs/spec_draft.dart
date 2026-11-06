import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../project/project_plan.dart' show PlanMessage;

/// An open question of the draft (`- P1 · …`, `  - Sugestão: …`).
@immutable
class DraftQuestion {
  const DraftQuestion(this.text, {this.suggestion = ''});

  final String text;
  final String suggestion;

  factory DraftQuestion.fromJson(Object? j) => j is Map
      ? DraftQuestion(_line(j['text']), suggestion: _line(j['suggestion']))
      : DraftQuestion(_line(j));

  Map<String, Object?> toJson() => {
    'text': text,
    if (suggestion.isNotEmpty) 'suggestion': suggestion,
  };

  @override
  bool operator ==(Object other) =>
      other is DraftQuestion &&
      other.text == text &&
      other.suggestion == suggestion;

  @override
  int get hashCode => Object.hash(text, suggestion);
}

/// One line: a line break inside an item would break the spec's lists.
String _line(Object? v) =>
    v == null ? '' : '$v'.replaceAll(RegExp(r'\s+'), ' ').trim();

List<String> _lines(Object? v) => [
  if (v is List)
    for (final x in v)
      if (_line(x).isNotEmpty) _line(x),
];

/// `- R3 · texto`, `R3: texto`, `R3 - texto` → `texto`.
String _withoutRequirementId(String text) =>
    text.replaceFirst(RegExp(r'^[-*\s]*\**R\d+\**\s*[·:.\-–—]*\s*'), '');

/// What one answer of the planner says the spec is (SPEC-039 R5).
@immutable
class PlannerDraft {
  const PlannerDraft({
    this.title = '',
    this.objective = '',
    this.requirements = const [],
    this.outOfScope = const [],
    this.dependsOn = const [],
    this.openQuestions = const [],
  });

  final String title;
  final String objective;
  final List<String> requirements;
  final List<String> outOfScope;
  final List<String> dependsOn;
  final List<DraftQuestion> openQuestions;

  factory PlannerDraft.fromJson(Object? json) {
    final j = json is Map ? json : const {};
    final questions = j['openQuestions'];
    return PlannerDraft(
      title: _line(j['title']),
      objective: _line(j['objective']),
      requirements: [
        for (final r in _lines(j['requirements']))
          if (_withoutRequirementId(r).isNotEmpty) _withoutRequirementId(r),
      ],
      outOfScope: _lines(j['outOfScope']),
      dependsOn: _lines(j['dependsOn']),
      openQuestions: [
        if (questions is List)
          for (final q in questions)
            if (DraftQuestion.fromJson(q).text.isNotEmpty)
              DraftQuestion.fromJson(q),
      ],
    );
  }
}

/// The conversation and the draft of "Nova spec" (`spec_drafts.data`).
@immutable
class SpecDraftData {
  const SpecDraftData({
    this.messages = const [],
    this.title = '',
    this.titleEdited = false,
    this.objective = '',
    this.requirements = const [],
    this.newRequirements = const [],
    this.outOfScope = const [],
    this.dependsOn = const [],
    this.openQuestions = const [],
  });

  /// R10: what passes this goes to "Fora do escopo".
  static const maxRequirements = 6;

  final List<PlanMessage> messages;
  final String title;

  /// Typed by the person: the planner no longer changes it (R5).
  final bool titleEdited;
  final String objective;
  final List<String> requirements;

  /// Added by the last answer: marked "novo" until the next one (R5).
  final List<String> newRequirements;
  final List<String> outOfScope;
  final List<String> dependsOn;
  final List<DraftQuestion> openQuestions;

  /// The planner answered at least once (R6).
  bool get hasReply => messages.any((m) => !m.fromUser);

  /// What the person sent after the last answer. Not empty with nothing
  /// running = the planner did not answer, even if the app closed on the way
  /// (R9).
  List<String> get unanswered {
    final last = messages.lastIndexWhere((m) => !m.fromUser);
    return [for (final m in messages.skip(last + 1)) m.text];
  }

  factory SpecDraftData.decode(String data) {
    Object? json;
    try {
      json = jsonDecode(data);
    } on FormatException {
      json = null;
    }
    final j = json is Map ? json : const {};
    final draft = PlannerDraft.fromJson(j);
    final messages = j['messages'];
    return SpecDraftData(
      messages: [
        if (messages is List)
          for (final m in messages)
            if (m is Map) PlanMessage.fromJson(m.cast<String, Object?>()),
      ],
      title: draft.title,
      titleEdited: j['titleEdited'] == true,
      objective: draft.objective,
      requirements: draft.requirements,
      newRequirements: _lines(j['newRequirements']),
      outOfScope: draft.outOfScope,
      dependsOn: draft.dependsOn,
      openQuestions: draft.openQuestions,
    );
  }

  String encode() => jsonEncode({
    'messages': [for (final m in messages) m.toJson()],
    'title': title,
    if (titleEdited) 'titleEdited': true,
    'objective': objective,
    'requirements': requirements,
    'newRequirements': newRequirements,
    'outOfScope': outOfScope,
    'dependsOn': dependsOn,
    'openQuestions': [for (final q in openQuestions) q.toJson()],
  });

  SpecDraftData withUserMessage(String text) => _copy(
    messages: [
      ...messages,
      PlanMessage(fromUser: true, text: text),
    ],
  );

  SpecDraftData withTitle(String text) => _copy(title: text, titleEdited: true);

  /// The draft after an answer: the title typed by hand stays, only specs of
  /// [knownSpecs] are dependencies and the requirements past
  /// [maxRequirements] move to "Fora do escopo" (R5, R10).
  SpecDraftData withAnswer({
    required String reply,
    required PlannerDraft draft,
    required List<String> suggestions,
    required Set<String> knownSpecs,
  }) {
    final kept = draft.requirements.take(maxRequirements).toList();
    final outOfScope = [...draft.outOfScope];
    for (final r in draft.requirements.skip(maxRequirements)) {
      final item = '${r.replaceFirst(RegExp(r'[.\s]+$'), '')}: $nextSpecHint';
      if (!outOfScope.contains(item)) outOfScope.add(item);
    }
    final next = _copy(
      title: titleEdited || draft.title.isEmpty ? title : draft.title,
      objective: draft.objective,
      requirements: kept,
      newRequirements: [
        for (final r in kept)
          if (!requirements.contains(r)) r,
      ],
      outOfScope: outOfScope,
      dependsOn: {
        for (final d in draft.dependsOn)
          if (knownSpecs.contains(d)) d,
      }.toList(),
      openQuestions: draft.openQuestions,
    );
    return next._copy(
      messages: [
        ...messages,
        PlanMessage(
          fromUser: false,
          text: reply.isEmpty ? 'Rascunho atualizado.' : reply,
          suggestions: suggestions,
          note: draftChanges(this, next),
        ),
      ],
    );
  }

  SpecDraftData _copy({
    List<PlanMessage>? messages,
    String? title,
    bool? titleEdited,
    String? objective,
    List<String>? requirements,
    List<String>? newRequirements,
    List<String>? outOfScope,
    List<String>? dependsOn,
    List<DraftQuestion>? openQuestions,
  }) => SpecDraftData(
    messages: messages ?? this.messages,
    title: title ?? this.title,
    titleEdited: titleEdited ?? this.titleEdited,
    objective: objective ?? this.objective,
    requirements: requirements ?? this.requirements,
    newRequirements: newRequirements ?? this.newRequirements,
    outOfScope: outOfScope ?? this.outOfScope,
    dependsOn: dependsOn ?? this.dependsOn,
    openQuestions: openQuestions ?? this.openQuestions,
  );
}

/// Ending of a requirement that did not fit (R10).
const nextSpecHint = 'sugestão de próxima spec.';

/// "Rascunho atualizado · Objetivo · Requisitos +2" (R3); null = nothing
/// changed.
String? draftChanges(SpecDraftData before, SpecDraftData after) {
  String count(String label, int was, int now) =>
      now > was ? '$label +${now - was}' : label;
  final parts = [
    if (before.title != after.title) 'Título',
    if (before.objective != after.objective) 'Objetivo',
    if (!listEquals(before.requirements, after.requirements))
      count(
        'Requisitos',
        before.requirements.length,
        after.requirements.length,
      ),
    if (!listEquals(before.outOfScope, after.outOfScope))
      count(
        'Fora do escopo',
        before.outOfScope.length,
        after.outOfScope.length,
      ),
    if (!listEquals(before.dependsOn, after.dependsOn)) 'Depende de',
    if (!listEquals(before.openQuestions, after.openQuestions))
      'Perguntas ${after.openQuestions.length}',
  ];
  return parts.isEmpty ? null : 'Rascunho atualizado · ${parts.join(' · ')}';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// "hoje às 18:20", "ontem às 18:20", "03/11 às 18:20".
String draftDateLabel(DateTime at, DateTime now) {
  final time = '${_two(at.hour)}:${_two(at.minute)}';
  final day = DateTime(at.year, at.month, at.day);
  final days = DateTime(now.year, now.month, now.day).difference(day).inDays;
  return switch (days) {
    0 => 'hoje às $time',
    1 => 'ontem às $time',
    _ => '${_two(at.day)}/${_two(at.month)} às $time',
  };
}

/// "Lembretes de consulta · 4 requisitos · ontem às 18:20" (R8).
String draftSummary(SpecDraftData data, DateTime at, DateTime now) {
  final n = data.requirements.length;
  return [
    data.title.isEmpty ? 'Sem título' : data.title,
    '$n ${n == 1 ? 'requisito' : 'requisitos'}',
    draftDateLabel(at, now),
  ].join(' · ');
}
