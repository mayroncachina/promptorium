import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_service.dart';
import '../../data/providers.dart';

import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/brand_mark.dart';
import '../widgets/cta_button.dart';
import '../../features/vibe/widgets/vibe_widgets.dart' show showVibeStartDialog;
import 'brand_activity.dart';
import 'navigation.dart';
import 'notification_center.dart';
import '../theme/ambient.dart';

/// Top bar (44px): logo, workspace selector, command search, contextual action.
class TitleBar extends StatelessWidget {
  const TitleBar({
    super.key,
    required this.section,
    required this.onOpenPalette,
    required this.onAction,
    required this.onWorkspace,
  });

  final AppSection section;
  final VoidCallback onOpenPalette;
  final VoidCallback onAction;
  final VoidCallback onWorkspace;

  @override
  Widget build(BuildContext context) {
    final action = section.actionLabel;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const TitleBarLogo(),
          const SizedBox(width: 12),
          _WorkspaceButton(onTap: onWorkspace),
          const SizedBox(width: 12),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: _SearchButton(onTap: onOpenPalette),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const NotificationBell(),
          if (action != null) ...[
            const SizedBox(width: 12),
            _ActionButton(
              key: const ValueKey('title-action'),
              label: action,
              section: section,
              onTap: onAction,
            ),
            // SPEC-069 R1: the menu of "Nova spec" in the Quadro.
            if (section == AppSection.tasks) _NewSpecMenu(onNewSpec: onAction),
          ],
        ],
      ),
    );
  }
}

/// The Promptorium mark and name (SPEC-031). While specs of the active
/// project run, the mark plays the splash's ambient loop and opens the
/// Quadro on click; when they stop, it finishes the loop and fades still.
class TitleBarLogo extends ConsumerStatefulWidget {
  const TitleBarLogo({super.key});
  @override
  ConsumerState<TitleBarLogo> createState() => _TitleBarLogoState();
}

class _TitleBarLogoState extends ConsumerState<TitleBarLogo> {
  AnimationController? _wave;
  bool _stopping = false;

  /// Starts, resumes or winds down the loop (R3, R5, R6).
  void _sync(bool wanted, bool reduced) {
    final c = _wave;
    if (wanted && c == null) {
      _wave = AnimationController(
        vsync: AmbientVsync(context),
        duration: brandMotionCycle,
      )..repeat();
    } else if (wanted && _stopping) {
      _stopping = false;
      c!.repeat();
    } else if (!wanted && c != null && reduced) {
      c.dispose();
      _wave = null;
      _stopping = false;
    } else if (!wanted && c != null && !_stopping) {
      _stopping = true;
      c.forward().whenCompleteOrCancel(() {
        if (!mounted || !_stopping || _wave != c) return;
        setState(() {
          c.dispose();
          _wave = null;
          _stopping = false;
        });
      });
    }
  }

  @override
  void dispose() {
    _wave?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activity = ref.watch(brandActivityProvider);
    final reduced = MediaQuery.disableAnimationsOf(context);
    _sync(activity != null && !reduced, reduced);
    final label = brandLabel(activity);
    final wave = _wave;
    Widget mark = AnimatedSwitcher(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 300),
      child: wave == null
          ? const BrandMark(key: ValueKey('brand-still'))
          : BrandMark(key: const ValueKey('brand-wave'), wave: wave),
    );
    if (activity != null) {
      // R9: while specs run the mark opens the Quadro.
      mark = InkWell(
        key: const ValueKey('brand-open-board'),
        borderRadius: BorderRadius.circular(6),
        onTap: () =>
            ref.read(navigationProvider.notifier).request(AppSection.tasks),
        child: mark,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: label,
          child: Semantics(
            key: const ValueKey('brand-mark'),
            label: label,
            image: activity == null,
            button: activity != null,
            child: mark,
          ),
        ),
        const SizedBox(width: 8),
        const ExcludeSemantics(
          child: Text(
            'Promptorium',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              letterSpacing: 0.2,
              color: AppColors.text,
            ),
          ),
        ),
      ],
    );
  }
}

/// Bordered 30px-high button used across the title bar.
class _BarButton extends StatelessWidget {
  const _BarButton({
    super.key,
    required this.onTap,
    required this.child,
    required this.background,
    this.semanticLabel,
  });

  final VoidCallback onTap;
  final Widget child;
  final Color background;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(6);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _WorkspaceButton extends ConsumerWidget {
  const _WorkspaceButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeWorkspaceProvider);
    final branch = active == null
        ? null
        : ref.watch(currentBranchProvider(active.path)).value;
    return _BarButton(
      key: const ValueKey('title-workspace'),
      onTap: () {
        // Branch may have changed outside the app: refresh on open.
        if (active != null) ref.invalidate(currentBranchProvider(active.path));
        onTap();
      },
      background: AppColors.surfaceRaised,
      semanticLabel: 'Selecionar workspace',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Workspace',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              active?.name ?? 'Selecionar…',
              key: const ValueKey('title-workspace-name'),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.text,
              ),
            ),
          ),
          if (branch != null) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                branch,
                key: const ValueKey('title-workspace-branch'),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.teal,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          AppIcon(
            AppIcons.chevronDown,
            size: 12,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _BarButton(
      key: const ValueKey('title-search'),
      onTap: onTap,
      background: AppColors.background,
      semanticLabel: 'Buscar ou executar comando',
      child: Row(
        children: [
          AppIcon(AppIcons.search, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Buscar ou executar comando…',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'Ctrl K',
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The menu next to "Nova spec" in the Quadro (SPEC-069 R1): "Nova spec"
/// and "Fazer como tarefa".
class _NewSpecMenu extends ConsumerWidget {
  const _NewSpecMenu({required this.onNewSpec});

  final VoidCallback onNewSpec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      key: const ValueKey('title-action-menu'),
      tooltip: 'Mais formas de começar',
      icon: const Icon(Icons.expand_more, size: 18),
      onSelected: (v) {
        if (v == 'spec') return onNewSpec();
        final ws = ref.read(activeWorkspaceProvider);
        if (ws != null) showVibeStartDialog(context, workspace: ws);
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'spec', child: Text('Nova spec')),
        PopupMenuItem(
          key: ValueKey('title-action-vibe'),
          value: 'vibe',
          child: Row(
            children: [
              Icon(Icons.bolt, size: 16, color: AppColors.lilac),
              SizedBox(width: 8),
              Text('Fazer como tarefa'),
            ],
          ),
        ),
      ],
    );
  }
}

/// The section's main action, as the animated call to action (SPEC-053):
/// it breathes in Specs and in the Quadro while the active workspace has no
/// spec (R4).
class _ActionButton extends ConsumerWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.section,
    required this.onTap,
  });

  final String label;
  final AppSection section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(activeWorkspaceProvider);
    final specs = ws == null ? null : ref.watch(specsProvider(ws.id)).value;
    final attention =
        (section == AppSection.specs || section == AppSection.tasks) &&
        specs != null &&
        specs.isEmpty;
    return CtaButton(label: label, onTap: onTap, attention: attention);
  }
}
