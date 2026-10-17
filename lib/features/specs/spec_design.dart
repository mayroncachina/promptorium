import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_args.dart';
import '../../core/claude/readonly_run.dart';
import '../../core/providers/claude_code_provider.dart';
import '../../data/providers.dart';
import '../project/project_memory.dart';
import 'spec_file.dart';

/// Instructions of "Gerar design" (read-only run in the repository).
const designPrompt = '''
Você é o planner do Promptorium. Leia a spec abaixo e o repositório (somente
leitura) e escreva a seção Design: como implementar cada requisito neste código —
componentes e arquivos que mudam ou nascem, decisões e alternativas descartadas,
riscos. Cite os requisitos (R1, R2…) em cada parte. Organize em subseções
"### R1 · …" quando houver mais de um requisito. Seja concreto e curto.

Em "etapas", para cada requisito liste os arquivos que a etapa toca e, quando
houver, um comando que verifica a etapa (ex.: um teste específico); deixe vazio
quando não houver.''';

final designSchema = {
  'type': 'object',
  'additionalProperties': false,
  'required': ['design', 'etapas'],
  'properties': {
    'design': {'type': 'string'},
    'etapas': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['requisito', 'arquivos', 'verificar'],
        'properties': {
          'requisito': {'type': 'string'},
          'arquivos': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'verificar': {'type': 'string'},
        },
      },
    },
  },
};

/// Text of the spec with the generated `## Design` / `## Etapas` (F7).
String applyDesignAnswer(String specText, Object? data) {
  if (data is! Map || '${data['design'] ?? ''}'.trim().isEmpty) {
    throw const PlannerException('O planner não devolveu um design.');
  }
  final plans = <String, StepPlan>{
    for (final e in (data['etapas'] as List? ?? const []))
      if (e is Map &&
          RegExp(r'^(REV|R)\d+$').hasMatch('${e['requisito'] ?? ''}'.trim()))
        '${e['requisito']}'.trim(): StepPlan(
          files: [
            for (final f in (e['arquivos'] as List? ?? const []))
              if ('$f'.trim().isNotEmpty) '$f'.trim(),
          ],
          verify: '${e['verificar'] ?? ''}'.trim().isEmpty
              ? null
              : '${e['verificar']}'.trim(),
        ),
  };
  return SpecDocument.parse(specText)
      .withDesign('${data['design']}'.trim(), plans: plans);
}

/// "Gerar design" of the Specs screen.
class SpecDesigner {
  SpecDesigner(this._ref);

  final Ref _ref;

  static const budgetUsd = 1.0;

  /// Returns [specText] with the generated design (not saved: the user
  /// reviews it in the editor).
  Future<String> generate(Workspace ws, String specText) async {
    final r = await runReadOnlyClaude(
      _ref,
      cwd: ws.path,
      options: ClaudeOptions(
        permissionMode: ClaudePermissionMode.defaultMode,
        disallowedTools: ClaudeCodeProvider.readOnlyDisallowedTools,
        appendSystemPrompt: designPrompt,
        jsonSchema: jsonEncode(designSchema),
        maxBudgetUsd: budgetUsd,
        includePartialMessages: false,
      ),
      prompt: [
        if (ProjectMemory.loadSync(ws.path) case final m when !m.isEmpty)
          'Memória do projeto:\n${m.toPrompt()}\n',
        'Spec:\n<spec>\n${specText.trimRight()}\n</spec>',
      ].join('\n'),
    );
    return applyDesignAnswer(specText, structuredOutput(r));
  }
}

final specDesignerProvider = Provider(SpecDesigner.new);
