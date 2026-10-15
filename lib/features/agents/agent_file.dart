import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';

/// Thrown by [AgentFile.parse] for a file without a valid YAML frontmatter.
class AgentFormatException implements Exception {
  const AgentFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One top-level key of the frontmatter.
///
/// [raw] is the original YAML text of the key (key line + continuation
/// lines); it is written back verbatim while the value is not changed, so
/// unknown fields, comments, quoting and order survive a save (round-trip).
@immutable
class FrontmatterEntry {
  const FrontmatterEntry({
    required this.key,
    required this.value,
    this.raw,
    this.leading = const [],
  });

  final String key;

  /// Plain Dart value (String / num / bool / null / List / Map).
  final Object? value;

  /// Original lines; null = changed (written by [AgentFile.serialize]).
  final List<String>? raw;

  /// Blank / comment lines that came right before the key.
  final List<String> leading;
}

/// A subagent file (`~/.claude/agents/*.md`, `<repo>/.claude/agents/*.md`):
/// YAML frontmatter + body (the system prompt). Plano 0.2.
///
/// Read with the `yaml` package; written by hand: unchanged keys keep their
/// original text, changed keys are written in a stable style.
@immutable
class AgentFile {
  const AgentFile._(this.entries, this.trailer, this.body);

  /// A file without keys nor body (new agent in the editor).
  factory AgentFile.empty() => const AgentFile._([], [], '');

  /// A new agent with the required fields.
  factory AgentFile.create({
    required String name,
    required String description,
    String body = '',
  }) => const AgentFile._([], [], '')
      .withValue('name', name)
      .withValue('description', description)
      .withBody(body);

  /// Parses an agent file. Throws [AgentFormatException].
  factory AgentFile.parse(String source) {
    var text = source.replaceAll('\r\n', '\n');
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final lines = text.split('\n');
    if (lines.isEmpty || lines.first.trimRight() != '---') {
      throw const AgentFormatException('Arquivo sem frontmatter (---).');
    }
    final end = lines.indexWhere((l) => l.trimRight() == '---', 1);
    if (end < 0) {
      throw const AgentFormatException('Frontmatter sem o --- de fechamento.');
    }
    final fmLines = lines.sublist(1, end);
    final Object? doc;
    try {
      doc = loadYaml(fmLines.join('\n'));
    } on YamlException catch (e) {
      throw AgentFormatException('YAML inválido: ${e.message}');
    }
    final map = doc == null ? const <String, Object?>{} : _plain(doc);
    if (map is! Map) {
      throw const AgentFormatException('O frontmatter não é um mapa YAML.');
    }
    final body = lines.sublist(end + 1).join('\n');

    final entries = <FrontmatterEntry>[];
    var pending = <String>[];
    String? key;
    var raw = <String>[];
    void flush() {
      if (key == null) return;
      // Trailing blank lines belong to whatever comes next.
      final tail = <String>[];
      while (raw.length > 1 && raw.last.trim().isEmpty) {
        tail.insert(0, raw.removeLast());
      }
      final k = key!;
      entries.add(
        FrontmatterEntry(key: k, value: map[k], raw: raw, leading: pending),
      );
      pending = tail;
      key = null;
      raw = [];
    }

    for (final line in fmLines) {
      final k = _topLevelKey(line);
      if (k != null) {
        flush();
        key = k;
        raw = [line];
      } else if (key != null &&
          (line.isEmpty ||
              line.startsWith(' ') ||
              line.startsWith('\t') ||
              line.startsWith('-') ||
              line.trim().isEmpty)) {
        raw.add(line);
      } else {
        // Comment at column 0 (or something before the first key).
        flush();
        pending.add(line);
      }
    }
    flush();
    // Keys the line scanner missed (unusual syntax): keep the values.
    for (final k in map.keys) {
      if (!entries.any((e) => e.key == '$k')) {
        entries.add(FrontmatterEntry(key: '$k', value: map[k]));
      }
    }
    return AgentFile._(List.unmodifiable(entries), pending, body);
  }

  final List<FrontmatterEntry> entries;

  /// Blank / comment lines after the last key.
  final List<String> trailer;

  /// System prompt (everything after the closing `---`).
  final String body;

  Iterable<String> get keys => entries.map((e) => e.key);

  Object? value(String key) =>
      entries.where((e) => e.key == key).firstOrNull?.value;

  bool has(String key) => entries.any((e) => e.key == key);

  // --- known fields ----------------------------------------------------------

  String? get name => _string('name');
  String? get description => _string('description');
  String? get model => _string('model');
  String? get permissionMode => _string('permissionMode');
  String? get color => _string('color');

  int? get maxTurns {
    final v = value('maxTurns');
    if (v is int) return v;
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  /// `tools` (comma-separated string or list). Empty = field absent (the
  /// agent inherits every tool).
  List<String> get tools => parseToolList(value('tools'));
  List<String> get disallowedTools => parseToolList(value('disallowedTools'));

  /// Server names in `mcpServers` (inline definitions are kept but not
  /// listed here).
  List<String> get mcpServerNames {
    final v = value('mcpServers');
    if (v is List) {
      return [
        for (final i in v)
          if (i is String) i,
      ];
    }
    if (v is String && v.trim().isNotEmpty) return parseToolList(v);
    return const [];
  }

  String? _string(String key) {
    final v = value(key);
    if (v == null) return null;
    return v is String ? v : '$v';
  }

  // --- changes ---------------------------------------------------------------

  /// Sets [key] (null removes it). Unchanged values keep the original text;
  /// new keys go to the end.
  AgentFile withValue(String key, Object? value) {
    final i = entries.indexWhere((e) => e.key == key);
    if (value == null) {
      if (i < 0) return this;
      final list = [...entries];
      final removed = list.removeAt(i);
      // Keep comments that were above the removed key.
      final keepLeading = removed.leading;
      if (keepLeading.isNotEmpty) {
        if (i < list.length) {
          final next = list[i];
          list[i] = FrontmatterEntry(
            key: next.key,
            value: next.value,
            raw: next.raw,
            leading: [...keepLeading, ...next.leading],
          );
        } else {
          return AgentFile._(list, [...keepLeading, ...trailer], body);
        }
      }
      return AgentFile._(list, trailer, body);
    }
    if (i >= 0 && deepEquals(entries[i].value, value)) {
      return this;
    }
    final entry = FrontmatterEntry(
      key: key,
      value: value,
      leading: i >= 0 ? entries[i].leading : const [],
    );
    final list = [...entries];
    if (i >= 0) {
      list[i] = entry;
    } else {
      list.add(entry);
    }
    return AgentFile._(list, trailer, body);
  }

  /// Sets a tool list field keeping its style: a comma-separated string
  /// (the CLI docs' style, also for new fields) unless it was a YAML list.
  /// Empty removes the field.
  AgentFile withToolList(String key, List<String> tools) {
    final clean = [
      for (final t in tools)
        if (t.trim().isNotEmpty) t.trim(),
    ];
    if (clean.isEmpty) return withValue(key, null);
    final current = value(key);
    if (current != null && deepEquals(parseToolList(current), clean)) {
      return this;
    }
    return withValue(key, current is List ? clean : clean.join(', '));
  }

  /// Sets the server names of `mcpServers`, keeping inline definitions.
  AgentFile withMcpServerNames(List<String> names) {
    if (deepEquals(mcpServerNames, names)) return this;
    final current = value('mcpServers');
    final kept = current is List
        ? [
            for (final i in current)
              if (i is! String || names.contains(i)) i,
          ]
        : <Object?>[];
    for (final n in names) {
      if (!kept.contains(n)) kept.add(n);
    }
    return withValue('mcpServers', kept.isEmpty ? null : kept);
  }

  AgentFile withBody(String body) =>
      body == this.body ? this : AgentFile._(entries, trailer, body);

  // --- output ----------------------------------------------------------------

  String serialize() {
    final out = StringBuffer('---\n');
    for (final e in entries) {
      for (final l in e.leading) {
        out.writeln(l);
      }
      final raw = e.raw;
      if (raw != null) {
        for (final l in raw) {
          out.writeln(l);
        }
      } else {
        out.write(writeYamlEntry(e.key, e.value));
      }
    }
    for (final l in trailer) {
      out.writeln(l);
    }
    out.write('---\n');
    out.write(body);
    return out.toString();
  }

  /// Equality of the parsed content (keys in order, values, body).
  bool sameContent(AgentFile other) =>
      body == other.body &&
      deepEquals(keys.toList(), other.keys.toList()) &&
      entries.every((e) => deepEquals(e.value, other.value(e.key)));
}

/// Deep equality of plain YAML values (lists in order, maps by key).
bool deepEquals(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !deepEquals(a[k], b[k])) return false;
    }
    return true;
  }
  return a == b;
}

/// `Read, Grep, Bash(git *)` or a YAML list → names (commas inside
/// parentheses do not split).
List<String> parseToolList(Object? v) {
  if (v == null) return const [];
  if (v is List) {
    return [
      for (final i in v)
        if (i != null && '$i'.trim().isNotEmpty) '$i'.trim(),
    ];
  }
  final s = '$v';
  final out = <String>[];
  var depth = 0;
  var cur = StringBuffer();
  for (final ch in s.split('')) {
    if (ch == '(') depth++;
    if (ch == ')' && depth > 0) depth--;
    if (ch == ',' && depth == 0) {
      out.add(cur.toString());
      cur = StringBuffer();
    } else {
      cur.write(ch);
    }
  }
  out.add(cur.toString());
  return [
    for (final t in out)
      if (t.trim().isNotEmpty) t.trim(),
  ];
}

String? _topLevelKey(String line) {
  if (line.isEmpty) return null;
  final c = line[0];
  if (c == ' ' || c == '\t' || c == '#' || c == '-') return null;
  final m = RegExp(r'''^("([^"]*)"|'([^']*)'|([^\s:#][^:]*?))\s*:(\s|$)''')
      .firstMatch(line);
  if (m == null) return null;
  return m.group(2) ?? m.group(3) ?? m.group(4);
}

Object? _plain(Object? v) {
  if (v is YamlMap) {
    return <String, Object?>{
      for (final e in v.entries) '${e.key}': _plain(e.value),
    };
  }
  if (v is YamlList) return [for (final i in v) _plain(i)];
  if (v is YamlScalar) return v.value;
  return v;
}

// --- YAML writer ---------------------------------------------------------------

/// `key: value` (with nested block lines), ending in a newline.
String writeYamlEntry(String key, Object? value, {int indent = 0}) {
  final pad = ' ' * indent;
  final k = _yamlKey(key);
  if (value is List) {
    if (value.isEmpty) return '$pad$k: []\n';
    final b = StringBuffer('$pad$k:\n');
    for (final item in value) {
      b.write(_listItem(item, indent + 2));
    }
    return b.toString();
  }
  if (value is Map) {
    if (value.isEmpty) return '$pad$k: {}\n';
    final b = StringBuffer('$pad$k:\n');
    for (final e in value.entries) {
      b.write(writeYamlEntry('${e.key}', e.value, indent: indent + 2));
    }
    return b.toString();
  }
  return '$pad$k: ${yamlScalar(value)}\n';
}

String _listItem(Object? item, int indent) {
  final pad = ' ' * indent;
  if (item is Map && item.isNotEmpty) {
    final lines = StringBuffer();
    var first = true;
    for (final e in item.entries) {
      final text = writeYamlEntry('${e.key}', e.value, indent: indent + 2);
      if (first) {
        // "- key: value" on the dash line.
        lines.write('$pad- ${text.substring(indent + 2)}');
        first = false;
      } else {
        lines.write(text);
      }
    }
    return lines.toString();
  }
  if (item is List && item.isNotEmpty) {
    final b = StringBuffer('$pad-\n');
    for (final i in item) {
      b.write(_listItem(i, indent + 2));
    }
    return b.toString();
  }
  if (item is List) return '$pad- []\n';
  if (item is Map) return '$pad- {}\n';
  return '$pad- ${yamlScalar(item)}\n';
}

String _yamlKey(String key) =>
    RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$').hasMatch(key)
    ? key
    : _doubleQuoted(key);

/// A YAML scalar: plain when the `yaml` package reads it back as the same
/// string, otherwise double-quoted.
String yamlScalar(Object? v) {
  if (v == null) return 'null';
  if (v is bool || v is int) return '$v';
  if (v is double) return v.isFinite ? '$v' : _doubleQuoted('$v');
  final s = '$v';
  if (_plainOk(s)) return s;
  return _doubleQuoted(s);
}

bool _plainOk(String s) {
  if (s.isEmpty || s.trim() != s) return false;
  if (s.contains('\n') || s.contains('\t') || s.contains('\r')) return false;
  if (s.contains(': ') || s.contains(' #') || s.endsWith(':')) return false;
  if ('-?:,[]{}#&*!|>\'"%@`~'.contains(s[0])) return false;
  try {
    final back = loadYaml('k: $s');
    return back is YamlMap && back['k'] == s;
  } catch (_) {
    return false;
  }
}

String _doubleQuoted(String s) {
  final b = StringBuffer('"');
  for (final r in s.runes) {
    switch (r) {
      case 0x5C:
        b.write(r'\\');
      case 0x22:
        b.write(r'\"');
      case 0x0A:
        b.write(r'\n');
      case 0x09:
        b.write(r'\t');
      case 0x0D:
        b.write(r'\r');
      default:
        if (r < 0x20) {
          b.write('\\x${r.toRadixString(16).padLeft(2, '0')}');
        } else {
          b.writeCharCode(r);
        }
    }
  }
  b.write('"');
  return b.toString();
}
