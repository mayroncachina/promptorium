import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/debt_links_repo.dart';
import 'package:promptorium/features/debts/debt_board.dart';
import 'package:promptorium/features/debts/debt_files.dart';
import 'package:promptorium/features/debts/debt_item.dart';
import 'package:promptorium/features/debts/debt_payment.dart';
import 'package:promptorium/features/debts/debt_table.dart';
import 'package:promptorium/features/project/project_service.dart'
    show trashFolderProvider;
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/review/review_service.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/vibe/vibe_service.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../prompt/prompt_test_utils.dart';
import '../sessions/session_test_utils.dart' show settle;
import 'debt_board_test.dart' show debtsText;

const _file = 'DEBITO_TECNICO.md';

/// SPEC-112 R15, P4, P7: "Pagar" with the real VIBE, the merge of the
/// Revisão and the discard, on a temporary git repository.
void main() {
  late Directory tmp;
  late String repo;
  late AppDatabase db;
  late FakeAgentProvider provider;
  late ProviderContainer c;
  late Workspace ws;
  final trashed = <String>[];

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('debt-payment-');
    repo = await createRepo(tmp);
    File('$repo/$_file').writeAsStringSync(debtsText);
    await gitIn(repo, ['add', '.']);
    await gitIn(repo, ['commit', '-q', '-m', 'débitos']);
    db = memoryDatabase();
    provider = FakeAgentProvider();
    trashed.clear();
    c = ProviderContainer(
      overrides: [
        databaseOverride(db),
        ...fakeProviderOverrides(provider),
        gitServiceFactoryProvider.overrideWithValue(
          (root) => GitService(root, worktreesBase: '${tmp.path}/wt'),
        ),
        trashFolderProvider.overrideWithValue((p) async {
          trashed.add(p);
          await File(p).delete();
        }),
      ],
    );
    c.listen(conversationManagerProvider, (_, _) {});
    ws = await addWorkspace(db, repo);
    await c.read(appSettingsProvider.notifier).load();
  });

  tearDown(() async {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<List<DebtItem>> items(List<String> codes) async {
    final doc = await DebtFiles.read(repo, _file, DebtKind.debt);
    return [for (final x in codes) doc.debts.firstWhere((d) => d.code == x)];
  }

  DebtLinksRepo links() => c.read(debtLinksRepoProvider);

  Future<Map<String, DebtRowState>> states() async {
    final board = DebtBoard.build(
      snapshot: await DebtSnapshot.load(repo),
      links: await links().forRepo(repo),
      specs: await c.read(specsRepoProvider).watchByWorkspace(ws.id).first,
    );
    return {for (final d in board.debts) d.item.code: d.state};
  }

  String row(int n) =>
      '| DT-${n.toString().padLeft(2, '0')} | 2026-11-25 | **Item $n**: novo. | `x$n.py` | fazer |';

  test('pagar 2 débitos sugere VIBE; eles ficam em pagamento e o merge risca '
      'as linhas (e o "pago de carona?" confirmado) num commit da branch, '
      'juntando as linhas novas dos dois lados (P4)', () async {
    final picked = await items(['DT-05', 'DT-06']);
    final mode = suggestedPayMode(picked.length);
    expect(mode, DebtPayMode.vibe);
    final spec = await c
        .read(debtPaymentProvider)
        .pay(ws, picked, mode, file: _file);
    expect(spec.kind, SpecKind.vibe);
    expect(spec.code, 'VIBE-001');
    expect(
      provider.last.sent.single,
      startsWith('Pague os débitos DT-05 e DT-06 de $_file.\nDT-05 · '),
    );
    expect(
      {for (final l in await links().payingBy(spec.id)) l.code},
      {'DT-05', 'DT-06'},
    );
    var now = await states();
    expect(now['DT-05'], DebtRowState.paying);
    expect(now['DT-06'], DebtRowState.paying);
    expect(now['DT-03'], DebtRowState.open);

    // "Pago de carona?" do DT-03 confirmado; o do DT-04 ainda a confirmar.
    for (final (code, state) in [
      ('DT-03', DebtPiggybackState.confirmed),
      ('DT-04', DebtPiggybackState.toConfirm),
    ]) {
      final id = await links().ensure(repo, DebtKind.debt.dbName, code);
      await links().update(
        id,
        DebtLinksCompanion(
          piggybackSpecId: Value(spec.id),
          piggybackState: Value(state),
        ),
      );
    }

    final run = provider.last;
    run.emit(initLine(run.options.sessionId!));
    run.emit(resultLine());
    await settle();
    final wt = (await c.read(specsRepoProvider).getById(spec.id))!
        .worktreePath!;
    // O agente trabalha e cria o DT-10 na worktree…
    File('$wt/a.txt').writeAsStringSync('pago\n');
    File('$wt/$_file').writeAsStringSync('$debtsText${row(10)}\n');
    // …enquanto outra spec já levou o DT-09 para a branch principal.
    File('$repo/$_file').writeAsStringSync('$debtsText${row(9)}\n');
    await gitIn(repo, ['commit', '-q', '-am', 'docs: DT-09']);

    final report = await c.read(vibeServiceProvider).sendToReview(spec.id);
    expect(report.ok, isTrue, reason: report.encode());
    final session = (await c.read(sessionsRepoProvider).bySpec(spec.id)).single;
    final r = await c
        .read(reviewServiceProvider)
        .merge(session.id, override: 'teste');
    expect(r.warnings.where((w) => w.contains('DT-')), isEmpty);

    final doc = await DebtFiles.read(repo, _file, DebtKind.debt);
    final byCode = {for (final d in doc.debts) d.code: d};
    for (final code in ['DT-03', 'DT-05', 'DT-06']) {
      expect(byCode[code]!.paid, isTrue, reason: code);
      expect(byCode[code]!.resolvedBy, 'VIBE-001', reason: code);
      expect(byCode[code]!.raw, contains('**resolvido** pela [VIBE-001]('));
      expect(byCode[code]!.raw.trimRight(), endsWith('| — |'));
    }
    expect(byCode['DT-04']!.paid, isFalse);
    expect(byCode['DT-01']!.paid, isFalse);
    // P4: as linhas dos dois lados, em ordem de ID.
    expect(doc.debts.map((d) => d.code).skip(7), ['DT-08', 'DT-09', 'DT-10']);
    expect(doc.table.unrecognized, isEmpty);
    expect(File('$repo/$_file').readAsStringSync(), isNot(contains('<<<<')));
    expect(
      await gitIn(repo, ['log', '--format=%s']),
      contains('docs: DT-03, DT-05, DT-06 pagos pela VIBE-001'),
    );
    expect((await gitIn(repo, ['status', '--porcelain'])).trim(), isEmpty);
    now = await states();
    expect(now['DT-05'], DebtRowState.paid);
  });

  test('descartar a VIBE devolve os débitos a "aberto" e apaga o "pago de '
      'carona?" (P7)', () async {
    final spec = await c
        .read(debtPaymentProvider)
        .pay(ws, await items(['DT-01']), DebtPayMode.vibe, file: _file);
    final id = await links().ensure(repo, DebtKind.debt.dbName, 'DT-03');
    await links().update(
      id,
      DebtLinksCompanion(
        piggybackSpecId: Value(spec.id),
        piggybackState: const Value(DebtPiggybackState.confirmed),
      ),
    );
    expect((await states())['DT-01'], DebtRowState.paying);
    provider.last.emit(resultLine());
    await settle();

    await c.read(vibeServiceProvider).discard(spec.id);

    expect(await links().payingBy(spec.id), isEmpty);
    expect(await links().piggybackOf(spec.id), isEmpty);
    final dt03 = await links().byCode(repo, 'DT-03');
    expect(dt03!.piggybackState, isNull);
    expect((await states())['DT-01'], DebtRowState.open);
    // O arquivo da branch principal nunca foi tocado.
    expect(File('$repo/$_file').readAsStringSync(), debtsText);
  });

  test('pagar 3 débitos sugere spec "Pagar débitos: …" com um requisito por '
      'débito; excluir a spec devolve os débitos a "aberto"', () async {
    final picked = await items(['DT-03', 'DT-05', 'DT-06']);
    final mode = suggestedPayMode(picked.length);
    expect(mode, DebtPayMode.spec);
    final spec = await c
        .read(debtPaymentProvider)
        .pay(ws, picked, mode, file: _file);
    expect(spec.kind, SpecKind.spec);
    expect(spec.title, 'Pagar débitos: DT-03, DT-05, DT-06');
    expect(spec.requirements.map((r) => r.id), ['R1', 'R2', 'R3']);
    final text = File('$repo/${spec.path}').readAsStringSync();
    expect(text, contains('- R2 · Pagar o DT-05 (Pagamento simulado)'));
    expect(provider.runs, isEmpty);
    final now = await states();
    expect([
      for (final x in ['DT-03', 'DT-05', 'DT-06']) now[x],
    ], everyElement(DebtRowState.paying));

    await c.read(specServiceProvider).delete(ws, spec);

    expect(trashed, hasLength(1));
    expect(await links().payingBy(spec.id), isEmpty);
    expect((await states())['DT-05'], DebtRowState.open);
  });
}
