import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/theme/tokens.dart';
import 'hygiene/hygiene_tab.dart';
import 'releases/releases_tab.dart';
import 'repository_info.dart';

/// A tab of the Repositório screen (SPEC-044 R1). The next specs add theirs
/// to [repositoryTabs]: Grafo (SPEC-045), Atividade (SPEC-046) and Higiene
/// (SPEC-047).
@immutable
class RepositoryTab {
  const RepositoryTab({
    required this.id,
    required this.label,
    required this.builder,
    this.count,
    this.headerTrailing,
  });

  /// Stable id, kept as the last tab seen (`releases`, `grafo`…).
  final String id;

  /// Name on the tab (`Releases`).
  final String label;

  /// Body of the tab, under the header, for the main repository [repo].
  final Widget Function(BuildContext context, RepositoryInfo repo) builder;

  /// Amber counter after the label (Higiene · 89): called in the build of
  /// the tab bar, so it may `ref.watch` providers. Null or 0 = no counter.
  final int? Function(WidgetRef ref, RepositoryInfo repo)? count;

  /// What the header shows on the right while this tab is open (`gh
  /// conectado como …`); null = nothing.
  final Widget Function(BuildContext context, RepositoryInfo repo)?
  headerTrailing;
}

/// The tabs, in order. Adding a tab = one more entry here.
final repositoryTabs = <RepositoryTab>[releasesTab, higieneTab];

/// Tab shown first and when the saved one no longer exists.
const defaultRepositoryTab = 'releases';

/// The open tab of the Repositório screen, kept in the app settings.
class RepositoryTabController extends Notifier<String> {
  static const settingKey = 'repo.tab';

  @override
  String build() {
    final saved = ref.read(appSettingsProvider.notifier).get(settingKey);
    return repositoryTabs.any((t) => t.id == saved)
        ? saved!
        : defaultRepositoryTab;
  }

  void select(String id) {
    if (!repositoryTabs.any((t) => t.id == id)) return;
    state = id;
    ref.read(appSettingsProvider.notifier).set(settingKey, id);
  }
}

final repositoryTabProvider = NotifierProvider<RepositoryTabController, String>(
  RepositoryTabController.new,
);

/// Something asked from outside the screen (the palette's "Criar release")
/// that the open tab carries out once and clears.
enum RepositoryAction { createRelease }

class RepositoryActionController extends Notifier<RepositoryAction?> {
  @override
  RepositoryAction? build() => null;

  void request(RepositoryAction action) => state = action;

  /// The action, cleared (null = nothing asked).
  RepositoryAction? take() {
    final a = state;
    if (a != null) state = null;
    return a;
  }
}

final repositoryActionProvider =
    NotifierProvider<RepositoryActionController, RepositoryAction?>(
      RepositoryActionController.new,
    );

/// Tela Repositório (docs/mockups/repositorio/Abas.dc.html): the header with
/// the repository, the remote and the default branch, the tabs and the open
/// tab's body.
class RepositoryScreen extends ConsumerWidget {
  const RepositoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(activeWorkspaceProvider);
    if (ws == null) {
      return const ColoredBox(
        color: AppColors.background,
        child: Center(
          child: Text(
            'Selecione um workspace na barra de título.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      );
    }
    final info = ref.watch(repositoryInfoProvider(ws.path));
    return ColoredBox(
      color: AppColors.background,
      child: switch (info) {
        AsyncData(:final value) => _Body(repo: value),
        AsyncError(:final error) => Center(
          child: Text(
            'Não foi possível ler o repositório: $error',
            style: const TextStyle(color: AppColors.red, fontSize: 13),
          ),
        ),
        _ => const Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.repo});

  final RepositoryInfo repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(repositoryTabProvider);
    final tab = repositoryTabs.firstWhere(
      (t) => t.id == id,
      orElse: () => repositoryTabs.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepositoryHeader(
          repo: repo,
          active: tab,
          onSelect: ref.read(repositoryTabProvider.notifier).select,
        ),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey('repo-tab-body-${tab.id}'),
            child: tab.builder(context, repo),
          ),
        ),
      ],
    );
  }
}

/// Title, `name · remote · branch`, what the tab adds on the right and the
/// row of tabs with their counters (Abas.dc.html).
class RepositoryHeader extends ConsumerWidget {
  const RepositoryHeader({
    super.key,
    required this.repo,
    required this.active,
    required this.onSelect,
  });

  final RepositoryInfo repo;
  final RepositoryTab active;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trailing = active.headerTrailing?.call(context, repo);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Repositório',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  repo.headline,
                  key: const ValueKey('repo-headline'),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final t in repositoryTabs)
                _TabButton(
                  tab: t,
                  active: t.id == active.id,
                  count: t.count?.call(ref, repo),
                  onTap: () => onSelect(t.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.active,
    required this.count,
    required this.onTap,
  });

  final RepositoryTab tab;
  final bool active;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: active,
    button: true,
    child: InkWell(
      key: ValueKey('repo-tab-${tab.id}'),
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.amber : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: active ? AppColors.text : AppColors.textSecondary,
              ),
            ),
            if ((count ?? 0) > 0) ...[
              const SizedBox(width: 8),
              Container(
                key: ValueKey('repo-tab-count-${tab.id}'),
                constraints: const BoxConstraints(minWidth: 22),
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.amberTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(fontSize: 12, color: AppColors.amber),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
