import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/secrets/gitleaks.dart';

/// SPEC-085 R13: gitleaks as an optional complement.
void main() {
  test('version ≥ 8.18 is supported', () {
    expect(gitleaksSupported('8.21.2'), isTrue);
    expect(gitleaksSupported('8.18'), isTrue);
    expect(gitleaksSupported('8.17.9'), isFalse);
    expect(gitleaksSupported('9.0.0'), isTrue);
    expect(gitleaksSupported(null), isFalse);
  });

  test('the redacted report becomes masked findings, paths relative to '
      'the copy', () {
    final report = jsonEncode([
      {
        'RuleID': 'generic-api-key',
        'File': '/tmp/x/src/app/a.py',
        'StartLine': 3,
        'Secret': 'REDACTED',
        'Match': 'key = REDACTED',
      },
    ]);
    final f = gitleaksFindings(report, salt: 's', prefix: '/tmp/x/src/').single;
    expect(f.path, 'app/a.py');
    expect(f.line, 3);
    expect(f.ruleId, 'gitleaks:generic-api-key');
    expect(f.masked, '•••• (oculto pelo gitleaks)');
    final again = gitleaksFindings(
      report.replaceAll('/tmp/x/', '/tmp/y/'),
      salt: 's',
      prefix: '/tmp/y/src/',
    ).single;
    expect(again.fingerprint, f.fingerprint);
    expect(gitleaksFindings('not json', salt: 's'), isEmpty);
  });
}
