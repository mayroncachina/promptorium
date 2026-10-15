import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/agent_provider.dart';
import '../../../data/providers.dart';
import '../../../ui/shell/footer_stats.dart' show formatTokens;
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import 'prompt_composer.dart' show FileChip;
import 'prompt_dialogs.dart';

/// Right column of the Prompt screen: context of the conversation and the
/// saved prompts (click inserts the body in the composer).
class PromptSidePanel extends ConsumerWidget {
  const PromptSidePanel({
    super.key,
    required this.workspace,
    required this.conversation,
    required this.mode,
    required this.files,
    required this.onInsert,
  });

  final Workspace? workspace;
  final Conversation? conversation;
  final PromptMode mode;

  /// `@files` of the conversation (sent + attached in the composer).
  final List<String> files;
  final ValueChanged<SavedPrompt> onInsert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prompts = ref.watch(savedPromptsProvider).value ?? const [];
    final c = conversation;
    const label = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    const value = TextStyle(fontSize: 12, color: AppColors.text);
    final mono = value.copyWith(fontFamily: AppFonts.mono);
    Widget row(String k, String v, TextStyle style, {Key? key}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(k, style: label),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              v,
              key: key,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );

    return ColoredBox(
      color: AppColors.panel,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('CONTEXTO', style: sectionTitleStyle),
          const SizedBox(height: 8),
          row('Pasta', workspace == null ? '—' : '${workspace!.name}/', mono),
          row(
            'Acesso',
            mode.access,
            value,
            key: const ValueKey('context-access'),
          ),
          row(
            'Tokens',
            c == null ? '—' : formatTokens(c.tokensIn + c.tokensOut),
            mono,
            key: const ValueKey('context-tokens'),
          ),
          if (files.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final f in files) FileChip(path: f)],
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text('PROMPTS SALVOS', style: sectionTitleStyle),
              ),
              InkWell(
                key: const ValueKey('saved-prompt-new'),
                onTap: () => showSavePromptDialog(context),
                child: const Text(
                  'Novo',
                  style: TextStyle(fontSize: 12, color: AppColors.amber),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (prompts.isEmpty)
            const Text(
              'Nenhum prompt salvo.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          for (final p in prompts)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: AppColors.surfaceRaised,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: InkWell(
                  key: ValueKey('saved-prompt-${p.command}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onInsert(p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '/${p.command}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: AppFonts.mono,
                                  fontSize: 12,
                                  color: AppColors.amber,
                                ),
                              ),
                            ),
                            Text(
                              p.uses == 1 ? '1 uso' : '${p.uses} usos',
                              key: ValueKey('saved-prompt-uses-${p.command}'),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        if (p.description.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            p.description,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
