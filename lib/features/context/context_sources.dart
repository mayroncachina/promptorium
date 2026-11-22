import 'package:flutter/foundation.dart';

import '../../core/claude/claude_event.dart';
import '../../core/providers/context_events.dart';
import 'context_snapshot.dart';

/// Groups of the Fontes tab (SPEC-087 R4), in display order.
enum ContextSourceGroup {
  instructions('Instruções e memória'),
  app('Spec e mensagens do app'),
  files('Arquivos lidos ou citados'),
  attachments('Anexos'),
  tools('Ferramentas e MCP'),

  /// Subagents of the Codex (SPEC-107 R12): separate contexts.
  subagents('Subagentes');

  const ContextSourceGroup(this.label);

  final String label;
}

/// How the app knows about a source (R4). Configuration alone is never
/// evidence.
enum ContextEvidence {
  /// Text the app put in a message (mention, spec path, attachment).
  sent,

  /// A `Read` call of the agent (its result came back).
  read,

  /// A write call of the agent (`Edit`, `Write`…): it saw the file.
  edited,

  /// The agent itself reported it (`system/init`, `get_context_usage`).
  agent,

  /// The agent says it loaded the file (Codex `instructionSources`,
  /// SPEC-107 R10).
  loaded,

  /// A command the agent classified as a read, search or listing (Codex
  /// `commandActions`, SPEC-107 R11).
  commandRead,

  /// A call of an MCP tool (Codex `mcpToolCall`, R11).
  mcpCall,

  /// A subagent with its own window (R12): never part of the measurement.
  separate,
}

/// One observed source. [ref] is a workspace path (opens the file) or null;
/// only the name and metadata are kept, never the content (R4).
@immutable
class ContextSource {
  const ContextSource({
    required this.group,
    required this.label,
    required this.evidence,
    required this.turn,
    required this.itemIndex,
    this.ref,
    this.historical = false,
    this.tokens,
    this.estimated = false,
    this.method,
    this.detail,
    this.count,
  });

  final ContextSourceGroup group;
  final String label;
  final String? ref;
  final ContextEvidence evidence;
  final int turn;

  /// Timeline position of the event that originated it (R5).
  final int itemIndex;

  /// Observed before the last compaction, without confirmation it stayed.
  final bool historical;

  /// Weight: measured only when the agent informs it; [estimated] = "≈".
  final int? tokens;
  final bool estimated;

  /// How [tokens] was obtained ("estimativa do agente", "caracteres ÷ 4").
  final String? method;

  /// Extra metadata ("14 ferramentas").
  final String? detail;

  /// Items folded into this row (earlier messages).
  final int? count;

  ContextSource copyWith({
    bool? historical,
    int? turn,
    int? itemIndex,
    ContextEvidence? evidence,
    int? tokens,
    bool? estimated,
    String? method,
    String? detail,
  }) => ContextSource(
    group: group,
    label: label,
    ref: ref,
    evidence: evidence ?? this.evidence,
    turn: turn ?? this.turn,
    itemIndex: itemIndex ?? this.itemIndex,
    historical: historical ?? this.historical,
    tokens: tokens ?? this.tokens,
    estimated: estimated ?? this.estimated,
    method: method ?? this.method,
    detail: detail ?? this.detail,
    count: count,
  );

  /// The state label (R4) relative to [currentTurn].
  String stateLabel(int currentTurn) {
    if (historical) return 'histórico · antes de compactar';
    return switch (evidence) {
      ContextEvidence.sent =>
        turn >= currentTurn ? 'enviado neste turno' : 'referência no histórico',
      ContextEvidence.read => 'leitura observada · t$turn',
      ContextEvidence.edited => 'edição observada · t$turn',
      ContextEvidence.agent => 'informado pelo agente',
      ContextEvidence.loaded => 'carregamento informado pelo agente',
      ContextEvidence.commandRead => 'leitura observada (comando) · t$turn',
      ContextEvidence.mcpCall => 'chamada MCP · t$turn',
      ContextEvidence.separate => 'contexto separado · medição indisponível',
    };
  }

  /// "peso indisponível", "≈ 3,4 mil · estimado".
  String get weightLabel {
    final t = tokens;
    if (t == null) return 'peso indisponível';
    return estimated ? '≈ ${contextTokens(t)} · estimado' : contextTokens(t);
  }
}

/// Collects [ContextSource]s from the events of one execution history.
class ContextSources {
  final Map<String, ContextSource> _byKey = {};
  final Map<String, String> _toolNames = {};
  int _turn = 1;

  /// Sources by group, newest first inside each group.
  Map<ContextSourceGroup, List<ContextSource>> get grouped {
    final out = {
      for (final g in ContextSourceGroup.values) g: <ContextSource>[],
    };
    for (final s in _byKey.values.toList().reversed) {
      out[s.group]!.add(s);
    }
    out.removeWhere((_, v) => v.isEmpty);
    return out;
  }

  int get length => _byKey.length;

  /// Turn the sources are relative to (the running / last turn).
  int get turn => _turn;

  static const _readTools = {'Read', 'NotebookRead'};

  /// [path] edited, unless the agent read it already (a read says more).
  void _edited(String path, int turn, int itemIndex) {
    final old = _byKey['file:$path'];
    if (old != null && old.evidence == ContextEvidence.read) return;
    _put(
      'file:$path',
      ContextSource(
        group: ContextSourceGroup.files,
        label: path,
        ref: path,
        evidence: ContextEvidence.edited,
        turn: turn,
        itemIndex: itemIndex,
      ),
    );
  }

  void apply(
    AgentEvent e, {
    required int turn,
    required DateTime at,
    required int itemIndex,
  }) {
    switch (e) {
      case SystemInit():
        _mcp(e, itemIndex);
      case AssistantMessage(parentToolUseId: null)
          when e.json['provider'] == 'codex':
        for (final b in e.blocks) {
          if (b is ToolUseBlock) _codexTool(b, turn, itemIndex);
        }
      case AssistantMessage(parentToolUseId: null):
        for (final b in e.blocks) {
          if (b is! ToolUseBlock) continue;
          final path =
              '${b.input['file_path'] ?? b.input['notebook_path'] ?? ''}';
          if (path.isEmpty) continue;
          if (_readTools.contains(b.name)) {
            _toolNames[b.id] = path;
            _put(
              'file:$path',
              ContextSource(
                group: ContextSourceGroup.files,
                label: path,
                ref: path,
                evidence: ContextEvidence.read,
                turn: turn,
                itemIndex: itemIndex,
              ),
            );
          } else if (b.fileChanges.isNotEmpty) {
            _edited(path, turn, itemIndex);
          }
        }
      // SPEC-095 R9: files of any provider (Codex: file changes, and the
      // files its commands read).
      case FileChangeEvent(:final path) when path.isNotEmpty:
        _edited(path, turn, itemIndex);
      // SPEC-107 R11: the actions the Codex classified (P4: only known
      // types; the command text is never parsed).
      case CommandEvent(:final actions) when actions.isNotEmpty:
        for (final a in actions) {
          _commandAction(a, e.cwd, turn, itemIndex);
        }
      case CommandEvent(:final reads) when reads.isNotEmpty:
        for (final path in reads) {
          _put(
            'file:$path',
            ContextSource(
              group: ContextSourceGroup.files,
              label: path,
              ref: path,
              evidence: ContextEvidence.read,
              turn: turn,
              itemIndex: itemIndex,
            ),
          );
        }
      case UnknownEvent(:final json)
          when json['type'] == ContextAppEvents.instructions:
        _instructions(json, itemIndex);
      case UnknownEvent(:final json) when json['type'] == 'promptorium_user':
        _turn = turn;
        _message('${json['text'] ?? ''}', turn, itemIndex);
      case Result():
        _turn = turn;
      default:
        break;
    }
  }

  /// Instruction files the Codex says it loaded (R10): proof of loading,
  /// with no weight.
  void _instructions(Map<String, dynamic> j, int itemIndex) {
    for (final path in j['sources'] as List? ?? const []) {
      if (path is! String || path.isEmpty) continue;
      _put(
        'instr:$path',
        ContextSource(
          group: ContextSourceGroup.instructions,
          label: path,
          ref: path,
          evidence: ContextEvidence.loaded,
          turn: _turn,
          itemIndex: itemIndex,
          detail: 'instructionSources',
        ),
      );
    }
  }

  void _commandAction(CommandAction a, String? cwd, int turn, int itemIndex) {
    final path = a.path ?? cwd ?? '.';
    final (key, label) = switch (a.type) {
      CommandAction.read => ('file:$path', path),
      CommandAction.search => (
        'search:$path:${a.query ?? ''}',
        a.query == null || a.query!.isEmpty ? path : '$path · "${a.query}"',
      ),
      _ => ('ls:$path', path),
    };
    _put(
      key,
      ContextSource(
        group: ContextSourceGroup.files,
        label: label,
        ref: a.path,
        evidence: ContextEvidence.commandRead,
        turn: turn,
        itemIndex: itemIndex,
        detail: a.type,
      ),
    );
  }

  /// MCP calls and subagents of the Codex (R11, R12): evidence of a call
  /// or of a separate context, never a weight.
  void _codexTool(ToolUseBlock b, int turn, int itemIndex) {
    if (b.name.startsWith('mcp__')) {
      final parts = b.name.split('__');
      final label = parts.length >= 3
          ? '${parts[1]} · ${parts.sublist(2).join('__')}'
          : b.name;
      _put(
        'mcpcall:${b.name}',
        ContextSource(
          group: ContextSourceGroup.tools,
          label: label,
          evidence: ContextEvidence.mcpCall,
          turn: turn,
          itemIndex: itemIndex,
        ),
      );
    } else if (b.name == 'Agent') {
      final threads = [
        for (final t in b.input['threads'] as List? ?? const [])
          if (t is String && t.isNotEmpty) t,
      ];
      final thread = threads.firstOrNull;
      _put(
        'agent:${b.id}',
        ContextSource(
          group: ContextSourceGroup.subagents,
          label: thread == null
              ? 'subagente'
              : 'subagente (thread ${thread.length > 4 ? '${thread.substring(0, 4)}…' : thread})',
          evidence: ContextEvidence.separate,
          turn: turn,
          itemIndex: itemIndex,
        ),
      );
    }
  }

  static final _mention = RegExp(r'(?:^|\s)@([^\s@]+)');
  static final _spec = RegExp(
    r'(?:^|[\s`(@])((?:[\w.-]+/)*docs/specs/SPEC-[\w.-]+\.md)',
  );
  static final _image = RegExp(r'\(image(?:m|ns) anexadas?: ([^)]+)\)');

  void _message(String text, int turn, int itemIndex) {
    for (final m in _spec.allMatches(text)) {
      final path = m.group(1)!;
      _put(
        'spec:$path',
        ContextSource(
          group: ContextSourceGroup.app,
          label: path,
          ref: path,
          evidence: ContextEvidence.sent,
          turn: turn,
          itemIndex: itemIndex,
        ),
      );
    }
    for (final m in _mention.allMatches(text)) {
      final path = m.group(1)!;
      if (_spec.hasMatch(' $path')) continue;
      final attachment = path.contains('.promptorium/attachments/');
      _put(
        attachment ? 'att:$path' : 'mention:$path',
        ContextSource(
          group: attachment
              ? ContextSourceGroup.attachments
              : ContextSourceGroup.files,
          label: attachment ? path.split('/').last : path,
          ref: path,
          evidence: ContextEvidence.sent,
          turn: turn,
          itemIndex: itemIndex,
        ),
      );
    }
    for (final m in _image.allMatches(text)) {
      for (final name in m.group(1)!.split(',')) {
        final n = name.trim();
        if (n.isEmpty) continue;
        _put(
          'img:$n:$turn',
          ContextSource(
            group: ContextSourceGroup.attachments,
            label: n,
            evidence: ContextEvidence.sent,
            turn: turn,
            itemIndex: itemIndex,
          ),
        );
      }
    }
    // The message itself: the app's own text, an estimate by length. One
    // row for the last message and one for the earlier ones (no flood).
    final body = text.replaceAll(_image, '').replaceAll(_mention, ' ').trim();
    if (body.isEmpty) return;
    final last = _byKey['msg:last'];
    if (last != null && last.turn < turn) {
      final old = _byKey['msg:earlier'];
      final count = (old?.count ?? 0) + 1;
      _put(
        'msg:earlier',
        ContextSource(
          group: ContextSourceGroup.app,
          label: count == 1
              ? '1 mensagem anterior'
              : '$count mensagens anteriores',
          evidence: ContextEvidence.sent,
          turn: last.turn,
          itemIndex: last.itemIndex,
          historical: last.historical || (old?.historical ?? false),
          count: count,
        ),
      );
    }
    _put(
      'msg:last',
      ContextSource(
        group: ContextSourceGroup.app,
        label: 'Mensagem do turno $turn',
        evidence: ContextEvidence.sent,
        turn: turn,
        itemIndex: itemIndex,
        tokens: (body.length / 4).ceil(),
        estimated: true,
        method: 'caracteres ÷ 4',
      ),
    );
  }

  void _mcp(SystemInit e, int itemIndex) {
    for (final s in e.mcpServers) {
      if (!s.isConnected) continue;
      final count = e.tools
          .where((t) => t.startsWith('mcp__${s.name}__'))
          .length;
      final key = 'mcp:${s.name}';
      final old = _byKey[key];
      if (old != null && !old.historical) continue;
      _put(
        key,
        ContextSource(
          group: ContextSourceGroup.tools,
          label: s.name,
          evidence: ContextEvidence.agent,
          turn: _turn,
          itemIndex: itemIndex,
          detail: count == 1 ? '1 ferramenta' : '$count ferramentas',
        ),
      );
    }
  }

  /// `get_context_usage` categories become agent-reported sources with the
  /// agent's estimate (never presented as measured).
  void categories(List<ContextCategory> cats) {
    for (final c in cats) {
      if (!c.used) continue;
      final (group, label) = switch (c.id) {
        'memory_files' => (
          ContextSourceGroup.instructions,
          'CLAUDE.md e memória',
        ),
        'system_prompt' => (
          ContextSourceGroup.instructions,
          'Prompt de sistema',
        ),
        'skills' => (ContextSourceGroup.instructions, 'Skills disponíveis'),
        'custom_agents' => (
          ContextSourceGroup.instructions,
          'Agentes personalizados',
        ),
        'mcp_tools' => (ContextSourceGroup.tools, 'Ferramentas MCP'),
        'mcp_instructions' => (
          ContextSourceGroup.tools,
          'Instruções dos servidores MCP',
        ),
        'system_tools' => (ContextSourceGroup.tools, 'Ferramentas do agente'),
        _ => (null, ''),
      };
      if (group == null) continue;
      _put(
        'cat:${c.id}',
        ContextSource(
          group: group,
          label: label,
          evidence: ContextEvidence.agent,
          turn: _turn,
          itemIndex: _byKey['cat:${c.id}']?.itemIndex ?? 0,
          tokens: c.tokens,
          estimated: true,
          method: 'estimativa do agente',
        ),
      );
    }
  }

  /// After a compaction nothing observed before is confirmed to remain.
  /// What the app sent in the running [turn] goes after the summary (the
  /// CLI compacts before handling the new message): it stays current.
  void compacted({int? turn}) {
    for (final k in _byKey.keys.toList()) {
      final s = _byKey[k]!;
      if (s.evidence == ContextEvidence.agent ||
          s.evidence == ContextEvidence.loaded ||
          s.evidence == ContextEvidence.separate) {
        continue;
      }
      if (turn != null &&
          s.evidence == ContextEvidence.sent &&
          s.turn >= turn &&
          k != 'msg:earlier') {
        continue;
      }
      _byKey[k] = s.copyWith(historical: true);
    }
  }

  void _put(String key, ContextSource s) {
    _byKey.remove(key);
    _byKey[key] = s;
  }
}
