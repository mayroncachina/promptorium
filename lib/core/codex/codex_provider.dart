import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../ui/widgets/app_icon.dart';
import '../claude/claude_args.dart';
import '../claude/claude_event.dart';
import '../claude/claude_process.dart' show ProcessStarter;
import '../providers/agent_provider.dart';
import '../providers/capabilities.dart';
import '../providers/permission_policy.dart';
import 'codex_mcp_overrides.dart';
import 'codex_neutral.dart';
import 'codex_quota.dart' show codexRateLimitUpdates;
import 'codex_rpc.dart';

class CodexModel {
  const CodexModel(this.id, this.efforts, this.modalities);
  final String id;
  final List<String> efforts;
  final List<String> modalities;
}

class CodexProvider implements AgentProvider {
  CodexProvider({
    String executable = 'codex',
    String Function()? resolveExecutable,
    this.starter,
    this.clientVersion,
    CodexMcpLister? mcpLister,
  }) : _resolve = resolveExecutable ?? (() => executable),
       _mcpLister = mcpLister ?? defaultCodexMcpLister;

  /// `codex mcp list --json` names (SPEC-105): which servers a run may
  /// override.
  final CodexMcpLister _mcpLister;

  /// Resolved only when used: listing the provider never runs the CLI.
  final String Function() _resolve;
  String get executable => _resolve();
  final ProcessStarter? starter;

  /// The app version sent in `initialize.clientInfo` (SPEC-093 D13).
  final String? Function()? clientVersion;

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
  ProviderCapabilities get capabilities => ProviderCapabilities.codex;

  @override
  Future<AgentRun> start(AgentStartOptions options) async {
    validateOptions(options);
    final args = ['app-server'];
    final mcp = await _mcpArgs(options);
    args.addAll(mcp.args);
    for (final MapEntry(:key, :value)
        in options.codex.configOverrides.entries) {
      args.addAll(['-c', '$key=$value']);
    }
    final Process process;
    // SPEC-096 R15: the real App Server leads its own process group.
    final group = starter == null && _setsidAvailable();
    try {
      process = await (starter ?? (group ? _startGroup : _start))(
        executable,
        args,
        workingDirectory: options.workingDirectory,
        environment: mcp.token == null
            ? options.environment
            : {...?options.environment, codexAppMcpTokenVar: mcp.token!},
      );
    } on ProcessException {
      throw const AgentUnavailable(
        'Codex CLI não encontrado. Instale o Codex e confira o PATH em Configurações → Provedores.',
      );
    }
    final run = CodexRun(
      CodexRpc(process, group: group),
      options,
      args: args,
      clientVersion: clientVersion?.call(),
    );
    try {
      await run.open();
      return run;
    } catch (_) {
      await run.stop(timeout: const Duration(seconds: 2));
      rethrow;
    }
  }

  /// SPEC-105 R7–R9: the MCP of the run by `-c` overrides. Read-only
  /// runs turn every configured server off (fails closed when they cannot
  /// be listed); "Bloqueado" rules become `disabled_tools`; the app's
  /// server comes from its `--mcp-config` file, with its token in the
  /// environment.
  Future<({List<String> args, String? token})> _mcpArgs(
    AgentStartOptions o,
  ) async {
    final readOnly = o.access.readOnly;
    final disallowed = o.codex.mcpDisallowedTools;
    var servers = const <String>[];
    if (readOnly || disallowed.isNotEmpty) {
      try {
        servers = await _mcpLister(executable, o.workingDirectory);
      } catch (e) {
        if (readOnly) {
          throw AgentUnavailable(
            'Codex: não deu para listar os servidores MCP (codex mcp list) '
            'para desligá-los neste modo de leitura. $e',
          );
        }
      }
    }
    CodexAppMcp? app;
    for (final path in o.appMcpConfigs) {
      app ??= readAppMcpConfig(path);
    }
    return (
      args: codexMcpOverrides(
        servers: servers,
        readOnly: readOnly,
        disallowed: disallowed,
        app: app,
      ),
      token: app?.token,
    );
  }

  /// Fail closed rather than send Claude flags or silently drop a control.
  /// Extras of another provider are programming errors: the services
  /// consult [capabilities] and never build them (SPEC-094 R5, R6). The
  /// app's MCP server goes by override (SPEC-105 R7).
  static void validateOptions(AgentStartOptions o) {
    checkExtras('codex', o.extras);
    if (o.forkSession && o.resumeId == null) {
      throw const AgentUnavailable('Codex: fork exige a thread de origem.');
    }
    final raw = o.codex.compactLimit;
    if (raw != null && raw != 'auto') {
      if (!RegExp(r'^\d+[kKmM]?$').hasMatch(raw)) {
        throw const AgentUnavailable('Codex: limiar de compactação inválido.');
      }
    }
  }

  static bool _setsidAvailable() =>
      File('/usr/bin/setsid').existsSync() || File('/bin/setsid').existsSync();

  /// `setsid codex app-server …`: Dart's children are not group leaders, so
  /// `setsid` does not fork and the pid stays the App Server's. A missing
  /// executable fails here, as without `setsid`.
  static Future<Process> _startGroup(
    String exe,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    if (exe.contains('/') && !File(exe).existsSync()) {
      throw ProcessException(exe, args, 'não encontrado');
    }
    return Process.start(
      'setsid',
      [exe, ...args],
      workingDirectory: workingDirectory,
      environment: environment,
    );
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
  CodexRun(this.rpc, this.options, {required this.args, this.clientVersion}) {
    _sub = rpc.messages.stream.listen(
      _message,
      onDone: () {
        unawaited(_events.close());
      },
    );
  }
  final CodexRpc rpc;
  final AgentStartOptions options;

  /// Version of the app in `clientInfo` (null in tests = `0.0.0`).
  final String? clientVersion;
  @override
  final List<String> args;
  late final StreamSubscription<Map<String, dynamic>> _sub;
  final _events = StreamController<ClaudeEvent>();
  final _pending = <String, (Object, String, Map<String, dynamic>)>{};
  final _texts = <String, StringBuffer>{};
  final _finishedItems = <String>{};
  final _startedTools = <String>{};
  final _models = <CodexModel>[];

  /// `fileChange` items seen in this turn, by id: the approval request
  /// does not carry the changes (SPEC-093 D5).
  final _fileItems = <String, Map<String, dynamic>>{};

  /// SPEC-103 P2: the block rules applied to command approvals while the
  /// app's hooks are not active; returns the rule that refuses the
  /// command, or null. A refused command never reaches the person.
  String? Function(Map<String, dynamic> params)? commandFilter;

  /// "Interromper" was asked: the turn ends as interrupted by the person
  /// (SPEC-096 P3).
  bool _interruptAsked = false;
  String? _thread;
  String? _turn;
  bool _busy = false;
  bool _stopping = false;
  String _answer = '';
  Map<String, dynamic> _lastUsage = const {};
  Map<String, dynamic> _baselineUsage = const {};
  Map<String, dynamic> _totalUsage = const {};
  ClaudePermissionMode? _permissionMode;

  /// Model of the thread (for the context readings, SPEC-095 R3).
  String? _model;

  /// A `contextCompaction` item running: its id, and the size the App
  /// Server reported meanwhile (the post-compaction size, R4).
  String? _compacting;
  int? _compactedTokens;

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
    _events.add(ClaudeEvent.fromJson(_clean(json)));
  }

  // Scrub before persistence; never store raw App Server authentication.
  Map<String, dynamic> _clean(Map<String, dynamic> json) =>
      CodexRpc.redactJson({
        ...json,
        'provider': 'codex',
        'session_id': _thread,
        if (_turn != null) 'turn_id': _turn,
      }) as Map<String, dynamic>;

  /// A file change: stored with the diff cut to the limit (R12), the whole
  /// diff kept in the live event.
  void _emitFile(Map<String, dynamic> json, String? diff) {
    if (_events.isClosed) return;
    final full = diff == null ? null : CodexRpc.redact(diff);
    final clean = _clean(json);
    if (full != null) {
      final cut = NeutralLimits.cut(full);
      clean['diff'] = cut.text;
      if (cut.cut > 0) clean['diff_cut'] = cut.cut;
    }
    _events.add(FileChangeEvent.live(clean, full));
  }

  bool get _readOnly => _access != null
      ? _access == AgentAccess.ask || _access == AgentAccess.plan
      : options.mode == PromptMode.ask ||
            options.mode == PromptMode.plan ||
            _permissionMode == ClaudePermissionMode.plan;

  /// Access chosen with the turn stopped (SPEC-096 R14): the Codex takes
  /// a policy per `turn/start`, so the next turn uses it.
  AgentAccess? _access;

  AgentAccess get access => _access ?? options.access;

  ({String sandbox, String approval}) get _policy => codexAccessPolicy(
    _readOnly ? AgentAccess.ask : access,
    extras: options.codex,
  );
  String get _sandbox => _policy.sandbox;
  String get _approval => _policy.approval;

  Future<void> open() async {
    _permissionMode = options.access.legacyMode;
    final init = await rpc.request('initialize', {
      'clientInfo': {
        'name': 'promptorium',
        'title': 'Promptorium',
        'version': clientVersion ?? '0.0.0',
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
    final compact = options.codex.compactLimit;
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
    // SPEC-093 D1, SPEC-096 R10: the thread always opens `read-only` +
    // `never` — a writable sandbox on `thread/*` makes the App Server save
    // trust in ~/.codex/config.toml. The real policy goes on each
    // `turn/start`.
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
        'sandbox': codexThreadSandbox,
        'approvalPolicy': codexThreadApproval,
        if (requested != null && requested != 'inherit') 'model': requested,
        if (options.appendSystemPrompt != null)
          'developerInstructions': options.appendSystemPrompt,
        if (config.isNotEmpty) 'config': config,
      },
    );
    final thread = result['thread'];
    _thread = thread is Map ? thread['id'] as String? : null;
    if (_thread == null || _thread!.isEmpty) {
      throw const AgentUnavailable(
        'Codex não devolveu o identificador da thread.',
      );
    }
    final model = '${result['model'] ?? requested ?? 'inherit'}';
    _model = model == 'inherit' ? null : model;
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
      // Perguntar and Planejar share the sandbox but keep their names.
      'permission_label': codexAccessLabel(access),
      'sandbox': _sandbox,
      'approvalPolicy': _approval,
      if (_sandbox == 'workspace-write' &&
          options.codex.writableRoots.isNotEmpty)
        'writableRoots': options.codex.writableRoots,
      'codex_version': init['userAgent'],
      'models': [
        for (final m in _models)
          {'id': m.id, 'efforts': m.efforts, 'modalities': m.modalities},
      ],
    });
  }

  /// Model of the thread (null = not reported).
  String? get model => _model;

  /// The selected model takes images (the `image` modality); else the
  /// app sends pictures as files (SPEC-051 R8).
  bool get supportsImages =>
      _models
          .where((m) => m.id == (_model ?? options.model))
          .firstOrNull
          ?.modalities
          .contains('image') ??
      false;

  /// `UserInput` of a message: text plus images as data URLs (SPEC-093
  /// R11 proved both data URL and `localImage`).
  static List<Map<String, dynamic>> _input(
    String text,
    List<ImagePart> images,
  ) => [
    {'type': 'text', 'text': text},
    for (final image in images)
      {
        'type': 'image',
        'url': 'data:${image.mediaType};base64,${image.base64}',
      },
  ];

  /// The turn's sandbox policy (SPEC-096 R10): `workspaceWrite` carries the
  /// writable roots (the worktree's slice of the git common dir).
  Map<String, dynamic> get _sandboxPolicy => switch (_sandbox) {
    'danger-full-access' => {'type': 'dangerFullAccess'},
    'read-only' => {'type': 'readOnly'},
    _ => {
      'type': 'workspaceWrite',
      if (options.codex.writableRoots.isNotEmpty)
        'writableRoots': options.codex.writableRoots,
    },
  };

  /// Whether a message sent now goes into the running turn (`turn/steer`).
  bool get steering => _busy && _turn != null;

  @override
  Future<void> send(String text, {List<ImagePart> images = const []}) async {
    if (images.isNotEmpty) {
      // The thread's model (the CLI default when `inherit`, SPEC-100 R6).
      final model = _model ?? options.model;
      final selected = _models.where((m) => m.id == model).firstOrNull;
      if (selected == null || !selected.modalities.contains('image')) {
        throw const AgentUnavailable(
          'Selecione um modelo Codex com suporte confirmado a imagens.',
        );
      }
    }
    if (_busy) {
      // SPEC-096 R7: a message during the turn directs it (`turn/steer`,
      // proved by SPEC-093 R13); before the turn has an id, it waits.
      final turn = _turn;
      if (turn == null) {
        throw const AgentUnavailable(
          'Codex já está respondendo. Aguarde ou interrompa o turno.',
        );
      }
      await rpc.request('turn/steer', {
        'threadId': _thread,
        'expectedTurnId': turn,
        'input': _input(text, images),
      });
      return;
    }
    _busy = true;
    _interruptAsked = false;
    _answer = '';
    _texts.clear();
    _finishedItems.clear();
    _startedTools.clear();
    _fileItems.clear();
    _lastUsage = const {};
    _baselineUsage = _totalUsage;
    try {
      final r = await rpc.request('turn/start', {
        'threadId': _thread,
        'approvalPolicy': _approval,
        'sandboxPolicy': _sandboxPolicy,
        'input': _input(text, images),
        if (options.effort != null && options.effort != 'default')
          'effort': options.effort,
        if (options.jsonSchema != null)
          'outputSchema': jsonDecode(options.jsonSchema!),
      });
      if (_busy) _turn ??= (r['turn'] as Map?)?['id'] as String?;
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
        // SPEC-095 R4: `last` is the context; during a compaction it is the
        // new size (`inputTokens = 0`), reported on the compaction event.
        final ctx = codexContextUsage(p, model: _model);
        if (_compacting != null) {
          _compactedTokens = ctx?['tokens'] as int?;
        } else if (ctx != null) {
          _emit(ctx);
        }
        final usage = p['tokenUsage'] as Map?;
        _totalUsage = Map<String, dynamic>.from(usage?['total'] as Map? ?? {});
        _lastUsage = {
          for (final k in [
            'inputTokens',
            'outputTokens',
            'cachedInputTokens',
            'cacheWriteInputTokens',
            'reasoningOutputTokens',
          ])
            k:
                ((_totalUsage[k] as num? ?? 0) -
                        (_baselineUsage[k] as num? ?? 0))
                    .clamp(0, 1 << 62),
        };
      case 'mcpServer/startupStatus/updated':
        // SPEC-105 R11: the footer counts the Codex servers.
        codexMcpStartupUpdates.add(p);
      case 'account/rateLimits/updated':
        // R5, P5: passed on, never stored (the session drops it); the quota
        // store merges it into the last reading (SPEC-097 R2).
        final quota = codexQuota(p);
        if (quota != null) _emit(quota);
        codexRateLimitUpdates.add(p);
      case 'thread/compacted':
        // Deprecated in 0.170 (the `contextCompaction` item replaced it).
        _emit(
          CompactionEvent.toJson(
            provider: 'codex',
            phase: CompactionEventPhase.completed,
            key: 'compacted:${p['turnId'] ?? _turn ?? ''}',
          ),
        );
      case 'serverRequest/resolved':
        _cancel('codex-${p['requestId']}');
      case 'turn/completed':
        final turn = p['turn'] as Map? ?? const {};
        if (!_busy) return;
        _busy = false;
        _clearPending();
        final ok = turn['status'] == 'completed';
        if (_compacting case final id?) {
          // The turn ended before the compaction item did.
          _finishedItems.add(id);
          _emit(
            CompactionEvent.toJson(
              provider: 'codex',
              phase: ok
                  ? CompactionEventPhase.completed
                  : CompactionEventPhase.failed,
              postTokens: _compactedTokens,
              key: id,
            ),
          );
          _compacting = null;
        }
        final cached = _lastUsage['cachedInputTokens'] as num? ?? 0;
        final input = _lastUsage['inputTokens'] as num? ?? 0;
        _emit({
          'type': 'result',
          'subtype': ok
              ? 'success'
              : turn['status'] == 'interrupted'
              ? 'interrupted'
              : 'error_during_execution',
          'is_error': !ok && turn['status'] != 'interrupted',
          if (turn['status'] == 'interrupted')
            'interrupt_reason': _interruptAsked ? 'user' : 'agent',
          'result': _answer,
          'cost_available': false,
          'num_turns': 1,
          'usage': {
            'input_tokens': (input - cached).clamp(0, 1 << 62),
            'cache_read_input_tokens': cached,
            'output_tokens': _lastUsage['outputTokens'] ?? 0,
            // Part of the output (SPEC-097 R8).
            'reasoning_output_tokens': _lastUsage['reasoningOutputTokens'] ?? 0,
          },
          if (turn['error'] != null) 'error': turn['error'],
        });
        _turn = null;
      case 'hook/started':
      case 'hook/completed':
        // SPEC-103 R6: which hook ran and how it ended; the details of the
        // app's hooks come from its hooks.log.
        final run = p['run'] as Map? ?? const {};
        _emit({
          'type': 'system',
          'subtype': 'codex_hook',
          'method': method,
          'hook': {
            for (final k in [
              'id',
              'eventName',
              'status',
              'source',
              'sourcePath',
              'statusMessage',
            ])
              if (run[k] != null) k: run[k],
            'entries': [
              for (final e in run['entries'] as List? ?? const [])
                if (e is Map) {'kind': e['kind'], 'text': e['text']},
            ],
          },
        });
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
    // SPEC-095 R7: files, commands and compactions in the neutral
    // vocabulary; no more `Edit` / `Bash` pretending to be Claude.
    switch (type) {
      case 'fileChange':
        _fileItems[id] = item;
        _fileChange(id, item, complete: complete);
        return;
      case 'commandExecution':
        if (complete ? _finishedItems.add(id) : _startedTools.add(id)) {
          _emit(codexCommand(item));
        }
        return;
      case 'contextCompaction':
        _compaction(id, complete: complete);
        return;
    }
    if (codexSilentItems.contains(type)) return;
    final name = switch (type) {
      'mcpToolCall' => 'mcp__${item['server']}__${item['tool']}',
      'webSearch' => 'WebSearch',
      'collabAgentToolCall' => 'Agent',
      _ => null,
    };
    if (name == null) {
      // R6: an item without translation is shown collapsed, not dropped.
      if (complete && _finishedItems.add(id)) _emit(codexOtherItem(item));
      return;
    }
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
                if (item['query'] != null) 'query': item['query'],
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
              'content': item['result'] ?? item['status'],
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

  /// One [FileChangeEvent] per entry of `changes[]` (R1), when the item
  /// starts (proposed) and when it ends.
  void _fileChange(
    String id,
    Map<String, dynamic> item, {
    required bool complete,
  }) {
    if (!(complete ? _finishedItems.add(id) : _startedTools.add(id))) return;
    final changes = item['changes'] as List? ?? const [];
    for (var i = 0; i < changes.length; i++) {
      final c = changes[i];
      if (c is! Map<String, dynamic>) continue;
      final f = codexFileChange(
        c,
        toolUseId: id,
        index: i,
        status: item['status'],
      );
      _emitFile(f.json, f.diff);
    }
  }

  /// `contextCompaction` (R4): started, then completed with the new size
  /// when the App Server reported it meanwhile. The reading stays "aguardando
  /// medição" until the next `tokenUsage`.
  void _compaction(String id, {required bool complete}) {
    if (!complete) {
      if (!_startedTools.add(id)) return;
      _compacting = id;
      _compactedTokens = null;
      _emit(
        CompactionEvent.toJson(
          provider: 'codex',
          phase: CompactionEventPhase.started,
          key: id,
        ),
      );
      return;
    }
    if (!_finishedItems.add(id)) return;
    _emit(
      CompactionEvent.toJson(
        provider: 'codex',
        phase: CompactionEventPhase.completed,
        postTokens: _compactedTokens,
        key: id,
      ),
    );
    _compacting = null;
    _compactedTokens = null;
  }

  void _request(Object id, String method, Map<String, dynamic> p) {
    final question = method == 'item/tool/requestUserInput';
    final command = method == 'item/commandExecution/requestApproval';
    final file = method == 'item/fileChange/requestApproval';
    final permissions = method == 'item/permissions/requestApproval';
    final approval = command || file || permissions;
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
          'result': permissions
              ? {'permissions': <String, dynamic>{}, 'scope': 'turn'}
              : {'decision': 'decline'},
        }),
      );
      return;
    }
    if (command && commandFilter != null) {
      final rule = commandFilter!(p);
      if (rule != null) {
        unawaited(
          rpc.write({
            'id': id,
            'result': {'decision': 'decline'},
          }),
        );
        _emit({
          'type': 'system',
          'subtype': 'codex_hook_refused',
          'command': p['command'],
          'rule': rule,
          'tool_use_id': p['itemId'],
        });
        return;
      }
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
            : command
            ? 'Bash'
            : permissions
            ? codexPermissionsTool
            : 'Edit',
        'tool_use_id': p['itemId'],
        'description': permissions ? codexPermissionsSummary(p) : p['reason'],
        'input': question
            ? {'questions': p['questions']}
            : file
            ? codexFileApprovalInput(p, _fileItems['${p['itemId']}'])
            : p,
        // SPEC-096 R6: "Aprovar nesta conversa" = `acceptForSession`, only
        // where the App Server offers it (never under `untrusted`, never
        // for permissions, which are granted for the turn only).
        'permission_suggestions': [
          if (!permissions && codexOffersSession(p)) codexSessionSuggestion,
        ],
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
    var decision = 'accept';
    if (updatedPermissions != null) {
      // Only "Aprovar nesta conversa" (acceptForSession); nothing that
      // writes in the global (no execpolicy amendment, SPEC-093 D6).
      final session = updatedPermissions.any(
        (s) => s is Map && s['type'] == codexSessionSuggestion['type'],
      );
      if (!session || !codexOffersSession(p.$3)) {
        throw const AgentUnavailable(
          'Codex: persistência dessa permissão ainda não validada.',
        );
      }
      decision = 'acceptForSession';
    }
    final question = p.$2 == 'item/tool/requestUserInput';
    final permissions = p.$2 == 'item/permissions/requestApproval';
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
      'result': question
          ? {'answers': answers}
          : permissions
          // R6: what was asked, for this turn only.
          ? {
              'permissions': {
                for (final k in ['fileSystem', 'network'])
                  if ((p.$3['permissions'] as Map?)?[k] != null)
                    k: (p.$3['permissions'] as Map)[k],
              },
              'scope': 'turn',
            }
          : {'decision': decision},
    });
    _cancel(requestId);
  }

  @override
  Future<void> deny(String requestId, String message) async {
    final p = _pending[requestId];
    if (p == null) return;
    await rpc.write({
      'id': p.$1,
      'result': switch (p.$2) {
        'item/tool/requestUserInput' => {'answers': <String, dynamic>{}},
        'item/permissions/requestApproval' => {
          'permissions': <String, dynamic>{},
          'scope': 'turn',
        },
        _ => {'decision': 'decline'},
      },
    });
    _cancel(requestId);
  }

  /// `hooks/list` of this thread (SPEC-103 R5): the hooks the App Server
  /// will really run, with their origin and trust.
  Future<Map<String, dynamic>> hooksList() =>
      rpc.request('hooks/list', {'threadId': _thread});

  @override
  Future<void> interrupt() async {
    if (_turn != null && _busy) {
      _interruptAsked = true;
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
    // R14: valid from the next `turn/start`; the thread stays read-only.
    _access = codexAccessFor(mode);
    _permissionMode = mode;
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

/// Sandbox and approval of every `thread/start|resume|fork` (SPEC-093 D1):
/// read-only never saves trust in ~/.codex/config.toml; the turn raises it.
const codexThreadSandbox = 'read-only';
const codexThreadApproval = 'never';

/// Tool name of `item/permissions/requestApproval` in the approval card.
const codexPermissionsTool = 'Permissões';

/// The suggestion behind "Aprovar nesta conversa" (SPEC-096 R6, P2): the
/// App Server's `acceptForSession`, valid until the process ends.
const codexSessionSuggestion = <String, dynamic>{
  'type': 'codexAcceptForSession',
  'destination': 'session',
};

/// Whether the request offers `acceptForSession`: always for file changes;
/// for commands, only when `availableDecisions` lists it (absent = the
/// `on-request` default, which offers it; `untrusted` does not, SPEC-093 R7).
bool codexOffersSession(Map<String, dynamic> p) {
  final decisions = p['availableDecisions'];
  if (decisions is! List) return true;
  return decisions.contains('acceptForSession');
}

/// "rede; gravar em /a, /b" of a permissions request (SPEC-096 R6).
String codexPermissionsSummary(Map<String, dynamic> p) {
  final perms = p['permissions'] as Map? ?? const {};
  final parts = <String>[];
  final net = perms['network'];
  if (net is Map && net['enabled'] == true) parts.add('acesso à rede');
  final fs = perms['fileSystem'];
  if (fs is Map) {
    final write = [
      for (final w in fs['write'] as List? ?? const []) '$w',
      for (final e in fs['entries'] as List? ?? const [])
        if (e is Map && e['access'] == 'write' && e['path'] is Map)
          '${(e['path'] as Map)['path'] ?? (e['path'] as Map)['pattern'] ?? ''}',
    ].where((w) => w.isNotEmpty).toList();
    final read = [
      for (final r in fs['read'] as List? ?? const []) '$r',
      for (final e in fs['entries'] as List? ?? const [])
        if (e is Map && e['access'] == 'read' && e['path'] is Map)
          '${(e['path'] as Map)['path'] ?? (e['path'] as Map)['pattern'] ?? ''}',
    ].where((r) => r.isNotEmpty).toList();
    if (write.isNotEmpty) parts.add('gravar em ${write.join(', ')}');
    if (read.isNotEmpty) parts.add('ler ${read.join(', ')}');
  }
  final what = parts.isEmpty ? 'permissões extras' : parts.join('; ');
  final reason = p['reason'];
  return 'O Codex quer liberar $what neste turno'
      '${reason is String && reason.isNotEmpty ? ': $reason' : ''}.';
}

/// Input of a file approval card (SPEC-093 D5): the request has no
/// changes, so they come from the `fileChange` item with the same id —
/// the first path and the whole diff of every file.
Map<String, dynamic> codexFileApprovalInput(
  Map<String, dynamic> p,
  Map<String, dynamic>? item,
) {
  final changes = item?['changes'] as List? ?? const [];
  final files = <String>[];
  final diffs = <String>[];
  for (var i = 0; i < changes.length; i++) {
    final c = changes[i];
    if (c is! Map<String, dynamic>) continue;
    final f = codexFileChange(
      c,
      toolUseId: '${p['itemId']}',
      index: i,
      status: null,
    );
    final path = '${f.json['path'] ?? ''}';
    if (path.isNotEmpty) files.add(path);
    if (f.diff case final d?) diffs.add(d);
  }
  return {
    ...p,
    'file_path': ?files.firstOrNull,
    if (files.length > 1) 'files': files,
    if (diffs.isNotEmpty) 'unified_diff': diffs.join(),
  };
}
