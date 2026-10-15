import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_service.dart';
import '../../data/providers.dart';
import '../../data/repos/saved_prompts_repo.dart';
import '../../data/repos/specs_repo.dart';
import '../../data/repos/tasks_repo.dart';
import '../sessions/session_manager.dart' show slugify;
import '../sessions/timeline.dart';
import '../specs/spec_service.dart' show nextSpecCode;
import 'conversation_manager.dart' show conversationTitle;

// --- transcript ----------------------------------------------------------------

/// One user message or Claude answer (top level only; tools are skipped).
typedef TranscriptEntry = ({bool user, String text});

List<TranscriptEntry> transcriptOf(List<TimelineItem> items) => [
  for (final i in items)
    if (i is UserItem)
      (user: true, text: i.text)
    else if (i is AssistantTextItem && i.parentToolUseId == null)
      (user: false, text: i.text),
];

/// Last top-level answer of Claude (null while there is none).
String? lastAnswer(List<TimelineItem> items) {
  for (final i in items.reversed) {
    if (i is AssistantTextItem && i.parentToolUseId == null) {
      return i.text.trim().isEmpty ? null : i.text;
    }
  }
  return null;
}

/// Last message typed by the user.
String? lastUserMessage(List<TimelineItem> items) {
  for (final i in items.reversed) {
    if (i is UserItem) return i.text;
  }
  return null;
}

/// `@path` mentions in [texts] (in order, without duplicates).
List<String> mentionedFiles(Iterable<String> texts) {
  final out = <String>[];
  final re = RegExp(r'(?:^|\s)@([^\s@]+)');
  for (final t in texts) {
    for (final m in re.allMatches(t)) {
      final p = m.group(1)!.replaceAll(RegExp(r'[,.;:)]+$'), '');
      if (p.isNotEmpty && !out.contains(p)) out.add(p);
    }
  }
  return out;
}

// --- composer triggers -----------------------------------------------------------

/// `@` / `/` being typed at the cursor: the token start and the query typed
/// after the trigger character.
typedef ComposerTrigger = ({String char, int start, String query});

/// Detects `@query` (file) or `/query` (saved prompt) right before [cursor].
/// The trigger must start a word; `/` only counts at the start of a line
/// (so paths like `lib/a` do not open the prompt list).
ComposerTrigger? triggerAt(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  var i = cursor;
  while (i > 0 && !_isSpace(text[i - 1])) {
    i--;
  }
  if (i >= cursor) return null;
  final ch = text[i];
  final query = text.substring(i + 1, cursor);
  if (ch == '@' && !query.contains('@')) {
    return (char: '@', start: i, query: query);
  }
  if (ch == '/' &&
      (i == 0 || text[i - 1] == '\n') &&
      RegExp(r'^[\w-]*$').hasMatch(query)) {
    return (char: '/', start: i, query: query);
  }
  return null;
}

bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t';

/// Files matching [query] (case-insensitive; file-name matches first).
List<String> filterFiles(List<String> files, String query, {int limit = 40}) {
  final q = query.toLowerCase();
  if (q.isEmpty) return files.take(limit).toList();
  final byName = <String>[], byPath = <String>[];
  for (final f in files) {
    final lower = f.toLowerCase();
    final name = lower.split('/').last;
    if (name.contains(q)) {
      byName.add(f);
    } else if (lower.contains(q)) {
      byPath.add(f);
    }
    if (byName.length >= limit) break;
  }
  return [...byName, ...byPath].take(limit).toList();
}

/// Files of the workspace for the `@` picker: `git ls-files` (tracked +
/// untracked not ignored).
final workspaceFilesProvider = FutureProvider.family<List<String>, String>((
  ref,
  root,
) async {
  final out = await ref.read(gitServiceFactoryProvider)(root).git([
    'ls-files',
    '--cached',
    '--others',
    '--exclude-standard',
  ]);
  final files = out
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toSet()
      .toList();
  return files..sort();
});

// --- tasks / specs -----------------------------------------------------------------

/// Title for a task created from an answer (first meaningful line).
String taskTitleFrom(String answer) => conversationTitle(answer, max: 70);

/// "Criar tarefa a partir daqui": `tasks` row (backlog) with the answer as
/// body.
Future<Task> createTaskFromAnswer(
  TasksRepo repo, {
  required int workspaceId,
  required String answer,
  String? title,
}) async {
  final code = await repo.nextCode(workspaceId);
  return repo.insert(
    workspaceId: workspaceId,
    code: code,
    title: (title?.trim().isNotEmpty ?? false)
        ? title!.trim()
        : taskTitleFrom(answer),
    body: answer,
  );
}

String _clip(String s, int max) {
  final t = s.trim();
  return t.length <= max ? t : '${t.substring(0, max).trimRight()} …';
}

/// Markdown of a spec draft made from a conversation ("conversa resumida":
/// each message clipped; tool calls left out).
String specMarkdown({
  required String code,
  required String title,
  required List<TranscriptEntry> transcript,
  DateTime? now,
}) {
  final day = (now ?? DateTime.now()).toIso8601String().substring(0, 10);
  final b = StringBuffer()
    ..writeln('---')
    ..writeln('id: $code')
    ..writeln('status: rascunho')
    ..writeln('---')
    ..writeln()
    ..writeln('# $title')
    ..writeln()
    ..writeln('> Rascunho gerado a partir de uma conversa do Prompt em $day.')
    ..writeln()
    ..writeln('## Objetivo')
    ..writeln()
    ..writeln(
      _clip(
        transcript
            .firstWhere((e) => e.user, orElse: () => (user: true, text: title))
            .text,
        600,
      ),
    )
    ..writeln()
    ..writeln('## Conversa (resumo)')
    ..writeln();
  for (final e in transcript) {
    final text = _clip(e.text, e.user ? 600 : 1500);
    b
      ..writeln(e.user ? '**Pergunta:**' : '**Resposta:**')
      ..writeln()
      ..writeln(text)
      ..writeln();
  }
  b
    ..writeln('## Requisitos')
    ..writeln()
    ..writeln('- [ ] A definir')
    ..writeln()
    ..writeln('## Critérios de aceite')
    ..writeln()
    ..writeln('- [ ] A definir');
  return b.toString();
}

/// "Transformar em spec": writes `specs/SPEC-NNN-<slug>.md` in the workspace
/// and registers it in `specs` (status draft). NNN = 1 + the highest number
/// found in the table or in `specs/`.
Future<Spec> createSpecFromConversation(
  SpecsRepo repo, {
  required Workspace workspace,
  required String title,
  required List<TranscriptEntry> transcript,
  DateTime? now,
}) async {
  final dir = Directory('${workspace.path}/specs');
  final code = await nextSpecCode(repo, workspace);
  final slug = slugify(title, maxLength: 40);
  final rel = 'specs/$code${slug.isEmpty ? '' : '-$slug'}.md';
  final file = File('${workspace.path}/$rel');
  await dir.create(recursive: true);
  // Exclusive create: a second click racing on the same number fails here
  // instead of overwriting the first draft.
  try {
    await file.create(exclusive: true);
  } on FileSystemException {
    throw FileSystemException('O arquivo já existe', file.path);
  }
  await file.writeAsString(
    specMarkdown(code: code, title: title, transcript: transcript, now: now),
  );
  return repo.insert(
    workspaceId: workspace.id,
    code: code,
    title: title,
    path: rel,
  );
}

// --- saved prompts -----------------------------------------------------------------

typedef SavedPromptSeed = ({String command, String description, String body});

/// Inserted on the first run (plano, Fase 6 item 6).
const defaultSavedPrompts = <SavedPromptSeed>[
  (
    command: 'explicar',
    description: 'Explica um arquivo ou trecho em linguagem simples',
    body:
        'Explique o código anexado em linguagem simples, em português:\n'
        '1. O que ele faz, em uma frase.\n'
        '2. Como funciona, passo a passo, citando as funções e linhas '
        'mais importantes.\n'
        '3. Dependências, efeitos colaterais e pontos que podem confundir '
        'quem lê pela primeira vez.\n'
        'Não altere nenhum arquivo.\n\n'
        'Arquivo ou trecho: ',
  ),
  (
    command: 'testes',
    description: 'Gera testes para o arquivo anexado',
    body:
        'Escreva testes automatizados para o arquivo anexado usando o '
        'framework de testes que o projeto já usa (siga os testes existentes '
        'como modelo).\n'
        '- Cubra o caminho feliz, casos de borda e os erros esperados.\n'
        '- Use nomes de teste que descrevam o comportamento.\n'
        '- Não use rede nem serviços externos: injete dependências ou use '
        'fakes.\n'
        '- No fim, liste o que ficou sem cobertura e por quê.\n\n'
        'Arquivo: ',
  ),
  (
    command: 'revisar-seguranca',
    description: 'Procura problemas de segurança no diff',
    body:
        'Revise as alterações ainda não commitadas deste repositório '
        '(git diff HEAD; se não puder executar git, peça que eu cole o diff) '
        'procurando problemas de segurança:\n'
        '- injeção de comandos, SQL ou caminhos; validação de entrada;\n'
        '- segredos ou tokens no código, em logs ou no banco;\n'
        '- execução de processos externos e permissões de arquivos;\n'
        '- dados sensíveis expostos na interface.\n'
        'Para cada achado informe arquivo:linha, gravidade (alta, média ou '
        'baixa), o risco e a correção sugerida. Se não houver problemas, '
        'diga isso claramente.',
  ),
  (
    command: 'spec',
    description: 'Transforma uma ideia solta em spec',
    body:
        'Transforme a ideia abaixo numa spec em Markdown, em português, com '
        'as seções:\n'
        '## Objetivo\n## Contexto\n'
        '## Requisitos (lista numerada; cada item verificável)\n'
        '## Fora do escopo\n## Critérios de aceite\n## Perguntas em aberto\n'
        'Seja conciso e não invente detalhes técnicos que não foram dados — '
        'coloque-os em "Perguntas em aberto".\n\n'
        'Ideia: ',
  ),
  (
    command: 'commit',
    description: 'Escreve a mensagem de commit do diff atual',
    body:
        'Escreva a mensagem de commit para as alterações atuais do '
        'repositório no padrão Conventional Commits, em português:\n'
        '- primeira linha "tipo(escopo): resumo" com até 72 caracteres;\n'
        '- uma linha em branco;\n'
        '- corpo curto explicando o porquê, em tópicos se houver mais de uma '
        'mudança.\n'
        'Responda só com a mensagem, dentro de um bloco de código. Não faça o '
        'commit.',
  ),
];

/// Inserts [defaultSavedPrompts] once (flag `prompts.seeded` in
/// `app_settings`). Existing commands are kept as they are.
Future<void> seedSavedPrompts(
  SavedPromptsRepo repo,
  AppSettingsController settings,
) async {
  if (settings.get(AppSettingKeys.savedPromptsSeeded) == '1') return;
  for (final p in defaultSavedPrompts) {
    if (await repo.getByCommand(p.command) == null) {
      await repo.upsert(
        command: p.command,
        body: p.body,
        description: p.description,
      );
    }
  }
  await settings.set(AppSettingKeys.savedPromptsSeeded, '1');
}

/// `/command` name rules for "Salvar como prompt".
String? validateCommand(String command) {
  final c = command.trim().replaceFirst(RegExp(r'^/'), '');
  if (c.isEmpty) return 'Informe o comando.';
  if (!RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(c)) {
    return 'Use letras minúsculas, números e hífens (ex.: revisar-testes).';
  }
  return null;
}
