import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../ui/widgets/app_icon.dart';
import '../claude/claude_args.dart';
import '../claude/claude_event.dart';
import '../claude/claude_process.dart' show ProcessStarter;
import '../providers/agent_provider.dart';
import '../providers/permission_policy.dart';
import 'codex_rpc.dart';

class CodexModel {
  const CodexModel(this.id, this.efforts, this.modalities);
  final String id;
  final List<String> efforts;
  final List<String> modalities;
}

class CodexProvider implements AgentProvider {
  CodexProvider({this.executable = 'codex', this.starter});
  final String executable;
  final ProcessStarter? starter;

  @override
  String get id => 'codex';
  @override
  String get displayName => 'Codex';
  @override
  AppIconData get icon => AppIcons.code;
  @override
  bool get enabled => true;
  @override
  List<String> get models => const ['inherit'];

  @override
  Future<AgentRun> start(AgentStartOptions options) async {
    validateOptions(options);
    final args = ['app-server'];
    if (options.mode == PromptMode.ask ||
        options.mode == PromptMode.plan ||
        options.strictMcpConfig) {
      args.addAll(['-c', 'mcp_servers={}']);
    }
    final Process process;
    try {
      process = await (starter ?? _start)(
        executable,
        args,
        workingDirectory: options.workingDirectory,
        environment: options.environment,
      );
    } on ProcessException {
      throw const AgentUnavailable(
        'Codex CLI não encontrado. Instale o Codex e confira o PATH em Configurações → Provedores.',
      );
    }
    final run = CodexRun(CodexRpc(process), options, args: args);
    try {
      await run.open();
      return run;
    } catch (_) {
      await run.stop(timeout: const Duration(seconds: 2));
      rethrow;
    }
  }

  /// Fail closed rather than send Claude flags or silently drop a control.
  static void validateOptions(AgentStartOptions o) {
    final unsupported = <String>[
      if (o.maxBudgetUsd != null) 'limite monetário',
      if (o.maxTurns != null) 'limite de turnos internos',
      if (o.agent != null) 'perfil de agente Claude',
      if (o.agentsJson != null) 'definições de subagentes Claude',
      if (o.settingsFile != null) 'hooks/settings Claude',
      if (o.mcpConfigs.isNotEmpty) 'arquivos MCP Claude',
      if (o.tools.isNotEmpty) 'restrição de ferramentas Claude',
      if (o.mcpAllowedTools.isNotEmpty || o.mcpDisallowedTools.isNotEmpty)
        'regras de ferramentas MCP Claude',
      if (o.permissionMode == ClaudePermissionMode.auto)
        'aprovação automática Claude',
    ];
    if (unsupported.isNotEmpty) {
      throw AgentUnavailable(
        'Codex: opções ainda sem equivalente validado: '
        '${unsupported.join(', ')}. Ajuste a configuração antes de executar.',
      );
    }
    if (o.forkSession && o.resumeId == null) {
      throw const AgentUnavailable('Codex: fork exige a thread de origem.');
    }
    if (o.autocompact != null && o.autocompact != 'auto') {
      final raw = o.autocompact!;
      if (!RegExp(r'^\d+[kKmM]?$').hasMatch(raw)) {
        throw const AgentUnavailable('Codex: limiar de compactação inválido.');
      }
    }
  }

  static Future<Process> _start(
    String exe,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) => Process.start(
    exe,
    args,
    workingDirectory: workingDirectory,
    environment: environment,
  );
}

/// The App Server persists threads; local ids are never passed as Codex ids.
class CodexRun implements ManagedAgentRun {
  CodexRun(this.rpc, this.options, {required this.args}) {
    _sub = rpc.messages.stream.listen(
      _message,
      onDone: () {
        unawaited(_events.close());
      },
    );
  }
  final CodexRpc rpc;
  final AgentStartOptions options;
  @override
  final List<String> args;
  late final StreamSubscription<Map<String, dynamic>> _sub;
  final _events = StreamController<ClaudeEvent>();
  final _pending = <String, (Object, String, Map<String, dynamic>)>{};
  final _texts = <String, StringBuffer>{};
  final _finishedItems = <String>{};
  final _startedTools = <String>{};
  final _models = <CodexModel>[];
  String? _thread;
  String? _turn;
  bool _busy = false;
  bool _stopping = false;
  String _answer = '';
  Map<String, dynamic> _lastUsage = const {};
  Map<String, dynamic> _baselineUsage = const {};
  Map<String, dynamic> _totalUsage = const {};
  ClaudePermissionMode? _permissionMode;

  @override
  Stream<ClaudeEvent> get events => _events.stream;
  @override
  Stream<String> get logs => rpc.logs.stream;
  @override
  bool get isRunning => !rpc.exited;
  @override
  Future<int> get exitCode => rpc.exitCode;
  @override
  int get pid => rpc.process.pid;

  void _emit(Map<String, dynamic> json) {
    if (_events.isClosed) return;
    // Scrub before persistence; never store raw App Server authentication.
    final clean = jsonDecode(
      CodexRpc.redact(
        jsonEncode({
          ...json,
          'provider': 'codex',
          'session_id': _thread,
          if (_turn != null) 'turn_id': _turn,
        }),
      ),
    ) as Map<String, dynamic>;
    _events.add(ClaudeEvent.fromJson(clean));
  }

  bool get _readOnly =>
      options.mode == PromptMode.ask ||
      options.mode == PromptMode.plan ||
      _permissionMode == ClaudePermissionMode.plan;

  ({String sandbox, String approval}) get _policy => codexPermissionPolicy(
    _permissionMode,
    readOnly: _readOnly,
    refine: options.mode == PromptMode.refine,
  );
  String get _sandbox => _policy.sandbox;
  String get _approval => _policy.approval;

  Future<void> open() async {
    _permissionMode = options.permissionMode;
    final init = await rpc.request('initialize', {
      'clientInfo': {
        'name': 'promptorium',
        'title': 'Promptorium',
        'version': '0.2.0',
      },
    });
    await rpc.write({'method': 'initialized', 'params': <String, dynamic>{}});
    final account = await rpc.request('account/read', {});
    if (account['requiresOpenaiAuth'] == true && account['account'] == null) {
      throw const AgentUnavailable(
        'Codex sem autenticação. Execute `codex login` e tente novamente.',
      );
    }
    String? cursor;
    final seen = <String>{};
    do {
      final catalog = await rpc.request('model/list', {
        'limit': 100,
        'cursor': ?cursor,
      });
      for (final m in catalog['data'] as List? ?? const []) {
        if (m is! Map) continue;
        _models.add(
          CodexModel(
            '${m['id']}',
            [
              for (final e
                  in m['supportedReasoningEfforts'] as List? ?? const [])
                if (e is Map && e['reasoningEffort'] is String)
                  e['reasoningEffort'] as String,
            ],
            [
              for (final v in m['inputModalities'] as List? ?? const ['text'])
                '$v',
            ],
          ),
        );
      }
      cursor = catalog['nextCursor'] as String?;
      if (cursor != null && !seen.add(cursor)) {
        throw const AgentUnavailable(
          'Codex: paginação inválida do catálogo de modelos.',
        );
      }
    } while (cursor != null);
    final requested = options.model;
    if (requested != null &&
        requested != 'inherit' &&
        !_models.any((m) => m.id == requested)) {
      throw AgentUnavailable(
        'Modelo Codex indisponível: $requested. Escolha o padrão do CLI ou atualize o catálogo.',
      );
    }
    final config = <String, dynamic>{};
    final compact = options.autocompact;
    if (compact != null && compact != 'auto') {
      final unit = compact.toLowerCase();
      final mult = unit.endsWith('k')
          ? 1000
          : unit.endsWith('m')
          ? 1000000
          : 1;
      config['model_auto_compact_token_limit'] =
          int.parse(unit.replaceAll(RegExp('[km]'), '')) * mult;
    }
    final resume = options.resumeId;
    final result = await rpc.request(
      resume == null
          ? 'thread/start'
          : options.forkSession
          ? 'thread/fork'
          : 'thread/resume',
      {
        'threadId': ?resume,
        if (resume != null) 'excludeTurns': true,
        'cwd': options.workingDirectory,
        'sandbox': _sandbox,
        'approvalPolicy': _approval,
        if (requested != null && requested != 'inherit') 'model': requested,
        if (options.appendSystemPrompt != null)
          'developerInstructions': options.appendSystemPrompt,
        if (config.isNotEmpty) 'config': config,
      },
    );
    final sandboxType = result['sandbox'] is Map
        ? (result['sandbox'] as Map)['type']
        : result['sandbox'];
    final expectedType = switch (_sandbox) {
      'danger-full-access' => 'dangerFullAccess',
      'read-only' => 'readOnly',
      _ => 'workspaceWrite',
    };
    final yolo =
        !_readOnly && _permissionMode == ClaudePermissionMode.skipPermissions;
    if ((yolo &&
            (result['approvalPolicy'] != _approval ||
                sandboxType != expectedType)) ||
        (result['approvalPolicy'] != null &&
            result['approvalPolicy'] != _approval) ||
        (sandboxType != null &&
            sandboxType != expectedType &&
            sandboxType != _sandbox)) {
      throw const AgentUnavailable(
        'Codex não aplicou o modo de permissão solicitado.',
      );
    }
    final thread = result['thread'];
    _thread = thread is Map ? thread['id'] as String? : null;
    if (_thread == null || _thread!.isEmpty) {
      throw const AgentUnavailable(
        'Codex não devolveu o identificador da thread.',
      );
    }
    final model = '${result['model'] ?? requested ?? 'inherit'}';
    final effort = options.effort;
    final selected = _models.where((m) => m.id == model).firstOrNull;
    if (effort != null &&
        effort != 'default' &&
        (selected == null || !selected.efforts.contains(effort))) {
      throw AgentUnavailable(
        'Esforço Codex indisponível para $model: $effort.',
      );
    }
    _emit({
      'type': 'system',
      'subtype': 'init',
      'model': model,
      'cwd': options.workingDirectory,
      'permissionMode': _readOnly
          ? 'plan'
          : _permissionMode?.cliValue ?? options.mode.name,
      'permission_label': permissionModeLabel(
        _readOnly ? ClaudePermissionMode.plan : _permissionMode,
        provider: 'codex',
      ),
      'sandbox': _sandbox,
      'approvalPolicy': _approval,
      'codex_version': init['userAgent'],
      'models': [
        for (final m in _models)
          {'id': m.id, 'efforts': m.efforts, 'modalities': m.modalities},
      ],
    });
  }

  @override
  Future<void> send(String text, {List<ImagePart> images = const []}) async {
    if (_busy) {
      throw const AgentUnavailable(
        'Codex já está respondendo. Aguarde ou interrompa o turno.',
      );
    }
    if (images.isNotEmpty) {
      final model = options.model;
      final selected = _models.where((m) => m.id == model).firstOrNull;
      if (selected == null || !selected.modalities.contains('image')) {
        throw const AgentUnavailable(
          'Selecione um modelo Codex com suporte confirmado a imagens.',
        );
      }
    }
    _busy = true;
    _answer = '';
    _texts.clear();
    _finishedItems.clear();
    _startedTools.clear();
    _lastUsage = const {};
    _baselineUsage = _totalUsage;
    try {
      final r = await rpc.request('turn/start', {
        'threadId': _thread,
        'approvalPolicy': _approval,
        'sandboxPolicy': {
          'type': switch (_sandbox) {
            'danger-full-access' => 'dangerFullAccess',
            'read-only' => 'readOnly',
            _ => 'workspaceWrite',
          },
        },
        'input': [
          {'type': 'text', 'text': text},
          for (final image in images)
            {
              'type': 'image',
              'url': 'data:${image.mediaType};base64,${image.base64}',
            },
        ],
        if (options.effort != null && options.effort != 'default')
          'effort': options.effort,
        if (options.jsonSchema != null)
          'outputSchema': jsonDecode(options.jsonSchema!),
      });
      if (_busy) _turn = (r['turn'] as Map?)?['id'] as String?;
    } catch (_) {
      _busy = false;
      rethrow;
    }
  }

  void _message(Map<String, dynamic> m) {
    final p = m['params'] is Map<String, dynamic>
        ? m['params'] as Map<String, dynamic>
        : <String, dynamic>{};
    if (p['threadId'] != null && p['threadId'] != _thread) return;
    final method = m['method'];
    if (m['id'] != null) {
      _request(m['id']!, '$method', p);
      return;
    }
    switch (method) {
      case 'turn/started':
        _turn = (p['turn'] as Map?)?['id'] as String?;
      case 'item/agentMessage/delta':
        final id = '${p['itemId']}';
        final text = '${p['delta'] ?? ''}';
        _texts.putIfAbsent(id, StringBuffer.new).write(text);
        _emit({
          'type': 'stream_event',
          'item_id': id,
          'event': {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': text},
          },
        });
      case 'item/started':
      case 'item/completed':
        if (p['item'] is Map<String, dynamic>) {
          _item(
            p['item'] as Map<String, dynamic>,
            complete: method == 'item/completed',
          );
        }
      case 'thread/tokenUsage/updated':
        final usage = p['tokenUsage'] as Map?;
        _totalUsage = Map<String, dynamic>.from(usage?['total'] as Map? ?? {});
        _lastUsage = {
          for (final k in [
            'inputTokens',
            'outputTokens',
            'cachedInputTokens',
            'cacheWriteInputTokens',
          ])
            k:
                ((_totalUsage[k] as num? ?? 0) -
                        (_baselineUsage[k] as num? ?? 0))
                    .clamp(0, 1 << 62),
        };
      case 'serverRequest/resolved':
        _cancel('codex-${p['requestId']}');
      case 'turn/completed':
        final turn = p['turn'] as Map? ?? const {};
        if (!_busy) return;
        _busy = false;
        _clearPending();
        final ok = turn['status'] == 'completed';
        final cached = _lastUsage['cachedInputTokens'] as num? ?? 0;
        final input = _lastUsage['inputTokens'] as num? ?? 0;
        _emit({
          'type': 'result',
          'subtype': ok
              ? 'success'
              : turn['status'] == 'interrupted'
              ? 'interrupted'
              : 'error_during_execution',
          'is_error': !ok,
          'result': _answer,
          'cost_available': false,
          'num_turns': 1,
          'usage': {
            'input_tokens': (input - cached).clamp(0, 1 << 62),
            'cache_read_input_tokens': cached,
            'output_tokens': _lastUsage['outputTokens'] ?? 0,
          },
          if (turn['error'] != null) 'error': turn['error'],
        });
        _turn = null;
      case 'error':
        if (p['willRetry'] != true) {
          _emit({'type': 'system', 'subtype': 'error', 'error': p['error']});
        }
      default:
        // Keep only the method, never raw authentication or unknown payloads.
        _emit({
          'type': 'system',
          'subtype': 'codex_notification',
          'method': method,
        });
    }
  }

  void _item(Map<String, dynamic> item, {required bool complete}) {
    final id = '${item['id']}';
    final type = item['type'];
    if (type == 'agentMessage') {
      if (!complete || !_finishedItems.add(id)) return;
      final text = '${item['text'] ?? _texts[id] ?? ''}';
      _answer = text;
      _emit({
        'type': 'assistant',
        'item_id': id,
        'message': {
          'id': id,
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': text},
          ],
        },
      });
      return;
    }
    final name = switch (type) {
      'commandExecution' => 'Bash',
      'fileChange' => 'Edit',
      'mcpToolCall' => 'mcp__${item['server']}__${item['tool']}',
      'webSearch' => 'WebSearch',
      'collabAgentToolCall' => 'Agent',
      _ => null,
    };
    if (name == null) return;
    if (_startedTools.add(id)) {
      _emit({
        'type': 'assistant',
        'item_id': id,
        'message': {
          'id': id,
          'role': 'assistant',
          'content': [
            {
              'type': 'tool_use',
              'id': id,
              'name': name,
              'input': {
                if (item['command'] != null) 'command': item['command'],
                if (item['cwd'] != null) 'cwd': item['cwd'],
                if (item['changes'] != null) 'changes': item['changes'],
                if (item['arguments'] != null) 'arguments': item['arguments'],
                if (item['prompt'] != null) 'prompt': item['prompt'],
              },
            },
          ],
        },
      });
    }
    if (complete && _finishedItems.add(id)) {
      _emit({
        'type': 'user',
        'item_id': id,
        'message': {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': id,
              'content':
                  item['aggregatedOutput'] ??
                  item['result'] ??
                  item['changes'] ??
                  item['status'],
              'is_error':
                  item['status'] == 'failed' ||
                  item['status'] == 'declined' ||
                  (item['exitCode'] != null && item['exitCode'] != 0),
            },
          ],
        },
      });
    }
  }

  void _request(Object id, String method, Map<String, dynamic> p) {
    final question = method == 'item/tool/requestUserInput';
    final approval =
        method == 'item/commandExecution/requestApproval' ||
        method == 'item/fileChange/requestApproval';
    if (!question && !approval) {
      unawaited(
        rpc.write({
          'id': id,
          'error': {
            'code': -32601,
            'message': 'Solicitação não suportada pelo Promptorium.',
          },
        }),
      );
      return;
    }
    if (_readOnly && approval) {
      unawaited(
        rpc.write({
          'id': id,
          'result': {'decision': 'decline'},
        }),
      );
      return;
    }
    final key = 'codex-$id';
    _pending[key] = (id, method, p);
    _emit({
      'type': 'control_request',
      'request_id': key,
      'request': {
        'subtype': 'can_use_tool',
        'tool_name': question
            ? 'AskUserQuestion'
            : method.contains('commandExecution')
            ? 'Bash'
            : 'Edit',
        'tool_use_id': p['itemId'],
        'description': p['reason'],
        'input': question ? {'questions': p['questions']} : p,
        'permission_suggestions': const [],
      },
    });
  }

  void _cancel(String key) {
    if (_pending.remove(key) != null) {
      _emit({'type': 'control_cancel_request', 'request_id': key});
    }
  }

  void _clearPending() {
    for (final key in _pending.keys.toList()) {
      _cancel(key);
    }
  }

  @override
  Future<void> approve(
    String requestId, {
    List<Object?>? updatedPermissions,
    Map<String, dynamic>? updatedInput,
  }) async {
    final p = _pending[requestId];
    if (p == null) {
      throw const AgentUnavailable('A solicitação Codex já foi resolvida.');
    }
    if (updatedPermissions != null) {
      throw const AgentUnavailable(
        'Codex: persistência dessa permissão ainda não validada.',
      );
    }
    final question = p.$2 == 'item/tool/requestUserInput';
    final answers = <String, dynamic>{};
    if (question) {
      final input = updatedInput?['answers'] as Map? ?? const {};
      for (final q in p.$3['questions'] as List? ?? const []) {
        if (q is! Map) continue;
        final answer = input[q['id']] ?? input[q['question']];
        if (answer == null) {
          throw const AgentUnavailable('Responda todas as perguntas do Codex.');
        }
        answers['${q['id']}'] = {
          'answers': answer is List ? answer : ['$answer'],
        };
      }
    }
    await rpc.write({
      'id': p.$1,
      'result': question ? {'answers': answers} : {'decision': 'accept'},
    });
    _cancel(requestId);
  }

  @override
  Future<void> deny(String requestId, String message) async {
    final p = _pending[requestId];
    if (p == null) return;
    await rpc.write({
      'id': p.$1,
      'result': p.$2 == 'item/tool/requestUserInput'
          ? {'answers': <String, dynamic>{}}
          : {'decision': 'decline'},
    });
    _cancel(requestId);
  }

  @override
  Future<void> interrupt() async {
    if (_turn != null && _busy) {
      await rpc.request('turn/interrupt', {
        'threadId': _thread,
        'turnId': _turn,
      });
    }
  }

  @override
  Future<void> setPermissionMode(ClaudePermissionMode mode) async {
    if (_busy) {
      throw const AgentUnavailable(
        'Pare o turno antes de alterar as permissões Codex.',
      );
    }
    throw const AgentUnavailable(
      'Reinicie a sessão para aplicar o modo de permissão Codex.',
    );
  }

  @override
  Future<int> stop({Duration timeout = const Duration(seconds: 5)}) async {
    if (!_stopping) {
      _stopping = true;
      _clearPending();
    }
    final code = await rpc.stop(timeout: timeout);
    await _sub.cancel();
    unawaited(_events.close());
    return code;
  }
}
