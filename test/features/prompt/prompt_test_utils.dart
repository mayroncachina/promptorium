import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/ui/widgets/app_icon.dart';

import '../sessions/session_test_utils.dart' show idSequence;

/// Agent run driven by the test: [emit] feeds events, calls are recorded.
class FakeRun implements AgentRun {
  FakeRun(this.options);

  final AgentStartOptions options;
  final _events = StreamController<ClaudeEvent>.broadcast();
  final _logs = StreamController<String>.broadcast();
  final _exit = Completer<int>();
  final sent = <String>[];
  final sentImages = <List<ImagePart>>[];
  final approvedInputs = <String, Map<String, dynamic>?>{};
  final approved = <(String, List<Object?>?)>[];
  final denied = <String>[];
  bool stopped = false;

  void emit(Map<String, dynamic> json) {
    for (final e in ClaudeEvent.expand(json)) {
      _events.add(e);
    }
  }

  Future<void> finish([int code = 0]) async {
    if (_exit.isCompleted) return;
    _exit.complete(code);
    await _events.close();
    await _logs.close();
  }

  @override
  Stream<ClaudeEvent> get events => _events.stream;

  @override
  Stream<String> get logs => _logs.stream;

  @override
  bool get isRunning => !_exit.isCompleted;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  List<String> get args => const [];

  @override
  Future<void> send(String text, {List<ImagePart> images = const []}) async {
    sent.add(text);
    sentImages.add(images);
  }

  @override
  Future<void> approve(
    String requestId, {
    List<Object?>? updatedPermissions,
    Map<String, dynamic>? updatedInput,
  }) async {
    approved.add((requestId, updatedPermissions));
    approvedInputs[requestId] = updatedInput;
  }

  @override
  Future<void> deny(String requestId, String message) async =>
      denied.add(requestId);

  @override
  Future<int> stop({Duration timeout = const Duration(seconds: 5)}) async {
    stopped = true;
    await finish(-15);
    return -15;
  }
}

/// [AgentProvider] that records every start.
class FakeAgentProvider implements AgentProvider {
  final runs = <FakeRun>[];

  FakeRun get last => runs.last;

  @override
  String get id => 'claude';

  @override
  String get displayName => 'Fake';

  @override
  AppIconData get icon => AppIcons.sparkle;

  @override
  bool get enabled => true;

  @override
  List<String> get models => const ['inherit', 'haiku'];

  @override
  Future<AgentRun> start(AgentStartOptions options) async {
    final r = FakeRun(options);
    runs.add(r);
    return r;
  }
}

List<Override> fakeProviderOverrides(FakeAgentProvider p) => [
  agentProvidersProvider.overrideWithValue([p]),
  sessionIdGeneratorProvider.overrideWithValue(idSequence()),
];

Map<String, dynamic> initLine(String sid) => {
  'type': 'system',
  'subtype': 'init',
  'session_id': sid,
  'model': 'claude-haiku',
  'tools': ['Read'],
  'mcp_servers': [],
  'permissionMode': 'default',
  'cwd': '/w',
};

Map<String, dynamic> textLine(String text, {String id = 'msg_1'}) => {
  'type': 'assistant',
  'message': {
    'id': id,
    'role': 'assistant',
    'content': [
      {'type': 'text', 'text': text},
    ],
  },
  'parent_tool_use_id': null,
  'session_id': 's',
};

Map<String, dynamic> resultLine({double cost = 0.01}) => {
  'type': 'result',
  'subtype': 'success',
  'is_error': false,
  'total_cost_usd': cost,
  'num_turns': 1,
  'duration_ms': 900,
  'usage': {'input_tokens': 100, 'output_tokens': 20},
  'permission_denials': [],
  'result': 'ok',
  'session_id': 's',
};

Future<Workspace> addWorkspace(AppDatabase db, String path) async {
  final ws = await db
      .into(db.workspaces)
      .insertReturning(WorkspacesCompanion.insert(path: path, name: 'repo'));
  await db
      .into(db.appSettings)
      .insert(
        AppSettingsCompanion.insert(
          key: AppSettingKeys.activeWorkspace,
          value: '${ws.id}',
        ),
      );
  return ws;
}

ProviderContainer promptContainer(List<Override> overrides) =>
    ProviderContainer(overrides: overrides);

/// Real [ConversationManager.create] (rows written as in the app) without
/// starting an agent: [send] only records the message.
class SilentConversationManager extends ConversationManager {
  final sent = <(int, String)>[];

  @override
  Future<void> send(
    int id,
    String text, {
    List<ImagePart> images = const [],
  }) async => sent.add((id, text));
}
