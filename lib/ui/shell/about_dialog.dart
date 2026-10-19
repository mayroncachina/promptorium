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
    final update = ref.watch(updateCheckerProvider);
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Row(
                    children: [
                      const _CheckNowButton(),
                      if (update != null) ...[
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const ValueKey('about-update-now'),
                          // The download and install flow arrives in the next
                          // steps.
                          onPressed: () {},
                          child: const Text('Atualizar agora'),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('about-changelog'),
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (update != null) ...[
                          Text(
                            'Novidades da ${update.version}',
                            key: const ValueKey('about-update-notes-title'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          MarkdownBody(
                            key: const ValueKey('about-update-notes'),
                            data: update.notes.trim().isEmpty
                                ? '_Sem notas nesta versão._'
                                : update.notes,
                            styleSheet: style,
                          ),
                          const SizedBox(height: 14),
                          const Divider(height: 1),
                          const SizedBox(height: 14),
                        ],
                        changelog.when(
                          data: (md) => MarkdownBody(
                            key: const ValueKey('about-changelog-body'),
                            data: md,
                            styleSheet: style,
                          ),
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const Text(
                            'Changelog indisponível.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
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

/// "Verificar agora": forces a lookup of the latest release; the dialog
/// watches [updateCheckerProvider], so the result shows up by itself.
class _CheckNowButton extends ConsumerStatefulWidget {
  const _CheckNowButton();

  @override
  ConsumerState<_CheckNowButton> createState() => _CheckNowButtonState();
}

class _CheckNowButtonState extends ConsumerState<_CheckNowButton> {
  bool _busy = false;
  bool _checked = false;

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      await ref.read(updateCheckerProvider.notifier).check(force: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _checked = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(updateCheckerProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          key: const ValueKey('about-check-now'),
          onPressed: _busy ? null : _check,
          child: Text(_busy ? 'Verificando…' : 'Verificar agora'),
        ),
        if (_checked && !_busy && update == null)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            key: ValueKey('about-up-to-date'),
            child: Text(
              'Você já está na versão mais recente.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }
}
