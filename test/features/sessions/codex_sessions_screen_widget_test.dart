import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/data/providers.dart';

import 'sessions_screen_test.dart' show pumpScreen, pumpFor;

/// SPEC-096 T3 on the screen. Under the fake clock the database writes go
/// through `tester.runAsync` and the codex availability is overridden (no
/// real `codex --version`), so nothing waits on real I/O.
void main() {
  testWidgets('R3, R12, R16, P3: header "Interrompida por você" with Retomar; '
      'panel with provider, thread, parent and forks', (tester) async {
    final (db, _) = await pumpScreen(
      tester,
      overrides: [
        providerAvailabilityProvider.overrideWith(
          (ref, id) async =>
              const ProviderAvailability(ProviderStatus.ready, 'ok'),
        ),
      ],
    );
    await tester.runAsync(() async {
      await (db.update(db.sessions)..where((s) => s.id.equals('s1'))).write(
        SessionsCompanion(
          provider: const Value('codex'),
          model: const Value('gpt-6.2-sol'),
          externalId: const Value('019a7c2e-4f1b-7d0a-9e33-5b1c0f6a2d84'),
          runConfig: Value(jsonEncode({'interrupted': 'user'})),
        ),
      );
    });
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('session-header-title')), findsOneWidget);
    await tester.runAsync(() async {
      await db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 's2',
              workspaceId: 1,
              worktreePath: '/work/repo-wt2',
              branch: 'pr/fork',
              model: 'gpt-6.2-sol',
              provider: const Value('codex'),
              title: const Value('Fork'),
              parentSessionId: const Value('s1'),
              status: const Value(SessionStatus.completed),
            ),
          );
    });
    await pumpFor(tester);
    // The newest session gets selected: pick s1 by hand.
    await tester.tap(find.byKey(const ValueKey('session-tile-s1')));
    await pumpFor(tester, 3);
    expect(find.text('Interrompida por você'), findsWidgets);
    expect(find.byKey(const ValueKey('session-resume')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-thread')), findsOneWidget);
    expect(find.text('019a7c2e…2d84'), findsOneWidget);
    expect(find.text('BIFURCAÇÕES'), findsOneWidget);
    expect(find.byKey(const ValueKey('session-fork-s2')), findsOneWidget);
    // The fork shows "bifurcada de …".
    await tester.tap(find.byKey(const ValueKey('session-tile-s2')));
    await pumpFor(tester, 3);
    expect(find.byKey(const ValueKey('session-parent')), findsOneWidget);
    expect(find.text('Shell da IDE'), findsWidgets);
  });
}
