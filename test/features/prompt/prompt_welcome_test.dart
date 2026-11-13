import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/rendering.dart' show SemanticsRole;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/agent_provider.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/prompt/widgets/prompt_welcome.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/widgets/app_icon.dart';

import '../../ui/app_shell_test.dart' as shell;
import 'prompt_screen_test.dart' show pumpPrompt, pumpFor, field, fieldText;

/// SPEC-055 t3: the welcome of the empty Prompt (R7, R9, R10).

Finder card(PromptMode m) => find.byKey(ValueKey('prompt-welcome-${m.name}'));

Finder example(PromptMode m, int i) =>
    find.byKey(ValueKey('prompt-example-${m.name}-$i'));

void main() {
  testWidgets('R7 · the title with the new icon and one card per mode, with '
      'its sentence, seal and two examples', (tester) async {
    await pumpPrompt(tester, withConversation: false);
    expect(find.byKey(const ValueKey('prompt-welcome')), findsOneWidget);
    expect(find.text('Converse com o seu projeto'), findsOneWidget);
    expect(
      find.text(
        'Escreva como num chat. Escolha abaixo o quanto o agente pode mexer.',
      ),
      findsOneWidget,
    );
    final icon = tester.widget<AppIcon>(
      find.byKey(const ValueKey('prompt-welcome-icon')),
    );
    expect(icon.icon, same(AppIcons.prompt));
    expect(icon.size, 30);

    for (final m in PromptMode.selectable) {
      final intro = modeIntros[m]!;
      expect(card(m), findsOneWidget, reason: m.name);
      for (final text in [m.label, intro.sentence, intro.seal]) {
        expect(
          find.descendant(of: card(m), matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
      expect(intro.examples, hasLength(2));
      expect(example(m, 0), findsOneWidget);
      expect(example(m, 1), findsOneWidget);
    }
    expect(modeIntros.keys, PromptMode.selectable);
    expect(modeIntros[PromptMode.ask]!.seal, 'Nada muda nos arquivos');
    expect(modeIntros[PromptMode.plan]!.seal, 'Você aprova antes');
    expect(modeIntros[PromptMode.edit]!.seal, 'Altera os arquivos');
    // The cards sit side by side on a wide window.
    expect(
      tester.getTopLeft(card(PromptMode.plan)).dy,
      tester.getTopLeft(card(PromptMode.ask)).dy,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('R7 · the cards mirror the mode switch of the composer, both '
      'ways', (tester) async {
    final (_, _, c) = await pumpPrompt(tester, withConversation: false);
    expect(c.read(promptDraftProvider).mode, PromptMode.ask);

    await tester.tap(card(PromptMode.plan));
    await pumpFor(tester, 3);
    expect(c.read(promptDraftProvider).mode, PromptMode.plan);
    expect(
      find.byKey(const ValueKey('prompt-mode-hint')).evaluate().isNotEmpty,
      isTrue,
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('prompt-mode-hint'))).data,
      PromptMode.plan.hint,
    );

    // The switch of the composer moves the card.
    await tester.tap(find.byKey(const ValueKey('mode-edit')));
    await pumpFor(tester, 3);
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(card(PromptMode.edit)),
      isSemantics(
        label: 'Editar · Altera os arquivos',
        isInMutuallyExclusiveGroup: true,
        isChecked: true,
        hasCheckedState: true,
      ),
    );
    expect(
      tester.getSemantics(card(PromptMode.plan)),
      isSemantics(
        label: 'Planejar · Você aprova antes',
        isInMutuallyExclusiveGroup: true,
        isChecked: false,
        hasCheckedState: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('R7 · an example picks the mode of its card and fills the '
      'field, without sending', (tester) async {
    final (db, cli, c) = await pumpPrompt(tester, withConversation: false);
    await tester.tap(example(PromptMode.edit, 1));
    await pumpFor(tester, 3);

    expect(fieldText(tester), 'Deixe o botão Comprar verde');
    expect(c.read(promptDraftProvider).mode, PromptMode.edit);
    // The cursor is at the end and the field has the focus, to adjust it.
    final ctl = tester.widget<TextField>(field).controller!;
    expect(ctl.selection.baseOffset, ctl.text.length);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    // Nothing went to the agent and no conversation was created.
    expect(cli.args, isEmpty);
    expect(await db.select(db.conversations).get(), isEmpty);
    expect(find.byKey(const ValueKey('prompt-welcome')), findsOneWidget);

    // Another example replaces the text and the mode.
    await tester.tap(example(PromptMode.ask, 0));
    await pumpFor(tester, 3);
    expect(fieldText(tester), 'O que esse projeto faz?');
    expect(c.read(promptDraftProvider).mode, PromptMode.ask);
  });

  testWidgets('R10 · the group, the cards and the examples are announced', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpPrompt(tester, withConversation: false);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('prompt-welcome-modes'))),
      isSemantics(label: 'Modo da conversa', role: SemanticsRole.radioGroup),
    );
    expect(
      tester.getSemantics(card(PromptMode.ask)),
      isSemantics(
        label: 'Perguntar · Nada muda nos arquivos',
        isInMutuallyExclusiveGroup: true,
        isChecked: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(example(PromptMode.plan, 0)),
      isSemantics(
        label: 'Como eu colocaria modo escuro?',
        isButton: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('R9 · below 760 px of height the examples go and the cards '
      'keep name, sentence and seal', (tester) async {
    await pumpPrompt(
      tester,
      withConversation: false,
      size: const Size(1440, 740),
    );
    for (final m in PromptMode.selectable) {
      expect(card(m), findsOneWidget);
      expect(
        find.descendant(of: card(m), matching: find.text(modeIntros[m]!.seal)),
        findsOneWidget,
      );
      expect(example(m, 0), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('R9 · in a narrow column the cards wrap instead of '
      'squeezing', (tester) async {
    await pumpPrompt(
      tester,
      withConversation: false,
      size: const Size(1100, 700),
    );
    expect(tester.takeException(), isNull);
    final ask = tester.getRect(card(PromptMode.ask));
    final edit = tester.getRect(card(PromptMode.edit));
    expect(ask.width, greaterThanOrEqualTo(220));
    expect(edit.top, greaterThan(ask.top));
    expect(example(PromptMode.ask, 0), findsNothing);
  });

  testWidgets('without a workspace the screen stays "Nenhum workspace"', (
    tester,
  ) async {
    await shell.pumpShell(tester);
    await shell.ctrl(tester, LogicalKeyboardKey.digit3);
    expect(shell.item(tester, AppSection.prompt).active, isTrue);
    expect(find.text('Nenhum workspace'), findsOneWidget);
    expect(find.byKey(const ValueKey('prompt-welcome')), findsNothing);
    // Unmount before the binding does it (drift's closing timer).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
