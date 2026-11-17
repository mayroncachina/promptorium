import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent, Selectable;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import 'code_block.dart';

/// The markdown of the app (SPEC-077 R6, R10): one [SelectionArea] for the
/// whole document, so a selection crosses paragraphs, lists and code blocks,
/// and every code block is a [CodeBlock] with its bar and Copiar.
///
/// [collapseLongCode] collapses long blocks (the timeline, R8). Blocks
/// remember being expanded while [owner] (the message) lives.
///
/// The text takes no Tab stop: Tab goes from button to button (the Copiar
/// of each block), and a click in the text still focuses it for Ctrl+C.
class AppMarkdown extends StatefulWidget {
  const AppMarkdown({
    super.key,
    required this.data,
    this.styleSheet,
    this.collapseLongCode = false,
    this.owner,
    this.imageDirectory,
  });

  final String data;

  /// Null = the theme's.
  final MarkdownStyleSheet? styleSheet;
  final bool collapseLongCode;
  final Object? owner;

  /// Folder a relative image path is read from (the spec's folder, so
  /// `../mockups/spec-073/print-1.png` shows the print, SPEC-083 R11).
  /// Null keeps the package's default.
  final String? imageDirectory;

  static final _memory = Expando<Map<String, bool>>('expanded code blocks');

  @override
  State<AppMarkdown> createState() => _AppMarkdownState();
}

class _AppMarkdownState extends State<AppMarkdown> {
  final _focus = FocusNode(debugLabel: 'markdown text', skipTraversal: true);
  final _blocks = BlockSelectionDelegate();

  @override
  void dispose() {
    _focus.dispose();
    _blocks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base =
        widget.styleSheet ?? MarkdownStyleSheet.fromTheme(Theme.of(context));
    // The block draws its own box; the default one would frame it again.
    final style = base.copyWith(
      codeblockDecoration: const BoxDecoration(),
      codeblockPadding: EdgeInsets.zero,
    );
    final owner = widget.owner;
    return SelectionArea(
      focusNode: _focus,
      child: SelectionContainer(
        delegate: _blocks,
        child: MarkdownBody(
          data: widget.data,
          styleSheet: style,
          imageBuilder: widget.imageDirectory == null
              ? null
              : (uri, title, alt) =>
                    markdownLocalImage(uri, widget.imageDirectory!, alt),
          builders: {
            'pre': _PreBuilder(
              collapsible: widget.collapseLongCode,
              memory: owner == null
                  ? null
                  : (AppMarkdown._memory[owner] ??= {}),
              textScaler: style.textScaler,
            ),
          },
        ),
      ),
    );
  }
}

/// A relative image of a markdown file in [dir], read from disk; anything
/// else (a URL, a missing file) shows only its alternative text.
Widget markdownLocalImage(Uri uri, String dir, String? alt) {
  Widget fallback() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      alt == null || alt.isEmpty ? uri.toString() : '[$alt]',
      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
    ),
  );
  if (uri.hasScheme || uri.path.isEmpty) return fallback();
  final path = p.normalize(p.join(dir, Uri.decodeComponent(uri.path)));
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 480),
      child: Image.file(
        File(path),
        key: ValueKey('markdown-image-${p.basename(path)}'),
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        semanticLabel: alt,
        errorBuilder: (_, _, _) => fallback(),
      ),
    ),
  );
}

/// Joins the copied text of the blocks of a document (R6): a line break
/// between a paragraph, a list item or a code block and the next one below
/// it, a space between pieces on the same line (bullet and item). The
/// default delegate glues them together ("menor:-- Pedidos").
class BlockSelectionDelegate extends StaticSelectionContainerDelegate {
  @override
  SelectedContent? getSelectedContent() {
    final buffer = StringBuffer();
    Rect? last;
    var any = false;
    for (final s in selectables) {
      final c = s.getSelectedContent();
      if (c == null) continue;
      any = true;
      if (c.plainText.isEmpty) continue;
      final rect = _globalRect(s);
      if (last != null && buffer.isNotEmpty) {
        if (rect.top >= last.bottom - 1) {
          buffer.write('\n');
        } else if (!buffer.toString().endsWith(' ')) {
          buffer.write(' ');
        }
      }
      buffer.write(c.plainText);
      last = rect;
    }
    return any ? SelectedContent(plainText: buffer.toString()) : null;
  }

  static Rect _globalRect(Selectable s) {
    final boxes = s.boundingBoxes;
    if (boxes.isEmpty) return Rect.zero;
    var r = boxes.first;
    for (final b in boxes.skip(1)) {
      r = r.expandToInclude(b);
    }
    return MatrixUtils.transformRect(s.getTransformTo(null), r);
  }
}

class _PreBuilder extends MarkdownElementBuilder {
  _PreBuilder({required this.collapsible, this.memory, this.textScaler});

  final bool collapsible;
  final Map<String, bool>? memory;
  final TextScaler? textScaler;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final c = codeOfPre(element);
    return CodeBlock(
      code: c.code,
      language: c.language,
      collapsible: collapsible,
      memory: memory,
      textScaler: textScaler,
    );
  }
}
