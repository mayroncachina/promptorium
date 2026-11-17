import 'package:flutter/foundation.dart';

/// The rules of the Vigia de segredos (SPEC-085 R3, R13), in one place.
///
/// They are data: the Dart scanner (`secret_scanner.dart`) and the Python
/// branch of the app's hook (`hookScript`) read the same list
/// ([secretRulesJson], written into the session's `secrets.json`), and a
/// test checks that both give the same findings on a corpus. Every regular
/// expression uses only what Dart and Python `re` (with `re.ASCII`) read
/// the same way: no inline flags, no named groups, no Unicode classes.
enum SecretRuleKind {
  /// A sensitive file entering the commit, by its name.
  file,

  /// A known key or token in an added line.
  pattern,

  /// A long quoted value assigned to a `password` / `token`… name, with high
  /// Shannon entropy.
  entropy,
}

/// A switch of Configurações › Vigia de segredos (R15): one or more rules.
enum SecretRuleGroup {
  files('Arquivos .env, chaves e certificados'),
  aws('AWS'),
  git('GitHub e GitLab'),
  stripe('Stripe live'),
  google('Google API'),
  ai('Anthropic e OpenAI'),
  slack('Slack'),
  jwt('JWT'),
  privateKey('Chave privada (BEGIN … PRIVATE KEY)'),
  urlPassword('URL com senha'),
  entropy('Alta entropia em atribuição');

  const SecretRuleGroup(this.label);

  final String label;

  /// `app_settings` key of its switch: '0' = off (default on).
  String get settingKey => 'secrets.rule.$name';
}

@immutable
class SecretRule {
  const SecretRule({
    required this.id,
    required this.group,
    required this.name,
    required this.kind,
    this.pattern,
    this.caseInsensitive = false,
    this.valueGroup = 0,
    this.prefixes = const [],
    this.fileName,
    this.fileExcept,
    this.fileContent,
    this.block = false,
    this.minEntropy = 4.0,
    this.minEntropyHex = 3.0,
  });

  /// Stable id (stored in `secret_waivers.rule`).
  final String id;
  final SecretRuleGroup group;

  /// Name shown on a finding ("Stripe live key").
  final String name;
  final SecretRuleKind kind;

  /// Searched in each added line ([SecretRuleKind.pattern] / entropy).
  final String? pattern;
  final bool caseInsensitive;

  /// Group of [pattern] holding the value (0 = the whole match).
  final int valueGroup;

  /// Public prefixes of the value, shown by the mask (`sk_live_`).
  final List<String> prefixes;

  /// [SecretRuleKind.file]: regular expression on the file's base name,
  /// the names it leaves out and, when set, what an added line must have
  /// for the file to count (`.npmrc` with a token).
  final String? fileName;
  final String? fileExcept;
  final String? fileContent;

  /// A private key: the value runs from the `BEGIN` line to the `END` one.
  final bool block;

  /// [SecretRuleKind.entropy]: minimum entropy (base64-like / hex value).
  final double minEntropy;
  final double minEntropyHex;

  Map<String, Object?> toHookJson() => {
    'id': id,
    'grupo': group.name,
    'nome': name,
    'tipo': kind.name,
    're': ?pattern,
    'i': caseInsensitive,
    'valor': valueGroup,
    'prefixos': prefixes,
    'arquivo': ?fileName,
    'exceto': ?fileExcept,
    'conteudo': ?fileContent,
    'bloco': block,
    'entropia': [minEntropy, minEntropyHex],
  };
}

/// Every rule, in the order they are tried: an added line keeps the first
/// finding of each stretch of text (the entropy rule never repeats a key
/// another rule already found).
const defaultSecretRules = <SecretRule>[
  // --- files -------------------------------------------------------------
  SecretRule(
    id: 'env-file',
    group: SecretRuleGroup.files,
    name: 'arquivo de ambiente',
    kind: SecretRuleKind.file,
    fileName: r'^\.env(\..+)?$',
    fileExcept: r'^\.env\.(example|sample|template)$',
  ),
  SecretRule(
    id: 'key-file',
    group: SecretRuleGroup.files,
    name: 'chave ou certificado',
    kind: SecretRuleKind.file,
    fileName: r'(\.(pem|key|p12|pfx)$)|(^id_(rsa|ecdsa|ed25519)$)',
  ),
  SecretRule(
    id: 'credentials-file',
    group: SecretRuleGroup.files,
    name: 'arquivo de credenciais',
    kind: SecretRuleKind.file,
    fileName: r'^(credentials\.json|service-account.*\.json)$',
  ),
  SecretRule(
    id: 'token-file',
    group: SecretRuleGroup.files,
    name: 'arquivo com token',
    kind: SecretRuleKind.file,
    fileName: r'^\.(npmrc|pypirc)$',
    fileContent: r'(_authToken|_auth|password|token)\s*[=:]',
  ),
  // --- known keys and tokens --------------------------------------------
  SecretRule(
    id: 'aws',
    group: SecretRuleGroup.aws,
    name: 'AWS access key',
    kind: SecretRuleKind.pattern,
    pattern: r'\b(AKIA|ASIA)[0-9A-Z]{16}\b',
    prefixes: ['AKIA', 'ASIA'],
  ),
  SecretRule(
    id: 'github',
    group: SecretRuleGroup.git,
    name: 'GitHub token',
    kind: SecretRuleKind.pattern,
    pattern:
        r'\b(gh[pousr]_[A-Za-z0-9]{36,255}|github_pat_[A-Za-z0-9_]{22,255})',
    prefixes: ['github_pat_', 'ghp_', 'gho_', 'ghu_', 'ghs_', 'ghr_'],
  ),
  SecretRule(
    id: 'gitlab',
    group: SecretRuleGroup.git,
    name: 'GitLab token',
    kind: SecretRuleKind.pattern,
    pattern: r'\bglpat-[A-Za-z0-9_-]{20,}',
    prefixes: ['glpat-'],
  ),
  SecretRule(
    id: 'stripe',
    group: SecretRuleGroup.stripe,
    name: 'Stripe live key',
    kind: SecretRuleKind.pattern,
    pattern: r'\b[sr]k_live_[A-Za-z0-9]{16,}',
    prefixes: ['sk_live_', 'rk_live_'],
  ),
  SecretRule(
    id: 'google',
    group: SecretRuleGroup.google,
    name: 'Google API key',
    kind: SecretRuleKind.pattern,
    pattern: r'\bAIza[0-9A-Za-z_-]{35}',
    prefixes: ['AIza'],
  ),
  SecretRule(
    id: 'anthropic',
    group: SecretRuleGroup.ai,
    name: 'Anthropic key',
    kind: SecretRuleKind.pattern,
    pattern: r'\bsk-ant-[A-Za-z0-9_-]{20,}',
    prefixes: ['sk-ant-'],
  ),
  SecretRule(
    id: 'openai',
    group: SecretRuleGroup.ai,
    name: 'OpenAI key',
    kind: SecretRuleKind.pattern,
    pattern: r'\bsk-(?!ant-)(proj-|svcacct-|admin-)?[A-Za-z0-9_-]{20,}',
    prefixes: ['sk-proj-', 'sk-svcacct-', 'sk-admin-', 'sk-'],
  ),
  SecretRule(
    id: 'slack',
    group: SecretRuleGroup.slack,
    name: 'Slack token',
    kind: SecretRuleKind.pattern,
    pattern: r'\bxox[abposr]-[A-Za-z0-9-]{10,}',
    prefixes: ['xoxa-', 'xoxb-', 'xoxo-', 'xoxp-', 'xoxr-', 'xoxs-'],
  ),
  SecretRule(
    id: 'jwt',
    group: SecretRuleGroup.jwt,
    name: 'JWT',
    kind: SecretRuleKind.pattern,
    pattern: r'\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}',
    prefixes: ['eyJ'],
  ),
  SecretRule(
    id: 'private-key',
    group: SecretRuleGroup.privateKey,
    name: 'chave privada',
    kind: SecretRuleKind.pattern,
    pattern: r'-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY-----',
    block: true,
  ),
  SecretRule(
    id: 'url-password',
    group: SecretRuleGroup.urlPassword,
    name: 'URL com senha',
    kind: SecretRuleKind.pattern,
    pattern:
        r'''\b[A-Za-z][A-Za-z0-9+.-]*://[^\s:/@'"]+:([^\s@/'"]+)@[^\s'"]+''',
    valueGroup: 1,
  ),
  // --- high entropy in an assignment ------------------------------------
  SecretRule(
    id: 'entropy',
    group: SecretRuleGroup.entropy,
    name: 'alta entropia',
    kind: SecretRuleKind.entropy,
    pattern: r'''\b[A-Za-z0-9_.-]*(password|passwd|pwd|secret|token|api_?key|apikey|auth)[A-Za-z0-9_.-]*['"]?\s*(:=|=>|=|:)\s*['"]([^'"\s]{20,})['"]''',
    caseInsensitive: true,
    valueGroup: 3,
  ),
];

/// Comments that let a line through (R4).
const secretAllowMarkers = ['promptorium:allow-secret', 'gitleaks:allow'];

/// Parts of an obvious example value (R4), compared in lower case.
const secretPlaceholders = [
  'xxx',
  'changeme',
  'your-',
  'your_',
  '<',
  r'${',
  '{{',
  'process.env',
  'os.environ',
];

/// Above this many bytes of diff only the file names and the private key
/// headers are checked (R3).
const secretDiffLimit = 5 * 1024 * 1024;

/// `segredos.ignorar` glob → regular expression on the path (`**` crosses
/// folders, `*` does not). A glob without `/` matches the base name in any
/// folder (like `.gitignore`).
({String re, bool base}) secretGlob(String glob) {
  var g = glob.trim();
  if (g.startsWith('/')) g = g.substring(1);
  final base = !g.contains('/');
  final b = StringBuffer('^');
  for (var i = 0; i < g.length; i++) {
    final c = g[i];
    if (c == '*') {
      if (i + 1 < g.length && g[i + 1] == '*') {
        i++;
        if (i + 1 < g.length && g[i + 1] == '/') {
          i++;
          b.write('([^/]+/)*');
        } else {
          b.write('.*');
        }
      } else {
        b.write('[^/]*');
      }
    } else if (c == '?') {
      b.write('[^/]');
    } else if (RegExp(r'[A-Za-z0-9_/-]').hasMatch(c)) {
      b.write(c);
    } else {
      b.write('\\$c');
    }
  }
  b.write(r'$');
  return (re: b.toString(), base: base);
}

/// A waiver as the scanners read it (R11).
@immutable
class SecretWaiverRef {
  const SecretWaiverRef({
    required this.id,
    required this.rule,
    required this.path,
    required this.fingerprint,
    required this.byValue,
  });

  final int id;
  final String rule;
  final String path;
  final String fingerprint;

  /// `valor`: the same value anywhere; else the rule in [path].
  final bool byValue;

  bool matches(String ruleId, String filePath, String print) => byValue
      ? fingerprint.isNotEmpty && fingerprint == print
      : rule == ruleId && path == filePath;

  Map<String, Object?> toHookJson() => {
    'id': id,
    'regra': rule,
    'caminho': path,
    'impressao': fingerprint,
    'alcance': byValue ? 'valor' : 'arquivo',
  };
}

/// What the hook reads (`secrets.json` of the session): the rules turned
/// on, the ignored paths, the waivers and the salt of the fingerprints.
Map<String, Object?> secretRulesJson({
  List<SecretRule> rules = defaultSecretRules,
  Set<SecretRuleGroup> disabled = const {},
  List<String> ignoredGlobs = const [],
  List<SecretWaiverRef> waivers = const [],
  required String salt,
}) => {
  'regras': [
    for (final r in rules)
      if (!disabled.contains(r.group)) r.toHookJson(),
  ],
  'ignorar': [
    for (final g in ignoredGlobs)
      if (g.trim().isNotEmpty)
        {'re': secretGlob(g).re, 'base': secretGlob(g).base},
  ],
  'permitir': secretAllowMarkers,
  'exemplos': secretPlaceholders,
  'limite': secretDiffLimit,
  'sal': salt,
  'ignorados': [for (final w in waivers) w.toHookJson()],
};
