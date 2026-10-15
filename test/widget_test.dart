import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/app.dart';
import 'package:promptorium/ui/shell/app_shell.dart';
import 'package:promptorium/ui/theme/tokens.dart';

void main() {
  testWidgets('app without splash shows the shell on dark background', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: PromptoriumApp(showSplash: false)),
    );

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text('Promptorium'), findsOneWidget);

    final theme = Theme.of(tester.element(find.byType(AppShell)));
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.brightness, Brightness.dark);
  });

  test('stream-json fixture is present and non-empty', () {
    final file = File('test/fixtures/stream-json-exemplo.jsonl');
    expect(file.existsSync(), isTrue);
    expect(
      file.readAsLinesSync().where((l) => l.trim().isNotEmpty),
      isNotEmpty,
    );
  });
}
