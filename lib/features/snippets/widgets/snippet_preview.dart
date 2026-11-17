import 'package:flutter/material.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/code_editor/code_highlight.dart';
import '../../../ui/widgets/code_editor/code_language.dart';
import '../snippet_naming.dart';

/// The first [maxLines] lines of [code] with syntax colors and "+ N linhas"
/// (R2: 12 in the balloon; R7: 14 in the palette). Read only.
class SnippetCodePreview extends StatelessWidget {
  const SnippetCodePreview({
    super.key,
    required this.code,
    this.language,
    this.maxLines = 14,
  });

  final String code;

  /// Word of the fence (`sql`); null = plain text.
  final String? language;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final lines = code.split('\n');
    final shown = lines.take(maxLines).join('\n');
    final hidden = lines.length - maxLines;
    final lang = CodeLanguage.forFence(language);
    return Container(
      key: const ValueKey('snippet-code-preview'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRect(
            child: Text.rich(
              CodeHighlight.spans(shown, lang) ?? TextSpan(text: shown),
              softWrap: false,
              overflow: TextOverflow.fade,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                height: 1.5,
                color: AppColors.text,
              ),
            ),
          ),
          if (hidden > 0) ...[
            const SizedBox(height: 6),
            Text(
              hidden == 1 ? '+ 1 linha' : '+ $hidden linhas',
              key: const ValueKey('snippet-preview-more'),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Right side of the palette with a snippet selected (R7): name,
/// description, code and its uses.
class SnippetPreview extends StatelessWidget {
  const SnippetPreview({super.key, required this.snippet});

  final Snippet snippet;

  @override
  Widget build(BuildContext context) {
    final s = snippet;
    final origin = s.originLabel;
    return Column(
      key: ValueKey('snippet-preview-${s.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          s.name,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        if (s.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            s.description,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 10),
        SnippetCodePreview(code: s.body, language: s.language),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            text: snippetUsage(s.uses, s.lastUsedAt),
            children: [
              if (origin != null && origin.isNotEmpty) ...[
                TextSpan(
                  text: s.originConversationId != null
                      ? ' · da conversa '
                      : (s.originSessionId != null
                            ? ' · da sessão '
                            : ' · de '),
                ),
                TextSpan(
                  text: origin,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
          key: const ValueKey('snippet-preview-usage'),
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }
}
