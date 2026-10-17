import 'package:flutter/foundation.dart';

import 'project_config.dart';
import 'project_plan.dart' show StackDecision;

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
  });

  final String id;
  final String label;

  /// `.promptorium/config.yml` written at creation.
  final ProjectConfig config;

  /// Stack decisions pinned for the planner (kept as they are).
  final List<StackDecision> decisions;

  /// `CLAUDE.md` written at creation (null = none; the planner proposes).
  final String? claudeMd;

  bool get isEmpty => id == 'empty';

  /// One-line description for the chip tooltip / the "O que acontece" box.
  String get summary => isEmpty
      ? 'nada preenchido: o planner propõe tudo'
      : [
          for (final d in decisions) d.choice,
          if (config.testCommand != null) 'testes: ${config.testCommand}',
        ].join(' · ');
}

const projectTemplates = [
  ProjectTemplate(id: 'empty', label: 'Vazio'),
  ProjectTemplate(
    id: 'flutter',
    label: 'Flutter app',
    config: ProjectConfig(
      testCommand: 'flutter test',
      lintCommand: 'flutter analyze',
      formatCommand: 'dart format {arquivo}',
      worktree: WorktreeConfig(prepare: 'flutter pub get'),
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
      worktree: WorktreeConfig(prepare: 'npm install', basePort: 3000),
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
        prepare: 'pip install -r requirements.txt',
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
      worktree: WorktreeConfig(prepare: 'dart pub get'),
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
