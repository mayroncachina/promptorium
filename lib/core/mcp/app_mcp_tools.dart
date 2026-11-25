import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repos/debt_links_repo.dart';
import '../../features/debts/debt_board.dart' show specLabel;
import '../../features/debts/debt_files.dart';
import '../../features/debts/debt_service.dart';
import '../../features/debts/debt_table.dart';
import '../../features/issues/issue_progress.dart';
import '../../data/providers.dart';
import '../../features/board/board_rules.dart' show stepsOf;
import '../../features/board/spec_runner.dart' show parseSessionSteps;
import '../../features/sessions/session_manager.dart'
    show sessionManagerProvider, sessionTitle;
import '../../features/specs/spec_lint.dart' show lintSpec;
import '../../features/specs/spec_service.dart';
import 'app_mcp_server.dart';

/// Name of the server in the `--mcp-config` file: the CLI shows its tools
/// as `mcp__promptorium__<tool>` (P7: Portuguese names).
const appMcpServerName = 'promptorium';

/// Names of the tools (SPEC-052 R3, R4).
abstract final class AppMcpToolNames {
  static const listSpecs = 'listar_specs';
  static const readSpec = 'ler_spec';
  static const board = 'estado_do_quadro';
  static const currentSpec = 'spec_atual';
  static const createSpec = 'criar_spec';
  static const createChildren = 'criar_filhas';
  static const note = 'anotar_andamento';
  static const registerDebt = 'registrar_debito';
  static const listDebts = 'listar_debitos';
}

/// Keys the MCP adds to the body of a debt suggestion (SPEC-112 R11), next
/// to the cells of [DebtDraft.toJson]: who suggested it (the label of the
/// strip, "Codex · MCP") and the title of the session.
abstract final class DebtSuggestionKeys {
  static const provider = 'provedor';
  static const sessionTitle = 'sessao_titulo';
}

/// Most children of one `criar_filhas` call (R4, P5).
const maxChildrenPerCall = 6;

/// Longest progress note (R7).
const maxNoteLength = 280;

const _specText = {
  'type': 'string',
  'description':
      'Markdown da spec: "# Título", "## Objetivo", "## Requisitos" '
      '("- R1 · O sistema deve …"), "## Fora do escopo" e "## Critérios de '
      'aceite" ("- [ ] … [R1]"). O app escolhe o código e o arquivo, grava '
      'status: rascunho e ignora id, status e caminhos do texto.',
};

/// Every tool of the server, reads first (R3, R4).
const appMcpCatalog = <McpToolDef>[
  McpToolDef(
    name: AppMcpToolNames.listSpecs,
    summary: 'Specs do workspace, com status, coluna, sprint e dependências',
    description:
        'Lista as specs do workspace: código, título, status, coluna do '
        'Quadro, sprint e depende-de. Filtros opcionais por status e coluna.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'status': {
          'type': 'string',
          'enum': [
            'ideia',
            'rascunho',
            'em-revisao',
            'aprovada',
            'concluida',
            'arquivada',
          ],
        },
        'coluna': {
          'type': 'string',
          'enum': ['backlog', 'em-execucao', 'review', 'concluida'],
        },
      },
      'additionalProperties': false,
    },
  ),
  McpToolDef(
    name: AppMcpToolNames.readSpec,
    summary: 'O texto de uma spec, as etapas e o último gate',
    description:
        'Devolve o texto de uma spec e o estado de cada etapa (Rn), com o '
        'resultado do último gate.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'codigo': {'type': 'string', 'description': 'Código, ex.: SPEC-012.'},
      },
      'required': ['codigo'],
      'additionalProperties': false,
    },
  ),
  McpToolDef(
    name: AppMcpToolNames.board,
    summary: 'Colunas, sessões vivas e o que espera você',
    description:
        'As specs de cada coluna do Quadro, as sessões vivas e o que espera '
        'a pessoa ("Precisa de você").',
    inputSchema: {
      'type': 'object',
      'properties': {},
      'additionalProperties': false,
    },
  ),
  McpToolDef(
    name: AppMcpToolNames.currentSpec,
    summary: 'A spec e a etapa desta execução',
    description:
        'A spec e as etapas em que esta execução trabalha, quando houver.',
    inputSchema: {
      'type': 'object',
      'properties': {},
      'additionalProperties': false,
    },
  ),
  McpToolDef(
    name: AppMcpToolNames.listDebts,
    summary: 'Débitos técnicos abertos e decisões pendentes, com ID e onde',
    description:
        'Lista os débitos técnicos abertos (DT-nn) e as decisões pendentes '
        '(DP-nn) do projeto, com ID, título e onde estão no código, lidos de '
        'DEBITO_TECNICO.md e DECISOES_PENDENTES.md (os da worktree da spec '
        'desta execução vêm marcados "na spec"). Use antes de registrar_debito '
        'para não repetir um que já existe, ou quando a pessoa perguntar o '
        'que ficou provisório ou por decidir.',
    inputSchema: {
      'type': 'object',
      'properties': {},
      'additionalProperties': false,
    },
  ),
  // Not a write (SPEC-112 R11): it only leaves a suggestion; the file is
  // written by the app when the person accepts it in Débitos e decisões.
  // So it is free in every mode and reaches the Codex too.
  McpToolDef(
    name: AppMcpToolNames.registerDebt,
    summary: 'Sugere um débito ou decisão; você aceita na tela Débitos',
    description:
        'Sugere um débito técnico ou uma decisão pendente para o projeto. Use '
        'quando a pessoa pedir para deixar algo simulado, provisório ou '
        'incompleto e registrar como débito técnico (tipo "debito"), ou para '
        'deixar uma decisão para depois (tipo "decisao", com a pergunta no '
        'título e a sua recomendação). Também quando você mesmo deixar algo '
        'simulado de propósito. Não grava nada no repositório: a sugestão '
        'aparece para a pessoa na tela Débitos e decisões e só vira DT-nn / '
        'DP-nn quando ela aceitar. Não escreva o débito à mão no '
        'DEBITO_TECNICO.md nem no DECISOES_PENDENTES.md.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'tipo': {
          'type': 'string',
          'enum': ['debito', 'decisao'],
          'description':
              'debito: algo deixado simulado/provisório. decisao: uma '
              'pergunta para a pessoa decidir depois.',
        },
        'titulo': {
          'type': 'string',
          'description':
              'Débito: o que ficou provisório, curto (ex.: "Pagamento '
              'simulado"). Decisão: a pergunta.',
        },
        'motivo': {
          'type': 'string',
          'description':
              'Débito: o porquê ou o comportamento atual (ex.: "PIX e cartão '
              'não chamam o gateway").',
        },
        'onde': {
          'type': 'string',
          'description':
              'Arquivos ou símbolos do código, ex.: "PagarView.vue · '
              'pagamentos_servico".',
        },
        'para_resolver': {
          'type': 'string',
          'description': 'Débito: o que falta fazer para pagar o débito.',
        },
        'recomendacao': {
          'type': 'string',
          'description': 'Decisão: a opção que você recomenda e por quê.',
        },
      },
      'required': ['tipo', 'titulo'],
      'additionalProperties': false,
    },
  ),
  McpToolDef(
    name: AppMcpToolNames.createSpec,
    write: true,
    summary: 'Cria um rascunho no próximo código, com os avisos do lint',
    description:
        'Cria uma spec nova como rascunho, no próximo código livre, e '
        'devolve o código e os avisos de estrutura. Pede a aprovação da '
        'pessoa. Nunca altera uma spec existente.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'texto': _specText,
        'depende_de': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'Códigos de specs existentes, ex.: ["SPEC-043"].',
        },
      },
      'required': ['texto'],
      'additionalProperties': false,
    },
  ),
  McpToolDef(
    name: AppMcpToolNames.createChildren,
    write: true,
    summary: 'Cria até 6 filhas com depende-de, numa aprovação só',
    description:
        'Cria até 6 specs rascunho que dependem de uma spec existente '
        '(depende-de: <pai>), numa aprovação só.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'pai': {'type': 'string', 'description': 'Código da spec pai.'},
        'filhas': {
          'type': 'array',
          'minItems': 1,
          'maxItems': maxChildrenPerCall,
          'items': {
            'type': 'object',
            'properties': {'texto': _specText},
            'required': ['texto'],
            'additionalProperties': false,
          },
        },
      },
      'required': ['pai', 'filhas'],
      'additionalProperties': false,
    },
  ),
  McpToolDef(
    name: AppMcpToolNames.note,
    write: true,
    summary: 'Nota curta no card e no histórico da spec',
    description:
        'Grava uma nota curta de andamento (até 280 caracteres) na spec '
        'desta execução. Não conclui etapa: isso continua com o marcador '
        'ETAPA CONCLUÍDA e o gate.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'nota': {'type': 'string', 'maxLength': maxNoteLength},
      },
      'required': ['nota'],
      'additionalProperties': false,
    },
  ),
];

/// `mcp__promptorium__<tool>`.
String appMcpToolId(String tool) => 'mcp__${appMcpServerName}__$tool';

/// Reads → `--allowedTools` (R3).
List<String> get appMcpReadToolIds => [
  for (final t in appMcpCatalog)
    if (!t.write) appMcpToolId(t.name),
];

/// Writes → `--disallowedTools` of the read-only runs (R8).
List<String> get appMcpWriteToolIds => [
  for (final t in appMcpCatalog)
    if (t.write) appMcpToolId(t.name),
];

/// `criar_spec` / `criar_filhas`: "Sempre permitir" only for the session
/// (R4), never in the project nor in every project.
bool isAppMcpCreateTool(String toolName) =>
    toolName == appMcpToolId(AppMcpToolNames.createSpec) ||
    toolName == appMcpToolId(AppMcpToolNames.createChildren);

/// The `permission_suggestions` of a request as the app sends them back
/// for "Sempre permitir": the CLI suggests `localSettings` (verified on
/// 2.1.325), which [isAppMcpCreateTool] turns into `session`.
List<Map<String, dynamic>> alwaysAllowSuggestions(
  String toolName,
  List<Map<String, dynamic>> suggestions,
) {
  if (!isAppMcpCreateTool(toolName)) return suggestions;
  return [
    for (final s in suggestions) {...s, 'destination': 'session'},
  ];
}

/// Whether [toolName] (`mcp__promptorium__…`) is a write tool of the app.
bool isAppMcpWriteTool(String toolName) =>
    appMcpWriteToolIds.contains(toolName);

/// Column of the Quadro as the tools name it.
String boardColumnValue(SpecStage s) => switch (s) {
  SpecStage.backlog => 'backlog',
  SpecStage.running => 'em-execucao',
  SpecStage.review => 'review',
  SpecStage.done => 'concluida',
};

const _columnLabels = {
  SpecStage.backlog: 'Backlog',
  SpecStage.running: 'Em execução',
  SpecStage.review: 'Review',
  SpecStage.done: 'Concluída',
};

/// Text of a spec written by the agent (R4, R5, R6): its own frontmatter is
/// dropped (no `id`, `status` or path of the agent survives) and the app's
/// goes in: the new [code], `status: rascunho`, `depende-de`, `origem:
/// agente` and the session.
String agentSpecText(
  String text, {
  required String code,
  required List<String> dependsOn,
  required String sessionId,
}) {
  final doc = SpecDocument.parse(text);
  final body = (doc.hasFrontmatter ? doc.body : doc.text).trimLeft();
  return SpecDocument.parse(body).withMeta(
    id: code,
    status: SpecStatus.draft,
    dependsOn: dependsOn.isEmpty ? null : dependsOn,
    fields: {specOriginKey: specOriginAgent, specSessionKey: sessionId},
  );
}

/// A spec the agent asked for, checked before anything is written.
typedef _Draft = ({String title, String text, List<String> dependsOn});

/// The tools of the server ([McpToolbox]): pure reads of the repositories
/// and writes through [SpecService] only (R5).
class AppMcpTools implements McpToolbox {
  AppMcpTools(this._ref, {this.onCreated});

  final Ref _ref;

  /// A write ran: the timeline of the run marks it (R8).
  final void Function(McpGrant grant, String text)? onCreated;

  @override
  List<McpToolDef> get catalog => appMcpCatalog;

  @override
  Future<McpToolOutcome> call(
    McpGrant grant,
    String tool,
    Map<String, Object?> args,
  ) async {
    final ws = await _ref
        .read(workspacesRepoProvider)
        .getById(grant.workspaceId);
    if (ws == null) {
      return const McpToolOutcome.error(
        'O workspace desta execução não existe.',
      );
    }
    return switch (tool) {
      AppMcpToolNames.listSpecs => _listSpecs(ws, args),
      AppMcpToolNames.readSpec => _readSpec(ws, args),
      AppMcpToolNames.board => _board(ws),
      AppMcpToolNames.currentSpec => _currentSpec(ws, grant),
      AppMcpToolNames.createSpec => _createSpec(ws, grant, args),
      AppMcpToolNames.createChildren => _createChildren(ws, grant, args),
      AppMcpToolNames.note => _note(ws, grant, args),
      AppMcpToolNames.registerDebt => _registerDebt(ws, grant, args),
      AppMcpToolNames.listDebts => _listDebts(ws, grant),
      _ => Future.value(
        McpToolOutcome.error('A ferramenta $tool ainda não responde.'),
      ),
    };
  }

  // --- reads (R3) ------------------------------------------------------------

  Future<List<Spec>> _specs(Workspace ws) =>
      _ref.read(specsRepoProvider).watchByWorkspace(ws.id).first;

  Future<McpToolOutcome> _listSpecs(
    Workspace ws,
    Map<String, Object?> args,
  ) async {
    final status = args['status'] as String?;
    final column = args['coluna'] as String?;
    final sprints = {
      for (final s in await _ref.read(sprintsRepoProvider).byWorkspace(ws.id))
        s.id: s.name,
    };
    final list = [
      for (final s in await _specs(ws))
        if ((status == null || specStatusValue(s.status) == status) &&
            (column == null || boardColumnValue(s.stage) == column))
          {
            'codigo': s.code,
            'titulo': s.title,
            'status': specStatusValue(s.status),
            'coluna': boardColumnValue(s.stage),
            if (s.inTray) 'bandeja': true,
            'sprint': ?sprints[s.sprintId],
            'depende_de': s.dependsOn,
            'requisitos': s.requirements.length,
          },
    ];
    final text = list.isEmpty
        ? 'Nenhuma spec com esse filtro.'
        : [
            for (final s in list)
              '${s['codigo']} · ${s['titulo']} · ${s['status']} · '
                  '${s['coluna']}'
                  '${s['sprint'] == null ? '' : ' · ${s['sprint']}'}'
                  '${(s['depende_de'] as List).isEmpty ? '' : ' · depende de ${(s['depende_de'] as List).join(', ')}'}',
          ].join('\n');
    return McpToolOutcome(text, data: {'specs': list});
  }

  Future<List<Map<String, Object?>>> _stepsJson(Spec spec) async {
    final rows = await _ref.read(specStepsRepoProvider).bySpec(spec.id);
    return [
      for (final s in stepsOf(spec, rows))
        {
          'etapa': s.id,
          'texto': s.text,
          'status': s.status.name,
          if (s.gate case final g?)
            'gate': {
              'ok': g.ok,
              'resumo': g.summary,
              'em': g.at.toIso8601String(),
            },
        },
    ];
  }

  static String _gateText(Object? gate) =>
      gate is Map ? ' · último gate: ${gate['resumo']}' : '';

  static String _stepsText(List<Map<String, Object?>> steps) => [
    for (final s in steps)
      '- ${s['etapa']} · ${s['status']}${_gateText(s['gate'])}',
  ].join('\n');

  Future<McpToolOutcome> _readSpec(
    Workspace ws,
    Map<String, Object?> args,
  ) async {
    final code = '${args['codigo'] ?? ''}'.trim().toUpperCase();
    final spec = await _ref.read(specsRepoProvider).getByCode(ws.id, code);
    if (spec == null) {
      return McpToolOutcome.error('$code não existe neste workspace.');
    }
    final text = await _ref.read(specServiceProvider).read(ws, spec) ?? '';
    final steps = await _stepsJson(spec);
    return McpToolOutcome(
      '$text\n\n---\nEtapas de ${spec.code} (${specStatusValue(spec.status)}, '
      '${boardColumnValue(spec.stage)}):\n${_stepsText(steps)}',
      data: {
        'codigo': spec.code,
        'status': specStatusValue(spec.status),
        'coluna': boardColumnValue(spec.stage),
        'etapas': steps,
      },
    );
  }

  Future<McpToolOutcome> _board(Workspace ws) async {
    final specs = await _specs(ws);
    final byId = {for (final s in specs) s.id: s};
    final sessions = await _ref
        .read(sessionsRepoProvider)
        .watchByWorkspace(ws.id)
        .first;
    final live = _ref.read(sessionManagerProvider);
    final steps = await _ref
        .read(specStepsRepoProvider)
        .watchByWorkspace(ws.id)
        .first;
    final columns = {
      for (final stage in SpecStage.values)
        boardColumnValue(stage): [
          for (final s in specs)
            if (s.stage == stage &&
                !s.inTray &&
                s.status != SpecStatus.archived)
              '${s.code} · ${s.title}',
        ],
    };
    final alive = [
      for (final s in sessions)
        if (live.isAlive(s.id))
          {
            'sessao': s.id,
            'titulo': sessionTitle(s),
            'spec': ?byId[s.specId]?.code,
            'etapas': ?s.steps,
            'status': s.status.name,
          },
    ];
    final own = {for (final s in sessions) s.id};
    final waiting = <String>[
      for (final a in live.approvals)
        if (own.contains(a.sessionId))
          'Aprovação pendente em "${a.sessionTitle}": '
              '${a.request.displayName ?? a.request.toolName}',
      for (final st in steps)
        if (st.status == StepStatus.needsInput && byId[st.specId] != null)
          '${byId[st.specId]!.code} ${st.step} aguardando você',
      for (final s in specs)
        if (s.stage == SpecStage.review && s.status != SpecStatus.archived)
          '${s.code} no Review',
      for (final s in sessions)
        if (s.status == SessionStatus.interrupted)
          'Sessão interrompida: ${sessionTitle(s)}',
    ];
    final text = [
      for (final MapEntry(:key, :value) in columns.entries)
        '${_columnLabels[SpecStage.values.firstWhere((s) => boardColumnValue(s) == key)]} (${value.length})'
            '${value.isEmpty ? '' : ':\n${value.map((v) => '- $v').join('\n')}'}',
      'Sessões vivas (${alive.length})'
          '${alive.isEmpty ? '' : ':\n${alive.map((a) => '- ${a['titulo']}${a['spec'] == null ? '' : ' · ${a['spec']} ${a['etapas'] ?? ''}'.trimRight()} · ${a['status']}').join('\n')}'}',
      'Precisa de você (${waiting.length})'
          '${waiting.isEmpty ? '' : ':\n${waiting.map((w) => '- $w').join('\n')}'}',
    ].join('\n\n');
    return McpToolOutcome(
      text,
      data: {
        'colunas': columns,
        'sessoes_vivas': alive,
        'precisa_de_voce': waiting,
      },
    );
  }

  Future<McpToolOutcome> _currentSpec(Workspace ws, McpGrant grant) async {
    final session = grant.conversationId != null
        ? null
        : await _ref.read(sessionsRepoProvider).getById(grant.sessionId);
    final specId = session?.specId;
    final spec = specId == null
        ? null
        : await _ref.read(specsRepoProvider).getById(specId);
    if (spec == null || spec.workspaceId != ws.id) {
      return const McpToolOutcome(
        'Esta execução não trabalha numa spec.',
        data: {'spec': null},
      );
    }
    final current = parseSessionSteps(session!.steps);
    final steps = await _stepsJson(spec);
    return McpToolOutcome(
      '${spec.code} · ${spec.title}\n'
      'Etapas desta execução: ${current.isEmpty ? '—' : current.join(', ')}\n'
      '${_stepsText(steps)}',
      data: {
        'spec': spec.code,
        'titulo': spec.title,
        'etapas_da_execucao': current,
        'etapas': steps,
      },
    );
  }

  // --- writes (R4, R5, R9) ---------------------------------------------------

  static String _limitError(McpGrant g, int asked) =>
      'Limite de ${g.limit} specs por execução '
      '(Configurações › Execução de specs): esta execução já criou '
      '${g.created} e pediu mais $asked. Nada foi gravado.';

  /// Checks one spec of the agent; a String is the error.
  Object _draft(Object? raw, Set<String> known, List<String> extraDeps) {
    final text = '${raw ?? ''}'.trim();
    if (text.isEmpty) return 'O texto da spec está vazio.';
    final doc = SpecDocument.parse(text);
    final body = SpecDocument.parse(
      (doc.hasFrontmatter ? doc.body : doc.text).trimLeft(),
    );
    final title = body.title;
    if (title == null || title.trim().isEmpty) {
      return 'A spec precisa de um título ("# Título") no começo do texto.';
    }
    final deps = <String>[
      for (final d in [...extraDeps, ...doc.dependsOn]) d.trim().toUpperCase(),
    ];
    final unique = {...deps}.toList();
    final unknown = unique.where((d) => !known.contains(d)).toList();
    if (unknown.isNotEmpty) {
      return 'depende-de cita ${unknown.join(', ')}, que não existe neste '
          'workspace. Nada foi gravado.';
    }
    final _Draft draft = (title: title.trim(), text: text, dependsOn: unique);
    return draft;
  }

  Future<({Spec spec, String text})> _write(
    Workspace ws,
    McpGrant grant,
    _Draft d,
  ) async {
    final service = _ref.read(specServiceProvider);
    late String written;
    final spec = await service.create(
      ws,
      title: d.title,
      agentSession: grant.sessionId,
      render: (code) => written = agentSpecText(
        d.text,
        code: code,
        dependsOn: d.dependsOn,
        sessionId: grant.sessionId,
      ),
    );
    return (spec: spec, text: written);
  }

  String _created(Spec spec, String text, Set<String> known) {
    final warnings = lintSpec(text, knownCodes: {...known, spec.code});
    return '${spec.code} criada como rascunho em ${spec.path}.'
        '${warnings.isEmpty ? '' : ' Avisos do lint: ${warnings.map((w) => 'L${w.line}: ${w.message}').join('; ')}.'}';
  }

  Map<String, Object?> _createdJson(
    Spec spec,
    String text,
    Set<String> known,
  ) => {
    'codigo': spec.code,
    'arquivo': spec.path,
    'avisos': [
      for (final w in lintSpec(text, knownCodes: {...known, spec.code}))
        'L${w.line}: ${w.message}',
    ],
  };

  String _how(McpGrant g) =>
      g.skipApproval ? 'sem aprovação ("sem perguntar")' : 'aprovada por você';

  Future<McpToolOutcome> _createSpec(
    Workspace ws,
    McpGrant grant,
    Map<String, Object?> args,
  ) async {
    if (grant.created + 1 > grant.limit) {
      return McpToolOutcome.error(_limitError(grant, 1));
    }
    final known = {for (final s in await _specs(ws)) s.code};
    final deps = [
      for (final d in args['depende_de'] as List? ?? const []) '$d',
    ];
    final d = _draft(args['texto'], known, deps);
    if (d is String) return McpToolOutcome.error(d);
    final out = await _write(ws, grant, d as _Draft);
    onCreated?.call(
      grant,
      'Criada pelo agente: ${out.spec.code} · ${out.spec.title} (${_how(grant)})',
    );
    return McpToolOutcome(
      _created(out.spec, out.text, known),
      data: _createdJson(out.spec, out.text, known),
      created: 1,
    );
  }

  Future<McpToolOutcome> _createChildren(
    Workspace ws,
    McpGrant grant,
    Map<String, Object?> args,
  ) async {
    final parent = '${args['pai'] ?? ''}'.trim().toUpperCase();
    final specs = await _specs(ws);
    final known = {for (final s in specs) s.code};
    if (!known.contains(parent)) {
      return McpToolOutcome.error('$parent não existe neste workspace.');
    }
    final raw = args['filhas'] as List? ?? const [];
    if (raw.isEmpty) {
      return const McpToolOutcome.error('Informe ao menos uma filha.');
    }
    if (raw.length > maxChildrenPerCall) {
      return McpToolOutcome.error(
        'No máximo $maxChildrenPerCall filhas por chamada; vieram '
        '${raw.length}. Nada foi gravado.',
      );
    }
    if (grant.created + raw.length > grant.limit) {
      return McpToolOutcome.error(_limitError(grant, raw.length));
    }
    final drafts = <_Draft>[];
    for (final (i, f) in raw.indexed) {
      final d = _draft(f is Map ? f['texto'] : f, known, [parent]);
      if (d is String) {
        return McpToolOutcome.error('Filha ${i + 1}: $d');
      }
      drafts.add(d as _Draft);
    }
    final made = <({Spec spec, String text})>[];
    try {
      for (final d in drafts) {
        made.add(await _write(ws, grant, d));
      }
    } catch (e) {
      if (made.isEmpty) rethrow;
      return McpToolOutcome(
        'Criadas ${made.map((m) => m.spec.code).join(', ')}; a seguinte '
        'falhou: $e',
        error: true,
        created: made.length,
      );
    } finally {
      if (made.isNotEmpty) {
        onCreated?.call(
          grant,
          'Criadas pelo agente: ${made.map((m) => m.spec.code).join(', ')}, '
          'filhas da $parent (${_how(grant)})',
        );
      }
    }
    return McpToolOutcome(
      [for (final m in made) _created(m.spec, m.text, known)].join('\n'),
      data: {
        'pai': parent,
        'filhas': [for (final m in made) _createdJson(m.spec, m.text, known)],
      },
      created: made.length,
    );
  }

  // --- progress note (R7) ----------------------------------------------------

  /// `anotar_andamento`: a short note on the spec of the run. It goes to
  /// `spec_notes` only: no step, status or file changes.
  Future<McpToolOutcome> _note(
    Workspace ws,
    McpGrant grant,
    Map<String, Object?> args,
  ) async {
    final text = '${args['nota'] ?? ''}'.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return const McpToolOutcome.error('A nota está vazia.');
    if (text.length > maxNoteLength) {
      return McpToolOutcome.error(
        'A nota tem ${text.length} caracteres; o limite é $maxNoteLength. '
        'Nada foi gravado.',
      );
    }
    final session = grant.conversationId != null
        ? null
        : await _ref.read(sessionsRepoProvider).getById(grant.sessionId);
    final spec = session?.specId == null
        ? null
        : await _ref.read(specsRepoProvider).getById(session!.specId!);
    if (spec == null || spec.workspaceId != ws.id) {
      return const McpToolOutcome.error(
        'Esta execução não trabalha numa spec: anotar_andamento só vale numa '
        'sessão de etapa do Quadro.',
      );
    }
    final note = await _ref
        .read(specNotesRepoProvider)
        .add(
          specId: spec.id,
          note: text,
          sessionId: grant.sessionId,
          steps: session!.steps,
        );
    // SPEC-074 R10: with the opt-in, the comment on the issue follows.
    final issue = spec.issueNumber;
    final published = await _ref
        .read(issueProgressPublisherProvider)
        .afterNote(spec.id);
    final where = switch (published) {
      null => '',
      (published: true, reason: _) => ' e publicada na issue #$issue',
      (published: false, :final reason) =>
        '; a issue #$issue não foi atualizada ($reason): a próxima nota '
            'tenta de novo',
    };
    return McpToolOutcome(
      'Nota gravada em ${spec.code}'
      '${session.steps == null ? '' : ' (${session.steps})'}$where. Ela '
      'aparece no card do Quadro e não conclui a etapa: isso continua com o '
      'marcador ETAPA CONCLUÍDA e o gate.',
      data: {
        'spec': spec.code,
        'nota': note.id,
        if (published != null) 'issue': issue,
        if (published != null) 'publicada': published.published,
      },
    );
  }

  // --- debts and decisions (SPEC-112 R11) ------------------------------------

  /// The session row of the run (null in a conversation of the Prompt).
  Future<Session?> _session(McpGrant grant) async =>
      grant.conversationId != null
      ? null
      : await _ref.read(sessionsRepoProvider).getById(grant.sessionId);

  /// The spec the session of the run works on, in [ws].
  Future<Spec?> _specOf(Workspace ws, Session? session) async {
    final id = session?.specId;
    if (id == null) return null;
    final spec = await _ref.read(specsRepoProvider).getById(id);
    return spec == null || spec.workspaceId != ws.id ? null : spec;
  }

  /// `claude` / `codex`: the provider of the session or conversation.
  Future<String> _provider(McpGrant grant, Session? session) async {
    if (session != null) return session.provider;
    final id = grant.conversationId;
    if (id == null) return 'claude';
    final c = await _ref.read(conversationsRepoProvider).getById(id);
    return c?.provider ?? 'claude';
  }

  /// `registrar_debito`: a pending suggestion only (R11). Nothing goes to
  /// the file: the app writes it when the person accepts.
  Future<McpToolOutcome> _registerDebt(
    Workspace ws,
    McpGrant grant,
    Map<String, Object?> args,
  ) async {
    final type = '${args['tipo'] ?? ''}'.trim();
    if (type != DebtKind.debt.dbName && type != DebtKind.decision.dbName) {
      return const McpToolOutcome.error(
        'tipo deve ser "debito" ou "decisao". Nada foi registrado.',
      );
    }
    final draft = DebtDraft.fromJson(args);
    if (draft.title.isEmpty) {
      return const McpToolOutcome.error(
        'O título está vazio. Nada foi registrado.',
      );
    }
    final session = await _session(grant);
    final spec = await _specOf(ws, session);
    final provider = await _provider(grant, session);
    final id = await _ref
        .read(debtServiceProvider)
        .suggest(
          ws.path,
          draft,
          source: DebtSuggestionSource.mcp,
          extra: {
            DebtSuggestionKeys.provider: provider,
            if (session != null)
              DebtSuggestionKeys.sessionTitle: sessionTitle(session),
          },
          link: DebtLinksCompanion(
            originSessionId: Value(session?.id),
            originSpecId: Value(spec?.id),
          ),
        );
    final what = draft.kind == DebtKind.debt ? 'débito' : 'decisão pendente';
    return McpToolOutcome(
      'Sugestão de $what registrada: "${draft.title}". Ela espera a pessoa '
      'aceitar na tela Débitos e decisões; só então o app grava a linha e dá '
      'o código (${draft.kind.prefix}-nn). Não escreva no arquivo à mão.',
      data: {
        'sugestao': id,
        'tipo': draft.kind.dbName,
        'estado': DebtSuggestionState.pending,
      },
    );
  }

  /// `listar_debitos`: open debts and pending decisions of the main branch
  /// and, when the run works on a spec with a worktree, of that worktree
  /// too ("na spec").
  Future<McpToolOutcome> _listDebts(Workspace ws, McpGrant grant) async {
    final main = await DebtSnapshot.load(ws.path);
    final spec = await _specOf(ws, await _session(grant));
    final wt = spec?.worktreePath;
    final DebtSnapshot? side =
        wt != null && wt != ws.path && Directory(wt).existsSync()
        ? await DebtSnapshot.load(wt)
        : null;
    final inSpec = spec == null ? null : specLabel(spec);
    final debts = <Map<String, Object?>>[
      for (final d in main.openDebts)
        {'id': d.code, 'titulo': d.title, 'onde': d.where},
      if (side != null)
        for (final d in side.openDebts)
          if (!main.debts.debts.any((m) => m.code == d.code))
            {
              'id': d.code,
              'titulo': d.title,
              'onde': d.where,
              'na_spec': inSpec,
            },
    ];
    final decisions = <Map<String, Object?>>[
      for (final d in main.pendingDecisions)
        {'id': d.code, 'titulo': d.title, 'origem': d.origin},
      if (side != null)
        for (final d in side.pendingDecisions)
          if (!main.decisions.decisions.any((m) => m.code == d.code))
            {
              'id': d.code,
              'titulo': d.title,
              'origem': d.origin,
              'na_spec': inSpec,
            },
    ];
    final pending = [
      for (final l in await _ref.read(debtLinksRepoProvider).forRepo(ws.path))
        if (l.suggestionState == DebtSuggestionState.pending)
          '${DebtLinksRepo.suggestionOf(l)['titulo'] ?? ''}',
    ];
    String line(Map<String, Object?> m, String key) =>
        '- ${m['id']} · ${m['titulo']}'
        '${'${m[key] ?? ''}'.isEmpty ? '' : ' · ${m[key]}'}'
        '${m['na_spec'] == null ? '' : ' (na ${m['na_spec']})'}';
    final text = [
      'Débitos abertos (${debts.length})'
          '${debts.isEmpty ? '' : ':\n${debts.map((d) => line(d, 'onde')).join('\n')}'}',
      'Decisões pendentes (${decisions.length})'
          '${decisions.isEmpty ? '' : ':\n${decisions.map((d) => line(d, 'origem')).join('\n')}'}',
      if (pending.isNotEmpty)
        'Sugestões esperando a pessoa aceitar (${pending.length}):\n'
            '${pending.map((p) => '- $p').join('\n')}',
    ].join('\n\n');
    return McpToolOutcome(
      text,
      data: {
        'debitos': debts,
        'decisoes': decisions,
        'sugestoes_pendentes': pending,
      },
    );
  }
}
