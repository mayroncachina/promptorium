import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/prompt/prompt_screen.dart';

import '../../core/codex/fake_codex.dart';
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

  testWidgets('SPEC-096: the first message of a new Codex conversation shows '
      'once', (tester) async {
    final servers = <FakeCodex>[];
    final (db, _, c) = await pumpPrompt(
      tester,
      withConversation: false,
      overrides: [
        providerAvailabilityProvider.overrideWith(
          (ref, id) async =>
              const ProviderAvailability(ProviderStatus.ready, 'ok'),
        ),
        codexProcessStarterProvider.overrideWithValue((
          exe,
          args, {
          workingDirectory,
          environment,
        }) async {
          final f = FakeCodex();
          servers.add(f);
          return f;
        }),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('prompt-provider')));
    await pumpFor(tester);
    await tester.tap(find.byKey(const ValueKey('provider-codex')).last);
    await pumpFor(tester);
    await tester.enterText(
      find.byKey(const ValueKey('prompt-field')),
      'Uma pergunta só',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFor(tester, 20);
    final id = c.read(selectedConversationProvider)!;
    final n = c
        .read(conversationTimelineProvider(id))
        .items
        .whereType<UserItem>()
        .length;
    expect(n, 1);
    expect(
      (await c.read(conversationsRepoProvider).getById(id))!.provider,
      'codex',
    );
    for (final s in servers) {
      await tester.runAsync(s.finish);
    }
  });
}
