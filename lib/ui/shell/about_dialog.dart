import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/update/update_check.dart';
import '../theme/tokens.dart';

const repositoryUrl = 'https://github.com/mayroncachina/promptorium';

/// Local `CHANGELOG.md` (bundled asset, so it works offline); read on first
/// use, when the dialog opens.
final changelogProvider = FutureProvider<String>(
  (ref) => rootBundle.loadString('CHANGELOG.md'),
);

/// Diálogo Sobre (F1).
Future<void> showAboutPromptorium(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) => const AboutPromptoriumDialog(),
);

class AboutPromptoriumDialog extends ConsumerWidget {
  const AboutPromptoriumDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).value;
    final changelog = ref.watch(changelogProvider);
    final style = MarkdownStyleSheet.fromTheme(Theme.of(context))
        .copyWith(p: const TextStyle(fontSize: 12));
    // The dialog route is outside AppShell's shortcuts: F1 closes here.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          key: const ValueKey('about-dialog'),
          backgroundColor: AppColors.panel,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: SessionColors.selectedBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Sobre o Promptorium',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Promptorium',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        version == null ? 'Versão …' : 'Versão $version',
                        key: const ValueKey('about-version'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        key: const ValueKey('about-repo'),
                        onTap: () => Process.run('xdg-open', [repositoryUrl]),
                        child: const Text(
                          repositoryUrl,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.amber,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('about-changelog'),
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                    child: changelog.when(
                      data: (md) => MarkdownBody(data: md, styleSheet: style),
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => const Text(
                        'Changelog indisponível.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
