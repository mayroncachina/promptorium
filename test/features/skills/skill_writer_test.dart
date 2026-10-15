import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/providers/claude_code_provider.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/agents/agent_repository.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/skills/skill_repository.dart';
import 'package:promptorium/features/skills/skill_writer.dart';

import '../../helpers/test_db.dart';
import '../project/project_planner_test.dart' show resultLine;
import '../sessions/session_test_utils.dart';

Map<String, Object?> draft({String name = 'Revisar Migration!'}) => {
  'name': name,
  'description': 'Revisa migrations antes do merge. Use quando houver uma.',
  'allowedTools': 'Read, Grep',
  'body': '# Revisar migration\n\n1. Leia o diff.',
};

void main() {
  test('transcript keeps user and main-thread assistant text, cut from the '
      'start', () {
    final lines = [
      jsonEncode(AppEventTypes.userMessage('Crie a migration', DateTime(2026))),
      jsonEncode({
        'type': 'assistant',
        'message': {
          'id': 'm1',
          'content': [
            {'type': 'text', 'text': 'Vou ler o schema.'},
            {
              'type': 'tool_use',
              'id': 't1',
              'name': 'Read',
              'input': {'file_path': 'schema.prisma'},
            },
          ],
        },
      }),
      jsonEncode({
        'type': 'assistant',
        'parent_tool_use_id': 't9',
        'message': {
          'id': 'm2',
          'content': [
            {'type': 'text', 'text': 'subagente'},
          ],
        },
      }),
      'não é json',
    ];
    final t = sessionTranscript(lines);
    expect(t, contains('## Usuário\nCrie a migration'));
    expect(t, contains('Vou ler o schema.\n[ferramenta Read]'));
    expect(t, isNot(contains('subagente')));
    expect(sessionTranscript(lines, maxChars: 10), startsWith('…'));
  });

  test('draft: slug name, allowed-tools only when given, incomplete fails', () {
    Result r(Object out) =>
        ClaudeEvent.fromJson(jsonDecode(resultLine(out))) as Result;
    var f = parseSkillDraft(r(draft()));
    expect(f.name, 'revisar-migration');
    expect(f.value('allowed-tools'), 'Read, Grep');
    expect(f.body, startsWith('# Revisar migration'));
    f = parseSkillDraft(r({...draft(), 'allowedTools': ''}), name: 'Meu Nome');
    expect(f.name, 'meu-nome');
    expect(f.has('allowed-tools'), isFalse);
    expect(
      () => parseSkillDraft(r({...draft(), 'body': ''})),
      throwsA(anything),
    );
    expect(skillSlug('Ação  rápida — já!'), 'acao-rapida-ja');
  });

  test('write: read-only run with --json-schema, saved in the scope, taken '
      'names get a suffix', () async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-writer-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final cli = FakeCli();
    final c = ProviderContainer(
      overrides: [
        ...sessionOverrides(
          db: memoryDatabase(),
          cli: cli,
          notifier: FakeNotifier(),
        ),
        agentHomeProvider.overrideWithValue(tmp.path),
      ],
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();

    Future<String> write() async {
      final f = c
          .read(skillWriterProvider)
          .write(
            workspace: null,
            scope: AgentScope.global,
            request: 'revisar migrations',
          );
      await settle();
      final args = cli.args.last;
      expect(
        jsonDecode(args[args.indexOf('--json-schema') + 1]),
        skillDraftSchema,
      );
      expect(
        args.sublist(args.indexOf('--disallowedTools') + 1),
        ClaudeCodeProvider.readOnlyDisallowedTools,
      );
      expect(
        cli.last.writtenJson.single['message']['content'],
        contains('revisar migrations'),
      );
      cli.last.emit(resultLine(draft()));
      return f;
    }

    final dir = await write();
    expect(dir, '${tmp.path}/.claude/skills/revisar-migration');
    final saved = await SkillRepository(home: tmp.path)
        .load(dir, AgentScope.global);
    expect(saved!.description, startsWith('Revisa migrations'));
    expect(await write(), '${tmp.path}/.claude/skills/revisar-migration-2');
  });
}
