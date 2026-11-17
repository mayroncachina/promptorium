import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/managed_hooks.dart';
import 'package:promptorium/core/secrets/secret_rules.dart';
import 'package:promptorium/core/secrets/secret_scanner.dart';

import 'fake_secrets.dart';

/// SPEC-085 R13: the Dart scanner and the Python branch of the hook read
/// the same rules and give the same findings on a corpus.
void main() {
  late Directory tmp;
  late String script;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-parity-');
    script = '${tmp.path}/promptorium_hook.py';
    await File(script).writeAsString(hookScript);
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  const salt = 'sal-paridade';
  final first = scanDiff(
    addedDiff('src/w.ts', ["k = '$fakeStripe';"]),
    salt: salt,
  ).single;
  final waivers = [
    SecretWaiverRef(
      id: 4,
      rule: 'stripe',
      path: 'x',
      fingerprint: first.fingerprint,
      byValue: true,
    ),
    const SecretWaiverRef(
      id: 5,
      rule: 'aws',
      path: 'src/aws.ts',
      fingerprint: '',
      byValue: false,
    ),
  ];
  const ignored = ['test/fixtures/**', '*.snap'];

  final corpus = <String, String>{
    'every rule': addedDiff('src/a.ts', [
      'aws = "$fakeAws"',
      "stripe = '$fakeStripe'",
      'gh = "$fakeGithub" and gl = "$fakeGitlab"',
      'slack: $fakeSlack',
      'g("$fakeGoogle")',
      'a = "$fakeAnthropic"; o = "$fakeOpenai"',
      'Bearer $fakeJwt',
      'DB = "postgres://app:S3nh4F0rte@db.local/loja"',
      'token = "$fakeToken"',
      'sha = "9fceb02d0ae598e95dc970b74767f19372d61af8"',
      'secret: "${'0123456789abcdef' * 2}"',
      "x = '$fakeStripe' // promptorium:allow-secret",
      'password = "changeme-changeme-changeme"',
      '   const tabbed = "$fakeGithub";   ',
      'long = "${'a' * 200}$fakeAws"',
    ]),
    'files': [
      addedDiff('.env', ['DATABASE_URL=x', 'export STRIPE_SECRET=y']),
      addedDiff('.env.example', ['A=1']),
      addedDiff('deploy/id_ed25519', ['k']),
      addedDiff('.npmrc', ['//r/:_authToken=abc']),
      addedDiff('.pypirc', ['[pypi]']),
      addedDiff('service-account-x.json', ['{}', '{}']),
      addedDiff('test/fixtures/a.json', ['"t": "$fakeGithub"']),
      addedDiff('ui/__snapshots__/x.snap', ['"t": "$fakeGithub"']),
    ].join(),
    'private key and hunks': [
      addedDiff('certs/k.txt', fakePrivateKey, from: 3),
      'diff --git a/src/b.ts b/src/b.ts\n--- a/src/b.ts\n+++ b/src/b.ts\n'
          '@@ -1,2 +1,2 @@\n context\n-old = "$fakeAws"\n+new = "$fakeAws"\n'
          '\\ No newline at end of file\n',
      'diff --git a/img.png b/img.png\n'
          'Binary files a/img.png and b/img.png differ\n',
      'diff --git a/gone.env b/gone.env\ndeleted file mode 100644\n',
    ].join(),
    'waivers': [
      addedDiff('src/w.ts', ["k = '$fakeStripe';"]),
      addedDiff('src/other.ts', ["k2 = '$fakeStripe';"]),
      addedDiff('src/aws.ts', ['k = "$fakeAws"']),
      addedDiff('src/aws2.ts', ['k = "$fakeAws"']),
    ].join(),
    'unicode': addedDiff('docs/ção.md', [
      'senha ção token = "${fakeChars(30, seed: 40)}" — fim',
      'DB = "mysql://usuário:Ç0nfidencial@db/x"',
    ]),
    'untracked': untrackedDiff(
      'cfg/app.yml',
      utf8.encode('api_key: "${fakeChars(28, seed: 41)}"\nok: 1\n'),
    ),
  };

  for (final MapEntry(key: name, value: diff) in corpus.entries) {
    test('same findings: $name', () async {
      final cfg = secretRulesJson(
        salt: salt,
        ignoredGlobs: ignored,
        waivers: waivers,
      );
      final cfgFile = File('${tmp.path}/secrets.json');
      await cfgFile.writeAsString(jsonEncode(cfg));
      final dart = scanSecrets(
        diff,
        salt: salt,
        ignored: ignored,
        waivers: waivers,
      );
      final p = await Process.start('python3', [
        script,
        '--scan',
        cfgFile.path,
      ]);
      p.stdin.add(utf8.encode(diff));
      await p.stdin.close();
      final out = await p.stdout.transform(utf8.decoder).join();
      final err = await p.stderr.transform(utf8.decoder).join();
      expect(await p.exitCode, 0, reason: err);
      final py = jsonDecode(out) as Map<String, dynamic>;
      expect(py['achados'], [
        for (final f in dart.findings) f.toJson(),
      ], reason: name);
      expect(py['ignorados'], dart.waived.toList()..sort());
      expect(py['parcial'], dart.partial);
      if (name == 'every rule') {
        // Stripe is waived by value (waiver 4); the copies of a value in the
        // same file count once.
        expect(dart.findings, hasLength(11));
      }
      if (name == 'waivers') expect(dart.waived, {4, 5});
    });
  }
}
