import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:promptorium/data/repos/app_settings_repo.dart';
import 'package:promptorium/ui/shell/about_dialog.dart';

import '../../helpers/test_db.dart';
import '../preferences_test.dart' show pumpLoadedShell, unmount;

/// SPEC-070 R6: the first start after an update says so, once.
void _version(String v) => PackageInfo.setMockInitialValues(
  appName: 'promptorium',
  packageName: 'promptorium',
  version: v,
  buildNumber: '6',
  buildSignature: '',
);

void main() {
  const notice = ValueKey('update-installed');
  setUp(() => _version('0.17.0'));

  testWidgets('the new copy shows "Atualizado para a <versão>" once, and '
      '"Ver novidades" opens Sobre', (tester) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final repo = AppSettingsRepo(db);
    await tester.runAsync(
      () => repo.set(AppSettingKeys.justInstalled, '0.17.0'),
    );
    var c = await pumpLoadedShell(tester, db);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(notice), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(notice),
        matching: find.text('Atualizado para a 0.17.0'),
      ),
      findsOneWidget,
    );
    // The mark goes away as soon as it is shown.
    final saved = await tester.runAsync(repo.getAll);
    expect(saved, isNot(contains(AppSettingKeys.justInstalled)));

    await tester.tap(find.text('Ver novidades'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AboutPromptoriumDialog), findsOneWidget);
    await unmount(tester, c);

    c = await pumpLoadedShell(tester, db);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(notice), findsNothing);
    await unmount(tester, c);
  });

  testWidgets('R13 · a copy on another version says the update did not '
      'reach it', (tester) async {
    _version('0.16.0');
    final db = memoryDatabase();
    addTearDown(db.close);
    final repo = AppSettingsRepo(db);
    await tester.runAsync(
      () => repo.set(AppSettingKeys.justInstalled, '0.17.0'),
    );
    final c = await pumpLoadedShell(tester, db);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(notice), findsNothing);
    expect(find.byKey(const ValueKey('update-not-applied')), findsOneWidget);
    expect(
      find.textContaining('A 0.17.0 foi instalada, mas esta cópia está na '
          '0.16.0'),
      findsOneWidget,
    );
    expect(find.text('Ver no Sobre'), findsOneWidget);
    await unmount(tester, c);
  });

  testWidgets('R4 · any start ends the wait for a restart', (tester) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final repo = AppSettingsRepo(db);
    await tester.runAsync(
      () => repo.set(
        AppSettingKeys.pendingRestart,
        '{"version":"0.17.0","executable":"/x/promptorium"}',
      ),
    );
    final c = await pumpLoadedShell(tester, db);
    await tester.pump();
    final saved = await tester.runAsync(repo.getAll);
    expect(saved, isNot(contains(AppSettingKeys.pendingRestart)));
    await unmount(tester, c);
  });

  testWidgets('without the mark nothing is said', (tester) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final c = await pumpLoadedShell(tester, db);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(notice), findsNothing);
    await unmount(tester, c);
  });
}
