import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/mcp/app_mcp_tools.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/debt_links_repo.dart';
import 'package:promptorium/features/debts/debt_files.dart';
import 'package:promptorium/features/debts/debt_service.dart';
import 'package:promptorium/features/debts/debt_table.dart';
import 'package:promptorium/features/debts/widgets/debt_suggestions_strip.dart';
import 'package:promptorium/features/project/project_config.dart';

import '../../helpers/test_db.dart';
import 'debts_screen_test.dart' show boardOf, pumpScreen;

/// The service without I/O: records accept and discard.
class _FakeDebtService extends DebtService {
  _FakeDebtService(AppDatabase db) : super(links: DebtLinksRepo(db));

  final accepted = <(int, DebtDraft?)>[];
  final discarded = <int>[];

  @override
  DebtsConfig configOf(String repoRoot) => const DebtsConfig();

  @override
  Future<bool> isDirty(String repoRoot, String rel) async => false;

  @override
  Future<DebtWritten> accept(
    int linkId, {
    DebtDraft? edited,
    String? writeRoot,
  }) async {
    accepted.add((linkId, edited));
    return DebtWritten(
      code: 'DT-10',
      linkId: linkId,
      root: '/r',
      relPath: 'DEBITO_TECNICO.md',
    );
  }

  @override
  Future<void> discard(int linkId) async => discarded.add(linkId);
}

DebtLink _mcp(int id, String provider, {String kind = 'debito'}) => DebtLink(
  id: id,
  repoRoot: '/r',
  kind: kind,
  originSessionId: 's-$id',
  suggestionState: DebtSuggestionState.pending,
  suggestionSource: DebtSuggestionSource.mcp,
  suggestionBody: jsonEncode({
    'titulo': 'Comprovante sem QR Code de conferência',
    'onde': 'ComprovanteView.vue',
    DebtSuggestionKeys.provider: provider,
    DebtSuggestionKeys.sessionTitle: 'Tela de comprovante',
  }),
  createdAt: DateTime(2026),
);

/// SPEC-112 R11, R13: the "Sugestões do agente" strip.
void main() {
  test('the label names the provider of the MCP', () {
    expect(suggestionProviderLabel('codex'), 'Codex · MCP');
    expect(suggestionProviderLabel('claude'), 'Claude · MCP');
    expect(suggestionProviderLabel(''), 'MCP');
  });

  testWidgets('an MCP suggestion shows "Codex · MCP" / "Claude · MCP" and '
      'the session it came from', (tester) async {
    await pumpScreen(
      tester,
      boardOf(links: [_mcp(5, 'codex'), _mcp(6, 'claude')]),
    );
    expect(find.text('SUGESTÕES DO AGENTE · 2'), findsOneWidget);
    expect(find.text('Codex · MCP'), findsOneWidget);
    expect(find.text('Claude · MCP'), findsOneWidget);
    expect(
      find.textContaining('sessão “Tela de comprovante”', findRichText: true),
      findsNWidgets(2),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('Aceitar writes through the service and gives the code; '
      'Descartar only discards', (tester) async {
    final db = memoryDatabase();
    final fake = _FakeDebtService(db);
    await pumpScreen(
      tester,
      boardOf(links: [_mcp(5, 'codex'), _mcp(6, 'claude')]),
      overrides: [debtServiceProvider.overrideWithValue(fake)],
    );
    await tester.tap(find.byKey(const ValueKey('debt-suggestion-discard-6')));
    await tester.pump();
    expect(fake.discarded, [6]);
    expect(fake.accepted, isEmpty);

    await tester.tap(find.byKey(const ValueKey('debt-suggestion-accept-5')));
    await tester.pumpAndSettle();
    expect(fake.accepted.single.$1, 5);
    expect(fake.discarded, [6]);
    // No worktree: the own commit is offered for the new code (R18).
    expect(find.text('Commitar o DT-10?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('debt-commit-later')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await db.close();
  });

  group('the service (R11, R13)', () {
    late Directory dir;
    late AppDatabase db;
    late DebtService service;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('debt_strip_');
      db = memoryDatabase();
      service = DebtService(
        links: DebtLinksRepo(db),
        now: () => DateTime(2026, 11, 24),
      );
    });
    tearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    const draft = DebtDraft(
      kind: DebtKind.debt,
      title: 'Comprovante sem QR Code',
      where: 'ComprovanteView.vue',
    );

    test('accepting an MCP suggestion writes the row and gives the code; '
        'the provider stays out of the file', () async {
      final id = await service.suggest(
        dir.path,
        draft,
        source: DebtSuggestionSource.mcp,
        extra: {DebtSuggestionKeys.provider: 'codex'},
        link: const DebtLinksCompanion(originSessionId: Value('s-1')),
      );
      expect(File('${dir.path}/DEBITO_TECNICO.md').existsSync(), isFalse);
      final w = await service.accept(id);
      expect(w.code, 'DT-01');
      final l = (await service.links.byId(id))!;
      expect(
        (l.code, l.suggestionState, l.originSessionId),
        ('DT-01', DebtSuggestionState.accepted, 's-1'),
      );
      final text = File('${dir.path}/DEBITO_TECNICO.md').readAsStringSync();
      expect(text, contains('| DT-01 | 2026-11-24 | **Comprovante sem QR '));
      expect(text, isNot(contains('codex')));
    });

    test('discarding writes nothing', () async {
      final id = await service.suggest(
        dir.path,
        draft,
        source: DebtSuggestionSource.mcp,
      );
      await service.discard(id);
      final l = (await service.links.byId(id))!;
      expect(
        (l.code, l.suggestionState),
        (null, DebtSuggestionState.discarded),
      );
      expect(File('${dir.path}/DEBITO_TECNICO.md').existsSync(), isFalse);
      expect((await DebtSnapshot.load(dir.path)).debts.debts, isEmpty);
    });
  });
}
