/// App events of the agent's conversation that went back (SPEC-110 R8–R10),
/// in `session_events`. No migration: what a restore point needs to know of
/// the conversation comes from here.
abstract final class AgentConversationEvents {
  /// The conversation went back to before a turn (`thread/revert`).
  static const reverted = 'conversation_reverted';

  /// It did not: the files are undone, the agent hears the notice.
  static const failed = 'conversation_revert_failed';

  /// "Refazer" adopted the copy.
  static const restored = 'conversation_restored';

  /// A copy nobody can adopt any more was archived (`thread/archive`).
  static const archived = 'conversation_copy_archived';

  static const all = {reverted, failed, restored, archived};
}

/// What an undo asked of the conversation and what came of it: the stored
/// JSON of [AgentConversationEvents.reverted] and [AgentConversationEvents.failed].
class ConversationRevert {
  const ConversationRevert({
    required this.key,
    required this.pointId,
    required this.turn,
    required this.lastTurn,
    required this.beforeTurnId,
    required this.threadId,
    required this.at,
    this.fromSeq,
    this.copyId,
    this.copiedAt,
    this.copyError,
    this.error,
    this.files = 0,
    this.commits = const [],
  });

  /// Id of the event (what "Refazer" answers to).
  final String key;

  /// The restore point undone and its turn; [lastTurn] = the newest turn
  /// undone with it.
  final int pointId;
  final int turn;
  final int lastTurn;

  /// The Codex turn dropped, with every later one.
  final String beforeTurnId;

  /// The thread of the session (its `externalId`) at that moment.
  final String threadId;
  final DateTime at;

  /// `seq` of the message that opened the turn: the events from it on left
  /// the conversation.
  final int? fromSeq;

  /// `thread/fork` made before reverting (P3); null with [copyError].
  final String? copyId;

  /// When the copy was made, if not [at] (a retry reuses the first one).
  final DateTime? copiedAt;
  final String? copyError;

  DateTime get copyAt => copiedAt ?? at;

  /// Why the conversation did not go back (null = it did).
  final String? error;

  /// What the undo did to the files (the timeline note).
  final int files;
  final List<String> commits;

  bool get ok => error == null;

  Map<String, dynamic> toJson() => {
    'type': ok
        ? AgentConversationEvents.reverted
        : AgentConversationEvents.failed,
    'v': 1,
    'provider': 'codex',
    'id': key,
    'point_id': pointId,
    'turn': turn,
    'last_turn': lastTurn,
    'before_turn_id': beforeTurnId,
    'thread_id': threadId,
    'from_seq': ?fromSeq,
    'copy_id': ?copyId,
    'copy_at': ?copiedAt?.toIso8601String(),
    'copy_error': ?copyError,
    'error': ?error,
    'files': files,
    if (commits.isNotEmpty) 'commits': commits,
    'at': at.toIso8601String(),
  };

  static ConversationRevert? fromJson(Object? j) {
    if (j is! Map) return null;
    final type = j['type'];
    if (type != AgentConversationEvents.reverted &&
        type != AgentConversationEvents.failed) {
      return null;
    }
    int n(Object? v) => v is num ? v.toInt() : 0;
    String? s(Object? v) => v is String && v.isNotEmpty ? v : null;
    final key = s(j['id']);
    if (key == null) return null;
    return ConversationRevert(
      key: key,
      pointId: n(j['point_id']),
      turn: n(j['turn']),
      lastTurn: n(j['last_turn']),
      beforeTurnId: s(j['before_turn_id']) ?? '',
      threadId: s(j['thread_id']) ?? '',
      at: DateTime.tryParse('${j['at']}')?.toLocal() ?? DateTime(1970),
      fromSeq: j['from_seq'] is num ? n(j['from_seq']) : null,
      copyId: s(j['copy_id']),
      copiedAt: DateTime.tryParse('${j['copy_at']}')?.toLocal(),
      copyError: s(j['copy_error']),
      error: type == AgentConversationEvents.failed
          ? (s(j['error']) ?? 'erro do App Server')
          : null,
      files: n(j['files']),
      commits: [for (final c in j['commits'] as List? ?? const []) '$c'],
    );
  }

  /// "turno 3", "turnos 3 a 5".
  String get turns => turnsLabel(turn, lastTurn);

  /// The timeline line (R8).
  String get note {
    final parts = [
      if (files > 0) filesLabel(files),
      if (commits.isNotEmpty) commitsLabel(commits),
    ];
    if (!ok) {
      final what = parts.isEmpty ? '' : ' Os arquivos continuam desfeitos e';
      return 'A conversa do Codex não voltou: $error.'
          '${what.isEmpty ? ' O' : '$what o'} agente recebe o aviso.';
    }
    final one = turn == lastTurn;
    final range = one ? '' : ' ($turns)';
    final done = parts.isEmpty
        ? 'a conversa do Codex$range'
        : '${parts.join(', ')} e a conversa do Codex$range';
    final copy = copyId != null
        ? ''
        : ' Sem cópia da conversa'
              '${copyError == null ? '' : ' ($copyError)'}: o Refazer volta '
              'só os arquivos.';
    return 'Turno $turn desfeito: $done. O agente não recebe aviso: ele já '
        'não conhece ${one ? 'esse turno' : 'esses turnos'}.$copy';
  }
}

/// "turno 3", "turnos 3 a 5".
String turnsLabel(int first, int last) =>
    last <= first ? 'turno $first' : 'turnos $first a $last';

/// "6 arquivos".
String filesLabel(int n) => '$n arquivo${n == 1 ? '' : 's'}';

/// "1 commit (wip)".
String commitsLabel(List<String> subjects) =>
    '${subjects.length} commit${subjects.length == 1 ? '' : 's'} '
    '(${subjects.first.split(':').first})';

/// The event of a "Refazer" that adopted the copy (R9).
Map<String, dynamic> conversationRestoredEvent({
  required ConversationRevert revert,
  required String previousThread,
  required int files,
  DateTime? at,
}) => {
  'type': AgentConversationEvents.restored,
  'v': 1,
  'provider': 'codex',
  'revert': revert.key,
  'turn': revert.turn,
  'copy_id': revert.copyId,
  'copy_at': revert.copyAt.toIso8601String(),
  'thread_id': previousThread,
  'files': files,
  'at': (at ?? DateTime.now()).toIso8601String(),
};

/// "Refeito: arquivos e conversa (cópia de 14:20)" (R9).
String conversationRestoredNote(Map<String, dynamic> j) {
  final at = DateTime.tryParse('${j['copy_at']}')?.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final when = at == null
      ? ''
      : ' (cópia de ${two(at.hour)}:${two(at.minute)})';
  return 'Refeito: arquivos e conversa$when';
}
