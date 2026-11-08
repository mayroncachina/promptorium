import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/gh_cli.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/home/tray_radar.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/repository/releases/release_dispatcher.dart';
import 'package:promptorium/features/sessions/app_notifier.dart';
import 'package:promptorium/core/tray_service.dart';

import '../../helpers/test_db.dart';
import 'fake_gh.dart';

class _Settings extends AppSettingsController {
  _Settings(this.initial);

  final Map<String, String> initial;

  @override
  Map<String, String> build() => initial;

  @override
  Future<void> set(String key, String value) async =>
      state = {...state, key: value};

  @override
  Future<void> remove(String key) async => state = {...state}..remove(key);
}

class _Notifier implements AppNotifier {
  final shown = <(String, String)>[];

  @override
  Future<void> show(String title, String body, {VoidCallback? onClick}) async =>
      shown.add((title, body));
}

class _Timer implements Timer {
  _Timer(this.every);

  final Duration every;
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

const _createRelease = '''
name: Criar Release
on:
  workflow_dispatch:
    inputs:
      version:
        description: Versão
''';

ReleaseWorkflow _w(String file, {String name = '', bool dispatch = true}) =>
    ReleaseWorkflow(file: file, name: name, dispatch: dispatch);

/// A container with `gh` faked, the settings in memory and the ticker
/// recorded.
class _Env {
  _Env({Map<String, String> settings = const {}, FakeGh? gh})
    : gh = gh ?? FakeGh() {
    c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        appSettingsProvider.overrideWith(
          () => this.settings = _Settings(settings),
        ),
        cliRunnerProvider.overrideWithValue(this.gh.call),
        appNotifierProvider.overrideWithValue(notifier),
        releaseTickerProvider.overrideWithValue((every, tick) {
          final t = _Timer(every);
          timers.add(t);
          return t;
        }),
      ],
    );
    c.read(appSettingsProvider);
  }

  final FakeGh gh;
  late final ProviderContainer c;
  late _Settings settings;
  final notifier = _Notifier();
  final timers = <_Timer>[];

  ReleaseDispatcher get d => c.read(releaseDispatcherProvider.notifier);
  ReleaseRun? get run => c.read(releaseDispatcherProvider)[1];
  Duration? get activeEvery =>
      timers.where((t) => !t.cancelled).lastOrNull?.every;

  Future<ReleaseRun> dispatch({ReleasePath? path}) => d.dispatch(
    workspaceId: 1,
    repoPath: '/r',
    branch: 'main',
    version: '0.12.0',
    tag: 'v0.12.0',
    path:
        path ??
        resolveReleasePath(const ReleasesConfig(), [
          parseWorkflow('create-release.yml', _createRelease)!,
        ]),
    changelog: '## [0.12.0]\n',
    now: DateTime.utc(2026, 11, 8, 21, 58),
  );
}

Map<String, Object?> _runRow(int id, String createdAt) => {
  'databaseId': id,
  'status': 'queued',
  'conclusion': '',
  'createdAt': createdAt,
  'url': 'https://github.com/o/r/actions/runs/$id',
  'displayTitle': 'Criar Release',
  'headBranch': 'main',
};

Map<String, Object?> _view(
  String status, {
  String conclusion = '',
  List<Map<String, Object?>>? jobs,
}) => {
  'databaseId': 42,
  'status': status,
  'conclusion': conclusion,
  'url': 'https://github.com/o/r/actions/runs/42',
  'jobs':
      jobs ??
      [
        {
          'name': 'prepare',
          'status': 'completed',
          'conclusion': 'success',
          'steps': <Object>[],
        },
        {
          'name': 'package / package',
          'status': 'in_progress',
          'conclusion': '',
          'steps': [
            {'name': 'Build', 'number': 5, 'status': 'in_progress'},
          ],
        },
      ],
};

void main() {
  group('R6 · the path of the release', () {
    test("the repository's workflows: only create-release.yml is a "
        'candidate, with its version input', () {
      final ws = readWorkflows(Directory.current.path);
      final byFile = {for (final w in ws) w.file: w};
      expect(byFile['create-release.yml']!.isReleaseCandidate, isTrue);
      expect(byFile['create-release.yml']!.name, 'Criar Release');
      expect(byFile['create-release.yml']!.inputs, ['version']);
      // release.yml is called by it (workflow_call), windows.yml has no
      // "release" in it.
      expect(byFile['release.yml']!.isReleaseCandidate, isFalse);
      expect(byFile['windows.yml']!.isReleaseCandidate, isFalse);
      final path = resolveReleasePath(const ReleasesConfig(), ws);
      expect(path.kind, ReleasePathKind.discovered);
      expect(
        path.command(branch: 'main', version: '0.12.0'),
        'gh workflow run create-release.yml --ref main -f version=0.12.0',
      );
    });

    test('order: config, then the only candidate, then a draft', () {
      final ws = [
        _w('create-release.yml', name: 'Criar Release'),
        _w('deploy.yml', name: 'Deploy'),
      ];
      final configured = resolveReleasePath(
        const ReleasesConfig(workflow: 'deploy.yml', input: 'tag'),
        ws,
      );
      expect(configured.kind, ReleasePathKind.configured);
      expect(configured.workflow!.file, 'deploy.yml');
      expect(configured.input, 'tag');
      expect(configured.origin, 'de .promptorium/config.yml');

      final found = resolveReleasePath(const ReleasesConfig(), ws);
      expect(found.kind, ReleasePathKind.discovered);
      expect(found.workflow!.file, 'create-release.yml');
      expect(found.input, 'version');

      final none = resolveReleasePath(const ReleasesConfig(), [
        _w('ci.yml', name: 'CI'),
        _w('release.yml', name: 'Release', dispatch: false),
      ]);
      expect(none.kind, ReleasePathKind.draft);
      expect(none.isWorkflow, isFalse);
    });

    test('two candidates and nothing configured: the dialog asks', () {
      final path = resolveReleasePath(const ReleasesConfig(), [
        _w('create-release.yml', name: 'Criar Release'),
        _w('release-beta.yml', name: 'Beta'),
      ]);
      expect(path.kind, ReleasePathKind.ambiguous);
      expect(path.isWorkflow, isFalse);
      expect(path.candidates.map((w) => w.file), [
        'create-release.yml',
        'release-beta.yml',
      ]);
      final chosen = path.choose(path.candidates.last);
      expect(chosen.workflow!.file, 'release-beta.yml');
    });

    test('the input: configured, version, or the only one', () {
      expect(
        inputFor(const ReleaseWorkflow(file: 'a', inputs: ['tag']), null),
        'tag',
      );
      expect(
        inputFor(const ReleaseWorkflow(file: 'a', inputs: ['tag', 'x']), null),
        'version',
      );
      expect(inputFor(const ReleaseWorkflow(file: 'a'), 'v'), 'v');
    });

    test('releases: in the config is read and written back', () {
      final c = ProjectConfig.parse(
        'specs: docs/specs\nreleases:\n  workflow: create-release.yml\n'
        '  input: version\n',
      );
      expect(c.releases.workflow, 'create-release.yml');
      expect(c.releases.input, 'version');
      expect(ProjectConfig.parse(c.toYaml()).releases, c.releases);
      expect(const ProjectConfig().releases.isDefault, isTrue);
      expect(const ProjectConfig().toYaml(), isNot(contains('releases')));
    });
  });

  group('R7 · following the run', () {
    test('dispatch, find the first run after it, read the jobs', () async {
      final env = _Env();
      addTearDown(env.c.dispose);
      final run = await env.dispatch();
      expect(env.gh.ghCalls('workflow run').single, [
        'workflow',
        'run',
        'create-release.yml',
        '--ref',
        'main',
        '-f',
        'version=0.12.0',
      ]);
      expect(run.status, ReleaseRunStatus.finding);
      // Polls at 60 s while the tab is not on screen, 10 s on it.
      expect(env.activeEvery, releasePollOffScreen);
      env.d.setVisible(true);
      expect(env.activeEvery, releasePollOnScreen);
      env.d.setVisible(false);
      expect(env.activeEvery, releasePollOffScreen);

      // Not listed yet.
      await env.d.poll(1, now: DateTime.utc(2026, 11, 8, 21, 58, 5));
      expect(env.run!.runId, isNull);
      expect(env.run!.error, isNull);

      env.gh.runLists = [
        [
          _runRow(43, '2026-11-08T21:58:04Z'),
          _runRow(42, '2026-11-08T21:58:02Z'),
          _runRow(40, '2026-11-08T20:00:00Z'),
        ],
      ];
      env.gh.runViews = [_view('in_progress')];
      await env.d.poll(1);
      expect(env.gh.ghCalls('run list').last, [
        'run',
        'list',
        '--workflow',
        'create-release.yml',
        '--event',
        'workflow_dispatch',
        '--limit',
        '10',
        '--json',
        GhCli.runFields,
      ]);
      expect(env.run!.runId, 42);
      expect(env.run!.status, ReleaseRunStatus.running);
      expect(env.run!.jobs.map((j) => j.name), [
        'prepare',
        'package / package',
      ]);
      expect(env.run!.doneJobs, 1);
      expect(env.gh.ghCalls('run view').last.take(3), ['run', 'view', '42']);
    });

    test('the run comes back after the app reopens, by the saved id', () async {
      final first = _Env()
        ..gh.runLists = [
          [_runRow(42, '2026-11-08T21:58:02Z')],
        ]
        ..gh.runViews = [_view('in_progress')];
      await first.dispatch();
      await first.d.poll(1);
      final saved = Map.of(first.settings.state);
      first.c.dispose();
      expect(saved[ReleaseDispatcher.settingKey(1)], contains('"runId":42'));

      final again = _Env(settings: saved)..gh.runViews = [_view('in_progress')];
      addTearDown(again.c.dispose);
      expect(again.run, isNull);
      await again.d.resume();
      expect(again.run!.runId, 42);
      expect(again.run!.tag, 'v0.12.0');
      expect(again.run!.jobs, hasLength(2));
      // Found by id: no new search.
      expect(again.gh.ghCalls('run list'), isEmpty);
      expect(again.activeEvery, releasePollOffScreen);
    });

    test('cancel asks gh to stop the run', () async {
      final env = _Env()
        ..gh.runLists = [
          [_runRow(42, '2026-11-08T21:58:02Z')],
        ]
        ..gh.runViews = [_view('in_progress')];
      addTearDown(env.c.dispose);
      await env.dispatch();
      await env.d.poll(1);
      env.gh.runViews = [_view('completed', conclusion: 'cancelled')];
      await env.d.cancel(1);
      expect(env.gh.ghCalls('run cancel').single, ['run', 'cancel', '42']);
      expect(env.run!.status, ReleaseRunStatus.cancelled);
    });

    test('a run that never shows up says so after a while', () async {
      final env = _Env();
      addTearDown(env.c.dispose);
      await env.dispatch();
      await env.d.poll(1, now: DateTime.utc(2026, 11, 8, 22, 10));
      expect(env.run!.error, contains('não apareceu'));
    });
  });

  group('R8 · the end', () {
    test(
      'success: notification, the PR of the version, the poll stops',
      () async {
        final env = _Env()
          ..gh.runLists = [
            [_runRow(42, '2026-11-08T21:58:02Z')],
          ]
          ..gh.runViews = [_view('completed', conclusion: 'success')]
          ..gh.prs = [
            {
              'number': 120,
              'url': 'https://github.com/o/r/pull/120',
              'title': 'chore(release): v0.12.0',
              'headRefName': 'release/v0.12.0',
              'state': 'OPEN',
            },
          ];
        addTearDown(env.c.dispose);
        await env.dispatch();
        await env.d.poll(1);
        expect(env.run!.status, ReleaseRunStatus.success);
        expect(env.run!.prUrl, 'https://github.com/o/r/pull/120');
        expect(env.run!.prNumber, 120);
        expect(
          env.gh.ghCalls('pr list').first,
          containsAllInOrder(['--head', 'release/v0.12.0']),
        );
        expect(env.notifier.shown.single.$1, 'v0.12.0 publicada');
        expect(env.activeEvery, isNull);
        final saved = await env.c.read(notificationsRepoProvider).recent();
        expect(saved.single.title, 'v0.12.0 publicada');
        expect(saved.single.section, 'repository');

        await env.d.dismiss(1);
        expect(env.run, isNull);
        expect(
          env.settings.state.containsKey(ReleaseDispatcher.settingKey(1)),
          isFalse,
        );
      },
    );

    test('failure: the job and step that failed and the last 40 lines of '
        '--log-failed', () async {
      final env = _Env()
        ..gh.runLists = [
          [_runRow(42, '2026-11-08T21:58:02Z')],
        ]
        ..gh.runViews = [
          _view(
            'completed',
            conclusion: 'failure',
            jobs: [
              {
                'name': 'prepare',
                'status': 'completed',
                'conclusion': 'success',
                'steps': <Object>[],
              },
              {
                'name': 'package / package',
                'status': 'completed',
                'conclusion': 'failure',
                'steps': [
                  {
                    'name': 'Versão do pubspec.yaml confere com a tag',
                    'number': 4,
                    'status': 'completed',
                    'conclusion': 'success',
                  },
                  {
                    'name': 'Run ./.github/actions/build-deb',
                    'number': 5,
                    'status': 'completed',
                    'conclusion': 'failure',
                  },
                ],
              },
            ],
          ),
        ]
        ..gh.failedLog = [
          for (var i = 1; i <= 60; i++)
            'package / package\tBuild\t2026-11-08T22:01:00Z linha $i',
        ].join('\n');
      addTearDown(env.c.dispose);
      await env.dispatch();
      await env.d.poll(1);
      final run = env.run!;
      expect(run.status, ReleaseRunStatus.failure);
      expect(run.failedJob, 'package / package');
      expect(run.failedStep, 'Run ./.github/actions/build-deb');
      expect(run.failedLog, hasLength(40));
      expect(run.failedLog.first, endsWith('linha 21'));
      expect(run.failedLog.last, endsWith('linha 60'));
      expect(env.gh.ghCalls('run view').last, [
        'run',
        'view',
        '42',
        '--log-failed',
      ]);
      expect(env.notifier.shown.single.$1, 'Release v0.12.0 falhou');
      expect(env.notifier.shown.single.$2, contains('package / package'));
    });

    test('the tray shows the release while it runs and how it ended', () {
      TrayStatus radar(ReleaseRunStatus s) => buildTrayRadar([
        RadarWorkspace(
          id: 1,
          name: 'promptorium',
          releases: [
            RadarRelease(tag: 'v0.12.0', status: s, doneJobs: 1, jobs: 4),
          ],
        ),
      ]).status;
      final running = radar(ReleaseRunStatus.running);
      expect(running.state, TrayState.working);
      expect(
        running.rows.map((r) => r.label),
        containsAll(['Releases', 'release v0.12.0 · 1 de 4 jobs']),
      );
      final ok = radar(ReleaseRunStatus.success);
      expect(ok.state, TrayState.idle);
      expect(ok.rows.map((r) => r.label), contains('v0.12.0 publicada'));
      expect(radar(ReleaseRunStatus.failure).state, TrayState.problem);
      final targets = buildTrayRadar([
        const RadarWorkspace(
          id: 1,
          name: 'p',
          releases: [
            RadarRelease(tag: 'v1.0.0', status: ReleaseRunStatus.running),
          ],
        ),
      ]).targets;
      expect(targets['release:1']!.section.name, 'repository');
    });
  });

  group('R6.3 and R9', () {
    test('without a workflow: a draft with the preview as notes', () async {
      final env = _Env();
      addTearDown(env.c.dispose);
      final run = await env.dispatch(
        path: resolveReleasePath(const ReleasesConfig(), const []),
      );
      final args = env.gh.ghCalls('release create').single;
      expect(args.take(3), ['release', 'create', 'v0.12.0']);
      expect(args, containsAllInOrder(['--target', 'main', '--draft']));
      expect(args, contains('--notes-file'));
      expect(run.status, ReleaseRunStatus.draftCreated);
      expect(run.releaseUrl, env.gh.draftUrl);
      expect(env.gh.ghCalls('workflow run'), isEmpty);
      expect(env.activeEvery, isNull);
    });

    test('without gh the dispatch fails and nothing is followed', () async {
      final env = _Env(gh: FakeGh(hasGh: false));
      addTearDown(env.c.dispose);
      await expectLater(env.dispatch(), throwsA(isA<GhException>()));
      expect(env.run, isNull);
      expect(env.timers, isEmpty);
    });
  });
}
