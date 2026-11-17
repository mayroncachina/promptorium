import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../../theme/tokens.dart';
import '../code_editor/code_highlight.dart';
import '../code_editor/code_language.dart';
import '../copy_button.dart';

/// Exact text and language of a markdown code block (the `pre` element,
/// SPEC-077 R2): what is between the fences, without the final line break
/// the parser adds. [language] is the fence's word as written, or null.
({String code, String? language}) codeOfPre(md.Element pre) {
  var code = pre.textContent;
  if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
  String? language;
  final kids = pre.children;
  if (kids != null && kids.isNotEmpty) {
    final first = kids.first;
    if (first is md.Element) {
      final cls = first.attributes['class'];
      if (cls != null && cls.startsWith('language-')) {
        final l = cls.substring('language-'.length).trim();
        if (l.isNotEmpty) language = l;
      }
    }
  }
  return (code: code, language: language);
}

/// `1 linha`, `17 linhas`.
String _lines(int n) => n == 1 ? '1 linha' : '$n linhas';

/// A code block of the markdown (SPEC-077 R1–R5, R8): bar with the language
/// and Copiar, syntax colors, and, when [collapsible], long blocks arrive
/// collapsed.
class CodeBlock extends StatefulWidget {
  const CodeBlock({
    super.key,
    required this.code,
    this.language,
    this.collapsible = false,
    this.memory,
    this.textScaler,
  });

  final String code;

  /// Word of the fence as written (`sql`, `Postgres`); null = none.
  final String? language;

  /// Long blocks collapse (the timeline, R8).
  final bool collapsible;

  /// Expanded state by code, kept while its owner (the message) lives.
  final Map<String, bool>? memory;
  final TextScaler? textScaler;

  /// More lines than this collapse (R8)…
  static const collapseAbove = 24;

  /// …showing these.
  static const collapsedLines = 16;

  static const _codeStyle = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 12.5,
    height: 1.55,
    color: AppColors.text,
  );

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  final _h = ScrollController();
  bool _hover = false;
  late bool _expanded = widget.memory?[widget.code] ?? false;
  late List<String> _lineList = widget.code.split('\n');

  @override
  void didUpdateWidget(CodeBlock old) {
    super.didUpdateWidget(old);
    if (old.code != widget.code) {
      _lineList = widget.code.split('\n');
      _expanded = widget.memory?[widget.code] ?? false;
    }
  }

  @override
  void dispose() {
    _h.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.memory?[widget.code] = _expanded;
    if (!_expanded) {
      // Collapsing a tall block: keep its top in view.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Scrollable.ensureVisible(
            context,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = _lineList.length;
    final long = widget.collapsible && n > CodeBlock.collapseAbove;
    final collapsed = long && !_expanded;
    final shown = collapsed
        ? _lineList.take(CodeBlock.collapsedLines).join('\n')
        : widget.code;
    final lang = CodeLanguage.forFence(widget.language);
    final name = widget.language?.toLowerCase() ?? 'texto';
    final spoken = switch ((lang, widget.language)) {
      (final CodeLanguage l, _) when l != CodeLanguage.plaintext =>
        ' ${l.label}',
      (_, final String w) => ' $w',
      _ => '',
    };

    CopyButton copy(Key key) => CopyButton(
      key: key,
      text: () => widget.code,
      emphasized: _hover,
      tooltip: 'Copiar o código (${_lines(n)})',
      semanticLabel: 'Copiar código$spoken, ${_lines(n)}',
      announcement: 'Código copiado',
    );

    final bar = SelectionContainer.disabled(
      child: Container(
        key: const ValueKey('code-block-bar'),
        padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: name),
                    if (n >= 3)
                      TextSpan(
                        text: '  · ${_lines(n)}',
                        style: const TextStyle(
                          fontFamily: AppFonts.sans,
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            copy(const ValueKey('code-copy')),
          ],
        ),
      ),
    );

    Widget code = Text.rich(
      CodeHighlight.spans(shown, lang) ?? TextSpan(text: shown),
      key: const ValueKey('code-block-text'),
      style: CodeBlock._codeStyle,
      softWrap: false,
      textScaler: widget.textScaler,
    );
    if (collapsed) {
      code = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0, .78, 1],
        ).createShader(r),
        child: code,
      );
    }
    final body = Scrollbar(
      controller: _h,
      child: SingleChildScrollView(
        controller: _h,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: code,
      ),
    );

    final hidden = n - CodeBlock.collapsedLines;
    final Widget? footer = !long
        ? null
        : SelectionContainer.disabled(
            child: Container(
              key: const ValueKey('code-block-footer'),
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  _ToggleButton(
                    key: const ValueKey('code-toggle'),
                    expanded: _expanded,
                    label: _expanded
                        ? 'Recolher'
                        : 'Mostrar as outras ${_lines(hidden)}',
                    onTap: _toggle,
                  ),
                  const Spacer(),
                  if (_expanded) copy(const ValueKey('code-copy-bottom')),
                ],
              ),
            ),
          );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        key: const ValueKey('code-block'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _hover ? AppColors.borderHover : AppColors.border,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [bar, body, ?footer],
        ),
      ),
    );
  }
}

/// "Mostrar as outras N linhas" / "Recolher" (R8).
class _ToggleButton extends StatefulWidget {
  const _ToggleButton({
    super.key,
    required this.expanded,
    required this.label,
    required this.onTap,
  });

  final bool expanded;
  final String label;
  final VoidCallback onTap;

  @override
  State<_ToggleButton> createState() => _ToggleButtonState();
}

class _ToggleButtonState extends State<_ToggleButton> {
  bool _hover = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final keyboard =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final radius = BorderRadius.circular(5);
    return MergeSemantics(
      child: Semantics(
        button: true,
        expanded: widget.expanded,
        label: widget.label,
        child: Material(
          color: _hover ? const Color(0x0AFFFFFF) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: keyboard
                  ? AppColors.amberLight
                  : (_hover ? AppColors.borderHover : AppColors.border),
              width: keyboard ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onTap,
            onHover: (v) => setState(() => _hover = v),
            onFocusChange: (v) => setState(() => _focused = v),
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(
                  height: 24,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.expanded ? Icons.expand_less : Icons.expand_more,
                        size: 14,
                        color: AppColors.text,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
