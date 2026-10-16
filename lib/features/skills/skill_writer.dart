import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_args.dart';
import '../../core/claude/claude_event.dart';
import '../../core/providers/claude_code_provider.dart';
import '../../data/providers.dart';
import '../agents/agent_file.dart';
import '../sessions/timeline.dart' show AppEventTypes;
import '../specs/task_planner.dart'
    show PlannerException, runReadOnlyClaude, structuredOutput;
import 'skill_repository.dart';

/// "Nova skill" with the Claude: a short, read-only `claude -p` with
/// `--json-schema` that writes the SKILL.md from a description or from the
/// transcript of a session.

const skillDraftSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': ['name', 'description', 'allowedTools', 'body'],
  'properties': {
    'name': {'type': 'string'},
    'description': {'type': 'string'},
    'allowedTools': {'type': 'string'},
    'body': {'type': 'string'},
  },
};

const skillWriterSystemPrompt =
    'Você escreve skills do Claude Code (arquivo SKILL.md). Escreva em '
    'português do Brasil. Responda somente com a saída estruturada: name '
    '(minúsculas, números e hífens, até 40 caracteres); description (até 2 '
    'frases: o que a skill faz e QUANDO usar — é por ela que o Claude decide '
    'carregar a skill); allowedTools (ferramentas que a skill precisa sem '
    'pedir permissão, separadas por vírgula, ex.: "Read, Grep, Bash(git '
    'diff *)"; vazio se nenhuma); body (Markdown com as instruções: título, '
    'quando usar e um passo a passo objetivo e verificável; sem '
    'frontmatter). Não altere arquivos.';

/// Messages of a session as plain text (user / assistant), newest last,
/// cut to [maxChars] from the end.
String sessionTranscript(List<String> eventJsonLines, {int maxChars = 12000}) {
  final b = StringBuffer();
  for (final line in eventJsonLines) {
    Object? j;
    try {
      j = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (j is! Map<String, dynamic>) continue;
    if (j['type'] == AppEventTypes.user) {
      b
        ..writeln('## Usuário')
        ..writeln('${j['text'] ?? ''}')
        ..writeln();
      continue;
    }
    final ClaudeEvent e;
    try {
      e = ClaudeEvent.fromJson(j);
    } catch (_) {
      continue;
    }
    if (e is AssistantMessage && e.parentToolUseId == null) {
      final parts = <String>[
        for (final c in e.blocks)
          if (c is TextBlock && c.text.trim().isNotEmpty)
            c.text.trim()
          else if (c is ToolUseBlock)
            '[ferramenta ${c.name}]',
      ];
      if (parts.isEmpty) continue;
      b
        ..writeln('## Claude')
        ..writeln(parts.join('\n'))
        ..writeln();
    }
  }
  final s = b.toString().trim();
  return s.length <= maxChars ? s : '…${s.substring(s.length - maxChars)}';
}

/// User message of a writer run.
String skillWriterPrompt({String? request, String? transcript, String? name}) {
  final b = StringBuffer();
  if (transcript != null) {
    b
      ..writeln(
        'Transforme o que funcionou nesta sessão numa skill reutilizável '
        '(o passo a passo, não os detalhes do caso).',
      )
      ..writeln();
    if (request != null && request.trim().isNotEmpty) {
      b
        ..writeln('Foco pedido: ${request.trim()}')
        ..writeln();
    }
    b
      ..writeln('<sessao>')
      ..writeln(transcript)
      ..writeln('</sessao>');
  } else {
    b
      ..writeln('Escreva uma skill para isto:')
      ..writeln(request?.trim() ?? '');
  }
  if (name != null && name.trim().isNotEmpty) {
    b
      ..writeln()
      ..writeln('Use o name "${name.trim()}".');
  }
  return b.toString().trimRight();
}

/// `my skill!` → `my-skill`.
String skillSlug(String s) {
  final out = s
      .toLowerCase()
      .replaceAll(RegExp('[áàâã]'), 'a')
      .replaceAll(RegExp('[éê]'), 'e')
      .replaceAll('í', 'i')
      .replaceAll(RegExp('[óôõ]'), 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp('^-+|-+\$'), '');
  return out.length > 40
      ? out.substring(0, 40).replaceAll(RegExp(r'-+$'), '')
      : out;
}

/// SKILL.md of a writer `result`.
AgentFile parseSkillDraft(Result r, {String? name}) {
  final data = structuredOutput(r);
  if (data is! Map) {
    throw const PlannerException(
      'O Claude não devolveu a skill (structured_output).',
    );
  }
  final n = skillSlug(
    (name != null && name.trim().isNotEmpty) ? name : '${data['name'] ?? ''}',
  );
  final description = '${data['description'] ?? ''}'.trim();
  final body = '${data['body'] ?? ''}'.trim();
  if (n.isEmpty || description.isEmpty || body.isEmpty) {
    throw const PlannerException('O Claude devolveu uma skill incompleta.');
  }
  final tools = '${data['allowedTools'] ?? ''}'.trim();
  return AgentFile.create(
    name: n,
    description: description,
    body: '$body\n',
  ).withValue('allowed-tools', tools.isEmpty ? null : tools);
}

/// Writes a draft with the Claude and saves it in [scope]. Returns the
/// folder. A taken name gets `-2`, `-3`…
class SkillWriter {
  SkillWriter(this._ref);

  final Ref _ref;

  Future<String> write({
    required Workspace? workspace,
    required AgentScope scope,
    String? request,
    String? sessionId,
    String? name,
  }) async {
    String? transcript;
    if (sessionId != null) {
      final rows = await _ref.read(sessionsRepoProvider).events(sessionId);
      transcript = sessionTranscript([for (final r in rows) r.json]);
      if (transcript.isEmpty) {
        throw const PlannerException('A sessão não tem mensagens.');
      }
    } else if (request == null || request.trim().isEmpty) {
      throw const PlannerException('Descreva o que a skill deve fazer.');
    }
    final r = await runReadOnlyClaude(
      _ref,
      cwd:
          workspace?.path ??
          _ref.read(skillRepositoryProvider(null)).home ??
          '/',
      options: ClaudeOptions(
        permissionMode: ClaudePermissionMode.defaultMode,
        disallowedTools: ClaudeCodeProvider.readOnlyDisallowedTools,
        appendSystemPrompt: skillWriterSystemPrompt,
        jsonSchema: jsonEncode(skillDraftSchema),
        maxBudgetUsd: 0.5,
        includePartialMessages: false,
      ),
      prompt: skillWriterPrompt(
        request: request,
        transcript: transcript,
        name: name,
      ),
    );
    var file = parseSkillDraft(r, name: name);
    final repo = _ref.read(skillRepositoryProvider(workspace?.path));
    final base = file.name!;
    var n = 1;
    while (await _exists(repo, file.name!, scope)) {
      n++;
      file = file.withValue('name', '$base-$n');
    }
    return repo.save(file, scope);
  }

  Future<bool> _exists(SkillRepository repo, String name, AgentScope s) async {
    try {
      return await Directory(repo.folderFor(name, s)).exists();
    } on SkillException {
      return false;
    }
  }
}

final skillWriterProvider = Provider(SkillWriter.new);
