import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/cmake.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/makefile.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart' show Mode;

/// Languages highlighted by [AppCodeEditor] (re_highlight modes).
enum CodeLanguage {
  markdown('markdown', 'Markdown'),
  dart('dart', 'Dart'),
  yaml('yaml', 'YAML'),
  json('json', 'JSON'),
  shell('bash', 'Shell'),
  javascript('javascript', 'JavaScript'),
  typescript('typescript', 'TypeScript'),
  python('python', 'Python'),
  xml('xml', 'XML/HTML'),
  css('css', 'CSS'),
  cpp('cpp', 'C/C++'),
  cmake('cmake', 'CMake'),
  kotlin('kotlin', 'Kotlin'),
  swift('swift', 'Swift'),
  java('java', 'Java'),
  go('go', 'Go'),
  rust('rust', 'Rust'),
  ini('ini', 'INI/TOML'),
  sql('sql', 'SQL'),
  dockerfile('dockerfile', 'Dockerfile'),
  makefile('makefile', 'Makefile'),
  plaintext('plaintext', 'Texto');

  const CodeLanguage(this.id, this.label);

  /// Key of the mode in `CodeHighlightTheme.languages`.
  final String id;

  /// Name shown in the status bar of the Code screen.
  final String label;

  Mode get mode => switch (this) {
    markdown => langMarkdown,
    dart => langDart,
    yaml => langYaml,
    json => langJson,
    shell => langBash,
    javascript => langJavascript,
    typescript => langTypescript,
    python => langPython,
    xml => langXml,
    css => langCss,
    cpp => langCpp,
    cmake => langCmake,
    kotlin => langKotlin,
    swift => langSwift,
    java => langJava,
    go => langGo,
    rust => langRust,
    ini => langIni,
    sql => langSql,
    dockerfile => langDockerfile,
    makefile => langMakefile,
    plaintext => langPlaintext,
  };

  /// Language of a file by its extension / name (unknown = plain text).
  static CodeLanguage forPath(String path) {
    final name = path.split('/').last.toLowerCase();
    if (name == 'dockerfile' || name.startsWith('dockerfile.')) {
      return dockerfile;
    }
    if (name == 'makefile' || name == 'gnumakefile') return makefile;
    if (name == 'cmakelists.txt') return cmake;
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1);
    return switch (ext) {
      'md' || 'markdown' || 'mdx' => markdown,
      'dart' => dart,
      'yaml' || 'yml' => yaml,
      'json' || 'jsonl' || 'arb' => json,
      'sh' || 'bash' || 'zsh' => shell,
      'js' || 'mjs' || 'cjs' || 'jsx' => javascript,
      'ts' || 'tsx' => typescript,
      'py' => python,
      'xml' || 'html' || 'htm' || 'svg' || 'plist' || 'xaml' => xml,
      'css' || 'scss' => css,
      'c' || 'h' || 'cc' || 'cpp' || 'cxx' || 'hpp' || 'hh' => cpp,
      'cmake' => cmake,
      'kt' || 'kts' => kotlin,
      'swift' => swift,
      'java' || 'gradle' => java,
      'go' => go,
      'rs' => rust,
      'ini' || 'toml' || 'cfg' || 'desktop' => ini,
      'sql' => sql,
      'mk' => makefile,
      _ => plaintext,
    };
  }
}
