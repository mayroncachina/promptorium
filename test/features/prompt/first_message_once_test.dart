import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/sessions/timeline_provider.dart';

/// A timeline whose load waits for [gate]: the row is written while the
/// load runs, the load reads it, and the live push of the same row comes
/// after the load (the race of the first message of a new conversation).
class _Gated extends StoredTimelineNotifier {
  static final rows = <StoredTimelineEvent>[];
  static Completer<void> gate = Completer<void>();

  @override
  String get debugName => 'teste';

  @override
  Future<List<StoredTimelineEvent>> loadStored() async {
    await gate.future;
    return List.of(rows);
  }
}

final _provider = NotifierProvider<_Gated, TimelineSnapshot>(_Gated.new);

void main() {
  test('SPEC-096: a live event of a row the load already read is not applied '
      'twice; one stored line expanded into several events still is', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(_provider, (_, _) {});
    final user = AppEventTypes.userMessage('Oi', DateTime(2026, 11, 21));
    // The row is written while the load runs, and the load reads it.
    _Gated.rows.add((json: jsonEncode(user), at: DateTime(2026), seq: 1));
    _Gated.gate.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    // The live push of the same row arrives after the load.
    c.read(_provider.notifier).push(UnknownEvent(user), seq: 1);
    expect(c.read(_provider).items.whereType<UserItem>(), hasLength(1));
    // A new row pushed twice (one line, two events) is applied both times.
    final next = AppEventTypes.userMessage('De novo', DateTime(2026, 11, 21));
    c.read(_provider.notifier).push(UnknownEvent(next), seq: 2);
    c.read(_provider.notifier).push(UnknownEvent(next), seq: 2);
    expect(c.read(_provider).items.whereType<UserItem>(), hasLength(3));
  });
}
