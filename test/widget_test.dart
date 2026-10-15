import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/app.dart';
import 'package:promptorium/ui/theme/tokens.dart';

void main() {
  testWidgets('placeholder home shows app name on dark background', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: PromptoriumApp()));

    expect(find.text('Promptorium'), findsOneWidget);

    final context = tester.element(find.byType(PlaceholderHome));
    final theme = Theme.of(context);
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
