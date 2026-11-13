import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/vibe/widgets/vibe_widgets.dart';

import '../prompt/prompt_screen_test.dart' show pumpPrompt, pumpFor;

/// "Fazer como tarefa", the warning and the bar (SPEC-069 R1, R2, R7, R13).
void main() {
  testWidgets('"Fazer como tarefa" opens the dialog with the number, the '
      'branch, the base and "Use com cuidado"; "Entendi" leaves a short '
      'line', (tester) async {
    final (_, _, c) = await pumpPrompt(tester, withConversation: false);
    await tester.enterText(
      find.byKey(const ValueKey('prompt-field')),
      'Deixa o botão Comprar verde',
    );
    // The preview reads the folder and git (real IO): in the real zone.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('prompt-vibe')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('vibe-start-dialog')), findsOneWidget);
    String plain(String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).textSpan!.toPlainText();
    expect(plain('vibe-start-code'), 'Número VIBE-001');
    expect(plain('vibe-start-branch'), startsWith('Branch vibe/001-deixa-o-'));
    expect(plain('vibe-start-base'), 'A partir de main');
    expect(find.text('Use com cuidado'), findsOneWidget);
    expect(find.textContaining('Requisitos revisados antes'), findsOneWidget);
    expect(find.textContaining('Gate (testes e lint)'), findsOneWidget);
    expect(find.text('Entra no Quadro em Em execução.'), findsOneWidget);
    expect(find.bySemanticsLabel('VIBE'), findsWidgets);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('vibe-start-text')),
    );
    expect(field.controller!.text, 'Deixa o botão Comprar verde');

    // "Entendi" is saved when the VIBE starts; set it directly here.
    await c.read(appSettingsProvider.notifier).set(vibeWarningSeenKey, '1');
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('vibe-warning')), findsNothing);
    expect(
      find.byKey(const ValueKey('vibe-start-short-warning')),
      findsOneWidget,
    );
  });

  testWidgets('the conversation of a VIBE has its bar with "Enviar para '
      'Review", and no "Fazer como tarefa"', (tester) async {
    late int specId;
    final (db, _, _) = await pumpPrompt(
      tester,
      overrides: const <Override>[],
      withConversation: true,
    );
    final spec = await db
        .into(db.specs)
        .insertReturning(
          SpecsCompanion.insert(
            workspaceId: 1,
            code: 'VIBE-007',
            title: 'Botão Comprar verde',
            path: 'docs/vibe/VIBE-007-botao.md',
            kind: const Value(SpecKind.vibe),
            stage: const Value(SpecStage.running),
            branch: const Value('vibe/007-botao-comprar-verde'),
          ),
        );
    specId = spec.id;
    await (db.update(db.conversations)..where((x) => x.id.equals(1))).write(
      ConversationsCompanion(specId: Value(specId)),
    );
    await pumpFor(tester, 20);
    expect(find.byKey(const ValueKey('vibe-bar-VIBE-007')), findsOneWidget);
    expect(find.text('VIBE-007 · Botão Comprar verde'), findsOneWidget);
    expect(find.text('vibe/007-botao-comprar-verde'), findsOneWidget);
    expect(find.text('Enviar para Review'), findsOneWidget);
    expect(find.byKey(const ValueKey('prompt-vibe')), findsNothing);
  });
}
