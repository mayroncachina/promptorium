import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart' show Mode;

/// Languages highlighted by [AppCodeEditor] (re_highlight modes).
enum CodeLanguage {
  markdown('markdown'),
  dart('dart'),
  yaml('yaml'),
  json('json'),
  plaintext('plaintext');

  const CodeLanguage(this.id);

  /// Key of the mode in `CodeHighlightTheme.languages`.
  final String id;

  Mode get mode => switch (this) {
    markdown => langMarkdown,
    dart => langDart,
    yaml => langYaml,
    json => langJson,
    plaintext => langPlaintext,
  };

  /// Language of a file by its extension (unknown = plain text).
  static CodeLanguage forPath(String path) {
    final name = path.split('/').last.toLowerCase();
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1);
    return switch (ext) {
      'md' || 'markdown' || 'mdx' => markdown,
      'dart' => dart,
      'yaml' || 'yml' => yaml,
      'json' || 'jsonl' || 'arb' => json,
      _ => plaintext,
    };
  }
}
