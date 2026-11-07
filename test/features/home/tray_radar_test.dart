import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/tray_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/home/home_inbox.dart';
import 'package:promptorium/features/home/tray_radar.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/review/review_service.dart'
    show selectedReviewProvider;
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/ui/shell/navigation.dart';

import '../../helpers/test_db.dart';

InboxItem item(
  InboxKind kind,
  String ref, {
  String title = 'Título',
  String? session,
  int? conversation,
  int minute = 0,
}) => InboxItem(
  kind: kind,
  ref: ref,
  title: title,
  detail: '',
  at: DateTime(2026, 11, 6, 12, minute),
  sessionId: session,
  conversationId: conversation,
);

RadarWorkspace ws(
  int id, {
  String name = 'promptorium',
  List<InboxItem> items = const [],
  List<RadarSession> running = const [],
}) => RadarWorkspace(
  id: id,
  name: name,
  inbox: [
    for (final kind in InboxKind.values)
      if (items.any((i) => i.kind == kind))
        InboxGroup(kind, items.where((i) => i.kind == kind).toList()),
  ],
  running: running,
);

RadarSession run(String id, {int minute = 0}) => RadarSession(
  id: id,
  ref: 'SPEC-001 · R1',
  title: 'Sessão $id',
  startedAt: DateTime(2026, 11, 6, 12, minute),
);

List<String> labels(TrayRadar radar) => [
  for (final row in radar.status.rows)
    if (!row.isSeparator) row.label,
];

void main() {
  group('R1: estado do ícone', () {
    TrayState stateOf(List<InboxItem> items, {bool running = false}) =>
        buildTrayRadar([
          ws(1, items: items, running: running ? [run('s')] : const []),
        ]).status.state;

    test('sem nada: Parado', () {
      expect(stateOf(const []), TrayState.idle);
    });

    test('sessão rodando: Trabalhando', () {
      expect(stateOf(const [], running: true), TrayState.working);
    });

    test('PR com problema vence Trabalhando', () {
      expect(
        stateOf([item(InboxKind.prProblem, 'PR')], running: true),
        TrayState.problem,
      );
    });

    test('aprovação e resposta vencem Problema', () {
      final pr = item(InboxKind.prProblem, 'PR');
      expect(stateOf([pr, item(InboxKind.approval, 'A')]), TrayState.attention);
      expect(
        stateOf([pr, item(InboxKind.needsAnswer, 'B')]),
        TrayState.attention,
      );
    });

    test('review e interrompida não mudam o ícone, mas entram no menu', () {
      final radar = buildTrayRadar([
        ws(
          1,
          items: [
            item(InboxKind.review, 'SPEC-039', title: 'Revisar'),
            item(InboxKind.interrupted, 'SPEC-038', title: 'Parou'),
          ],
        ),
      ]);
      expect(radar.status.state, TrayState.idle);
      expect(labels(radar), [
        '2 precisam de você',
        'Precisa de você',
        'SPEC-039 · Revisar',
        'SPEC-038 · Parou',
      ]);
    });

    test('sessão ociosa ou esperando aprovação não está rodando', () {
      expect(isRadarRunning(null), isFalse);
      expect(isRadarRunning(const LiveSession()), isFalse);
      expect(isRadarRunning(LiveSession(busySince: DateTime(2026))), isTrue);
    });

    test('os quatro ícones estão no projeto', () {
      for (final state in TrayState.values) {
        expect(File(state.asset).existsSync(), isTrue, reason: state.asset);
      }
    });
  });

  group('R3: vários workspaces', () {
    test('item de outro workspace muda o ícone e entra no menu', () {
      final radar = buildTrayRadar([
        ws(1),
        ws(2, name: 'loja', items: [item(InboxKind.approval, 'SPEC-012')]),
      ]);
      expect(radar.status.state, TrayState.attention);
      expect(radar.targets.values.single.workspaceId, 2);
    });

    test('o mesmo item em dois workspaces conta uma vez', () {
      final pr = item(InboxKind.prProblem, 'PR', session: 's1');
      final radar = buildTrayRadar([
        ws(1, items: [pr]),
        ws(2, items: [pr]),
      ]);
      expect(radar.status.tooltip, 'Promptorium · 1 precisa de você');
    });

    test('PR observado fica só no workspace da sessão dele', () {
      final groups = [
        InboxGroup(InboxKind.prProblem, [
          item(InboxKind.prProblem, 'A', session: 'minha'),
          item(InboxKind.prProblem, 'B', session: 'outra'),
        ]),
        InboxGroup(InboxKind.review, [item(InboxKind.review, 'C')]),
      ];
      final out = radarInbox(groups, {'minha'});
      expect(out.first.items.map((i) => i.ref), ['A']);
      expect(out.last.items.map((i) => i.ref), ['C']);
    });

    test('com itens de dois workspaces o rótulo traz o nome', () {
      final radar = buildTrayRadar([
        ws(1, items: [item(InboxKind.approval, 'A', session: 's1')]),
        ws(
          2,
          name: 'loja',
          items: [item(InboxKind.approval, 'B', session: 's2')],
        ),
      ]);
      expect(labels(radar), containsAll(['promptorium · A · Título']));
      expect(labels(radar), contains('loja · B · Título'));
    });

    test('com um workspace só o rótulo não traz o nome', () {
      final radar = buildTrayRadar([
        ws(1, items: [item(InboxKind.approval, 'A')]),
        ws(2, name: 'loja'),
      ]);
      expect(labels(radar), contains('A · Título'));
    });
  });

  group('R4: tooltip', () {
    test('só números, com singular e plural', () {
      expect(
        radarSummary(running: 2, waiting: 3),
        '2 rodando · 3 precisam de você',
      );
      expect(radarSummary(running: 0, waiting: 1), '1 precisa de você');
      expect(radarSummary(running: 1, waiting: 0), '1 rodando');
    });

    test('sem nada para contar é Promptorium', () {
      final status = buildTrayRadar([ws(1)]).status;
      expect(status.tooltip, 'Promptorium');
      expect(status.rows, isEmpty);
    });

    test('não traz títulos', () {
      final status = buildTrayRadar([
        ws(1, items: [item(InboxKind.approval, 'A', title: 'Segredo')]),
      ]).status;
      expect(status.tooltip, isNot(contains('Segredo')));
    });
  });

  group('R5: menu', () {
    test('resumo, pendências e rodando, nessa ordem', () {
      final radar = buildTrayRadar([
        ws(
          1,
          items: [item(InboxKind.review, 'R'), item(InboxKind.approval, 'A')],
          running: [run('s')],
        ),
      ]);
      expect(labels(radar), [
        '1 rodando · 2 precisam de você',
        'Precisa de você',
        'A · Título',
        'R · Título',
        'Rodando',
        'SPEC-001 · R1 · Sessão s',
      ]);
      final rows = radar.status.rows;
      expect(rows.first.id, isNull);
      expect(rows[1].isSeparator, isTrue);
      expect(rows[2].id, isNull);
      expect(rows[3].id, isNotNull);
    });

    test('dentro do mesmo tipo o mais novo vem antes', () {
      final radar = buildTrayRadar([
        ws(
          1,
          items: [
            item(InboxKind.approval, 'velho', session: 'a', minute: 1),
            item(InboxKind.approval, 'novo', session: 'b', minute: 9),
          ],
        ),
      ]);
      expect(labels(radar)[2], startsWith('novo'));
    });

    test('passando dos limites vira a linha Mais N', () {
      final radar = buildTrayRadar([
        ws(
          1,
          items: [
            for (var i = 0; i < 10; i++)
              item(InboxKind.approval, 'A$i', session: 's$i'),
          ],
          running: [for (var i = 0; i < 5; i++) run('r$i')],
        ),
      ]);
      final all = labels(radar);
      expect(all.first, '5 rodando · 10 precisam de você');
      expect(all.where((l) => l.startsWith('A')), hasLength(6));
      expect(all.where((l) => l.startsWith('SPEC-001')), hasLength(3));
      expect(all, containsAll(['Mais 4 em Início', 'Mais 2 em Sessões']));
    });

    test('Mais N abre o workspace do primeiro item oculto', () {
      final radar = buildTrayRadar([
        ws(
          1,
          items: [
            for (var i = 0; i < 6; i++)
              item(InboxKind.approval, 'A$i', session: 'a$i', minute: 30),
          ],
        ),
        ws(
          2,
          name: 'loja',
          items: [item(InboxKind.approval, 'B', session: 'b', minute: 1)],
        ),
      ]);
      expect(
        radar.targets['more:inbox'],
        const RadarTarget(workspaceId: 2, section: AppSection.home),
      );
    });

    test('corta em 48 caracteres com reticências', () {
      final label = radarLabel('SPEC-041 · R3', 'x' * 60, workspace: 'loja');
      expect(label.runes, hasLength(radarLabelLimit));
      expect(label, endsWith('…'));
      final exact = radarLabel('', 'y' * radarLabelLimit);
      expect(exact, 'y' * radarLabelLimit);
    });

    test('referência igual ao título não se repete', () {
      expect(radarLabel('Sessão', 'Sessão'), 'Sessão');
      expect(radarLabel('', 'Sessão'), 'Sessão');
    });
  });

  group('R6/R7: destinos', () {
    late ProviderContainer container;

    ProviderContainer radarWith(List<RadarWorkspace> workspaces) {
      final c = ProviderContainer(
        overrides: [
          databaseOverride(memoryDatabase()),
          trayRadarProvider.overrideWithValue(buildTrayRadar(workspaces)),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    String idOf(String label) => container
        .read(trayRadarProvider)
        .status
        .rows
        .firstWhere((r) => r.label == label)
        .id!;

    int? activeWorkspace() => int.tryParse(
      container.read(appSettingsProvider)['workspace.active'] ?? '',
    );

    test('aprovação de sessão abre a sessão, no workspace dela', () async {
      container = radarWith([
        ws(7, items: [item(InboxKind.approval, 'A', session: 's1')]),
      ]);
      await openRadarItem(container, idOf('A · Título'));
      expect(activeWorkspace(), 7);
      expect(container.read(selectedSessionProvider), 's1');
      expect(container.read(navigationProvider), AppSection.sessions);
    });

    test('aprovação de conversa abre a conversa no Prompt', () async {
      container = radarWith([
        ws(1, items: [item(InboxKind.approval, 'Prompt', conversation: 9)]),
      ]);
      await openRadarItem(container, idOf('Prompt · Título'));
      expect(container.read(selectedConversationProvider), 9);
      expect(container.read(navigationProvider), AppSection.prompt);
    });

    test('resposta pendente abre Início', () async {
      container = radarWith([
        ws(1, items: [item(InboxKind.needsAnswer, 'B', session: 's1')]),
      ]);
      container.read(navigationProvider.notifier).go(AppSection.review);
      await openRadarItem(container, idOf('B · Título'));
      expect(container.read(navigationProvider), AppSection.home);
      expect(container.read(selectedSessionProvider), isNull);
    });

    test('review e PR abrem o item em Review', () async {
      for (final kind in [InboxKind.review, InboxKind.prProblem]) {
        container = radarWith([
          ws(1, items: [item(kind, 'R', session: 's1')]),
        ]);
        await openRadarItem(container, idOf('R · Título'));
        expect(container.read(selectedReviewProvider), 's1');
        expect(container.read(navigationProvider), AppSection.review);
      }
    });

    test('interrompida abre a sessão sem retomar', () async {
      container = radarWith([
        ws(1, items: [item(InboxKind.interrupted, 'I', session: 's1')]),
      ]);
      await openRadarItem(container, idOf('I · Título'));
      expect(container.read(selectedSessionProvider), 's1');
      expect(container.read(navigationProvider), AppSection.sessions);
      expect(container.read(sessionManagerProvider).live, isEmpty);
    });

    test('sessão rodando abre a sessão', () async {
      container = radarWith([
        ws(1, running: [run('s1')]),
      ]);
      await openRadarItem(container, 'running:s1');
      expect(container.read(selectedSessionProvider), 's1');
      expect(container.read(navigationProvider), AppSection.sessions);
    });

    test('item que saiu do radar abre Início', () async {
      container = radarWith([ws(1)]);
      container.read(navigationProvider.notifier).go(AppSection.review);
      await openRadarItem(container, 'approval:s1:r1');
      expect(container.read(navigationProvider), AppSection.home);
    });

    test('abrir uma aprovação não responde nada', () async {
      container = radarWith([
        ws(1, items: [item(InboxKind.approval, 'A', session: 's1')]),
      ]);
      await openRadarItem(container, idOf('A · Título'));
      expect(container.read(sessionManagerProvider).approvals, isEmpty);
    });
  });
}
