import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/capabilities.dart';
import '../../../core/providers/provider_availability.dart';
import '../../../data/providers.dart';
import '../../../ui/providers/provider_logos.dart';
import '../../../ui/theme/tokens.dart';
import '../session_manager.dart';
import '../widgets/session_style.dart';
import 'continue_controller.dart';
import 'continue_dialog.dart';
import 'continue_link.dart';
import 'session_summary.dart' show providerWords;

/// Under `flutter test` the header never starts the CLI probes by itself
/// (they would run real processes in every screen test): it uses them only
/// once something else created them.
final _inTest = Platform.environment['FLUTTER_TEST'] == 'true';

ProviderAvailability? _availability(WidgetRef ref, String id) {
  final p = providerAvailabilityProvider(id);
  if (_inTest && !ref.exists(p)) return null;
  return ref.watch(p).value;
}

/// The availability of "Continuar no …" for [session] (R1).
ContinueAvailability watchContinueAvailability(WidgetRef ref, Session s) {
  final target = continueTarget(s.provider);
  if (target == null) return const ContinueAvailability.hidden();
  final live = ref.watch(sessionManagerProvider.select((m) => m.live[s.id]));
  return continueAvailability(
    session: s,
    busy: live?.busy ?? false,
    approvals: live?.approvals.length ?? 0,
    origin: _availability(ref, s.provider),
    target: _availability(ref, target),
    flows: ref.watch(providerFlowsProvider),
    workspacePath: ref.watch(activeWorkspaceProvider)?.path,
  );
}

/// "Continuar no Codex" of the session header, beside Fork (R1). Hidden
/// when it does not apply (P4); disabled with the reason as a tooltip.
class ContinueButton extends ConsumerWidget {
  const ContinueButton({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = watchContinueAvailability(ref, session);
    if (!a.visible) return const SizedBox.shrink();
    final button = SmallButton(
      key: const ValueKey('session-continue'),
      label: continueLabel(a.target!),
      color: AppColors.teal,
      border: a.enabled ? ReviewColors.acceptBorder : AppColors.border,
      onTap: a.enabled ? () => openContinue(context, ref, session) : null,
    );
    if (a.reason == null) return button;
    return Tooltip(
      key: const ValueKey('session-continue-reason'),
      message: a.reason!,
      child: button,
    );
  }
}

/// The link of a continued session (R9): "continuada de (título) · Claude
/// Code" on the new one, "Continuada no Codex → (título)" on the origin.
/// Each end opens the other session; a removed one leaves no link.
class ContinueLinkLine extends ConsumerWidget {
  const ContinueLinkLine({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = session;
    final links =
        ref.watch(continuationLinksProvider(s.workspaceId)).value ??
        const ContinuationLinks();
    final all =
        ref.watch(sessionsProvider(s.workspaceId)).value ?? const <Session>[];
    Session? byId(String? id) =>
        id == null ? null : all.where((x) => x.id == id).firstOrNull;
    final from = links.of(s.id);
    final parent = from == null ? null : byId(from.fromId);
    final child = byId(links.continuedInto(s.id));
    if (parent == null && child == null) return const SizedBox.shrink();
    void open(Session x) =>
        ref.read(selectedSessionProvider.notifier).select(x.id);
    const style = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    Widget link(Session x, String key) => InkWell(
      key: ValueKey(key),
      onTap: () => open(x),
      child: Text(
        sessionTitle(x),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.text,
          decoration: TextDecoration.underline,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (parent != null) ...[
            const Icon(Icons.link, size: 13, color: AppColors.textSecondary),
            const Text('continuada de', style: style),
            link(parent, 'session-continued-from'),
            if (hasProviderIdentity(parent.provider))
              ProviderChip(parent.provider, dense: true),
          ],
          if (child != null) ...[
            if (parent != null) const Text('·', style: style),
            Text(
              'Continuada no ${providerWords(child.provider).split(' ').first} →',
              style: const TextStyle(fontSize: 12, color: AppColors.teal),
            ),
            link(child, 'session-continued-into'),
          ],
        ],
      ),
    );
  }
}
