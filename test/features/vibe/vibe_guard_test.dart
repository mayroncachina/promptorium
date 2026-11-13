import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/vibe/vibe_flow.dart';
import 'package:promptorium/features/vibe/vibe_guard.dart';
import 'package:promptorium/features/vibe/vibe_service.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../prompt/prompt_test_utils.dart';
import '../sessions/session_test_utils.dart' show settle;

/// Proteções (SPEC-069 R5, R6, R8).
void main() {
  test('VibeSize: the label, the ratio and the cap', () {
    const cap = VibeConfig();
    const s = VibeSize(files: 2, lines: 13);
    expect(s.label(cap), '2/15 arquivos · 13/400 linhas');
    expect(s.over(cap), isFalse);
    const big = VibeSize(files: 18, lines: 520);
    expect(big.over(cap), isTrue);
    expect(big.over(cap, threshold: 1.5), isFalse);
    expect(big.ratio(cap), closeTo(1.3, .01));
  });

  test('touchesScreen: screens, widgets, styles', () {
    expect(touchesScreen(['lib/widgets/buy_button.dart']), isTrue);
    expect(touchesScreen(['lib/home_screen.dart']), isTrue);
    expect(touchesScreen(['web/style.css']), isTrue);
    expect(touchesScreen(['lib/core/parser.dart', 'README.md']), isFalse);
  });

  test('unrelatedPrompt has only the title, the diff, what was accepted '
      'and the request', () {
    final p = unrelatedPrompt(
      title: 'Botão Comprar verde',
      changed: ['lib/widgets/buy_button.dart'],
      accepted: ['troca o texto do login'],
      request: 'arruma o rodapé',
    );
    expect(p, contains('Botão Comprar verde'));
    expect(p, contains('lib/widgets/buy_button.dart'));
    expect(p, contains('troca o texto do login'));
    expect(p, contains('arruma o rodapé'));
    expect(const UnrelatedVerdict(unrelated: true, confidence: .9).ask, isTrue);
    expect(
      const UnrelatedVerdict(unrelated: true, confidence: .6).ask,
      isFalse,
      reason: 'only asks with high confidence',
    );
  });

  group('with a VIBE', () {
    late Directory tmp;
    late String repo;
    late AppDatabase db;
    late FakeAgentProvider provider;
    late ProviderContainer c;
    late Workspace ws;
    late List<({String request, List<String> accepted})> checks;
    late UnrelatedVerdict Function(String request, List<String> accepted)
    verdict;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('vibe-guard-');
      repo = await createRepo(tmp);
      db = memoryDatabase();
      provider = FakeAgentProvider();
      checks = [];
      verdict = (_, _) =>
          const UnrelatedVerdict(unrelated: false, confidence: .9);
      c = ProviderContainer(
        overrides: [
          databaseOverride(db),
          ...fakeProviderOverrides(provider),
          gitServiceFactoryProvider.overrideWithValue(
            (root) => GitService(root, worktreesBase: '${tmp.path}/wt'),
          ),
          unrelatedRequestProvider.overrideWithValue(({
            required vibe,
            required changed,
            required accepted,
            required request,
          }) async {
            checks.add((request: request, accepted: List.of(accepted)));
            return verdict(request, accepted);
          }),
        ],
      );
      c.listen(conversationManagerProvider, (_, _) {});
      c.listen(vibeFlowProvider, (_, _) {});
      ws = await addWorkspace(db, repo);
      await c.read(appSettingsProvider.notifier).load();
    });

    tearDown(() async {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    void config(String yaml) {
      File('$repo/.promptorium/config.yml')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(yaml);
    }

    Future<({Spec spec, int conv})> start() async {
      final r = await c.read(vibeServiceProvider).start(ws, 'Botão verde');
      provider.last.emit(initLine(provider.last.options.sessionId!));
      provider.last.emit(resultLine());
      await settle();
      return (spec: r.spec, conv: r.conversationId);
    }

    void edit(Spec spec, String rel, int lines) {
      final wt = spec.worktreePath!;
      File('$wt/$rel')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(List.filled(lines, 'x').join('\n'));
    }

    test('the size leaves the VIBE file out', () async {
      final v = await start();
      final spec = (await c.read(specsRepoProvider).getById(v.spec.id))!;
      edit(spec, 'lib/a.dart', 3);
      final size = await vibeSize(
        GitService(spec.worktreePath!),
        base: 'main',
        ownFile: spec.path,
      );
      expect(size.files, 1);
      expect(size.lines, 3);
      expect(size.paths, ['lib/a.dart']);
    });

    test('R8: below the cap the request goes; above it the request waits '
        'for the choice; "Continuar como VIBE" asks again at 150%', () async {
      config('vibe:\n  teto:\n    arquivos: 2\n    linhas: 400\n');
      final v = await start();
      final spec = (await c.read(specsRepoProvider).getById(v.spec.id))!;
      final flow = c.read(vibeFlowProvider.notifier);
      edit(spec, 'lib/a.dart', 1);
      expect(await flow.submit(v.conv, 'mais um'), isTrue);
      expect(provider.last.sent.last, 'mais um');

      edit(spec, 'lib/b.dart', 1);
      edit(spec, 'lib/c.dart', 1);
      expect(await flow.submit(v.conv, 'e o checkout'), isFalse);
      expect(provider.last.sent.last, 'mais um', reason: 'blocked');
      final p = c.read(vibeFlowProvider)[v.conv]!;
      expect(p.ask, VibeAsk.cap);
      expect(p.size!.files, 3);

      await flow.continueAsVibe(v.conv, spec.id);
      expect(flow.threshold(spec.id), 1.5);
      expect(provider.last.sent.last, 'e o checkout');
      expect(c.read(vibeFlowProvider)[v.conv], isNull);

      // 3 files is under 150% of 2; 4 is over.
      edit(spec, 'lib/d.dart', 1);
      expect(await flow.submit(v.conv, 'mais'), isFalse);
      expect(c.read(vibeFlowProvider)[v.conv]!.ask, VibeAsk.cap);
    });

    test('R5: an unrelated request waits; "Continuar nesta" runs it and does '
        'not ask again about it', () async {
      final v = await start();
      final flow = c.read(vibeFlowProvider.notifier);
      verdict = (request, accepted) => UnrelatedVerdict(
        unrelated: !accepted.any((a) => a.contains('login')),
        confidence: .95,
        reason: 'é a tela de login',
      );
      expect(await flow.submit(v.conv, 'troca o texto do login'), isFalse);
      expect(provider.last.sent, ['Botão verde'], reason: 'not executed');
      expect(c.read(vibeFlowProvider)[v.conv]!.ask, VibeAsk.unrelated);

      await flow.continueHere(v.conv, v.spec.id);
      expect(provider.last.sent.last, 'troca o texto do login');
      expect(await flow.submit(v.conv, 'e o subtítulo do login'), isTrue);
      expect(checks.last.accepted, ['troca o texto do login']);
      expect(provider.last.sent.last, 'e o subtítulo do login');
    });

    test('R5: "Abrir VIBE nova" takes the request to a new VIBE', () async {
      final v = await start();
      final flow = c.read(vibeFlowProvider.notifier);
      verdict = (_, _) =>
          const UnrelatedVerdict(unrelated: true, confidence: .9);
      expect(await flow.submit(v.conv, 'arruma o rodapé'), isFalse);
      final id = await flow.openNew(v.conv, ws);
      expect(id, isNot(v.conv));
      final other = await c.read(specsRepoProvider).ofConversation(id!);
      expect(other!.code, 'VIBE-002');
      expect(provider.last.sent, ['arruma o rodapé']);
      expect(provider.runs.first.sent, ['Botão verde']);
    });

    test('a failing check does not block the request', () async {
      final v = await start();
      verdict = (_, _) => throw StateError('sem claude');
      expect(
        await c.read(vibeFlowProvider.notifier).submit(v.conv, 'mais'),
        isTrue,
      );
    });

    test('R6: a diff on a screen brings the prints to the Review (taken by '
        'vibe.prints, "antes" never in the main checkout)', () async {
      config('vibe:\n  prints: "pwd > {saida}"\n');
      final v = await start();
      final spec = (await c.read(specsRepoProvider).getById(v.spec.id))!;
      edit(spec, 'lib/widgets/buy_button.dart', 4);
      final report = await c.read(vibeServiceProvider).sendToReview(spec.id);
      expect(report.ok, isTrue, reason: report.encode());
      final dir = '${spec.worktreePath}/${vibePrintsDir(spec.code)}';
      final before = File('$dir/antes.png').readAsStringSync().trim();
      final after = File('$dir/depois.png').readAsStringSync().trim();
      expect(before, isNot(repo));
      expect(before, isNot(spec.worktreePath));
      expect(after, spec.worktreePath);
      expect(await gitIn(spec.worktreePath!, ['status', '--porcelain']), '');
      expect(
        await gitIn(repo, ['status', '--porcelain']),
        '?? .promptorium/\n',
      );
    });

    test('R6: without the prints a diff on a screen does not pass', () async {
      final v = await start();
      final spec = (await c.read(specsRepoProvider).getById(v.spec.id))!;
      edit(spec, 'lib/widgets/buy_button.dart', 4);
      final report = await c.read(vibeServiceProvider).sendToReview(spec.id);
      expect(report.ok, isFalse);
      expect(report.failures.single.name, 'prints');
      final now = (await c.read(specsRepoProvider).getById(spec.id))!;
      expect(now.stage, SpecStage.running);
    });

    test('R8: "Virar spec" writes SPEC-NNN with origem, in the same worktree '
        'and branch, with the prints as Telas', () async {
      final v = await start();
      var spec = (await c.read(specsRepoProvider).getById(v.spec.id))!;
      final dir = '${spec.worktreePath}/${vibePrintsDir(spec.code)}';
      Directory(dir).createSync(recursive: true);
      File('$dir/antes.png').writeAsStringSync('a');
      File('$dir/depois.png').writeAsStringSync('b');
      edit(spec, 'lib/a.dart', 3);
      final vibeFile = spec.path;
      final promoted = await c
          .read(vibeServiceProvider)
          .promote(
            spec.id,
            transcript: const [
              (user: true, text: 'Botão verde'),
              (user: false, text: 'Feito.'),
              (user: true, text: 'Agora o checkout inteiro'),
            ],
          );
      expect(promoted.code, 'SPEC-001');
      expect(promoted.kind, SpecKind.spec);
      expect(promoted.status, SpecStatus.draft);
      expect(promoted.worktreePath, spec.worktreePath);
      expect(promoted.branch, spec.branch);
      expect(promoted.stage, SpecStage.running);
      expect(promoted.requirements.map((r) => r.text), [
        'Botão verde',
        'Agora o checkout inteiro',
      ]);
      expect(File('${spec.worktreePath}/$vibeFile').existsSync(), isFalse);
      final text = File('${spec.worktreePath}/${promoted.path}')
          .readAsStringSync();
      final doc = SpecDocument.parse(text);
      expect(doc.origin, 'VIBE-001');
      expect(doc.id, 'SPEC-001');
      expect(text, contains('## Telas'));
      expect(text, contains('vibe-001/antes.png'));
      expect(File('${spec.worktreePath}/lib/a.dart').existsSync(), isTrue);
      // The conversation goes on in the same worktree.
      spec = (await c.read(specsRepoProvider).ofConversation(v.conv))!;
      expect(spec.id, promoted.id);
      // The VIBE number is not given back.
      expect(
        await nextSpecCode(c.read(specsRepoProvider), ws, kind: SpecKind.vibe),
        'VIBE-002',
      );
    });
  });
}
