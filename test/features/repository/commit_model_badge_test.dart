import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/gh_cli.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/repository/graph/commit_log.dart';
import 'package:promptorium/features/repository/graph/commit_model_badge.dart';
import 'package:promptorium/features/repository/graph/graph_controller.dart';
import 'package:promptorium/features/repository/graph/graph_sources.dart';
import 'package:promptorium/features/repository/graph/graph_tab.dart';
import 'package:promptorium/features/repository/releases/releases_state.dart';
import 'package:promptorium/features/repository/repository_info.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/git/git_test_utils.dart';
import 'fake_gh.dart';

class _Settings extends AppSettingsController {
  @override
  Map<String, String> build() => {};

  @override
  Future<void> set(String key, String value) async =>
      state = {...state, key: value};
}

void main() {
  late Directory tmp;
  late String repo;
  late List<List<String>> calls;

  Future<String> commit(String msg, {String? trailer}) async {
    File('$repo/${msg.hashCode}.txt').writeAsStringSync(msg);
    await gitIn(repo, ['add', '-A']);
    await gitIn(repo, [
      'commit',
      '-q',
      '-m',
      msg,
      if (trailer != null) ...['--trailer', trailer],
    ]);
    return (await gitIn(repo, ['rev-parse', 'HEAD'])).trim();
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-model-badge-');
    repo = await createRepo(tmp);
    calls = [];
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'commitOriginsOf lê várias origens numa chamada, na ordem pedida',
    () async {
      final a = await commit(
        'feat: a',
        trailer: 'Promptorium-Agente: sonnet · SPEC-042 T4',
      );
      final b = await commit('fix: b');
      final c = await commit(
        'chore: c',
        trailer: 'Promptorium-Agente: app · SPEC-042 R2',
      );
      final git = GitService(
        repo,
        run: (exe, args) {
          calls.add(args);
          return Process.run(exe, args);
        },
      );
      final got = await git.commitOriginsOf([c, a, b]);
      expect(calls, hasLength(1));
      expect(got.map((o) => o.sha), [c, a, b]);
      expect(got[0].kind, CommitOriginKind.app);
      expect(got[1].model, 'sonnet');
      expect(got[1].origin, 'SPEC-042 T4');
      expect(got[1].trailer, 'Promptorium-Agente: sonnet · SPEC-042 T4');
      expect(got[2].kind, CommitOriginKind.unmarked);
      expect(await git.commitOriginsOf(const []), isEmpty);
    },
  );

  testWidgets('R9 · a etiqueta do modelo ao lado do autor, lida em lote, com '
      'a origem e a linha do trailer', (tester) async {
    late String sonnet, opus, app, plain;
    await tester.runAsync(() async {
      plain = await commit('fix: sem marca');
      opus = await commit(
        'feat(tray): radar',
        trailer: 'Promptorium-Agente: opus · SPEC-041 R1',
      );
      app = await commit(
        'SPEC-042 R2: arquivos restantes da etapa',
        trailer: 'Promptorium-Agente: app · SPEC-042 R2',
      );
      sonnet = await commit(
        'feat(sprints): concluir sprint',
        trailer: 'Promptorium-Agente: sonnet · SPEC-042 T4',
      );
    });
    final info = RepositoryInfo(path: repo, defaultBranch: 'main');
    final c = GraphController(
      CommitLog(GitService(repo), defaultBranch: 'main'),
    );
    await tester.runAsync(c.load);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gh = FakeGh();
    final ws = Workspace(
      id: 1,
      path: repo,
      name: 'repo',
      createdAt: DateTime(2026),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(_Settings.new),
          activeWorkspaceProvider.overrideWithValue(ws),
          repositoryInfoProvider.overrideWith((ref, p) async => info),
          gitServiceFactoryProvider.overrideWithValue(
            (root) => GitService(
              root,
              run: (exe, args) {
                calls.add(args);
                return Process.run(exe, args);
              },
            ),
          ),
          cliRunnerProvider.overrideWithValue(gh.call),
          specsProvider.overrideWith((ref, id) => Stream.value(const [])),
          sessionsProvider.overrideWith((ref, id) => Stream.value(const [])),
          graphBusyBranchesProvider.overrideWithValue(const {}),
          graphAuthorBadgeProvider.overrideWithValue(commitModelBadge),
          releasesProvider.overrideWith(
            (ref, repo) => Completer<ReleasesData>().future,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: GraphTab(repo: info, controller: c, watchRefs: false),
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byKey(ValueKey('graph-model-$sonnet')).evaluate().isNotEmpty) {
        break;
      }
    }
    // One `git log --no-walk` for every row on screen.
    final reads = calls.where((a) => a.contains('--no-walk=unsorted')).toList();
    expect(reads, hasLength(1));
    expect(reads.single, containsAll([sonnet, opus, app, plain]));

    String label(String sha) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(ValueKey('graph-model-$sha')),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .join();
    expect(label(sonnet), 'sonnet');
    expect(label(opus), 'opus');
    expect(label(app), 'app');
    expect(find.byKey(ValueKey('graph-model-$plain')), findsNothing);
    expect(modelColor('sonnet'), isNot(modelColor('opus')));

    await tester.tap(find.byKey(ValueKey('graph-model-$sonnet')));
    await tester.pump();
    expect(find.text('Commit feito por um agente'), findsOneWidget);
    expect(
      find.text('Promptorium-Agente: sonnet · SPEC-042 T4'),
      findsOneWidget,
    );
    final detail = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text.toPlainText())
        .join('\n');
    expect(
      detail,
      contains('Modelo sonnet, na etapa SPEC-042 T4. O autor no git continua'),
    );
  });
}
