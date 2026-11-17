import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/widgets/app_toast.dart';
import 'snippet_naming.dart';

/// A composer that can take a snippet (SPEC-078 R8): the Prompt's and the
/// Sessions' one.
class ComposerTarget {
  ComposerTarget({required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;
}

/// The composers on screen; the one used last (focused or mounted last)
/// takes an inserted snippet ("o composer da tela aberta").
class ComposerTargets {
  final _list = <ComposerTarget>[];

  /// The composer of the open screen; null = none (another screen).
  ComposerTarget? get current => _list.isEmpty ? null : _list.last;

  /// Registers [t] and moves it to the top when it gets focus. Returns the
  /// function that unregisters it (the composer's dispose).
  VoidCallback register(ComposerTarget t) {
    _list
      ..remove(t)
      ..add(t);
    void onFocus() {
      if (t.focusNode.hasFocus && _list.remove(t)) _list.add(t);
    }

    t.focusNode.addListener(onFocus);
    return () {
      t.focusNode.removeListener(onFocus);
      _list.remove(t);
    };
  }
}

final composerTargetProvider = Provider((ref) => ComposerTargets());

/// Snippet that waits for the Prompt's composer: inserting from a screen
/// without a composer opens the Prompt and it goes there (R8).
class PendingSnippetInsert extends Notifier<Snippet?> {
  @override
  Snippet? build() => null;

  void set(Snippet? s) => state = s;

  /// Takes the pending snippet (and clears it).
  Snippet? take() {
    final s = state;
    state = null;
    return s;
  }
}

final pendingSnippetInsertProvider =
    NotifierProvider<PendingSnippetInsert, Snippet?>(PendingSnippetInsert.new);

/// [body] in a fence with [language] (P4): ```` ```sql ````. A body with
/// its own ``` gets a longer fence.
String fencedSnippet(String body, String? language) {
  var fence = '```';
  while (body.contains(fence)) {
    fence += '`';
  }
  final lang = language?.trim() ?? '';
  return '$fence$lang\n$body\n$fence';
}

/// Puts [s] as a fenced block in [c] at the cursor (or over the selection):
/// a blank line before when the cursor is not at the start of a line, and a
/// line break after, so writing goes on below it (R8).
void insertFencedSnippet(TextEditingController c, Snippet s) {
  final text = c.text;
  final sel = c.selection;
  final start = sel.isValid ? sel.start : text.length;
  final end = sel.isValid ? sel.end : text.length;
  final before = text.substring(0, start);
  final lineStart = before.isEmpty || before.endsWith('\n');
  final block = fencedSnippet(s.body, s.language);
  final insert = '${lineStart ? '' : '\n\n'}$block\n';
  c.value = TextEditingValue(
    text: text.replaceRange(start, end, insert),
    selection: TextSelection.collapsed(offset: start + insert.length),
  );
}

void _toast(ScaffoldMessengerState? m, String text) => m
  ?..hideCurrentSnackBar()
  ..showAppToast(SnackBar(content: Text(text)));

/// Copies the exact code of [s], counts a use and says so (R8).
Future<void> copySnippet(
  WidgetRef ref,
  Snippet s, {
  ScaffoldMessengerState? messenger,
}) async {
  await Clipboard.setData(ClipboardData(text: s.body));
  _toast(messenger, 'Snippet copiado: ${shortName(s.name)}');
  await ref.read(snippetsRepoProvider).markUsed(s.id);
}

/// Inserts [s] in the composer of the open screen as a fenced block and
/// counts a use (R8). Without a composer on screen, the Prompt opens (on the
/// selected conversation, or a new one) and the snippet goes there.
Future<void> insertSnippet(
  WidgetRef ref,
  Snippet s, {
  ScaffoldMessengerState? messenger,
}) async {
  final target = ref.read(composerTargetProvider).current;
  if (target == null) {
    ref.read(pendingSnippetInsertProvider.notifier).set(s);
    final went = await ref
        .read(navigationProvider.notifier)
        .request(AppSection.prompt);
    if (!went) {
      ref.read(pendingSnippetInsertProvider.notifier).set(null);
      return;
    }
  } else {
    insertFencedSnippet(target.controller, s);
    target.focusNode.requestFocus();
  }
  _toast(messenger, 'Snippet inserido: ${shortName(s.name)}');
  await ref.read(snippetsRepoProvider).markUsed(s.id);
}
