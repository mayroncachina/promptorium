import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/sessions/widgets/session_terminal.dart';
import 'package:promptorium/ui/shell/shell_intents.dart';

void main() {
  testWidgets('F1 in the terminal opens "Sobre" and never reaches the PTY; '
      'F2 still does', (tester) async {
    final term = SessionTerminal('s1');
    final sent = <String>[];
    term.terminal.onOutput = sent.add;
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Shortcuts(
          shortcuts: shellShortcuts,
          child: Actions(
            actions: {
              OpenAboutIntent: CallbackAction<OpenAboutIntent>(
                onInvoke: (_) {
                  opened++;
                  return null;
                },
              ),
            },
            child: Scaffold(body: AppTerminalView(term: term)),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pump();
    expect(opened, 1);
    expect(sent, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    expect(opened, 1);
    expect(sent, isNotEmpty);
  });
}
