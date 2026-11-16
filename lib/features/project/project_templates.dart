import 'dart:io';

import 'package:flutter/foundation.dart';

import 'project_config.dart';
import 'project_plan.dart' show StackCommands, StackDecision;
import 'stack_commands.dart';

/// Starting points of "Novo projeto" (UX v2, U7; docs/mockups/v2/
/// NovoProjeto.dc.html): a template fills the stack, the test / lint /
/// format commands and a minimal CLAUDE.md; the planner only adjusts. "Vazio"
/// leaves everything to the planner.
@immutable
class ProjectTemplate {
  const ProjectTemplate({
    required this.id,
    required this.label,
    this.config = const ProjectConfig(),
    this.decisions = const [],
    this.claudeMd,
    this.scaffold = '',
  });

  /// A stack defined with "Outro…" (SPEC-072 R18): the proposal of the
  /// modal as a template. Its commands go to the config.yml, its decisions
  /// are pinned and its CLAUDE.md base carries the scaffold.
  factory ProjectTemplate.fromStack(CustomStack s) => ProjectTemplate(
    id: customTemplateId,
    label: s.name,
    config: mergeStackCommands(const ProjectConfig(), s.commands).config,
    decisions: [for (final d in s.decisions) d.copyWith(pinned: true)],
    claudeMd: customClaudeMd(s.claudeMd, scaffold: s.scaffold),
    scaffold: s.scaffold,
  );

  final String id;
  final String label;

  /// `.promptorium/config.yml` written at creation.
  final ProjectConfig config;

  /// Stack decisions pinned for the planner (kept as they are).
  final List<StackDecision> decisions;

  /// `CLAUDE.md` written at creation (null = none; the planner proposes).
  final String? claudeMd;

  /// The skeleton command of a custom stack (empty for the built-in ones).
  final String scaffold;

  bool get isEmpty => id == 'empty';

  bool get isCustom => id == customTemplateId;

  /// One-line description for the chip tooltip / the "O que acontece" box.
  String get summary => isEmpty
      ? 'nada preenchido: o planner propõe tudo'
      : [
          for (final d in decisions) d.choice,
          if (config.testCommand != null) 'testes: ${config.testCommand}',
          if (isCustom && claudeMd != null) 'CLAUDE.md base',
        ].join(' · ');
}

/// The `preparar:` of each template skips while the manifest does not exist:
/// the project starts empty and its first spec usually creates it.
const projectTemplates = [
  ProjectTemplate(id: 'empty', label: 'Vazio'),
  ProjectTemplate(
    id: 'flutter',
    label: 'Flutter app',
    config: ProjectConfig(
      testCommand: 'flutter test',
      lintCommand: 'flutter analyze',
      formatCommand: 'dart format {arquivo}',
      worktree: WorktreeConfig(
        prepare: 'test ! -f pubspec.yaml || flutter pub get',
      ),
    ),
    decisions: [
      StackDecision(area: 'App', choice: 'Flutter', pinned: true),
      StackDecision(area: 'Estado', choice: 'Riverpod', pinned: true),
    ],
    claudeMd:
        '# Projeto Flutter\n\n'
        '- Testes: `flutter test` · Lint: `flutter analyze` · Formatar: '
        '`dart format`\n'
        '- Estado com Riverpod; um widget por arquivo; nada de lógica de '
        'negócio em widgets.\n'
        '- Commits pequenos, mensagem em português, imperativo.\n',
  ),
  ProjectTemplate(
    id: 'nextjs',
    label: 'Next.js',
    config: ProjectConfig(
      testCommand: 'npm test',
      lintCommand: 'npm run lint',
      formatCommand: 'npx prettier --write {arquivo}',
      worktree: WorktreeConfig(
        prepare: 'test ! -f package.json || npm install',
        basePort: 3000,
      ),
    ),
    decisions: [
      StackDecision(area: 'Web', choice: 'Next.js (App Router)', pinned: true),
      StackDecision(area: 'Linguagem', choice: 'TypeScript', pinned: true),
    ],
    claudeMd:
        '# Projeto Next.js\n\n'
        '- Testes: `npm test` · Lint: `npm run lint` · Formatar: `prettier`\n'
        '- TypeScript estrito; componentes de servidor por padrão.\n'
        '- A porta do dev server vem de `PROMPTORIUM_PORT`.\n',
  ),
  ProjectTemplate(
    id: 'python-api',
    label: 'API Python',
    config: ProjectConfig(
      testCommand: 'pytest',
      lintCommand: 'ruff check .',
      formatCommand: 'ruff format {arquivo}',
      worktree: WorktreeConfig(
        prepare:
            'test ! -f requirements.txt || pip install -r requirements.txt',
        basePort: 8000,
      ),
    ),
    decisions: [
      StackDecision(area: 'API', choice: 'FastAPI', pinned: true),
      StackDecision(area: 'Linguagem', choice: 'Python 3.12', pinned: true),
    ],
    claudeMd:
        '# API Python\n\n'
        '- Testes: `pytest` · Lint e formatar: `ruff`\n'
        '- FastAPI com tipagem; um módulo por recurso.\n'
        '- A porta do servidor vem de `PROMPTORIUM_PORT`.\n',
  ),
  ProjectTemplate(
    id: 'dart-cli',
    label: 'CLI Dart',
    config: ProjectConfig(
      testCommand: 'dart test',
      lintCommand: 'dart analyze',
      formatCommand: 'dart format {arquivo}',
      worktree: WorktreeConfig(
        prepare: 'test ! -f pubspec.yaml || dart pub get',
      ),
    ),
    decisions: [
      StackDecision(area: 'Linguagem', choice: 'Dart', pinned: true),
      StackDecision(area: 'CLI', choice: 'package:args', pinned: true),
    ],
    claudeMd:
        '# CLI em Dart\n\n'
        '- Testes: `dart test` · Lint: `dart analyze` · Formatar: '
        '`dart format`\n'
        '- Comandos em `lib/src/commands/`, um por arquivo.\n',
  ),
];

ProjectTemplate templateById(String? id) =>
    projectTemplates.where((t) => t.id == id).firstOrNull ??
    projectTemplates.first;

/// The `CLAUDE.md` of [workspacePath] when it is still the minimal one a
/// template wrote at creation (SPEC-071 R23): the plan's CLAUDE.md replaces
/// it, and the planner starts from it. Null when absent or edited.
String? templateClaudeMd(String workspacePath) {
  final f = File('$workspacePath/CLAUDE.md');
  if (!f.existsSync()) return null;
  final String text;
  try {
    text = f.readAsStringSync();
  } on FileSystemException {
    return null;
  }
  final mine = text.trim();
  for (final t in projectTemplates) {
    if (t.claudeMd?.trim() == mine && mine.isNotEmpty) return text;
  }
  // The CLAUDE.md base of an "Outro…" stack, still as written (SPEC-072).
  if (isCustomClaudeMd(text)) return text.substring(text.indexOf('\n') + 1);
  return null;
}

/// Id of the "Outro…" template.
const customTemplateId = 'custom';

/// A stack the Claude defined in the "Outro…" modal (SPEC-072 R17).
@immutable
class CustomStack {
  const CustomStack({
    required this.name,
    this.decisions = const [],
    this.commands = const StackCommands(),
    this.scaffold = '',
    this.claudeMd = '',
  });

  /// Short name for the chip ("Go · Fiber").
  final String name;
  final List<StackDecision> decisions;
  final StackCommands commands;
  final String scaffold;

  /// The CLAUDE.md base (without the app's marker).
  final String claudeMd;

  CustomStack copyWith({StackCommands? commands}) => CustomStack(
    name: name,
    decisions: decisions,
    commands: commands ?? this.commands,
    scaffold: scaffold,
    claudeMd: claudeMd,
  );
}

const _customMark = '<!-- promptorium: CLAUDE.md base da stack';

/// FNV-1a of [text] (stable across runs, unlike `hashCode`).
String _fnv(String text) {
  var h = 0x811c9dc5;
  for (final c in text.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// The CLAUDE.md base of a custom stack: the scaffold in the commands
/// section (R18) and a first line that lets [templateClaudeMd] know it is
/// still the base (a hash of the rest: an edit makes it the user's).
String customClaudeMd(String base, {String scaffold = ''}) {
  var body = base.trim();
  final sc = scaffold.trim();
  if (sc.isNotEmpty && !body.contains(sc)) {
    final line = '- Esqueleto (scaffold): `$sc`';
    final m = RegExp(r'^##\s+Comandos.*$', multiLine: true).firstMatch(body);
    if (m != null) {
      body = '${body.substring(0, m.end)}\n$line${body.substring(m.end)}';
    } else {
      body = '$body\n\n## Comandos\n$line';
    }
  }
  body = '$body\n';
  return '$_customMark ${_fnv(body)} -->\n$body';
}

/// Whether [text] is a custom CLAUDE.md base nobody edited.
bool isCustomClaudeMd(String text) {
  if (!text.startsWith(_customMark)) return false;
  final nl = text.indexOf('\n');
  if (nl < 0) return false;
  final head = text.substring(0, nl);
  final hash = RegExp(r'([0-9a-f]{8}) -->$').firstMatch(head)?.group(1);
  return hash != null && hash == _fnv(text.substring(nl + 1));
}
