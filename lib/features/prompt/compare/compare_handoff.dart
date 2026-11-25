import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/codex/codex_rpc.dart';
import '../../../core/secrets/secret_rules.dart';
import '../../../core/secrets/secret_scanner.dart';
import '../../sessions/handoff/session_summary.dart' show providerWords;
import '../../sessions/timeline.dart';
import '../prompt_actions.dart';

/// The starting context of a side that cannot fork the session of the
/// conversation (SPEC-108 R4): the app summary of "Passar o trabalho entre
/// agentes" (SPEC-099), with the last messages, the files cited, the plan
/// in force and the git state. Built without calling a model, with the
/// secrets masked; the person reviews and edits it before sending.
@immutable
class CompareHandoff {
  const CompareHandoff({
    required this.text,
    this.files = const [],
    this.messages = 0,
    this.git,
    this.hasPlan = false,
    this.edited = false,
  });

  final String text;

  /// Files cited in the conversation, relative to the workspace.
  final List<String> files;

  /// How many messages of the conversation are in [text].
  final int messages;

  /// `main · limpo` (null = not read).
  final String? git;
  final bool hasPlan;

  /// The person changed [text].
  final bool edited;

  /// Order of magnitude (4 characters per token).
  int get tokens => (text.length / 4).ceil();

  CompareHandoff withText(String text) => CompareHandoff(
    text: maskHandoffSecrets(text),
    files: files,
    messages: messages,
    git: git,
    hasPlan: hasPlan,
    edited: true,
  );

  /// What the event keeps (R10): the text and the list of files.
  Map<String, dynamic> toJson() => {'text': text, 'files': files};

  static CompareHandoff? fromJson(Object? j) =>
      j is! Map || j['text'] is! String
      ? null
      : CompareHandoff(
          text: j['text'] as String,
          files: [
            for (final f in (j['files'] as List?) ?? const [])
              if (f is String) f,
          ],
        );
}

/// Messages kept in the package and their limits.
const handoffMessages = 6;
const _maxAsk = 600;
const _maxAnswer = 1500;
const _maxPlan = 4000;
const _maxFiles = 20;

/// Builds the package from the timeline of the conversation. Null when
/// there is nothing to pass on (a new conversation). Pure.
CompareHandoff? buildCompareHandoff({
  required String title,
  required String provider,
  required List<TimelineItem> items,
  String? root,
  String? plan,
  String? branch,
  int? changed,
}) {
  final all = transcriptOf(items);
  if (all.isEmpty) return null;
  final last = all.length <= handoffMessages
      ? all
      : all.sublist(all.length - handoffMessages);
  String cut(String t, int max) {
    final s = t.trim().replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return s.length <= max ? s : '${s.substring(0, max).trimRight()}…';
  }

  final files = citedFiles(items, root: root);
  final current = (plan ?? planOfTimeline(items))?.trim() ?? '';
  final git = branch == null && changed == null
      ? null
      : [
          ?branch,
          if (changed != null)
            changed == 0
                ? 'limpo'
                : changed == 1
                ? '1 arquivo não commitado'
                : '$changed arquivos não commitados',
        ].join(' · ');
  final b = StringBuffer(
    'Contexto da conversa "$title" (${providerWords(provider)}), montado '
    'pelo app. Você não tem a sessão dela.\n',
  );
  b.write('\nÚltimas mensagens:\n');
  for (final e in last) {
    b.write(
      e.user
          ? '\nPessoa: ${cut(e.text, _maxAsk)}\n'
          : '\nResposta: ${cut(e.text, _maxAnswer)}\n',
    );
  }
  if (current.isNotEmpty) {
    b.write('\nPlano vigente:\n${cut(current, _maxPlan)}\n');
  }
  if (files.isNotEmpty) {
    b.write('\nArquivos citados: ${files.map((f) => '@$f').join(' ')}\n');
  }
  if (git != null) b.write('\nEstado do git: $git\n');
  return CompareHandoff(
    text: maskHandoffSecrets(b.toString().trimRight()),
    files: files,
    messages: last.length,
    git: git,
    hasPlan: current.isNotEmpty,
  );
}

/// The message of a side that starts from the package: the package and
/// the question, whole.
String handoffPrompt(CompareHandoff h, String prompt) =>
    '${h.text}\n\nPergunta atual:\n$prompt';

/// The plan of the last `ExitPlanMode` of the conversation.
String? planOfTimeline(List<TimelineItem> items) {
  for (final i in items.reversed) {
    if (i is ToolItem && i.name == 'ExitPlanMode') {
      final p = i.input['plan'];
      if (p is String && p.trim().isNotEmpty) return p;
    }
  }
  return null;
}

/// Files of the conversation: `@mentions` of the person, files the agent
/// read or changed (both providers), relative to [root]; outside of it
/// they stay out. Newest limit of [_maxFiles].
List<String> citedFiles(List<TimelineItem> items, {String? root}) {
  final out = <String>[];
  void add(String? path) {
    if (path == null || path.isEmpty) return;
    var p = path;
    if (p.startsWith('/')) {
      if (root == null || !p.startsWith('$root/')) return;
      p = p.substring(root.length + 1);
    }
    if (!out.contains(p)) out.add(p);
  }

  mentionedFiles([
    for (final i in items)
      if (i is UserItem) i.text,
  ]).forEach(add);
  for (final i in items) {
    if (i is! ToolItem) continue;
    if (i.commandEvent case final c?) {
      c.reads.forEach(add);
    } else {
      add(i.filePath);
    }
  }
  return out.length <= _maxFiles ? out : out.sublist(out.length - _maxFiles);
}

/// [text] with the secrets of the Vigia rules (SPEC-085) and the agent
/// credentials masked: the package never carries one (R4).
String maskHandoffSecrets(String text) {
  final clean = CodexRpc.redact(text);
  final findings = scanSecrets(
    untrackedDiff('conversa.txt', utf8.encode(clean)),
    rules: defaultSecretRules,
    salt: 'compare',
  ).findings;
  if (findings.isEmpty) return clean;
  final byLine = <int, SecretFinding>{for (final f in findings) ?f.line: f};
  final out = <String>[];
  final lines = clean.split('\n');
  var skipping = false;
  for (var i = 0; i < lines.length; i++) {
    if (skipping) {
      if (lines[i].contains('-----END')) skipping = false;
      continue;
    }
    final f = byLine[i + 1];
    if (f == null) {
      out.add(lines[i]);
      continue;
    }
    out.add(f.maskedLine ?? '[segredo omitido]');
    // The body of a private key goes with its header.
    skipping =
        lines[i].contains('-----BEGIN') && !lines[i].contains('-----END');
  }
  return out.join('\n');
}
