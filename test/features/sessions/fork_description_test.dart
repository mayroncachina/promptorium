import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/sessions/new_session_dialog.dart';

void main() {
  test('o fork do Codex cita o thread/fork, não as flags do Claude', () {
    final codex = forkDescription(provider: 'codex', branch: 'pr/x');
    expect(codex, contains('thread/fork'));
    expect(codex, isNot(contains('--resume')));
    expect(codex, isNot(contains('--fork-session')));
    expect(codex, contains('pr/x'));

    final claude = forkDescription(provider: 'claude', branch: 'pr/x');
    expect(claude, contains('--resume --fork-session'));
  });
}
