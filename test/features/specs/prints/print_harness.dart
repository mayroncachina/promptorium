import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/clipboard/clipboard_image.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/ideas/widgets/idea_field.dart';
import 'package:promptorium/features/specs/spec_design.dart';
import 'package:promptorium/features/specs/spec_planner.dart';
import 'package:promptorium/features/specs/specs_screen.dart';
import 'package:promptorium/features/specs/workspace_watcher.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:re_editor/re_editor.dart' show CodeEditor;

import '../../../helpers/test_db.dart';
import '../../sessions/session_test_utils.dart';
import '../spec_action_lock_test.dart' show FakeDesigner;
import '../spec_file_test.dart' show sample;
import '../specs_screen_test.dart' show QuietWorkspaceWatcher, settleIo;
import 'print_test_utils.dart';

Finder key(String k) => find.byKey(ValueKey(k));

/// The clipboard of the test: an image, nothing, or no tool.
class FakeReader extends ClipboardImageReader {
  FakeReader() : super(environment: const {});

  ClipboardImageResult next = const ClipboardNoImage();
  var reads = 0;

  @override
  Future<ClipboardImageResult> read() async {
    reads++;
    return next;
  }
}

/// State of the print widget tests (shared by the files of R1–R12).
late Directory tmp;
late FakeCli cli;
late ProviderContainer c;
late Workspace ws;
late FakeReader reader;
String? picked;
String? clipboardText;
late Uint8List png;

/// Registers the setUp and tearDown of the harness.
void setUpPrintHarness() {
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-print-paste-');
    Directory('${tmp.path}/specs').createSync();
    File('${tmp.path}/specs/SPEC-002-sessoes.md').writeAsStringSync(sample);
    reader = FakeReader();
    picked = null;
    clipboardText = null;
  });
  tearDown(() => tmp.deleteSync(recursive: true));
}

Future<void> pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => switch (call.method) {
      'Clipboard.getData' =>
        clipboardText == null ? null : {'text': clipboardText},
      'Clipboard.hasStrings' => {'value': clipboardText != null},
      _ => null,
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  final db = memoryDatabase();
  cli = FakeCli();
  c = ProviderContainer(
    overrides: [
      ...sessionOverrides(db: db, cli: cli, notifier: FakeNotifier()),
      workspaceWatcherProvider.overrideWith(QuietWorkspaceWatcher.new),
      specDesignerProvider.overrideWith((ref) => FakeDesigner(ref)),
      clipboardImageReaderProvider.overrideWithValue(reader),
      printFilePickerProvider.overrideWithValue(() async => picked),
    ],
  );
  await tester.runAsync(() async {
    png = await pngBytes(2880, 1800);
    ws = await db
        .into(db.workspaces)
        .insertReturning(
          WorkspacesCompanion.insert(path: tmp.path, name: 'ws'),
        );
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: AppSettingKeys.activeWorkspace,
            value: '${ws.id}',
          ),
        );
    await c.read(appSettingsProvider.notifier).load();
  });
  c.read(navigationProvider.notifier).go(AppSection.specs);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: SpecsScreen()),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(Duration.zero);
  });
  await settleIo(
    tester,
    until: () => find.byType(CodeEditor).evaluate().isNotEmpty,
  );
  c.read(newSpecFlowProvider.notifier).open();
  await settleIo(tester, until: () => key('new-spec-idea').present);
}

bool enabled(WidgetTester tester, String k) =>
    (tester.widget(key(k)) as dynamic).onTap != null;

Future<void> ctrlV(WidgetTester tester) async {
  await tester.tap(key('new-spec-idea'));
  await tester.pump();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

List<File> attachments() {
  final d = Directory('${tmp.path}/.promptorium/attachments');
  if (!d.existsSync()) return const [];
  return d.listSync(recursive: true).whereType<File>().toList();
}

extension FinderPresent on Finder {
  bool get present => evaluate().isNotEmpty;
}
