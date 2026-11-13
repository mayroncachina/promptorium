import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/app_database.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../autopilot.dart';

/// "Executar tudo" (SPEC-064 R1–R3, R7): what starts now, what waits and
/// what never enters, before the autopilot turns on. Returns whether it
/// started.
Future<bool> showAutopilotPreview(
  BuildContext context,
  WidgetRef ref,
  int workspaceId, {
  Rect? origin,
}) async =>
    await showAppDialog<bool>(
      context: context,
      barrierColor: Colors.transparent,
      origin: origin,
      builder: (_) => AutopilotPreview(workspaceId: workspaceId),
    ) ??
    false;

/// The text of a waiting spec (SPEC-064 R1).
String autopilotWaitText(AutopilotWait w, UnblockAt at) {
  if (w.reason != null) return w.reason!;
  final c = w.waitingFor;
  final list = c.length == 1
      ? 'da ${c.single}'
      : '${c.take(c.length - 1).map((x) => 'da $x').join(', ')} e da ${c.last}';
  return 'depois $list chegar em ${at.label}';
}

class AutopilotPreview extends ConsumerStatefulWidget {
  const AutopilotPreview({super.key, required this.workspaceId});

  final int workspaceId;

  @override
  ConsumerState<AutopilotPreview> createState() => _AutopilotPreviewState();
}

class _AutopilotPreviewState extends ConsumerState<AutopilotPreview> {
  late UnblockAt _at = ref
      .read(autopilotProvider.notifier)
      .unblockAtOf(widget.workspaceId);
  late Future<AutopilotPlan> _plan = _load();

  Future<AutopilotPlan> _load() => ref
      .read(autopilotProvider.notifier)
      .planFor(widget.workspaceId, unblockAt: _at);

  Future<void> _setAt(UnblockAt v) async {
    if (v == _at) return;
    setState(() {
      _at = v;
      _plan = _load();
    });
    await ref
        .read(autopilotProvider.notifier)
        .setUnblockAt(widget.workspaceId, v);
  }

  Future<void> _run(AutopilotPlan p) async {
    if (p.nothingToDo) return;
    final pilot = ref.read(autopilotProvider.notifier);
    await pilot.setUnblockAt(widget.workspaceId, _at);
    if (!mounted) return;
    Navigator.of(context).pop(true);
    await pilot.start(widget.workspaceId);
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topRight,
    child: Padding(
      padding: const EdgeInsets.only(top: 118, right: 24, left: 24),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          key: const ValueKey('autopilot-preview'),
          width: 470,
          constraints: const BoxConstraints(maxHeight: 560),
          decoration: BoxDecoration(
            color: AppColors.panelSolid,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderHover),
            boxShadow: const [
              BoxShadow(
                color: Color(0x8C000000),
                blurRadius: 60,
                offset: Offset(0, 24),
              ),
            ],
          ),
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: 'Executar tudo',
            child: FutureBuilder<AutopilotPlan>(
              future: _plan,
              builder: (context, snap) {
                final p = snap.data;
                return CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): () {
                      if (p != null) _run(p);
                    },
                    const SingleActivator(LogicalKeyboardKey.numpadEnter): () {
                      if (p != null) _run(p);
                    },
                    const SingleActivator(LogicalKeyboardKey.escape): () =>
                        Navigator.of(context).pop(false),
                  },
                  child: Focus(
                    autofocus: true,
                    child: p == null
                        ? const SizedBox(
                            height: 120,
                            child: Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          )
                        : _content(p),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );

  Widget _content(AutopilotPlan p) {
    final sub = p.nothingToDo
        ? 'Nenhuma spec pode começar agora.'
        : p.parallel == null
        ? 'Sem limite de specs em paralelo · ajuste em Configurar projeto'
        : 'Até ${p.parallel} specs em paralelo · ajuste em Configurar projeto';
    final waitLabel = p.nothingToDo ? 'Bloqueadas' : 'Esperam';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Executar tudo',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                sub,
                key: const ValueKey('autopilot-preview-sub'),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              if (p.start.isNotEmpty)
                _group(
                  'autopilot-start',
                  Icons.play_arrow,
                  AppColors.teal,
                  'Começam agora · ${p.start.length}',
                  [for (final s in p.start) (s, null)],
                ),
              if (p.wait.isNotEmpty)
                _group(
                  'autopilot-wait',
                  p.nothingToDo ? Icons.warning_amber : Icons.schedule,
                  AppColors.amber,
                  '$waitLabel · ${p.wait.length}',
                  [for (final w in p.wait) (w.spec, autopilotWaitText(w, _at))],
                ),
              if (p.skip.isNotEmpty)
                _group(
                  'autopilot-skip',
                  Icons.lock_outline,
                  AppColors.textMuted,
                  'Não entram · ${p.skip.length}',
                  [for (final s in p.skip) (s.spec, s.reason)],
                ),
              if (p.start.isEmpty && p.wait.isEmpty && p.skip.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 6, 18, 6),
                  child: Text(
                    'Não há specs aprovadas no Backlog.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!p.nothingToDo) _unblockOption(),
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          // A Wrap: with large text the buttons stack instead of overflowing.
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const ValueKey('autopilot-cancel'),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(p.nothingToDo ? 'Fechar' : 'Cancelar'),
              ),
              FilledButton.icon(
                key: const ValueKey('autopilot-run'),
                onPressed: p.nothingToDo ? null : () => _run(p),
                icon: const Icon(Icons.play_arrow, size: 16),
                label: Text(
                  p.nothingToDo
                      ? 'Executar'
                      : 'Executar ${p.count} ${p.count == 1 ? 'spec' : 'specs'}',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _group(
    String key,
    IconData icon,
    Color color,
    String label,
    List<(Spec, String?)> items,
  ) => Padding(
    key: ValueKey(key),
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final (s, why) in items)
          Padding(
            key: ValueKey('$key-${s.code}'),
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 78,
                  child: Text(
                    s.code,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.title, style: const TextStyle(fontSize: 13)),
                      if (why != null)
                        Text(
                          why,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _unblockOption() => Container(
    margin: const EdgeInsets.fromLTRB(18, 8, 18, 0),
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'Liberar quem espera quando a dependência chegar em',
            style: TextStyle(fontSize: 12.5, color: AppColors.text),
          ),
        ),
        const SizedBox(width: 8),
        SegmentedButton<UnblockAt>(
          key: const ValueKey('autopilot-unblock'),
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: UnblockAt.review, label: Text('Review')),
            ButtonSegment(value: UnblockAt.done, label: Text('Feito')),
          ],
          selected: {_at},
          onSelectionChanged: (v) => _setAt(v.first),
        ),
      ],
    ),
  );
}
