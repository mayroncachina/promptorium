import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/process/process_runner.dart';
import 'package:promptorium/core/providers/agent_provider.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/home/home_inbox.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/prompt/prompt_activity.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/ui/shell/app_shell.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/motion.dart';
import 'package:promptorium/ui/widgets/app_icon.dart';

import '../../features/prompt/prompt_test_utils.dart' show addWorkspace;
import '../../helpers/test_db.dart';

/// SPEC-055 t2: the new icon (R5), the "respondendo" dot and the Prompt
/// counter (R4), and what the item announces (R10).

Finder nav(AppSection s) => find.byKey(ValueKey('nav-${s.name}'));

const _live = ValueKey('nav-prompt-live');

const _activity = PromptActivity(
  conversationId: 1,
  title: 'Como funciona o carrinho?',
  mode: PromptMode.ask,
);

/// What the sidebar reads, set by the test.
class _Activity extends Notifier<PromptActivity?> {
  @override
  PromptActivity? build() => null;

  void set(PromptActivity? v) => state = v;
}

final _activityNow = NotifierProvider<_Activity, PromptActivity?>(
  _Activity.new,
);

/// A conversation manager whose live state the test sets.
class _Manager extends ConversationManager {
  @override
  ConversationManagerState build() => const ConversationManagerState();

  void set(Map<int, LiveConversation> live) =>
      state = ConversationManagerState(live: live);
}

Future<ProviderContainer> pumpShell(
  WidgetTester tester, {
  Map<AppSection, int> badges = const {},
  bool reduced = false,
  bool motion = true,
}) async {
  AppMotion.enabled = motion;
  addTearDown(() => AppMotion.enabled = false);
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (reduced) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  final overrides = <Override>[
    processRunnerProvider.overrideWithValue(
      (exe, args) async =>
          ProcessResult(0, 1, '', 'not installed in widget fixture'),
    ),
    databaseOverride(memoryDatabase()),
    promptActivityProvider.overrideWith((ref) => ref.watch(_activityNow)),
    navBadgesProvider.overrideWith((ref) => badges),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: AppTheme.dark(), home: const AppShell()),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
  return ProviderScope.containerOf(tester.element(find.byType(AppShell)));
}

PendingApproval approval(String sid, String tool, String title) =>
    PendingApproval(
      sessionId: sid,
      sessionTitle: title,
      request:
          ClaudeEvent.parseLine(
                '{"type":"control_request","request_id":"req-$sid",'
                '"request":{"subtype":"can_use_tool","tool_name":"$tool",'
                '"input":{}}}',
              ).single
              as PermissionRequest,
      receivedAt: DateTime(2026, 11, 10),
    );

void main() {
  group('R5 · the new icon', () {
    test('a balloon with two lines and a filled spark outside it, on every '
        'place of the Prompt', () {
      final icon = AppIcons.prompt;
      expect(icon.strokeWidth, 1.8);
      final spark = icon.fill!.getBounds();
      final balloon = icon.path.getBounds();
      // The spark sits at the top right, past the outline's top.
      expect(spark.left, greaterThan(14));
      expect(spark.top, lessThan(balloon.top));
      expect(spark.right, lessThanOrEqualTo(24));
      expect(AppSection.prompt.icon, same(icon));
      // Stroke-only icons stay without a fill.
      expect(AppIcons.specs.fill, isNull);
    });

    testWidgets('paints at 16, 24 and 30 px', (tester) async {
      await tester.pumpWidget(
        Row(
          textDirection: TextDirection.ltr,
          children: [
            for (final size in [16.0, 24.0, 30.0])
              AppIcon(AppIcons.prompt, size: size),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(AppIcon).first), const Size(16, 16));
    });

    testWidgets('the palette shows it next to "Ir para Prompt"', (
      tester,
    ) async {
      await pumpShell(tester, motion: false);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'prompt');
      await tester.pumpAndSettle();
      final icon = tester.widget<AppIcon>(
        find.byKey(const ValueKey('palette-icon-Ir para Prompt')),
      );
      expect(icon.icon, same(AppIcons.prompt));
      expect(icon.size, 16);
    });
  });

  group('R4 · the item tells what happens on the Prompt', () {
    testWidgets('a teal dot pulses while a conversation answers, the tooltip '
        'names it, and it goes when the answer ends', (tester) async {
      final semantics = tester.ensureSemantics();
      final c = await pumpShell(tester);
      expect(find.byKey(_live), findsNothing);

      c.read(_activityNow.notifier).set(_activity);
      await tester.pump();
      expect(find.byKey(_live), findsOneWidget);
      expect(
        find.byTooltip('Respondendo “Como funciona o carrinho?” · Perguntar'),
        findsOneWidget,
      );
      final ink = find.descendant(
        of: nav(AppSection.prompt),
        matching: find.byType(InkWell),
      );
      expect(
        tester.getSemantics(ink),
        isSemantics(label: 'Prompt · respondendo', isButton: true),
      );
      // It pulses: the opacity moves.
      double opacity() => tester
          .widget<FadeTransition>(
            find
                .ancestor(
                  of: find.byKey(_live),
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;
      final first = opacity();
      await tester.pump(const Duration(milliseconds: 400));
      expect(opacity(), isNot(first));
      expect(tester.hasRunningAnimations, isTrue);

      c.read(_activityNow.notifier).set(null);
      await tester.pump();
      expect(find.byKey(_live), findsNothing);
      expect(tester.getSemantics(ink), isSemantics(label: 'Prompt'));
      expect(tester.hasRunningAnimations, isFalse);
      semantics.dispose();
    });

    testWidgets('with reduced motion the dot stays still', (tester) async {
      final c = await pumpShell(tester, reduced: true);
      c.read(_activityNow.notifier).set(_activity);
      await tester.pump();
      expect(find.byKey(_live), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('the amber counter counts what waits on the Prompt and is '
        'announced', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpShell(tester, badges: {AppSection.prompt: 2}, motion: false);
      expect(find.byKey(const ValueKey('nav-badge-prompt')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('nav-badge-prompt')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.descendant(
            of: nav(AppSection.prompt),
            matching: find.byType(InkWell),
          ),
        ),
        isSemantics(label: 'Prompt · 2 pendentes'),
      );
      semantics.dispose();
    });

    test('approvals and plans of Prompt conversations count on the Prompt, '
        'the ones of sessions on Sessões', () {
      final groups = buildInbox(
        sessionApprovals: [approval('s1', 'Bash', 'Sessão 1')],
        conversationApprovals: {
          7: [approval('c7', 'Edit', 'Carrinho')],
          8: [approval('c8', 'ExitPlanMode', 'Cupom')],
        },
        specs: const [],
        stepRows: const [],
        sessions: const [],
        reviewQueue: const [],
        prWatches: const {},
        isAlive: (_) => false,
      );
      final c = ProviderContainer(
        overrides: [inboxProvider.overrideWithValue(groups)],
      );
      addTearDown(c.dispose);
      expect(c.read(navBadgesProvider), {
        AppSection.home: 3,
        AppSection.sessions: 1,
        AppSection.prompt: 2,
      });
    });

    test('promptActivityProvider: the newest busy conversation of the '
        'active workspace, with its title and mode', () async {
      final db = memoryDatabase();
      final ws = await addWorkspace(db, '/work/loja');
      Future<int> conversation(String title, String mode) async =>
          (await db
                  .into(db.conversations)
                  .insertReturning(
                    ConversationsCompanion.insert(
                      workspaceId: ws.id,
                      title: title,
                      model: 'sonnet',
                      mode: Value(mode),
                    ),
                  ))
              .id;
      final plan = await conversation('Plano: cupom de desconto', 'plan');
      final other = await conversation('Trocar cor do botão', 'edit');
      final c = ProviderContainer(
        overrides: [
          databaseOverride(db),
          conversationManagerProvider.overrideWith(_Manager.new),
        ],
      );
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final sub = c.listen(promptActivityProvider, (_, _) {});
      addTearDown(sub.close);
      // The Prompt list (and the inbox) keep the conversations loaded.
      final list = c.listen(conversationsProvider(ws.id), (_, _) {});
      addTearDown(list.close);
      await c.read(conversationsProvider(ws.id).future);
      expect(sub.read(), isNull);

      final manager = c.read(conversationManagerProvider.notifier) as _Manager;
      manager.set({
        plan: const LiveConversation(busy: true),
        other: const LiveConversation(),
      });
      expect(
        sub.read(),
        PromptActivity(
          conversationId: plan,
          title: 'Plano: cupom de desconto',
          mode: PromptMode.plan,
        ),
      );
      expect(
        sub.read()!.tooltip,
        'Respondendo “Plano: cupom de desconto” · Planejar',
      );

      manager.set({plan: const LiveConversation()});
      expect(sub.read(), isNull);
    });
  });
}
