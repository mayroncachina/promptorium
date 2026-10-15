import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/agents/agent_file.dart';
import 'package:yaml/yaml.dart';

const source = '''---
# Agente de revisão
name: code-reviewer
description: "Revisa diffs: aponta bugs e riscos."
tools: Read, Grep, Bash(git diff *, git log *)
model: sonnet
color: purple

# campos que o Promptorium não conhece
hooks:
  PreToolUse:
    - matcher: Bash
      command: ./check.sh
skills: [review, lint]
effort: high
notes: |
  linha 1

  linha 3
mcpServers:
  - youtrack
  - local:
      command: node
      args: [srv.js]
---

Você é um revisor.
Seja direto.
''';

void main() {
  test('round-trip: parse → serialize is byte-identical when unchanged', () {
    final f = AgentFile.parse(source);
    expect(f.serialize(), source);
    expect(AgentFile.parse(f.serialize()).sameContent(f), isTrue);
  });

  test('known fields are read; unknown fields keep values and order', () {
    final f = AgentFile.parse(source);
    expect(f.name, 'code-reviewer');
    expect(f.description, 'Revisa diffs: aponta bugs e riscos.');
    expect(f.tools, ['Read', 'Grep', 'Bash(git diff *, git log *)']);
    expect(f.model, 'sonnet');
    expect(f.color, 'purple');
    expect(f.mcpServerNames, ['youtrack']);
    expect(f.keys, [
      'name',
      'description',
      'tools',
      'model',
      'color',
      'hooks',
      'skills',
      'effort',
      'notes',
      'mcpServers',
    ]);
    expect(f.value('notes'), 'linha 1\n\nlinha 3\n');
    expect(f.value('skills'), ['review', 'lint']);
    expect(f.body, '\nVocê é um revisor.\nSeja direto.\n');
  });

  test('editing known fields keeps unknown fields, comments and order', () {
    final f = AgentFile.parse(source)
        .withValue('model', 'opus')
        .withValue('description', 'Revisa: tudo # menos testes')
        .withToolList('tools', ['Read', 'Glob'])
        .withValue('maxTurns', 12)
        .withValue('permissionMode', 'plan')
        .withMcpServerNames(['context7'])
        .withBody('\nNovo prompt.\n');
    final out = f.serialize();
    // The YAML is valid and reads back the same values.
    final back = AgentFile.parse(out);
    expect(back.sameContent(f), isTrue);
    expect(back.model, 'opus');
    expect(back.description, 'Revisa: tudo # menos testes');
    expect(back.tools, ['Read', 'Glob']);
    expect(back.value('tools'), 'Read, Glob', reason: 'keeps the string style');
    expect(back.maxTurns, 12);
    expect(back.permissionMode, 'plan');
    // Inline MCP definition kept, name list replaced.
    expect(back.value('mcpServers'), [
      {
        'local': {
          'command': 'node',
          'args': ['srv.js'],
        },
      },
      'context7',
    ]);
    // Unknown keys untouched (original text) and in the same place.
    expect(out, contains('# Agente de revisão\nname: code-reviewer\n'));
    expect(
      out,
      contains('''hooks:
  PreToolUse:
    - matcher: Bash
      command: ./check.sh
skills: [review, lint]
effort: high
notes: |
  linha 1

  linha 3
'''),
    );
    expect(back.keys.take(10).toList(), [
      'name',
      'description',
      'tools',
      'model',
      'color',
      'hooks',
      'skills',
      'effort',
      'notes',
      'mcpServers',
    ]);
    expect(back.keys.skip(10), ['maxTurns', 'permissionMode']);
    expect(back.body, '\nNovo prompt.\n');
    // Second round-trip is stable.
    expect(AgentFile.parse(out).serialize(), out);
  });

  test('removing a key keeps the comment above it', () {
    final f = AgentFile.parse(source).withValue('name', null);
    final out = f.serialize();
    expect(out, startsWith('---\n# Agente de revisão\ndescription:'));
    expect(AgentFile.parse(out).has('name'), isFalse);
  });

  test('YAML list style of tools is kept; empty list removes the key', () {
    const src =
        '---\nname: a\ndescription: b\ntools:\n  - Read\n  - Grep\n---\n';
    final f = AgentFile.parse(src);
    expect(f.tools, ['Read', 'Grep']);
    final g = f.withToolList('tools', ['Read', 'Grep', 'Edit']);
    expect(
      g.serialize(),
      '---\nname: a\ndescription: b\ntools:\n  - Read\n  - Grep\n  - Edit\n---\n',
    );
    expect(f.withToolList('tools', []).has('tools'), isFalse);
    expect(identical(f.withToolList('tools', ['Read', 'Grep']), f), isTrue);
  });

  test('new agent file', () {
    final f = AgentFile.create(
      name: 'tester',
      description: 'Escreve testes',
      body: '\nVocê escreve testes.\n',
    ).withToolList('tools', ['Read', 'Write']).withValue('model', 'haiku');
    expect(
      f.serialize(),
      '---\nname: tester\ndescription: Escreve testes\ntools: Read, Write\n'
      'model: haiku\n---\n\nVocê escreve testes.\n',
    );
  });

  test('scalars needing quotes survive a round-trip', () {
    for (final s in [
      'true',
      'null',
      '123',
      '1.5',
      'a: b',
      'x #y',
      '- item',
      '[x]',
      '{y}',
      '*alias',
      '"quoted"',
      "it's",
      'multi\nline',
      ' leading',
      'trailing:',
      '~',
      '2026-10-15',
      'plain text, with comma',
      r'back\slash',
    ]) {
      final out = AgentFile.empty().withValue('k', s).serialize();
      final yaml = loadYaml(out.split('---\n')[1]) as YamlMap;
      expect(yaml['k'], s, reason: out);
    }
  });

  test('CRLF, BOM and invalid files', () {
    final f = AgentFile.parse('﻿---\r\nname: a\r\ndescription: b\r\n---\r\nx');
    expect(f.name, 'a');
    expect(f.body, 'x');
    expect(
      () => AgentFile.parse('sem frontmatter'),
      throwsA(isA<AgentFormatException>()),
    );
    expect(
      () => AgentFile.parse('---\nname: a\n'),
      throwsA(isA<AgentFormatException>()),
    );
    expect(
      () => AgentFile.parse('---\nname: [\n---\n'),
      throwsA(isA<AgentFormatException>()),
    );
    expect(
      () => AgentFile.parse('---\n- a\n---\n'),
      throwsA(isA<AgentFormatException>()),
    );
  });

  test('parseToolList splits on top-level commas only', () {
    expect(parseToolList('Read,Grep , Bash(git a, b)'), [
      'Read',
      'Grep',
      'Bash(git a, b)',
    ]);
    expect(parseToolList(['Read', ' ']), ['Read']);
    expect(parseToolList(null), isEmpty);
  });
}
