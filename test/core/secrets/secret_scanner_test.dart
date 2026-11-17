import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/secrets/secret_rules.dart';
import 'package:promptorium/core/secrets/secret_scanner.dart';

import 'fake_secrets.dart';

const salt = 'sal-de-teste';

List<SecretFinding> scan(String diff, {List<String> ignored = const []}) =>
    scanDiff(diff, salt: salt, ignored: ignored);

void main() {
  group('rules (R3)', () {
    final cases = <String, String>{
      'aws': 'aws_key = "$fakeAws"',
      'stripe': "const stripeKey = '$fakeStripe';",
      'github': 'GH=$fakeGithub',
      'gitlab': 'token: $fakeGitlab',
      'slack': 'SLACK = "$fakeSlack"',
      'google': 'maps("$fakeGoogle")',
      'anthropic': 'k = "$fakeAnthropic"',
      'openai': 'k = "$fakeOpenai"',
      'jwt': 'Authorization: Bearer $fakeJwt',
      'url-password': 'DB = "postgres://app:S3nh4F0rte@db.local/loja"',
      'entropy': 'token = "$fakeToken"',
    };
    for (final MapEntry(key: rule, value: line) in cases.entries) {
      test('$rule finds its example', () {
        final f = scan(addedDiff('src/a.ts', ['// x', line]));
        expect(f.map((e) => e.ruleId), [rule]);
        expect(f.single.line, 2);
        expect(f.single.path, 'src/a.ts');
      });
    }

    test('a private key is one finding with its header and length', () {
      final key = fakePrivateKey;
      final f = scan(addedDiff('certs/chave.txt', key)).single;
      expect(f.ruleId, 'private-key');
      final len = key.join('\n').length;
      expect(f.masked, startsWith(fakeKeyHeader));
      expect(
        f.masked,
        endsWith(
          '(${len ~/ 1000}.${(len % 1000).toString().padLeft(3, '0')} '
          'caracteres)',
        ),
      );
    });

    test('.env counts and .env.example does not; the keys are shown', () {
      final env = scan(
        addedDiff('.env', [
          'DATABASE_URL=postgres://app:S3nh4@db/loja',
          'export STRIPE_SECRET=$fakeStripe',
        ]),
      );
      expect(env.single.ruleId, 'env-file');
      expect(env.single.masked, 'DATABASE_URL, STRIPE_SECRET');
      expect(env.single.line, isNull);
      expect(scan(addedDiff('.env.example', ['DATABASE_URL=x'])), isEmpty);
      expect(scan(addedDiff('.env.sample', ['A=1'])), isEmpty);
      expect(
        scan(addedDiff('config/.env.local', ['A=1'])).single.ruleId,
        'env-file',
      );
    });

    test('key files, credentials and .npmrc with a token', () {
      expect(scan(addedDiff('id_rsa', ['x'])).single.ruleId, 'key-file');
      expect(
        scan(addedDiff('tls/server.pem', ['x'])).single.ruleId,
        'key-file',
      );
      expect(
        scan(addedDiff('service-account-prod.json', ['{}'])).single.ruleId,
        'credentials-file',
      );
      expect(
        scan(addedDiff('.npmrc', ['//registry/:_authToken=abc'])).single.ruleId,
        'token-file',
      );
      expect(scan(addedDiff('.npmrc', ['save-exact=true'])), isEmpty);
    });

    test('only added lines count; removed and context lines do not', () {
      final diff = [
        'diff --git a/src/a.ts b/src/a.ts',
        '--- a/src/a.ts',
        '+++ b/src/a.ts',
        '@@ -10,3 +10,3 @@',
        " const old = '$fakeStripe';",
        "-const gone = '$fakeGithub';",
        "+const novo = '$fakeAws';",
        '',
      ].join('\n');
      final f = scan(diff);
      expect(f.map((e) => e.ruleId), ['aws']);
      expect(f.single.line, 11);
    });

    test('binary files and deleted files are left out', () {
      final diff = [
        'diff --git a/img.png b/img.png',
        'Binary files /dev/null and b/img.png differ',
        'diff --git a/.env b/.env',
        'deleted file mode 100644',
        '--- a/.env',
        '+++ /dev/null',
        '@@ -1 +0,0 @@',
        '-A=1',
        '',
      ].join('\n');
      expect(scan(diff), isEmpty);
    });

    test('entropy: a commit hash in `sha` and a low-entropy value do not '
        'count; a random 32-char token does', () {
      expect(
        scan(
          addedDiff('a.py', [
            'sha = "9fceb02d0ae598e95dc970b74767f19372d61af8"',
          ]),
        ),
        isEmpty,
      );
      expect(
        scan(addedDiff('a.py', ['password = "aaaaaaaaaaaaaaaaaaaaaaaa"'])),
        isEmpty,
      );
      expect(
        scan(addedDiff('a.py', ['token = "$fakeToken"'])).single.ruleId,
        'entropy',
      );
    });

    test('the entropy rule does not repeat a key another rule found', () {
      final f = scan(addedDiff('a.py', ['api_key = "$fakeGithub"']));
      expect(f.map((e) => e.ruleId), ['github']);
    });

    test('above 5 MB only file names and private keys are checked', () {
      final big = List.filled(60000, 'x' * 90);
      final res = scanSecrets(
        addedDiff('big.txt', [...big, 'k = "$fakeAws"', ...fakePrivateKey]) +
            addedDiff('.env', ['A=1']),
        salt: salt,
      );
      expect(res.partial, isTrue);
      expect(res.findings.map((e) => e.ruleId), ['private-key', 'env-file']);
    });
  });

  group('exceptions (R4)', () {
    test('promptorium:allow-secret and gitleaks:allow', () {
      expect(
        scan(
          addedDiff('a.ts', [
            "k = '$fakeStripe' // promptorium:allow-secret",
            "j = '$fakeGithub' # gitleaks:allow",
          ]),
        ),
        isEmpty,
      );
    });

    test('ignored paths of segredos.ignorar', () {
      final diff = addedDiff('test/fixtures/hook/webhook.json', [
        '"t": "$fakeGithub"',
      ]);
      expect(scan(diff, ignored: ['test/fixtures/**']), isEmpty);
      expect(scan(diff, ignored: ['*.json']), isEmpty);
      expect(scan(diff, ignored: ['test/*.json']), hasLength(1));
    });

    test('obvious example values', () {
      for (final v in [
        'xxxxxxxxxxxxxxxxxxxxxxxxxx',
        'changeme-changeme-changeme',
        'your-api-key-goes-here-123',
        '<TOKEN_TOKEN_TOKEN_TOKEN>',
        r'${STRIPE_SECRET_KEY_VALUE}',
      ]) {
        expect(scan(addedDiff('a.ts', ['token = "$v"'])), isEmpty, reason: v);
      }
      expect(
        scan(addedDiff('a.ts', [r'DB = "postgres://app:${DB_PASS}@db/x"'])),
        isEmpty,
      );
    });

    test('waivers by value and by file', () {
      final diff = addedDiff('src/a.ts', ["k = '$fakeStripe';"]);
      final f = scan(diff).single;
      final byValue = SecretWaiverRef(
        id: 1,
        rule: 'stripe',
        path: 'outro.ts',
        fingerprint: f.fingerprint,
        byValue: true,
      );
      final res = scanSecrets(diff, salt: salt, waivers: [byValue]);
      expect(res.findings, isEmpty);
      expect(res.waived, {1});
      const byFile = SecretWaiverRef(
        id: 2,
        rule: 'stripe',
        path: 'src/a.ts',
        fingerprint: '',
        byValue: false,
      );
      expect(scanDiff(diff, salt: salt, waivers: [byFile]), isEmpty);
      const otherFile = SecretWaiverRef(
        id: 3,
        rule: 'stripe',
        path: 'src/b.ts',
        fingerprint: '',
        byValue: false,
      );
      expect(scanDiff(diff, salt: salt, waivers: [otherFile]), hasLength(1));
    });

    test('turned-off rule groups', () {
      final diff = addedDiff('a.ts', ["k = '$fakeStripe';"]);
      expect(
        scanDiff(diff, salt: salt, disabled: {SecretRuleGroup.stripe}),
        isEmpty,
      );
    });
  });

  group('mask (R8)', () {
    test('never more than the public prefix or 2 characters; the length '
        'shows', () {
      final values = {
        'stripe': fakeStripe,
        'github': fakeGithub,
        'aws': fakeAws,
        'url-password': 'S3nh4F',
        'entropy': fakeToken,
      };
      for (final MapEntry(key: id, value: v) in values.entries) {
        final rule = defaultSecretRules.firstWhere((r) => r.id == id);
        final m = maskSecret(v, rule);
        final visible = m.split('•').first;
        final allowed = rule.prefixes.any(v.startsWith)
            ? rule.prefixes.firstWhere(v.startsWith)
            : v.substring(0, 2);
        expect(visible, allowed, reason: id);
        expect(m, endsWith('(${v.length})'));
        expect(m.contains(v.substring(visible.length + 2)), isFalse);
      }
      final pwd = defaultSecretRules.firstWhere((r) => r.id == 'url-password');
      expect(maskSecret('S3nh4F', pwd), 'S3••••••••(6)');
    });

    test('the masked line hides the value', () {
      final f = scan(addedDiff('a.ts', ["const k = '$fakeStripe';"])).single;
      expect(f.maskedLine, "const k = 'sk_live_••••••••(107)';");
      expect(f.toJson().toString().contains(fakeStripe), isFalse);
    });

    test('fingerprint depends on the salt and is not the value', () {
      expect(fingerprintOf('abc', 'a'), isNot(fingerprintOf('abc', 'b')));
      expect(fingerprintOf('abc', 'a'), hasLength(64));
    });
  });

  test('untrackedDiff reads a new file as added lines', () {
    final d = untrackedDiff('.env', 'A=1\nB=2\n'.codeUnits);
    expect(scan(d).single.masked, 'A, B');
    expect(untrackedDiff('x.bin', [1, 0, 2]), contains('Binary files'));
  });
}
