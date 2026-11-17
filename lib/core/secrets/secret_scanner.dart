import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'secret_rules.dart';

/// One finding of the Vigia de segredos (SPEC-085 R3, R8). It never holds
/// the value: only [masked], the [fingerprint] (salted `sha256`) and the
/// line with the value masked.
@immutable
class SecretFinding {
  const SecretFinding({
    required this.path,
    required this.ruleId,
    required this.ruleName,
    required this.kind,
    required this.masked,
    required this.fingerprint,
    this.line,
    this.maskedLine,
  });

  /// Relative to the repository.
  final String path;

  /// Line of the value in the new file; null for a sensitive file.
  final int? line;
  final String ruleId;

  /// "Stripe live key", "arquivo de ambiente".
  final String ruleName;
  final SecretRuleKind kind;

  /// `sk_live_••••••••(107)`, or the variable names of a `.env`.
  final String masked;
  final String fingerprint;

  /// The code line with every value found in it masked.
  final String? maskedLine;

  bool get isFile => kind == SecretRuleKind.file;

  /// `src/config/pagamento.ts:12`, `.env`.
  String get where => line == null ? path : '$path:$line';

  /// Base name of [path].
  String get fileName => path.split('/').last;

  Map<String, Object?> toJson() => {
    'arquivo': path,
    'linha': line,
    'regra': ruleId,
    'nome': ruleName,
    'tipo': kind.name,
    'mascara': masked,
    'impressao': fingerprint,
    'linha_mascarada': maskedLine,
  };

  static SecretFinding? fromJson(Object? j) {
    if (j is! Map) return null;
    final path = j['arquivo'];
    final rule = j['regra'];
    if (path is! String || rule is! String) return null;
    return SecretFinding(
      path: path,
      line: (j['linha'] as num?)?.toInt(),
      ruleId: rule,
      ruleName: '${j['nome'] ?? rule}',
      kind: SecretRuleKind.values.firstWhere(
        (k) => k.name == j['tipo'],
        orElse: () => SecretRuleKind.pattern,
      ),
      masked: '${j['mascara'] ?? ''}',
      fingerprint: '${j['impressao'] ?? ''}',
      maskedLine: j['linha_mascarada'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SecretFinding &&
      other.path == path &&
      other.line == line &&
      other.ruleId == ruleId &&
      other.masked == masked &&
      other.fingerprint == fingerprint &&
      other.maskedLine == maskedLine;

  @override
  int get hashCode =>
      Object.hash(path, line, ruleId, masked, fingerprint, maskedLine);

  @override
  String toString() => 'SecretFinding($where, $ruleId, $masked)';
}

/// Result of [scanSecrets].
@immutable
class SecretScan {
  const SecretScan({
    this.findings = const [],
    this.waived = const {},
    this.partial = false,
  });

  final List<SecretFinding> findings;

  /// Ids of the waivers that matched (their `last_used_at` is touched, R12).
  final Set<int> waived;

  /// The diff was over [secretDiffLimit]: only file names and private keys
  /// were checked (R3).
  final bool partial;

  bool get clean => findings.isEmpty;
}

/// Mask of [value] (R8, P6): the rule's public prefix (or the first 2
/// characters), dots and the length; a private key shows its header.
String maskSecret(String value, SecretRule rule, {String? header}) {
  final runes = value.runes.toList();
  if (rule.block) {
    return '${header ?? '-----BEGIN PRIVATE KEY-----'} •••• '
        '(${_thousands(runes.length)} caracteres)';
  }
  var prefix = '';
  for (final p in rule.prefixes) {
    if (value.startsWith(p)) {
      prefix = p;
      break;
    }
  }
  if (prefix.isEmpty && runes.length > 4) {
    prefix = String.fromCharCodes(runes.take(2));
  }
  return '$prefix••••••••(${runes.length})';
}

String _thousands(int n) {
  final s = '$n';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Salted `sha256` of [value] (R8): recognises the same secret again
/// without keeping it.
String fingerprintOf(String value, String salt) =>
    sha256.convert(utf8.encode('$salt\u0000$value')).toString();

/// Shannon entropy of [s], in bits per character.
double shannonEntropy(String s) {
  final runes = s.runes.toList();
  if (runes.isEmpty) return 0;
  final counts = <int, int>{};
  for (final r in runes) {
    counts[r] = (counts[r] ?? 0) + 1;
  }
  var h = 0.0;
  for (final c in counts.values) {
    final p = c / runes.length;
    h -= p * (math.log(p) / math.ln2);
  }
  return h;
}

final _hex = RegExp(r'^[0-9a-fA-F]+$');
final _envKey = RegExp(r'^\s*(export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=');
final _hunk = RegExp(r'^@@ -\d+(,\d+)? \+(\d+)');

class _DiffFile {
  String? path;
  bool binary = false;
  bool deleted = false;
  final added = <(int, String)>[];
}

List<_DiffFile> _parse(String diff) {
  final files = <_DiffFile>[];
  _DiffFile? cur;
  var inHunk = false;
  var newLine = 0;
  for (final raw in diff.split('\n')) {
    if (raw.startsWith('diff --git ')) {
      cur = _DiffFile();
      files.add(cur);
      inHunk = false;
      final i = raw.lastIndexOf(' b/');
      if (i >= 0) cur.path = raw.substring(i + 3);
      continue;
    }
    if (cur == null) continue;
    if (raw.startsWith('@@')) {
      final m = _hunk.firstMatch(raw);
      if (m != null) {
        newLine = int.parse(m.group(2)!);
        inHunk = true;
      }
      continue;
    }
    if (inHunk) {
      if (raw.startsWith('+')) {
        cur.added.add((newLine, raw.substring(1)));
        newLine++;
        continue;
      }
      if (raw.startsWith(' ')) {
        newLine++;
        continue;
      }
      if (raw.startsWith('-') || raw.startsWith(r'\')) continue;
      inHunk = false;
    }
    if (raw.startsWith('+++ ')) {
      final p = raw.substring(4);
      if (p == '/dev/null') {
        cur.deleted = true;
      } else if (p.startsWith('b/')) {
        cur.path = p.substring(2);
      }
    } else if (raw.startsWith('deleted file mode')) {
      cur.deleted = true;
    } else if (raw.startsWith('Binary files ')) {
      cur.binary = true;
      if (raw.endsWith(' and /dev/null differ')) cur.deleted = true;
    }
  }
  return files;
}

String _strip(String s) {
  var a = 0, b = s.length;
  bool ws(int c) => c == 0x20 || c == 0x09 || c == 0x0d;
  while (a < b && ws(s.codeUnitAt(a))) {
    a++;
  }
  while (b > a && ws(s.codeUnitAt(b - 1))) {
    b--;
  }
  return s.substring(a, b);
}

/// The masked line shown on a finding: at most 160 characters.
String _shortLine(String s) {
  final t = _strip(s).runes.toList();
  return t.length <= 160
      ? String.fromCharCodes(t)
      : '${String.fromCharCodes(t.take(160))}…';
}

class _Hit {
  _Hit(this.start, this.end, this.rule, this.masked, this.print, this.waived);

  final int start, end;
  final SecretRule rule;
  final String masked, print;
  final bool waived;
}

/// Reads the unified [diff] (only the added lines), applies [rules], the
/// entropy and the exceptions (R3, R4). Pure. The value of a finding never
/// leaves this function.
SecretScan scanSecrets(
  String diff, {
  List<SecretRule> rules = defaultSecretRules,
  Set<SecretRuleGroup> disabled = const {},
  List<String> ignored = const [],
  List<SecretWaiverRef> waivers = const [],
  required String salt,
}) {
  final on = [
    for (final r in rules)
      if (!disabled.contains(r.group)) r,
  ];
  final partial = utf8.encode(diff).length > secretDiffLimit;
  final globs = [
    for (final g in ignored)
      if (g.trim().isNotEmpty) secretGlob(g),
  ];
  final compiled = {
    for (final r in on)
      if (r.pattern != null)
        r.id: RegExp(r.pattern!, caseSensitive: !r.caseInsensitive),
  };
  bool ignoredPath(String path) {
    final base = path.split('/').last;
    for (final g in globs) {
      if (RegExp(g.re).hasMatch(g.base ? base : path)) return true;
    }
    return false;
  }

  bool placeholder(String v) {
    final low = v.toLowerCase();
    return secretPlaceholders.any(low.contains);
  }

  SecretWaiverRef? waiverOf(String rule, String path, String print) {
    for (final w in waivers) {
      if (w.matches(rule, path, print)) return w;
    }
    return null;
  }

  final findings = <SecretFinding>[];
  final seen = <String>{};
  final waived = <int>{};
  void add(SecretFinding f) {
    if (seen.add('${f.path}\u0000${f.ruleId}\u0000${f.fingerprint}')) {
      findings.add(f);
    }
  }

  for (final f in _parse(diff)) {
    final path = f.path;
    if (path == null || f.deleted || ignoredPath(path)) continue;
    final base = path.split('/').last;
    SecretRule? fileRule;
    for (final r in on) {
      if (r.kind != SecretRuleKind.file) continue;
      if (!RegExp(r.fileName!).hasMatch(base)) continue;
      if (r.fileExcept != null && RegExp(r.fileExcept!).hasMatch(base)) {
        continue;
      }
      if (r.fileContent != null) {
        final c = RegExp(r.fileContent!);
        if (!f.added.any((l) => c.hasMatch(l.$2))) continue;
      }
      fileRule = r;
      break;
    }
    if (fileRule != null) {
      final keys = <String>[];
      for (final (_, text) in f.added) {
        final m = _envKey.firstMatch(text);
        if (m != null && !keys.contains(m.group(2))) keys.add(m.group(2)!);
      }
      final n = f.added.length;
      final masked = keys.isNotEmpty
          ? keys.join(', ')
          : '•••• ($n ${n == 1 ? 'linha' : 'linhas'})';
      final print = fingerprintOf(
        [for (final (_, t) in f.added) t].join('\n'),
        salt,
      );
      final w = waiverOf(fileRule.id, path, print);
      if (w != null) {
        waived.add(w.id);
        continue;
      }
      add(
        SecretFinding(
          path: path,
          ruleId: fileRule.id,
          ruleName: fileRule.name,
          kind: SecretRuleKind.file,
          masked: masked,
          fingerprint: print,
        ),
      );
      continue;
    }
    if (f.binary) continue;
    for (var i = 0; i < f.added.length; i++) {
      final (lineNo, text) = f.added[i];
      if (secretAllowMarkers.any(text.contains)) continue;
      final hits = <_Hit>[];
      for (final r in on) {
        if (r.kind == SecretRuleKind.file) continue;
        if (partial && !r.block) continue;
        for (final m in compiled[r.id]!.allMatches(text)) {
          final value = m.group(r.valueGroup);
          if (value == null || value.isEmpty) continue;
          final start = r.valueGroup == 0
              ? m.start
              : m.start + m.group(0)!.indexOf(value);
          final end = start + value.length;
          if (hits.any((h) => start < h.end && h.start < end)) continue;
          if (placeholder(value)) continue;
          if (r.kind == SecretRuleKind.entropy) {
            final limit = _hex.hasMatch(value) ? r.minEntropyHex : r.minEntropy;
            if (shannonEntropy(value) <= limit) continue;
          }
          var full = value;
          if (r.block) {
            final parts = [text.substring(start)];
            for (var j = i + 1; j < f.added.length; j++) {
              final (n, t) = f.added[j];
              if (n != f.added[j - 1].$1 + 1) break;
              parts.add(t);
              if (t.contains('-----END')) break;
            }
            full = parts.join('\n');
          }
          final print = fingerprintOf(full, salt);
          final w = waiverOf(r.id, path, print);
          if (w != null) waived.add(w.id);
          hits.add(
            _Hit(
              start,
              r.block ? text.length : end,
              r,
              maskSecret(full, r, header: r.block ? m.group(0) : null),
              print,
              w != null,
            ),
          );
        }
      }
      if (hits.isEmpty) continue;
      var line = text;
      for (final h in [...hits]..sort((a, b) => b.start.compareTo(a.start))) {
        line = line.replaceRange(h.start, h.end, h.masked);
      }
      final shown = _shortLine(line);
      for (final h in hits) {
        if (h.waived) continue;
        add(
          SecretFinding(
            path: path,
            line: lineNo,
            ruleId: h.rule.id,
            ruleName: h.rule.name,
            kind: h.rule.kind,
            masked: h.masked,
            fingerprint: h.print,
            maskedLine: shown,
          ),
        );
      }
    }
  }
  return SecretScan(findings: findings, waived: waived, partial: partial);
}

/// [scanSecrets], findings only (SPEC-085 "Componentes").
List<SecretFinding> scanDiff(
  String diff, {
  List<SecretRule> rules = defaultSecretRules,
  Set<SecretRuleGroup> disabled = const {},
  List<String> ignored = const [],
  List<SecretWaiverRef> waivers = const [],
  required String salt,
}) => scanSecrets(
  diff,
  rules: rules,
  disabled: disabled,
  ignored: ignored,
  waivers: waivers,
  salt: salt,
).findings;

/// A unified diff of an untracked file (every line added), the way the
/// scanners read it; binary files (a NUL in the first 8000 bytes) only get
/// the header.
String untrackedDiff(String path, List<int> bytes) {
  final head = 'diff --git a/$path b/$path\nnew file mode 100644\n';
  final probe = bytes.length > 8000 ? bytes.sublist(0, 8000) : bytes;
  if (probe.contains(0)) {
    return '${head}Binary files /dev/null and b/$path differ\n';
  }
  final text = utf8.decode(bytes, allowMalformed: true);
  final lines = text.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  if (lines.isEmpty) return '$head--- /dev/null\n+++ b/$path\n';
  final b = StringBuffer(head)
    ..write('--- /dev/null\n+++ b/$path\n@@ -0,0 +1,${lines.length} @@\n');
  for (final l in lines) {
    b
      ..write('+')
      ..write(l)
      ..write('\n');
  }
  return b.toString();
}
