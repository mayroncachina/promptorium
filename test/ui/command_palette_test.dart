import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/ui/shell/command_palette.dart';
import 'package:promptorium/ui/shell/navigation.dart';

import '../features/board/board_screen_test.dart' show pumpBoard, pumpFor;

void main() {
  test('fuzzy filter: every char in order, best match first', () {
    var ran = '';
    PaletteCommand c(String l) => PaletteCommand(label: l, run: () => ran = l);
    final all = [
      c('Ir para Quadro'),
      c('Executar SPEC-003'),
      c('SPEC-003 · Agentes'),
      c('Ir para Sessões'),
    ];
    expect(filterCommands(all, ''), all);
    expect(filterCommands(all, 'spec3').map((x) => x.label), [
      'SPEC-003 · Agentes',
      'Executar SPEC-003',
    ]);
    expect(filterCommands(all, 'xyz'), isEmpty);
    filterCommands(all, 'quadro').single.run();
    expect(ran, 'Ir para Quadro');
    expect(AppSection.agents.shortcutLabel, 'Ctrl 9');
    expect(AppSection.skills.shortcutLabel, isNull);
  });

  testWidgets('Ctrl+K lists specs, actions and runs "Ir para"', (tester) async {
    final (c, db) = await pumpBoard(tester);
    await tester.runAsync(
      () => db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 's-1',
              workspaceId: 1,
              worktreePath: '/w',
              branch: 'pr/x',
              model: 'sonnet',
              title: const Value('Sessão de teste'),
            ),
          ),
    );
    await pumpFor(tester, 10);
    // The board's element is a WidgetRef.
    final element = tester.element(find.byType(BoardScreen));
    final commands = paletteCommands(
      element,
      element as WidgetRef,
      onNavigate: (s) => c.read(navigationProvider.notifier).go(s),
    );
    final labels = commands.map((x) => x.label).toList();
    expect(labels, contains('SPEC-003 · Agentes'));
    expect(labels, contains('Executar SPEC-003'));
    // SPEC-004 waits for SPEC-002 (still running): not offered.
    expect(labels, isNot(contains('Executar SPEC-004')));
    expect(labels, contains('Ligar Autopilot (Executar tudo)'));
    expect(labels, contains('Sessão de teste'));
    expect(
      commands.firstWhere((x) => x.label == 'Executar SPEC-003').group,
      'Ações',
    );
    commands.firstWhere((x) => x.label == 'Ir para Review').run();
    expect(c.read(navigationProvider), AppSection.review);
    expect(LogicalKeyboardKey.keyK, isNotNull);
  });
}
