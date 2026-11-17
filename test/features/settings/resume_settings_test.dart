import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/resume/activity_journal.dart';
import 'package:promptorium/features/resume/presence.dart';
import 'package:promptorium/features/resume/resume_settings.dart';
import 'package:promptorium/features/resume/resume_summary.dart';
import 'package:promptorium/features/settings/settings_sections.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

/// The journal's drift stream leaves a timer when the tree goes.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
}

Future<ProviderContainer> pumpView(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(1366, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseOverride(db)],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: SingleChildScrollView(child: ResumeSettingsView()),
        ),
      ),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(
    tester.element(find.byType(ResumeSettingsView)),
  );
}

void main() {
  test('Configurações finds the section by "retomar", "fora" and "visto" '
      '(R14)', () {
    for (final q in ['retomar', 'fora', 'visto']) {
      expect(filterSections(q), contains(SettingsSection.resume));
    }
    final i = SettingsSection.values.indexOf(SettingsSection.resume);
    expect(SettingsSection.values[i - 1], SettingsSection.sessions);
    expect(SettingsSection.resume.group, SettingsGroup.app);
    expect(sectionChanged(SettingsSection.resume, const {}, null), isFalse);
    expect(
      sectionChanged(SettingsSection.resume, const {
        AppSettingKeys.resumeOnOpen: '0',
      }, null),
      isTrue,
    );
  });

  testWidgets('turns "ao abrir" off, changes the limit and the kinds (R14)', (
    tester,
  ) async {
    final db = memoryDatabase();
    final c = await pumpView(tester, db);
    Map<String, String> s() => c.read(appSettingsProvider);

    await tester.tap(find.byKey(const ValueKey('resume-open-off')));
    await tester.pump();
    expect(s()[AppSettingKeys.resumeOnOpen], '0');
    await tester.tap(find.byKey(const ValueKey('resume-open-on')));
    await tester.pump();
    expect(s().containsKey(AppSettingKeys.resumeOnOpen), isFalse);

    await tester.tap(find.byKey(const ValueKey('resume-away-60')));
    await tester.pump();
    expect(awayLimitOf(s()), const Duration(hours: 1));
    await tester.tap(find.byKey(const ValueKey('resume-away-0')));
    await tester.pump();
    expect(awayLimitOf(s()), isNull);
    expect(find.text('nunca'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('resume-kind-prs')));
    await tester.pump();
    expect(ResumeKindGroup.decode(s()[AppSettingKeys.resumeHiddenKinds]), {
      ResumeKindGroup.prs,
    });
    await tester.tap(find.byKey(const ValueKey('resume-kind-prs')));
    await tester.pump();
    expect(s().containsKey(AppSettingKeys.resumeHiddenKinds), isFalse);
    await unmount(tester);
  });

  testWidgets('the last seen, the count and "Limpar o diário" (R14)', (
    tester,
  ) async {
    final db = memoryDatabase();
    await db.customStatement(
      "INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')",
    );
    final c = await pumpView(tester, db);
    final repo = c.read(activityEventsRepoProvider);
    await writeJournal(repo, autopilotFinished(1, 1));
    await writeJournal(repo, autopilotFinished(1, 2));
    await tester.pump();
    await tester.pump();
    expect(find.text('O diário guarda 14 dias · 2 registros'), findsOneWidget);
    expect(find.textContaining('Visto por último'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('resume-clear')));
    await tester.pump();
    await tester.pump();
    expect(find.text('O diário guarda 14 dias · 0 registros'), findsOneWidget);
    await unmount(tester);
  });

  test('lastSeenLabel', () {
    final now = DateTime(2026, 11, 17, 10);
    expect(lastSeenLabel(DateTime(2026, 11, 17, 9, 12), now), 'hoje 09:12');
    expect(lastSeenLabel(DateTime(2026, 11, 16, 9, 12), now), 'ontem 09:12');
    expect(lastSeenLabel(null, now), '—');
  });
}
