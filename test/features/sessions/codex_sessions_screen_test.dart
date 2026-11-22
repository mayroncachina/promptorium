import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/widgets/session_terminal.dart';

/// SPEC-096 R10, R13 (P4): texts of the app's commit and of the terminal.
void main() {
  test('P4: the terminal message names the single writer', () {
    expect(codexTerminalBusyMessage, contains('um escritor por thread'));
    expect(codexTerminalBusyMessage, contains('turno parado'));
  });

  test("R10: the app's commit has the title as subject and the agent's "
      'message as body', () {
    expect(codexTurnCommitMessage('Ledger', null), 'Ledger');
    expect(codexTurnCommitMessage(' ', ''), 'Alterações do Codex');
    expect(
      codexTurnCommitMessage('Ledger', 'Gravei o provedor.'),
      'Ledger\n\nGravei o provedor.',
    );
    expect(codexTurnCommitMessage('L', 'x' * 5000).length, lessThan(4100));
  });
}
