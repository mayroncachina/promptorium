import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'secret_rules.dart';
import 'secret_scanner.dart';

/// Lowest gitleaks the app uses (SPEC-085 R13).
const gitleaksMinVersion = (8, 18);

/// `8.21.2` of `gitleaks version` output; null when it does not run.
Future<String?> gitleaksVersion({String exe = 'gitleaks'}) async {
  try {
    final r = await Process.run(exe, ['version']);
    if (r.exitCode != 0) return null;
    return RegExp(r'(\d+\.\d+(\.\d+)?)').firstMatch('${r.stdout}')?.group(1);
  } catch (_) {
    return null;
  }
}

/// Whether [version] is at least [gitleaksMinVersion].
bool gitleaksSupported(String? version) {
  if (version == null) return false;
  final p = version.split('.').map(int.tryParse).toList();
  final major = p.isNotEmpty ? p[0] ?? 0 : 0;
  final minor = p.length > 1 ? p[1] ?? 0 : 0;
  return major > gitleaksMinVersion.$1 ||
      (major == gitleaksMinVersion.$1 && minor >= gitleaksMinVersion.$2);
}

/// The gitleaks report (`--report-format json`) → findings. The app only
/// runs gitleaks with `--redact`, so `Secret` / `Match` never hold the
/// value; they are not read anyway.
/// [prefix] is taken off the paths (the copy's folder).
List<SecretFinding> gitleaksFindings(
  String report, {
  required String salt,
  String prefix = '',
}) {
  Object? j;
  try {
    j = jsonDecode(report);
  } on FormatException {
    return const [];
  }
  if (j is! List) return const [];
  String rel(String p) => prefix.isNotEmpty && p.startsWith(prefix)
      ? p.substring(prefix.length)
      : p;
  return [
    for (final e in j)
      if (e is Map && e['File'] is String && e['RuleID'] is String)
        SecretFinding(
          path: rel(e['File'] as String),
          line: (e['StartLine'] as num?)?.toInt(),
          ruleId: 'gitleaks:${e['RuleID']}',
          ruleName: '${e['RuleID']} (gitleaks)',
          kind: SecretRuleKind.pattern,
          masked: '•••• (oculto pelo gitleaks)',
          fingerprint: fingerprintOf(
            'gitleaks:${rel(e['File'] as String)}:${e['RuleID']}:'
            '${e['StartLine']}',
            salt,
          ),
        ),
  ];
}

/// Runs `gitleaks dir --redact` on a copy of [paths] of [root] (R13).
/// Errors give no findings: the app's own rules always run.
Future<List<SecretFinding>> runGitleaks(
  String root,
  List<String> paths, {
  required String salt,
  String exe = 'gitleaks',
}) async {
  if (paths.isEmpty) return const [];
  final tmp = await Directory.systemTemp.createTemp('promptorium-gitleaks-');
  try {
    for (final p in paths) {
      final src = File('$root/$p');
      if (!src.existsSync()) continue;
      final dst = File('${tmp.path}/src/$p');
      await dst.parent.create(recursive: true);
      await src.copy(dst.path);
    }
    final report = '${tmp.path}/report.json';
    final r = await Process.run(exe, [
      'dir',
      '--redact',
      '--no-banner',
      '--exit-code',
      '0',
      '--report-format',
      'json',
      '--report-path',
      report,
      '${tmp.path}/src',
    ]).timeout(const Duration(seconds: 10));
    if (r.exitCode != 0 || !File(report).existsSync()) return const [];
    return gitleaksFindings(
      await File(report).readAsString(),
      salt: salt,
      prefix: '${tmp.path}/src/',
    );
  } catch (e) {
    debugPrint('gitleaks não rodou — $e');
    return const [];
  } finally {
    await tmp.delete(recursive: true);
  }
}
