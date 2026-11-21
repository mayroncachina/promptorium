import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/prompt/prompt_screen.dart';

import 'prompt_screen_test.dart' show pumpPrompt, pumpFor;

/// SPEC-096 R4 on the screen: another provider never continues a
/// conversation — a new one opens, with the notice.
void main() {
  testWidgets('R4: choosing the Codex in a Claude conversation with history '
      'opens a new conversation with the notice', (tester) async {
    final (_, _, c) = await pumpPrompt(tester);
    expect(c.read(selectedConversationProvider), 1);
    await tester.tap(find.byKey(const ValueKey('prompt-provider')));
    await pumpFor(tester);
    await tester.tap(find.byKey(const ValueKey('provider-codex')).last);
    await pumpFor(tester);
    expect(c.read(selectedConversationProvider), isNull);
    expect(c.read(promptDraftProvider).providerId, 'codex');
    expect(
      find.text(providerSwitchNotice('Codex', 'Claude Code')),
      findsOneWidget,
    );
    // The Claude conversation is still there, untouched.
    final conv = await c.read(conversationsRepoProvider).getById(1);
    expect(conv!.provider, 'claude');
  });
}
