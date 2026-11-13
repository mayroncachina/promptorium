import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_args.dart';
import '../../core/claude/readonly_run.dart';
import '../../core/providers/agent_registry.dart' show ClaudeCodeProvider;
import '../../data/db/app_database.dart';
import 'prompt_actions.dart';

/// "Dividir em specs" (SPEC-068 R2): an auxiliary run in Perguntar mode,
/// with no write tool, that splits a conversation into specs in the format
/// of `/spec`, with provisional codes and `depende-de` among them. Nothing
/// is created here: the answer goes to the review list.

/// Index of the answer of the specs created by "Dividir em specs" (their
/// origin, R6): not an answer of the conversation. A second split of the
/// same conversation recognizes them by provisional code and title.
const splitAnswerIndex = -1;

/// The prompt of the run: the conversation, then the instructions.
String splitSpecsPrompt(
  List<TranscriptEntry> transcript, {
  Iterable<String> existing = const [],
}) {
  final b = StringBuffer()
    ..writeln(
      'Divida a conversa abaixo em specs independentes, uma por entrega '
      'que faça sentido executar sozinha, em português. Não crie nem edite '
      'arquivos: só responda com as specs.',
    )
    ..writeln()
    ..writeln(
      'Cada spec vai num bloco cercado ```markdown e começa pelo '
      'cabeçalho, exatamente neste formato:',
    )
    ..writeln('---')
    ..writeln('id: SPEC-A')
    ..writeln('status: rascunho')
    ..writeln('depende-de: [SPEC-A]')
    ..writeln('---')
    ..writeln(
      'Use códigos provisórios em ordem: SPEC-A, SPEC-B, SPEC-C… O app '
      'troca pelos números reais ao criar. A linha depende-de só entra se '
      'a spec depender de outra (provisória ou já existente no projeto), e '
      'a chave é sempre depende-de, com os códigos entre colchetes. Ponha '
      'primeiro as specs de que as outras dependem e não crie ciclos.',
    )
    ..writeln()
    ..writeln('Depois do cabeçalho, em cada spec:')
    ..writeln('# Título curto')
    ..writeln('## Objetivo')
    ..writeln('## Requisitos (R1, R2…; cada item verificável)')
    ..writeln('## Fora do escopo')
    ..writeln('## Critérios de aceite')
    ..writeln(
      'Seja conciso e não invente detalhes técnicos que a conversa não '
      'deu. Se a conversa só justificar uma spec, devolva uma só.',
    );
  if (existing.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Specs que já existem no projeto: ${existing.join(', ')}.');
  }
  b
    ..writeln()
    ..writeln('--- Conversa ---');
  for (final e in transcript) {
    b
      ..writeln()
      ..writeln(e.user ? '**Pessoa:**' : '**Claude:**')
      ..writeln(e.text.trim());
  }
  return b.toString();
}

/// Runs the split and returns the answer text. [cancelled] stops the run
/// ("Cancelar").
typedef SplitSpecsRunner = Future<String> Function(
  Workspace ws,
  String prompt, {
  Future<void>? cancelled,
});

final splitSpecsRunnerProvider = Provider<SplitSpecsRunner>(
  (ref) => (ws, prompt, {cancelled}) async {
    final r = await runReadOnlyClaude(
      ref,
      workspaceId: ws.id,
      cwd: ws.path,
      options: const ClaudeOptions(
        permissionMode: ClaudePermissionMode.defaultMode,
        disallowedTools: ClaudeCodeProvider.readOnlyDisallowedTools,
        includePartialMessages: false,
      ),
      prompt: prompt,
      cancelled: cancelled,
      denyMessage: '"Dividir em specs" é somente leitura.',
    );
    if (!r.isSuccess) {
      throw PlannerException(
        'O Claude terminou com erro '
        '(${r.subtype.isEmpty ? 'erro' : r.subtype}).',
      );
    }
    return r.result ?? '';
  },
);
