import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_service.dart';
import '../../core/process/shell_runner.dart';
import '../../ui/theme/tokens.dart';
import '../project/project_config.dart';
import '../sessions/widgets/session_style.dart';

// --- Problemas ---------------------------------------------------------------------

/// One diagnostic of the `lint:` output.
@immutable
class Problem {
  const Problem({
    required this.path,
    required this.line,
    required this.message,
    this.column,
    this.severity = 'erro',
  });

  /// Relative to the worktree.
  final String path;
  final int line;
  final int? column;
  final String message;

  /// `erro` / `aviso` / `info`.
  final String severity;
}

/// Diagnostics of a lint output: `arquivo:linha:col: mensagem` (gcc, eslint
/// unix, ruff, go vet…) and the `flutter analyze` / `dart analyze` lines
/// (`info • mensagem • lib/a.dart:12:5 • regra`). Absolute paths under
/// [root] become relative.
List<Problem> parseProblems(String output, String root) {
  String rel(String p) =>
      p.startsWith('$root/') ? p.substring(root.length + 1) : p;
  String sev(String s) {
    final l = s.toLowerCase();
    if (l.contains('warn') || l.contains('aviso')) return 'aviso';
    if (l.contains('info') || l.contains('hint') || l.contains('note')) {
      return 'info';
    }
    return 'erro';
  }

  final out = <Problem>[];
  final dart = RegExp(
    r'^\s*(error|warning|info|hint)\s+•\s+(.+?)\s+•\s+(\S+?):(\d+):(\d+)\s+•',
  );
  final generic = RegExp(r'^(\S[^:\n]*?):(\d+)(?::(\d+))?:\s*(.+)$');
  for (final line in const LineSplitter().convert(output)) {
    final d = dart.firstMatch(line);
    if (d != null) {
      out.add(
        Problem(
          path: rel(d.group(3)!),
          line: int.parse(d.group(4)!),
          column: int.parse(d.group(5)!),
          message: d.group(2)!,
          severity: sev(d.group(1)!),
        ),
      );
      continue;
    }
    final g = generic.firstMatch(line.trim());
    if (g == null || g.group(1)!.contains(' ')) continue;
    final msg = g.group(4)!.trim();
    out.add(
      Problem(
        path: rel(g.group(1)!),
        line: int.parse(g.group(2)!),
        column: g.group(3) == null ? null : int.parse(g.group(3)!),
        message: msg,
        severity: sev(msg.split(RegExp(r'[\s:\]]')).first),
      ),
    );
  }
  return out;
}

@immutable
class ProblemsState {
  const ProblemsState({
    this.running = false,
    this.problems = const [],
    this.command,
    this.at,
    this.ok,
  });

  final bool running;
  final List<Problem> problems;
  final String? command;
  final DateTime? at;

  /// Exit status of the last run (null = never ran).
  final bool? ok;
}

/// `lint:` of the project run in a worktree (on save; Problemas tab).
class ProblemsNotifier extends Notifier<ProblemsState> {
  ProblemsNotifier(this.worktree);

  final String worktree;

  @override
  ProblemsState build() => const ProblemsState();

  /// Runs `lint:` of [root]'s config (no-op without one or while running).
  Future<void> run(String root) async {
    final config = ProjectConfig.loadSync(root);
    final cmd = config.lintCommand;
    if (cmd == null || state.running) return;
    state = ProblemsState(
      running: true,
      problems: state.problems,
      command: cmd,
      at: state.at,
      ok: state.ok,
    );
    final r = await ref.read(shellRunnerProvider)(
      cmd,
      cwd: worktree,
      timeout: config.gate.timeout,
    );
    if (!ref.mounted) return;
    state = ProblemsState(
      problems: parseProblems(r.output, worktree),
      command: cmd,
      at: DateTime.now(),
      ok: r.ok,
    );
  }
}

final problemsProvider =
    NotifierProvider.family<ProblemsNotifier, ProblemsState, String>(
      ProblemsNotifier.new,
    );

class ProblemsBody extends ConsumerWidget {
  const ProblemsBody({
    super.key,
    required this.worktree,
    required this.root,
    required this.onOpen,
  });

  final String worktree;
  final String root;
  final void Function(String path, int line) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(problemsProvider(worktree));
    final lint = ProjectConfig.loadSync(root).lintCommand;
    if (lint == null) {
      return const _Note(
        'Defina "lint:" na configuração do projeto (ex.: flutter analyze): '
        'ele roda ao salvar e os problemas aparecem aqui.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  s.running
                      ? 'Rodando $lint…'
                      : s.at == null
                      ? '$lint roda ao salvar.'
                      : '$lint · ${s.problems.length} problema(s)',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              SmallButton(
                key: const ValueKey('code-problems-run'),
                label: 'Rodar agora',
                height: 22,
                onTap: s.running
                    ? null
                    : () => ref
                          .read(problemsProvider(worktree).notifier)
                          .run(root),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final (i, p) in s.problems.indexed)
                InkWell(
                  key: ValueKey('code-problem-$i'),
                  onTap: () => onOpen(p.path, p.line),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 3,
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${p.severity} ',
                            style: TextStyle(
                              color: p.severity == 'erro'
                                  ? AppColors.red
                                  : p.severity == 'aviso'
                                  ? AppColors.amber
                                  : AppColors.blue,
                            ),
                          ),
                          TextSpan(
                            text:
                                '${p.path}:${p.line}${p.column == null ? '' : ':${p.column}'} ',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          TextSpan(text: p.message),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 11,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- Git -------------------------------------------------------------------------

@immutable
class GitPanelState {
  const GitPanelState({
    this.branch,
    this.entries = const [],
    this.error,
    this.busy = false,
  });

  final String? branch;
  final List<GitStatusEntry> entries;
  final String? error;
  final bool busy;
}

/// Git of a worktree for the Código screen (F13): status, stage / unstage
/// per file, commit.
class GitPanelNotifier extends Notifier<GitPanelState> {
  GitPanelNotifier(this.worktree);

  final String worktree;

  GitService get _git => ref.read(gitServiceFactoryProvider)(worktree);

  @override
  GitPanelState build() {
    Future.microtask(refresh);
    return const GitPanelState(busy: true);
  }

  Future<void> refresh() async {
    try {
      final branch = await _git.currentBranch();
      final entries = await _git.status();
      if (ref.mounted) {
        state = GitPanelState(branch: branch, entries: entries);
      }
    } catch (e) {
      if (ref.mounted) state = GitPanelState(error: '$e');
    }
  }

  Future<void> _do(Future<void> Function() job) async {
    state = GitPanelState(
      branch: state.branch,
      entries: state.entries,
      busy: true,
    );
    try {
      await job();
    } catch (e) {
      if (ref.mounted) {
        state = GitPanelState(
          branch: state.branch,
          entries: state.entries,
          error: '$e',
        );
      }
      return;
    }
    await refresh();
  }

  Future<void> stage(String path) => _do(() => _git.git(['add', '--', path]));

  Future<void> unstage(String path) =>
      _do(() => _git.git(['restore', '--staged', '--', path]));

  /// Commits what is staged (nothing staged = everything).
  Future<void> commit(String message) => _do(() async {
    final m = message.trim();
    if (m.isEmpty) throw const GitException('Escreva a mensagem do commit.');
    final staged = state.entries.any((e) => e.x != ' ' && e.x != '?');
    if (!staged) await _git.git(['add', '-A']);
    await _git.git(['commit', '-q', '-m', m]);
  });
}

final gitPanelProvider =
    NotifierProvider.family<GitPanelNotifier, GitPanelState, String>(
      GitPanelNotifier.new,
    );

class GitBody extends ConsumerStatefulWidget {
  const GitBody({super.key, required this.worktree, required this.onOpen});

  final String worktree;
  final void Function(String path) onOpen;

  @override
  ConsumerState<GitBody> createState() => _GitBodyState();
}

class _GitBodyState extends ConsumerState<GitBody> {
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(gitPanelProvider(widget.worktree));
    final n = ref.read(gitPanelProvider(widget.worktree).notifier);
    bool staged(GitStatusEntry e) => e.x != ' ' && e.x != '?';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Text(
                      s.branch == null ? 'HEAD destacado' : '⎇ ${s.branch}',
                      key: const ValueKey('code-git-branch'),
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 11,
                        color: AppColors.teal,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      key: const ValueKey('code-git-refresh'),
                      tooltip: 'Atualizar',
                      iconSize: 14,
                      icon: const Icon(
                        Icons.refresh,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: n.refresh,
                    ),
                  ],
                ),
              ),
              if (s.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    s.error!,
                    style: const TextStyle(fontSize: 11, color: AppColors.red),
                  ),
                ),
              if (s.entries.isEmpty && s.error == null && !s.busy)
                const _Note('Nada para commitar.'),
              for (final e in s.entries)
                InkWell(
                  key: ValueKey('code-git-entry-${e.path}'),
                  onTap: () => widget.onOpen(e.path),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 26,
                          child: Text(
                            '${e.x}${e.y}',
                            style: TextStyle(
                              fontFamily: AppFonts.mono,
                              fontSize: 11,
                              color: staged(e)
                                  ? AppColors.teal
                                  : AppColors.amber,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            e.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppFonts.mono,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        TextButton(
                          key: ValueKey(
                            'code-git-${staged(e) ? 'unstage' : 'stage'}-${e.path}',
                          ),
                          onPressed: s.busy
                              ? null
                              : () => staged(e)
                                    ? n.unstage(e.path)
                                    : n.stage(e.path),
                          child: Text(
                            staged(e) ? '−' : '+',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          width: 260,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('code-git-message'),
                    controller: _message,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: 'Mensagem do commit',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SmallButton(
                  key: const ValueKey('code-git-commit'),
                  label: 'Commit',
                  height: 26,
                  onTap: s.busy || s.entries.isEmpty
                      ? null
                      : () async {
                          await n.commit(_message.text);
                          if (ref
                                  .read(gitPanelProvider(widget.worktree))
                                  .error ==
                              null) {
                            _message.clear();
                          }
                        },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// --- Busca -----------------------------------------------------------------------

@immutable
class SearchHit {
  const SearchHit({required this.path, required this.line, required this.text});

  final String path;
  final int line;
  final String text;
}

/// Whether `rg` runs (checked once).
Future<bool> ripgrepAvailable() => _rg ??= () async {
  try {
    return (await Process.run('rg', ['--version'])).exitCode == 0;
  } catch (_) {
    return false;
  }
}();
Future<bool>? _rg;

/// Lines of `rg --json` → hits (relative paths).
List<SearchHit> parseRipgrepJson(String out, String root) {
  final hits = <SearchHit>[];
  for (final l in const LineSplitter().convert(out)) {
    Object? j;
    try {
      j = jsonDecode(l);
    } on FormatException {
      continue;
    }
    if (j is! Map || j['type'] != 'match') continue;
    final d = j['data'];
    if (d is! Map) continue;
    var path = '${(d['path'] as Map?)?['text'] ?? ''}';
    if (path.startsWith('$root/')) path = path.substring(root.length + 1);
    if (path.startsWith('./')) path = path.substring(2);
    hits.add(
      SearchHit(
        path: path,
        line: (d['line_number'] as num?)?.toInt() ?? 0,
        text: '${(d['lines'] as Map?)?['text'] ?? ''}'.trimRight(),
      ),
    );
  }
  return hits;
}

/// Global search (Ctrl+Shift+F): `rg --json --fixed-strings` when it is
/// installed, else a scan of [files] (the worktree's tracked files). At
/// most [limit] hits.
Future<List<SearchHit>> searchWorktree(
  String root,
  String query,
  List<String> files, {
  int limit = 500,
  bool? useRipgrep,
}) async {
  if (query.isEmpty) return const [];
  if (useRipgrep ?? await ripgrepAvailable()) {
    final r = await Process.run('rg', [
      '--json',
      '--fixed-strings',
      '--smart-case',
      '--max-count',
      '50',
      '--',
      query,
      '.',
    ], workingDirectory: root);
    return parseRipgrepJson('${r.stdout}', root).take(limit).toList();
  }
  final hits = <SearchHit>[];
  final lower = query.toLowerCase();
  final smart = query != lower;
  for (final f in files) {
    final file = File('$root/$f');
    try {
      if (await file.length() > 2 * 1024 * 1024) continue;
      final lines = await file.readAsLines();
      for (final (i, l) in lines.indexed) {
        if (smart ? l.contains(query) : l.toLowerCase().contains(lower)) {
          hits.add(SearchHit(path: f, line: i + 1, text: l));
          if (hits.length >= limit) return hits;
        }
      }
    } catch (_) {
      // binary / unreadable
    }
  }
  return hits;
}

class SearchBody extends StatefulWidget {
  const SearchBody({
    super.key,
    required this.root,
    required this.files,
    required this.onOpen,
    this.focus,
  });

  final String root;
  final List<String> files;
  final void Function(String path, int line) onOpen;
  final FocusNode? focus;

  @override
  State<SearchBody> createState() => _SearchBodyState();
}

class _SearchBodyState extends State<SearchBody> {
  final _query = TextEditingController();
  List<SearchHit> _hits = const [];
  bool _busy = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _busy = true);
    final hits = await searchWorktree(widget.root, _query.text, widget.files);
    if (mounted) {
      setState(() {
        _hits = hits;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: TextField(
          key: const ValueKey('code-search-field'),
          controller: _query,
          focusNode: widget.focus,
          style: const TextStyle(fontSize: 12, fontFamily: AppFonts.mono),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Buscar em todos os arquivos (Enter)',
            suffixText: _busy
                ? 'buscando…'
                : _hits.isEmpty
                ? null
                : '${_hits.length} resultado(s)',
          ),
          onSubmitted: (_) => _search(),
        ),
      ),
      Expanded(
        child: ListView(
          children: [
            for (final (i, h) in _hits.indexed)
              InkWell(
                key: ValueKey('code-search-hit-$i'),
                onTap: () => widget.onOpen(h.path, h.line),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${h.path}:${h.line}  ',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        TextSpan(text: h.text.trim()),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                      color: AppColors.text,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
    ),
  );
}
