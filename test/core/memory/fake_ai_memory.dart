import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A fake `ai-memory` executable for the SPEC-098 tests: a shell script in a
/// temporary folder (an isolated HOME with `~/.local/bin`, or a PATH dir)
/// that answers each subcommand with canned output and appends every
/// invocation (arguments and cwd) to [log]. Nothing real is installed and
/// no installer runs.
class FakeAiMemory {
  FakeAiMemory._(this.root, this.binDir);

  final Directory root;
  final Directory binDir;

  String get home => p.join(root.path, 'home');
  String get executable => p.join(binDir.path, 'ai-memory');
  File get log => File(p.join(root.path, 'calls.log'));

  /// Every recorded call: `[args, cwd]` per line.
  List<String> get calls =>
      log.existsSync() ? log.readAsLinesSync() : const <String>[];

  /// Creates the script. [version] is printed by `--version` (null = the
  /// binary exits 127, as a broken one); [replies] maps a subcommand key
  /// (`call memory_handoff_list`, `setup`, `uninstall hooks`, `doctor`,
  /// `status`, `install-hooks`, `install-mcp`) to its stdout; [sleep]
  /// makes `call` hang that many seconds first.
  static Future<FakeAiMemory> create({
    String? version = '3.5.1',
    Map<String, String> replies = const {},
    int sleep = 0,
    bool inLocalBin = false,
  }) async {
    final root = await Directory.systemTemp.createTemp('fake-ai-memory-');
    final home = Directory(p.join(root.path, 'home'))..createSync();
    final bin = inLocalBin
        ? (Directory(p.join(home.path, '.local', 'bin'))
            ..createSync(recursive: true))
        : (Directory(p.join(root.path, 'bin'))..createSync());
    final fake = FakeAiMemory._(root, bin);
    String reply(String key) {
      final text = replies[key];
      if (text == null) return 'exit 2';
      final file = File(p.join(root.path, 'reply-${key.replaceAll(' ', '_')}'))
        ..writeAsStringSync(text);
      return 'cat ${_quote(file.path)}; exit 0';
    }

    final script = StringBuffer()
      ..writeln('#!/bin/sh')
      ..writeln(
        'printf "%s\\t%s\\n" "\$*" "\$(pwd)" >> ${_quote(fake.log.path)}',
      );
    if (version == null) {
      script.writeln('exit 127');
    } else {
      script
        ..writeln('case "\$1" in')
        ..writeln('  --version) echo "ai-memory $version"; exit 0 ;;')
        ..writeln('  call)')
        ..writeln(sleep > 0 ? '    sleep $sleep' : '    :')
        ..writeln('    case "\$2" in');
      for (final tool in [
        'memory_handoff_list',
        'memory_briefing',
        'memory_handoff_cancel',
      ]) {
        script.writeln('      $tool) ${reply('call $tool')} ;;');
      }
      script
        ..writeln('    esac; exit 2 ;;')
        ..writeln('  setup) ${reply('setup')} ;;')
        ..writeln('  uninstall)')
        ..writeln('    case "\$*" in *--apply*) exit 3 ;; esac')
        ..writeln('    case "\$3" in')
        ..writeln('      hooks) ${reply('uninstall hooks')} ;;')
        ..writeln('      mcp) ${reply('uninstall mcp')} ;;')
        ..writeln('    esac; exit 2 ;;')
        ..writeln('  doctor) ${reply('doctor')} ;;')
        ..writeln('  status) ${reply('status')} ;;')
        ..writeln('  install-hooks) ${reply('install-hooks')} ;;')
        ..writeln('  install-mcp) ${reply('install-mcp')} ;;')
        ..writeln('esac')
        ..writeln('exit 2');
    }
    File(fake.executable).writeAsStringSync(script.toString());
    await Process.run('chmod', ['+x', fake.executable]);
    return fake;
  }

  /// PATH with only the fake's folder (and the system's, for `sh`).
  Map<String, String> environment({bool onPath = true}) => {
    'PATH': [if (onPath) binDir.path, '/usr/bin', '/bin'].join(':'),
    'HOME': home,
  };

  Future<void> dispose() => root.delete(recursive: true);

  static String _quote(String s) => "'${s.replaceAll("'", "'\\''")}'";
}

/// JSON of `memory_handoff_list` recorded in the shape of ai-memory 3.5.1
/// (`Handoff` flattened: scope, origin, content, lifecycle).
String handoffListJson({bool unended = false, bool history = false}) =>
    jsonEncode({
      'handoffs': [
        {
          'id': '01JDX4AUTO0000000000000000',
          'workspace_id': 'w1',
          'project_id': 'p1',
          'from_session_id': 'sess-claude-1',
          'from_agent': 'claude-code',
          'to_agent': null,
          'cwd': '/repo/promptorium-wt/spec-parser',
          'owner_user': null,
          'summary':
              'Parser trocado de regex para leitor por linhas em '
              'lib/core/spec_parser.dart.',
          'open_questions': ['Front-matter vazio deve virar erro?'],
          'next_steps': ['Escrever test/spec_parser_bom_test.dart'],
          'files_touched': ['lib/core/spec_parser.dart'],
          'state': 'open',
          'created_at': '2026-11-20T14:41:00Z',
          'accepted_by': null,
          'accepted_at': null,
          'accepted_by_session': null,
          'accepted_by_user': null,
        },
        {
          'id': '01JDX5CODEX000000000000000',
          'workspace_id': 'w1',
          'project_id': 'p1',
          'from_session_id': 'sess-codex-1',
          'from_agent': 'codex',
          'cwd': '/repo/promptorium-wt/review-021',
          'owner_user': null,
          'summary': 'Revisão da 0.21.1: falta conferir o changelog.',
          'open_questions': [],
          'next_steps': [],
          'files_touched': [],
          'state': 'open',
          'created_at': '2026-11-20T12:15:00Z',
        },
        if (history)
          {
            'id': '01JDX1OLD00000000000000000',
            'from_session_id': 'sess-old',
            'from_agent': 'codex',
            'cwd': '/repo/promptorium',
            'summary': 'Uma passagem antiga.',
            'state': 'accepted',
            'created_at': '2026-11-18T10:00:00Z',
            'accepted_by': 'claude-code',
            'accepted_at': '2026-11-18T11:00:00Z',
          },
      ],
      if (unended)
        'newer_unended_session': {
          'session_id': '019a3f2c-0000-4000-8000-000000000000',
          'agent_kind': 'codex',
          'cwd': '/repo/promptorium',
          'last_activity_at': '2026-11-20T15:20:00Z',
          'ended': false,
          'handed_off': false,
          'current': false,
        },
    });

/// JSON of `memory_briefing` (ai-memory 3.5.1 `BriefingResponse`).
String briefingJson() => jsonEncode({
  'counts': {
    'pages_latest': 138,
    'pages_all': 400,
    'sessions': 27,
    'observations': 4198,
    'evidence_rows': 0,
  },
  'last_observation_at': '2026-11-20T15:20:00Z',
  'pending_handoff_count': 2,
  'recent_pages': [
    {
      'path': 'sessions/2026-11-20-claude-code.md',
      'title': 'Sessão',
      'kind': 'session',
      'updated_at': '2026-11-20T14:41:00Z',
    },
    {
      'path': 'decisions/parser-por-linhas.md',
      'title': 'Parser por linhas',
      'kind': 'decision',
      'updated_at': '2026-11-20T14:38:00Z',
    },
  ],
  'recent_sessions': [],
  'scope': {
    'workspace': 'default',
    'project': 'promptorium',
    'resolved_by': 'explicit',
  },
});
