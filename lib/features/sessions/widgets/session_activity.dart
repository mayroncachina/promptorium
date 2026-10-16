import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../ui/theme/tokens.dart';
import '../timeline.dart';

/// What the agent is doing now, from the end of the [items] of a running
/// turn ("Executando Bash", "Escrevendo a resposta", "Pensando").
String activityLabel(List<TimelineItem> items) {
  final last = items.isEmpty ? null : items.last;
  return switch (last) {
    ToolItem(done: false, isSubagent: true) => 'Subagente trabalhando',
    ToolItem(done: false, :final name) => 'Executando $name',
    AssistantTextItem(live: true) => 'Escrevendo a resposta',
    _ => 'Pensando',
  };
}

/// `1:05` / `42s`.
String formatElapsed(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  if (s < 60) return '${s}s';
  final m = s ~/ 60;
  final r = (s % 60).toString().padLeft(2, '0');
  return m < 60
      ? '$m:$r'
      : '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

/// Cheap fingerprint of the end of the timeline: it changes whenever the
/// agent produced something (the items are mutated in place).
int _signature(List<TimelineItem> items) {
  final last = items.isEmpty ? null : items.last;
  return Object.hash(items.length, switch (last) {
    AssistantTextItem(:final text) => text.length,
    ToolItem(:final done, :final children) => Object.hash(
      done,
      children.length,
    ),
    _ => 0,
  });
}

/// Spinner + what the agent is doing + elapsed time of the turn. When
/// nothing new arrives for a while it says so, so the user can tell a long
/// step from a stuck one.
class SessionActivity extends StatefulWidget {
  const SessionActivity({
    super.key,
    required this.items,
    required this.since,
    this.quiet = const Duration(seconds: 45),
  });

  final List<TimelineItem> items;
  final DateTime since;

  /// Silence after which the "sem novidades" hint shows.
  final Duration quiet;

  @override
  State<SessionActivity> createState() => _SessionActivityState();
}

class _SessionActivityState extends State<SessionActivity>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _sig = 0;
  DateTime _lastChange = DateTime.now();
  int _shownSecond = -1;

  @override
  void initState() {
    super.initState();
    _sig = _signature(widget.items);
    _ticker = createTicker((_) {
      final sec = DateTime.now().difference(widget.since).inSeconds;
      if (sec != _shownSecond) setState(() {});
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sig = _signature(widget.items);
    if (sig != _sig) {
      _sig = sig;
      _lastChange = now;
    }
    _shownSecond = now.difference(widget.since).inSeconds;
    final silent = now.difference(_lastChange);
    final stale = silent >= widget.quiet;
    final color = stale ? AppColors.amber : AppColors.teal;
    return Row(
      key: const ValueKey('session-activity'),
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            '${activityLabel(widget.items)}… · '
            '${formatElapsed(now.difference(widget.since))}'
            '${stale ? ' · sem novidades há ${formatElapsed(silent)}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ),
      ],
    );
  }
}

/// Small spinner of a running session in the list.
class BusyDot extends StatelessWidget {
  const BusyDot(this.color, {super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 10,
    height: 10,
    child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
  );
}
