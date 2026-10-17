import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_service.dart';
import '../../data/providers.dart';

import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import 'navigation.dart';
import 'notification_center.dart';

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
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const _Logo(),
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
              withIcon: section == AppSection.sessions,
              onTap: onAction,
            ),
          ],
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppColors.amber,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: AppIcon(AppIcons.flask, size: 16, color: AppColors.onAmber),
        ),
        const SizedBox(width: 8),
        const Text(
          'Promptorium',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            letterSpacing: 0.2,
            color: AppColors.text,
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
    this.border = true,
    this.padding = 10,
    this.semanticLabel,
  });

  final VoidCallback onTap;
  final Widget child;
  final Color background;
  final bool border;
  final double padding;
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
          side: border
              ? const BorderSide(color: AppColors.border)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            height: 30,
            padding: EdgeInsets.symmetric(horizontal: padding),
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.withIcon,
    required this.onTap,
  });

  final String label;
  final bool withIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _BarButton(
      onTap: onTap,
      background: AppColors.amber,
      border: false,
      padding: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (withIcon) ...[
            AppIcon(AppIcons.plus, size: 14, color: AppColors.onAmber),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.onAmber,
            ),
          ),
        ],
      ),
    );
  }
}
