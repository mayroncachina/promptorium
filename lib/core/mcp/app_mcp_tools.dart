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

/// Whether [toolName] (`mcp__promptorium__…`) is a write tool of the app.
bool isAppMcpWriteTool(String toolName) =>
    appMcpWriteToolIds.contains(toolName);

/// The tools of the server ([McpToolbox]).
class AppMcpTools implements McpToolbox {
  AppMcpTools();

  @override
  List<McpToolDef> get catalog => appMcpCatalog;

  @override
  Future<McpToolOutcome> call(
    McpGrant grant,
    String tool,
    Map<String, Object?> args,
  ) async => McpToolOutcome.error('A ferramenta $tool ainda não responde.');
}
