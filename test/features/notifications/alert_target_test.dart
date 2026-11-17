import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/activities/activities_screen.dart'
    show activitiesTabProvider;
import 'package:promptorium/features/activities/activity.dart' show ActivityTab;
import 'package:promptorium/features/board/board_screen.dart'
    show boardFocusSpecProvider, boardSelectedSpecProvider;
import 'package:promptorium/features/notifications/alert_target.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/widgets/side_panel.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

/// SPEC-086 R6, R7: the click on the notification opens the request — the
/// workspace, the screen, the session and the card, with the focus on its
/// main button.

PendingApproval _approval(String id, {String tool = 'Bash'}) => PendingApproval(
  sessionId: 's1',
  sessionTitle: 'SPEC-031 · R2',
  request:
      ClaudeEvent.parseLine(
            jsonEncode({
              'type': 'control_request',
              'request_id': id,
              'request': {
                'subtype': 'can_use_tool',
                'tool_name': tool,
                'input': tool == 'AskUserQuestion'
                    ? {
                        'questions': [
                          {
                            'question': 'Qual banco?',
                            'header': 'Banco',
                            'multiSelect': false,
                            'options': [
                              {'label': 'Postgres', 'description': ''},
                              {'label': 'SQLite', 'description': ''},
                            ],
                          },
                        ],
                      }
                    : {'command': 'flutter test --coverage'},
              },
            }),
          ).single
          as PermissionRequest,
  receivedAt: DateTime(2026, 11, 16, 15, 18),
);

void main() {
  group('openAlertTarget', () {
    late ProviderContainer c;

    setUp(() {
      c = ProviderContainer(overrides: [databaseOverride(memoryDatabase())]);
      addTearDown(c.dispose);
    });

    int? active() =>
        int.tryParse(c.read(appSettingsProvider)['workspace.active'] ?? '');

    test('aprovação de sessão: troca o workspace, abre Sessões, seleciona e '
        'pede o foco do cartão', () async {
      c.read(navigationProvider.notifier).go(AppSection.code);
      await openAlertTarget(
        c.read,
        const AlertTarget(
          workspaceId: 7,
          kind: AlertKind.approval,
          sessionId: 's1',
          requestId: 'req-1',
        ),
        pending: true,
        announce: 'Ada, SPEC-031: quer executar flutter test',
      );
      expect(active(), 7);
      expect(c.read(navigationProvider), AppSection.sessions);
      expect(c.read(selectedSessionProvider), 's1');
      final focus = c.read(alertFocusProvider)!;
      expect(focus.requestId, 'req-1');
      expect(focus.announce, 'Ada, SPEC-031: quer executar flutter test');
      expect(c.read(alertNoticeProvider), isNull);
    });

    test('conversa: abre o Prompt na conversa', () async {
      await openAlertTarget(
        c.read,
        const AlertTarget(
          workspaceId: 1,
          kind: AlertKind.plan,
          conversationId: 9,
          requestId: 'req-2',
        ),
        pending: true,
      );
      expect(c.read(navigationProvider), AppSection.prompt);
      expect(c.read(selectedConversationProvider), 9);
    });

    test('etapa parada: o painel da etapa no Quadro', () async {
      await openAlertTarget(
        c.read,
        const AlertTarget(
          workspaceId: 1,
          kind: AlertKind.needsInput,
          specId: 4,
          requestId: 'step:4:R2',
        ),
        pending: true,
      );
      expect(c.read(navigationProvider), AppSection.tasks);
      expect(c.read(boardSelectedSpecProvider), 4);
      expect(c.read(boardFocusSpecProvider), 4);
    });

    test('pedido já respondido: abre a sessão e avisa', () async {
      await openAlertTarget(
        c.read,
        const AlertTarget(
          workspaceId: 1,
          kind: AlertKind.approval,
          sessionId: 's1',
          requestId: 'req-1',
        ),
        pending: false,
      );
      expect(c.read(selectedSessionProvider), 's1');
      expect(c.read(alertFocusProvider), isNull);
      expect(c.read(alertNoticeProvider)!.text, alertAnsweredText);
    });

    test('o resumo abre a Atividades em "Precisa de você"', () {
      openNeedsYou(c.read);
      expect(c.read(navigationProvider), AppSection.activities);
      expect(c.read(activitiesTabProvider), ActivityTab.needsYou);
    });
  });

  group('o cartão do pedido', () {
    Future<ProviderContainer> pump(
      WidgetTester tester,
      List<PendingApproval> approvals,
    ) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    // Pushes the card out of view: it has to scroll.
                    const SizedBox(height: 1500),
                    for (final a in approvals)
                      SizedBox(
                        width: 520,
                        child: ApprovalCard(
                          approval: a,
                          onOpen: () {},
                          onApprove: ({required bool always, input}) async {},
                          onDeny: () async {},
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return c;
    }

    testWidgets('rola até o cartão, foca o Aprovar e acende o anel por '
        '1,5 s', (tester) async {
      final c = await pump(tester, [_approval('req-0'), _approval('req-1')]);
      final approve = find.byKey(const ValueKey('approve-req-1'));
      expect(tester.getTopLeft(approve).dy, greaterThan(700));
      c
          .read(alertFocusProvider.notifier)
          .request(
            const AlertFocus(
              'req-1',
              announce: 'Ada, SPEC-031: quer executar flutter test',
            ),
          );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(approve).dy, lessThan(700));
      final focused = FocusManager.instance.primaryFocus!;
      expect(focused.debugLabel, 'approval-primary');
      expect(tester.getRect(approve).contains(focused.rect.center), isTrue);
      expect(c.read(alertFocusProvider), isNull, reason: 'o cartão pegou');
      final ring = find.byKey(const ValueKey('alert-spotlight-req-1'));
      BoxDecoration deco() =>
          tester.widget<AnimatedContainer>(ring).foregroundDecoration!
              as BoxDecoration;
      expect((deco().border! as Border).top.color, isNot(Colors.transparent));
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();
      expect((deco().border! as Border).top.color, Colors.transparent);
      // The other card was left alone.
      final other = find.byKey(const ValueKey('alert-spotlight-req-0'));
      expect(
        ((tester.widget<AnimatedContainer>(other).foregroundDecoration!
                        as BoxDecoration)
                    .border!
                as Border)
            .top
            .color,
        Colors.transparent,
      );
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('o cartão montado depois do pedido também pega o foco', (
      tester,
    ) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(alertFocusProvider.notifier).request(const AlertFocus('req-1'));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 520,
                child: ApprovalCard(
                  approval: _approval('req-1'),
                  onOpen: () {},
                  onApprove: ({required bool always, input}) async {},
                  onDeny: () async {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'approval-primary',
      );
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('pergunta: o foco vai para a primeira resposta', (
      tester,
    ) async {
      final c = await pump(tester, [
        _approval('req-q', tool: 'AskUserQuestion'),
      ]);
      c.read(alertFocusProvider.notifier).request(const AlertFocus('req-q'));
      await tester.pumpAndSettle();
      final focused = FocusManager.instance.primaryFocus!;
      expect(focused.debugLabel, isNot('approval-primary'));
      final card = find.byKey(const ValueKey('approval-req-q'));
      final rect = tester.getRect(card);
      expect(rect.contains(focused.rect.center), isTrue);
      await tester.pump(const Duration(seconds: 6));
    });
  });
}
