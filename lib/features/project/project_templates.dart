import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/providers/workspace_assets.dart'
    show
        agentsMdMarker,
        agentsMdName,
        claudeImportLine,
        claudeImportLines,
        claudeMdName;
import 'project_config.dart';
import 'project_plan.dart' show StackCommands, StackDecision;
import 'stack_commands.dart';

/// Starting points of "Novo projeto" (UX v2, U7; docs/mockups/v2/
/// NovoProjeto.dc.html): a template fills the stack, the test / lint /
/// format commands and minimal instructions (the `AGENTS.md`, imported by the
/// `CLAUDE.md`, SPEC-113 R2); the planner only adjusts. "Vazio" leaves
/// everything to the planner.
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

  /// Instructions written at creation (null = none; the planner proposes).
  /// They go to the `AGENTS.md`, and the `CLAUDE.md` gets the import
  /// (SPEC-113 R2, [writeNewProjectInstructions]).
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
          if (isCustom && claudeMd != null) 'AGENTS.md base',
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

/// The minimal instructions a template wrote at creation, when they are
/// still as written (SPEC-071 R23): the plan's instructions replace them, and
/// the planner starts from them. Read from the `AGENTS.md` (SPEC-113 R2) or,
/// in a project created before it, from the `CLAUDE.md`. Null when absent or
/// edited.
String? templateClaudeMd(String workspacePath) {
  for (final name in [agentsMdName, claudeMdName]) {
    final text = _read('$workspacePath/$name');
    if (text == null) continue;
    final mine = text.trim();
    for (final t in projectTemplates) {
      if (t.claudeMd?.trim() == mine && mine.isNotEmpty) return text;
    }
    // The base of an "Outro…" stack, still as written (SPEC-072).
    if (isCustomClaudeMd(text)) return text.substring(text.indexOf('\n') + 1);
  }
  return null;
}

String? _read(String path) {
  final f = File(path);
  if (!f.existsSync()) return null;
  try {
    return f.readAsStringSync();
  } on FileSystemException {
    return null;
  }
}

/// The `CLAUDE.md` of a new project: only the import (SPEC-113 R2).
const claudeImportMd = '$claudeImportLine\n';

/// Who wrote an instruction file at the root of a project being created.
enum InstructionFileOwner {
  /// The file does not exist.
  none,

  /// The app: a template's minimal text, an unedited "Outro…" base, an
  /// `AGENTS.md` generated from the `CLAUDE.md` (SPEC-104), a `CLAUDE.md`
  /// with only the import, or exactly what would be written now.
  app,

  /// The person: never overwritten.
  person,
}

/// The two instruction files of a project root, as "Criar projeto" sees
/// them (SPEC-113 R2).
@immutable
class InstructionFiles {
  const InstructionFiles({required this.agents, required this.claude});

  final InstructionFileOwner agents;
  final InstructionFileOwner claude;

  /// A file of the person's is there: nothing is written, not even the
  /// other file (one alone would make two sources).
  bool get blocked =>
      agents == InstructionFileOwner.person ||
      claude == InstructionFileOwner.person;

  /// The person's files, by name (for the "kept" notice).
  List<String> get personal => [
    if (agents == InstructionFileOwner.person) agentsMdName,
    if (claude == InstructionFileOwner.person) claudeMdName,
  ];
}

bool _isTemplateText(String text) {
  final mine = text.trim();
  if (mine.isEmpty) return false;
  if (isCustomClaudeMd(text)) return true;
  return projectTemplates.any((t) => t.claudeMd?.trim() == mine);
}

bool _isImportOnly(String text) {
  return claudeImportLines.contains(text.trim());
}

/// Who wrote the `AGENTS.md` and the `CLAUDE.md` of [path]. [text] is what
/// would go to the `AGENTS.md` now: a file already equal to it is the app's
/// (a retry after a failure halfway).
InstructionFiles instructionFilesOf(String path, {String? text}) {
  InstructionFileOwner owner(String name, bool Function(String) isApp) {
    final f = File('$path/$name');
    if (!f.existsSync()) return InstructionFileOwner.none;
    final current = _read(f.path);
    if (current == null) return InstructionFileOwner.person;
    return isApp(current)
        ? InstructionFileOwner.app
        : InstructionFileOwner.person;
  }

  return InstructionFiles(
    agents: owner(
      agentsMdName,
      (c) =>
          _isTemplateText(c) ||
          agentsMdMarker(c) != null ||
          (text != null && c == text),
    ),
    claude: owner(claudeMdName, (c) => _isImportOnly(c) || _isTemplateText(c)),
  );
}

/// Writes [text] to the `AGENTS.md` of [path] and the import to its
/// `CLAUDE.md` (SPEC-113 R2). Returns the two names, or nothing when [text]
/// is empty or a file of the person's is there ([InstructionFiles.blocked]):
/// then neither file is touched.
Future<List<String>> writeNewProjectInstructions(
  String path,
  String text,
) async {
  if (text.trim().isEmpty) return const [];
  if (instructionFilesOf(path, text: text).blocked) return const [];
  await File('$path/$agentsMdName').writeAsString(text);
  await File('$path/$claudeMdName').writeAsString(claudeImportMd);
  return const [agentsMdName, claudeMdName];
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
