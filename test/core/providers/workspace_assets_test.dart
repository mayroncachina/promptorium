import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/providers/workspace_assets.dart';
import 'package:promptorium/features/context/context_sources.dart';
import 'package:promptorium/features/context/context_tracker.dart';

/// SPEC-104 T2: the instruction files of a project, the generated
/// `AGENTS.md` (hash + marker) and "duas fontes" (R3, R4, R5), and the
/// plano B link of the skills (R10).
void main() {
  late Directory tmp;
  late String root;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('workspace-assets-');
    root = tmp.path;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  void write(String rel, String text) {
    final f = File('$root/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(text);
  }

  String read(String rel) => File('$root/$rel').readAsStringSync();

  group('R3: the generated AGENTS.md', () {
    test('is a full copy with the header and the source hash marker', () {
      const claude = '# vitrine\n- Rode `flutter analyze` antes de commitar.\n';
      final out = generatedAgentsMd(claude);
      expect(
        out,
        startsWith(
          '<!-- Gerado do CLAUDE.md pelo Promptorium. Edite o CLAUDE.md.\n',
        ),
      );
      expect(
        out,
        contains('promptorium:origem sha256=${claudeMdHash(claude)}'),
      );
      expect(out, endsWith(claude));
      expect(agentsMdMarker(out), claudeMdHash(claude));
      expect(agentsMdBody(out), claude);
    });

    test('writeGeneratedAgentsMd writes it next to the CLAUDE.md', () async {
      write('CLAUDE.md', '# regras\n');
      await writeGeneratedAgentsMd(root);
      expect(agentsMdMarker(read('AGENTS.md')), claudeMdHash('# regras\n'));
    });
  });

  group('R4: the three cases', () {
    test('generated and up to date', () {
      const claude = '# a\n';
      expect(
        agentsMdState(claude: claude, agents: generatedAgentsMd(claude)),
        AgentsMdState.fresh,
      );
    });

    test('generated, the CLAUDE.md changed: stale, updated only after the '
        'diff was confirmed', () async {
      write('CLAUDE.md', '# a\n');
      await writeGeneratedAgentsMd(root);
      write('CLAUDE.md', '# a\n- nova regra\n');
      final inv = await scanInstructions(root);
      expect(inv.agentsState, AgentsMdState.stale);
      // Without the confirmation of the diff, nothing is written.
      await expectLater(
        writeGeneratedAgentsMd(root),
        throwsA(isA<InstructionsException>()),
      );
      expect(agentsMdBody(read('AGENTS.md')), '# a\n');
      await writeGeneratedAgentsMd(root, replaceGenerated: true);
      expect(agentsMdBody(read('AGENTS.md')), '# a\n- nova regra\n');
      expect((await scanInstructions(root)).agentsState, AgentsMdState.fresh);
    });

    test('written by the person (no marker): never overwritten', () async {
      write('CLAUDE.md', '# a\n');
      write('AGENTS.md', '# meu AGENTS\n');
      final inv = await scanInstructions(root);
      expect(inv.agentsState, AgentsMdState.personal);
      for (final replace in [false, true]) {
        await expectLater(
          writeGeneratedAgentsMd(root, replaceGenerated: replace),
          throwsA(isA<InstructionsException>()),
        );
      }
      expect(read('AGENTS.md'), '# meu AGENTS\n');
    });

    test('no AGENTS.md', () {
      expect(agentsMdState(claude: '# a'), AgentsMdState.absent);
    });
  });

  group('SPEC-113 R1: single source', () {
    test('a CLAUDE.md importing a person\'s AGENTS.md is the single source, '
        'never two sources', () async {
      for (final line in ['@AGENTS.md', '@./AGENTS.md', '  @AGENTS.md  ']) {
        expect(
          agentsMdState(claude: '$line\n\n# só Claude\n', agents: '# a\n'),
          AgentsMdState.singleSource,
          reason: line,
        );
      }
      expect(claudeImportLine, '@AGENTS.md');
      write('CLAUDE.md', '# Projeto\n\n@AGENTS.md\n');
      write('AGENTS.md', '# regras\n');
      expect(
        (await scanInstructions(root)).agentsState,
        AgentsMdState.singleSource,
      );
    });

    test('an import inside a code block does not count', () {
      for (final claude in [
        '```md\n@AGENTS.md\n```\n',
        '~~~\n@AGENTS.md\n~~~\n',
        '````\n```\n@AGENTS.md\n````\n',
        '# a\n\n    @AGENTS.md\n',
        'Use `@AGENTS.md` aqui.\n',
        '@AGENTS.md e mais\n',
      ]) {
        expect(hasAgentsImport(claude), isFalse, reason: claude);
        expect(
          agentsMdState(claude: claude, agents: '# a\n'),
          AgentsMdState.personal,
          reason: claude,
        );
      }
      // After the block closes, the import counts.
      expect(agentsImportLineIndex('```\nx\n```\n@AGENTS.md\n'), 3);
    });

    test('a generated AGENTS.md stays generated even with the import', () {
      const claude = '@AGENTS.md\n';
      expect(
        agentsMdState(claude: claude, agents: generatedAgentsMd(claude)),
        AgentsMdState.fresh,
      );
    });

    test('an old project (CLAUDE.md only) is unchanged: absent, no file '
        'written', () async {
      write('CLAUDE.md', '# antigo\n');
      final inv = await scanInstructions(root);
      expect(inv.agentsState, AgentsMdState.absent);
      expect(File('$root/AGENTS.md').existsSync(), isFalse);
      expect(tmp.listSync().map((e) => e.path.split('/').last), ['CLAUDE.md']);
    });
  });

  test('R5: the root files and the nested ones (read-only), skipping dot '
      'folders and build output', () async {
    write('CLAUDE.md', '# raiz\nlinha\n');
    write('packages/api/CLAUDE.md', 'x\n');
    write('lib/ui/AGENTS.md', 'y\n');
    write('.git/CLAUDE.md', 'nao\n');
    write('node_modules/p/CLAUDE.md', 'nao\n');
    final inv = await scanInstructions(root);
    expect(inv.claude!.path, 'CLAUDE.md');
    expect(inv.claude!.lines, 2);
    expect(inv.agents, isNull);
    expect(
      [for (final f in inv.nested) f.path],
      ['lib/ui/AGENTS.md', 'packages/api/CLAUDE.md'],
    );
    expect(inv.nested.every((f) => f.nested), isTrue);
  });

  group('R10: Disponibilizar no Codex', () {
    test('links the project skill inside the repository, relative', () async {
      write('.claude/skills/gerar-release/SKILL.md', '---\nname: x\n---\n');
      final path = await linkSkillForCodex(root, 'gerar-release');
      expect(path, '$root/.agents/skills/gerar-release');
      expect(Link(path).targetSync(), '../../.claude/skills/gerar-release');
      expect(linkedSkillDir(root, 'gerar-release'), path);
      // Nothing outside the repository.
      expect(path.startsWith(root), isTrue);
    });

    test('refuses when something is already there', () async {
      write('.claude/skills/a/SKILL.md', 'x');
      write('.agents/skills/a/SKILL.md', 'outra');
      await expectLater(
        linkSkillForCodex(root, 'a'),
        throwsA(isA<InstructionsException>()),
      );
      expect(linkedSkillDir(root, 'a'), isNull);
    });
  });

  test('R2: the instructionSources of a run become an agent-reported source '
      'of the Contexto panel', () {
    final sources = ContextSources();
    sources.apply(
      UnknownEvent(
        ContextEventTypes.runEvent(
          provider: 'codex',
          instructionSources: ['CLAUDE.md'],
        ),
      ),
      turn: 1,
      at: DateTime(2026),
      itemIndex: 0,
    );
    final s = sources.grouped[ContextSourceGroup.instructions]!.single;
    expect(s.label, 'CLAUDE.md');
    expect(s.evidence, ContextEvidence.agent);
    expect(s.detail, 'carregado pelo Codex');
  });
}
