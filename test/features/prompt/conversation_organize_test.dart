import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/prompt/conversation_actions.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/prompt/prompt_actions.dart';
import 'package:promptorium/features/prompt/prompt_screen.dart';
import 'package:promptorium/features/prompt/widgets/prompt_side_panel.dart';
import 'package:promptorium/features/prompt/widgets/title_field.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import 'prompt_test_utils.dart';

/// SPEC-056: archive, unarchive and the tabs of the conversation list;
/// renaming.

const titles = [
  'Como funciona o carrinho?',
  'Plano: cupom de desconto',
  'Trocar cor do botão Comprar',
];

/// Prompt screen with [titles] (ids 1… newest first); [archived] ids start
/// archived; [select] opens one.
Future<(AppDatabase, FakeCli, ProviderContainer)> pumpList(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  Set<int> archived = const {},
  int? select,
  Map<String, String> settings = const {},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = memoryDatabase();
  final cli = FakeCli();
  final ws = await addWorkspace(db, '/work/repo');
  for (final e in settings.entries) {
    await db
        .into(db.appSettings)
        .insert(AppSettingsCompanion.insert(key: e.key, value: e.value));
  }
  final now = DateTime.now();
  for (var i = 0; i < titles.length; i++) {
    await db
        .into(db.conversations)
        .insert(
          ConversationsCompanion.insert(
            workspaceId: ws.id,
            title: titles[i],
            model: 'sonnet',
            claudeSessionId: Value('sid-${i + 1}'),
            messageCount: const Value(2),
            tokensIn: const Value(18000),
            tokensOut: const Value(400),
            updatedAt: Value(now.subtract(Duration(minutes: i))),
            archivedAt: Value(
              archived.contains(i + 1)
                  ? now.subtract(Duration(minutes: i))
                  : null,
            ),
          ),
        );
  }
  final container = ProviderContainer(
    overrides: [
      ...sessionOverrides(db: db, cli: cli, notifier: FakeNotifier()),
      workspaceFilesProvider.overrideWith((ref, root) async => <String>[]),
    ],
  );
  await container.read(appSettingsProvider.notifier).load();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: PromptScreen()),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(Duration.zero);
  });
  await pumpFor(tester);
  if (select != null) {
    container.read(selectedConversationProvider.notifier).select(select);
    await pumpFor(tester);
  }
  return (db, cli, container);
}

Future<void> pumpFor(WidgetTester tester, [int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Finder row(int id) => find.byKey(ValueKey('conversation-$id'));
Finder archiveButton(int id) =>
    find.byKey(ValueKey('conversation-archive-$id'));
String title(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('prompt-title'))).data!;

TestGesture? _mouse;

/// One mouse for the whole test, moved over [f].
Future<void> hover(WidgetTester tester, Finder f) async {
  var g = _mouse;
  if (g == null) {
    g = _mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: Offset.zero);
    addTearDown(() async {
      await _mouse?.removePointer();
      _mouse = null;
    });
  }
  await g.moveTo(tester.getCenter(f));
  await tester.pump();
}

/// Lets the archive notice and its timers go.
Future<void> letNoticeGo(WidgetTester tester) async {
  await tester.pump(archiveUndoWindow + const Duration(seconds: 1));
  await pumpFor(tester, 30);
}

Future<void> archiveByHover(WidgetTester tester, int id) async {
  await hover(tester, row(id));
  await tester.tap(archiveButton(id));
  await pumpFor(tester);
}

void main() {
  testWidgets('the row shows Arquivar on hover and on focus; ⋯ only on the '
      'selected one (R1)', (tester) async {
    await pumpList(tester, select: 1);
    expect(archiveButton(2), findsNothing);
    expect(find.byKey(const ValueKey('conversation-more-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('conversation-more-2')), findsNothing);

    await hover(tester, row(2));
    expect(archiveButton(2), findsOneWidget);
    expect(find.byTooltip('Arquivar'), findsOneWidget);
    await _mouse!.moveTo(const Offset(1400, 880));
    await tester.pump();
    expect(archiveButton(2), findsNothing);

    // Keyboard: focus inside the row shows the same button.
    Focus.of(
      tester.element(
        find.descendant(of: row(3), matching: find.byType(Padding)).first,
      ),
    ).requestFocus();
    await tester.pump();
    expect(archiveButton(3), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('archiving the open conversation takes it out, selects the '
      'one above and offers Desfazer, which brings it back (R4, R5)', (
    tester,
  ) async {
    final (db, _, _) = await pumpList(tester, select: 2);
    expect(find.byKey(const ValueKey('conversation-tabs')), findsNothing);
    expect(
      find.byKey(const ValueKey('conversation-archived-footer')),
      findsNothing,
    );

    await archiveByHover(tester, 2);
    expect(row(2), findsNothing);
    expect(title(tester), titles[0]);
    expect(find.text('“${titles[1]}” arquivada'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('conversation-archived-count')),
          )
          .data,
      '1',
    );
    // R6: the tabs show up with the first archived one.
    expect(find.byKey(const ValueKey('conversation-tabs')), findsOneWidget);
    expect(
      (await (db.select(
        db.conversations,
      )..where((c) => c.id.equals(2))).getSingle()).archivedAt,
      isNotNull,
    );

    await tester.tap(find.text('Desfazer'));
    await pumpFor(tester, 30);
    expect(row(2), findsOneWidget);
    expect(title(tester), titles[1]);
    expect(find.byKey(const ValueKey('conversation-tabs')), findsNothing);
    expect(find.text('“${titles[1]}” arquivada'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the first one passes the selection to the one below; Ctrl+Z '
      'undoes while the notice is up, not after (R4, R5)', (tester) async {
    await pumpList(tester, select: 1);
    await archiveByHover(tester, 1);
    expect(title(tester), titles[1]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFor(tester, 30);
    expect(row(1), findsOneWidget);
    expect(title(tester), titles[0]);

    await archiveByHover(tester, 3);
    expect(row(3), findsNothing);
    // The notice leaves after 6 s; then Ctrl+Z is the field's again.
    await letNoticeGo(tester);
    expect(find.text('“${titles[2]}” arquivada'), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFor(tester);
    expect(row(3), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a conversation that is answering can be archived and keeps '
      'running (R4)', (tester) async {
    final (_, cli, container) = await pumpList(tester, select: 2);
    await tester.enterText(
      find.byKey(const ValueKey('prompt-field')),
      'Continue',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFor(tester);
    expect(container.read(conversationManagerProvider).isBusy(2), isTrue);

    await archiveByHover(tester, 2);
    expect(row(2), findsNothing);
    expect(container.read(conversationManagerProvider).isBusy(2), isTrue);
    expect(cli.last.signals, isEmpty);
    expect(tester.takeException(), isNull);
    await letNoticeGo(tester);
  });

  testWidgets('Arquivadas lists the archived ones, newest first, and '
      'Desarquivar brings one back (R6)', (tester) async {
    await pumpList(tester, archived: {2, 3});
    expect(row(2), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('conversation-archived-footer')),
    );
    await pumpFor(tester);
    expect(row(1), findsNothing);
    expect(
      tester.getTopLeft(row(2)).dy,
      lessThan(tester.getTopLeft(row(3)).dy),
    );
    expect(find.text('Sonnet · arquivada hoje'), findsNWidgets(2));
    // R11: the tabs are a TabBar; the archived one is selected.
    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabs.controller!.index, 1);

    await hover(tester, row(3));
    await tester.tap(find.byKey(const ValueKey('conversation-unarchive-3')));
    await pumpFor(tester);
    expect(row(3), findsNothing);
    await tester.tap(find.byKey(const ValueKey('conversation-tab-active')));
    await pumpFor(tester, 30);
    expect(row(3), findsOneWidget);
    expect(row(1), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an archived conversation shows the notice; a message '
      'unarchives it and goes back to Ativas (R7)', (tester) async {
    final (db, cli, container) = await pumpList(tester, archived: {2});
    await tester.tap(find.byKey(const ValueKey('conversation-tab-archived')));
    await pumpFor(tester, 30);
    await tester.tap(row(2));
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('archived-banner')), findsOneWidget);
    expect(
      find.textContaining('Mandar uma mensagem desarquiva.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('prompt-field')),
      'E o frete?',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFor(tester, 30);
    expect(cli.last.writtenJson.single['message']['content'], 'E o frete?');
    final c = await (db.select(
      db.conversations,
    )..where((c) => c.id.equals(2))).getSingle();
    expect(c.archivedAt, isNull);
    expect(find.byKey(const ValueKey('archived-banner')), findsNothing);
    expect(container.read(conversationTabProvider), ConversationTab.active);
    expect(find.byKey(const ValueKey('conversation-tabs')), findsNothing);
    expect(row(2), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Desarquivar of the notice brings the open one back', (
    tester,
  ) async {
    await pumpList(tester, archived: {3}, select: 3);
    await tester.tap(find.byKey(const ValueKey('archived-banner-unarchive')));
    await pumpFor(tester, 30);
    expect(find.byKey(const ValueKey('archived-banner')), findsNothing);
    expect(row(3), findsOneWidget);
    expect(title(tester), titles[2]);
  });

  testWidgets('right click on the row and ⋯ of the header open the same '
      'menu (R1)', (tester) async {
    await pumpList(tester, select: 1);
    await tester.tap(row(2), buttons: kSecondaryButton);
    await pumpFor(tester);
    for (final a in ['archive', 'toSpec', 'continueSession']) {
      expect(find.byKey(ValueKey('conversation-menu-$a')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('conversation-menu-archive')));
    await pumpFor(tester);
    expect(row(2), findsNothing);
    expect(title(tester), titles[0]);

    await tester.tap(find.byKey(const ValueKey('prompt-more')));
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('conversation-menu-archive')), findsOne);
    expect(find.text('Transformar em spec'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('conversation-menu-archive')));
    await pumpFor(tester);
    expect(row(1), findsNothing);
    expect(title(tester), titles[2]);
    expect(tester.takeException(), isNull);
    await letNoticeGo(tester);
  });

  group('renomear (R2, R3)', () {
    Finder titleField() => find.byKey(const ValueKey('title-field'));
    TextEditingController fieldCtl(WidgetTester tester) =>
        tester.widget<TextField>(titleField()).controller!;
    Future<String> stored(AppDatabase db, int id) async => (await (db.select(
      db.conversations,
    )..where((c) => c.id.equals(id))).getSingle()).title;

    Future<void> f2(WidgetTester tester) async {
      // F2 reaches the screen from wherever the focus is (here, the field).
      await tester.tap(find.byKey(const ValueKey('prompt-field')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await pumpFor(tester);
    }

    testWidgets('F2 turns the title into a field with all of it selected; '
        'Enter saves', (tester) async {
      final (db, _, _) = await pumpList(tester, select: 2);
      await f2(tester);
      expect(titleField(), findsOneWidget);
      expect(find.text('Enter salva · Esc cancela'), findsOneWidget);
      final ctl = fieldCtl(tester);
      expect(ctl.selection.start, 0);
      expect(ctl.selection.end, titles[1].length);
      // The actions wait while the title is edited.
      expect(find.byKey(const ValueKey('prompt-to-spec')), findsNothing);

      await tester.enterText(titleField(), '  Cupom 10% primeira compra ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpFor(tester);
      expect(titleField(), findsNothing);
      expect(await stored(db, 2), 'Cupom 10% primeira compra');
      expect(title(tester), 'Cupom 10% primeira compra');
      expect(find.text('Cupom 10% primeira compra'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty title shows the message and is not saved; Esc goes '
        'back to the previous one', (tester) async {
      final (db, _, _) = await pumpList(tester, select: 2);
      await tester.tap(find.byKey(const ValueKey('prompt-rename')));
      await pumpFor(tester);
      await tester.enterText(titleField(), '   ');
      await pumpFor(tester, 2);
      expect(find.text(emptyTitleMessage), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpFor(tester);
      expect(titleField(), findsOneWidget);
      final save = tester.widget<IconButton>(
        find.descendant(
          of: find.byKey(const ValueKey('title-save')),
          matching: find.byType(IconButton),
        ),
      );
      expect(save.onPressed, isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFor(tester);
      expect(titleField(), findsNothing);
      expect(title(tester), titles[1]);
      expect(await stored(db, 2), titles[1]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaving the field saves; the cancel button does not', (
      tester,
    ) async {
      final (db, _, _) = await pumpList(tester, select: 2);
      await tester.tap(find.byKey(const ValueKey('prompt-rename')));
      await pumpFor(tester);
      await tester.enterText(titleField(), 'Cupom');
      await tester.tap(find.byKey(const ValueKey('title-cancel')));
      await pumpFor(tester);
      expect(await stored(db, 2), titles[1]);

      await tester.tap(find.byKey(const ValueKey('prompt-rename')));
      await pumpFor(tester);
      await tester.enterText(titleField(), 'Cupom');
      // Another field takes the focus.
      await tester.tap(find.byKey(const ValueKey('prompt-field')));
      await pumpFor(tester);
      expect(titleField(), findsNothing);
      expect(await stored(db, 2), 'Cupom');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a double click renames in the row itself; one click only '
        'selects', (tester) async {
      final (db, _, container) = await pumpList(tester, select: 1);
      await tester.tap(row(3));
      await tester.pump(const Duration(milliseconds: 500));
      expect(container.read(selectedConversationProvider), 3);
      expect(titleField(), findsNothing);

      await tester.tap(row(2));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(row(2));
      await pumpFor(tester);
      final inRow = find.byKey(const ValueKey('conversation-title-field-2'));
      expect(inRow, findsOneWidget);
      // Only in the row: the header keeps its title.
      expect(find.byKey(const ValueKey('prompt-title-field-2')), findsNothing);
      await tester.enterText(titleField(), 'x' * 130);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpFor(tester);
      expect(await stored(db, 2), 'x' * maxTitleLength);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Renomear of the menu and of the hover edit the row', (
      tester,
    ) async {
      final (db, _, _) = await pumpList(tester, select: 1);
      await tester.tap(row(3), buttons: kSecondaryButton);
      await pumpFor(tester);
      expect(find.text('F2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('conversation-menu-rename')));
      await pumpFor(tester);
      expect(
        find.byKey(const ValueKey('conversation-title-field-3')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFor(tester);
      expect(titleField(), findsNothing);

      await hover(tester, row(2));
      expect(find.byTooltip('Renomear'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('conversation-rename-2')));
      await pumpFor(tester);
      await tester.enterText(titleField(), 'Cupom');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpFor(tester);
      expect(await stored(db, 2), 'Cupom');
      expect(tester.takeException(), isNull);
    });
  });

  test('normalizeTitle', () {
    expect(normalizeTitle('  a \n b  '), 'a b');
    expect(normalizeTitle('   '), isNull);
    expect(normalizeTitle('y' * 200), hasLength(maxTitleLength));
  });

  group('recolher o painel (R8–R10)', () {
    final strip = find.byKey(const ValueKey('prompt-side-strip'));
    final panel = find.byKey(const ValueKey('prompt-side-panel'));
    String? stored(ProviderContainer c) =>
        c.read(appSettingsProvider)[AppSettingKeys.promptPanelCollapsed];

    Future<void> ctrlAltB(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await pumpFor(tester);
    }

    testWidgets('the button collapses it into a 48 px strip, Ctrl+Alt+B '
        'shows it again and the choice is stored', (tester) async {
      final (_, _, container) = await pumpList(tester, select: 1);
      expect(panel, findsOneWidget);
      expect(strip, findsNothing);
      expect(find.byTooltip('Recolher painel (Ctrl+Alt+B)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('side-panel-collapse')));
      await pumpFor(tester);
      expect(strip, findsOneWidget);
      expect(tester.getSize(strip).width, sideStripWidth);
      expect(stored(container), '1');
      expect(find.byTooltip('Mostrar painel (Ctrl+Alt+B)'), findsOneWidget);
      for (final s in SideSection.values) {
        expect(find.byKey(ValueKey('side-strip-${s.name}')), findsOneWidget);
      }
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('side-strip-tokens')))
            .data,
        '18k tokens',
      );

      // The shortcut works from the composer too.
      await tester.tap(find.byKey(const ValueKey('prompt-field')));
      await tester.pump();
      await ctrlAltB(tester);
      expect(panel, findsOneWidget);
      expect(stored(container), '0');
      await ctrlAltB(tester);
      expect(strip, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the stored choice comes back with the app', (tester) async {
      await pumpList(
        tester,
        select: 1,
        settings: {AppSettingKeys.promptPanelCollapsed: '1'},
      );
      expect(strip, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('side-panel-expand')));
      await pumpFor(tester);
      expect(panel, findsOneWidget);
    });

    testWidgets('each section opens alone in a 260 px balloon; Esc or a '
        'click outside closes it (R9)', (tester) async {
      await pumpList(
        tester,
        select: 1,
        settings: {AppSettingKeys.promptPanelCollapsed: '1'},
      );
      await tester.tap(find.byKey(const ValueKey('side-strip-context')));
      await pumpFor(tester);
      final balloon = find.byKey(const ValueKey('side-balloon-context'));
      expect(balloon, findsOneWidget);
      expect(tester.getSize(balloon).width, sideBalloonWidth);
      expect(find.byKey(const ValueKey('context-tokens')), findsOneWidget);
      expect(find.text('PROMPTS SALVOS'), findsNothing);
      // Over the conversation, left of the strip.
      expect(
        tester.getTopRight(balloon).dx,
        lessThan(tester.getTopLeft(strip).dx),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFor(tester);
      expect(balloon, findsNothing);

      await tester.tap(find.byKey(const ValueKey('side-strip-files')));
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('side-balloon-files')), findsOneWidget);
      expect(find.text('Nenhum arquivo citado.'), findsOneWidget);
      // Another section replaces it.
      await tester.tap(find.byKey(const ValueKey('side-strip-prompts')));
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('side-balloon-files')), findsNothing);
      expect(
        find.byKey(const ValueKey('side-balloon-prompts')),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(700, 400));
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('side-balloon-prompts')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('below 1100 px it starts collapsed; the button holds until '
        'the band changes (R10)', (tester) async {
      final (_, _, container) = await pumpList(
        tester,
        size: const Size(1044, 628),
        select: 1,
      );
      expect(strip, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('side-panel-expand')));
      await pumpFor(tester);
      expect(panel, findsOneWidget);
      // Only for this band: nothing stored.
      expect(stored(container), isNull);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(1440, 900);
      await pumpFor(tester);
      expect(panel, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('side-panel-collapse')));
      await pumpFor(tester);
      expect(stored(container), '1');
      await tester.tap(find.byKey(const ValueKey('side-panel-expand')));
      await pumpFor(tester);
      expect(stored(container), '0');

      // Back in the narrow band: collapsed again.
      tester.view.physicalSize = const Size(1044, 628);
      await pumpFor(tester);
      expect(strip, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('neighbourOf and archivedWhen', () {
    Conversation c(int id) => Conversation(
      id: id,
      workspaceId: 1,
      title: '$id',
      provider: 'claude',
      model: 'sonnet',
      createdAt: DateTime(2026),
      mode: 'ask',
      tokensIn: 0,
      tokensOut: 0,
      costUsd: 0,
      messageCount: 0,
    );
    final list = [c(1), c(2), c(3)];
    expect(neighbourOf(list, 2), 1);
    expect(neighbourOf(list, 1), 2);
    expect(neighbourOf([c(1)], 1), isNull);
    final now = DateTime(2026, 11, 10, 15);
    expect(archivedWhen(DateTime(2026, 11, 10, 9), now: now), 'hoje');
    expect(archivedWhen(DateTime(2026, 11, 9, 23), now: now), 'ontem');
    expect(archivedWhen(DateTime(2026, 11, 3), now: now), '3 nov');
    expect(archivedWhen(DateTime(2025, 10, 12), now: now), '12 out 2025');
  });
}
