import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/code/code_model.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../core/claude/claude_event_test.dart' show permissionRequestLine;
import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import '../tasks/task_rules_test.dart' show resultLine;

/// Makes sure the next stat differs from the one the tab saw.
void touch(String path, String text) {
  final f = File(path)..writeAsStringSync(text);
  f.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String repo;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-code-model-');
    repo = await createRepo(tmp);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  ({ProviderContainer c, FakeCli cli}) container() {
    final cli = FakeCli();
    final c = sessionContainer(
      sessionOverrides(
        db: memoryDatabase(),
        cli: cli,
        notifier: FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
    );
    addTearDown(c.dispose);
    return (c: c, cli: cli);
  }

  test('open, edit and save writes the file in the worktree', () async {
    final (:c, cli: _) = container();
    final m = c.read(codeWorktreeModelProvider(repo));
    await m.refresh();
    expect(m.index.files, contains('a.txt'));
    final r = await m.open('a.txt');
    final tab = (r as Opened).tab;
    expect(tab.dirty, isFalse);
    tab.controller.text = 'novo conteúdo\n';
    expect(tab.dirty, isTrue);
    await m.save(tab);
    expect(File('$repo/a.txt').readAsStringSync(), 'novo conteúdo\n');
    expect(tab.dirty, isFalse);
    // Ctrl+W path: closing disposes the tab.
    m.close(tab);
    expect(m.tabs, isEmpty);
  });

  test(
    'external change: reload when clean, ask when there are edits',
    () async {
      final (:c, cli: _) = container();
      final m = c.read(codeWorktreeModelProvider(repo));
      final tab = ((await m.open('a.txt')) as Opened).tab;

      touch('$repo/a.txt', 'agente escreveu\n');
      await m.checkDisk();
      expect(tab.controller.text, 'agente escreveu\n');
      expect(tab.dirty, isFalse);
      expect(tab.externalChange, isFalse);

      tab.controller.text = 'minha edição\n';
      touch('$repo/a.txt', 'agente de novo, mais longo\n');
      await m.checkDisk();
      expect(tab.externalChange, isTrue);
      expect(
        tab.controller.text,
        'minha edição\n',
      ); // kept until the user picks

      await m.keepMine(tab);
      expect(tab.externalChange, isFalse);
      await m.checkDisk();
      expect(tab.externalChange, isFalse); // same disk version: not asked again

      touch('$repo/a.txt', 'terceira versão\n');
      await m.checkDisk();
      expect(tab.externalChange, isTrue);
      await m.reload(tab);
      expect(tab.controller.text, 'terceira versão\n');
      expect(tab.dirty, isFalse);
    },
  );

  test('create / rename / delete update the tree and open tabs', () async {
    final (:c, cli: _) = container();
    final m = c.read(codeWorktreeModelProvider(repo));
    await m.refresh();
    final p = await m.createFile('lib/novo.dart');
    expect(m.index.files, contains('lib/novo.dart'));
    final tab = ((await m.open(p)) as Opened).tab;
    await m.rename('lib', 'src');
    expect(tab.path, 'src/novo.dart');
    expect(m.index.files, contains('src/novo.dart'));
    await m.createFolder('vazia');
    expect(m.index.isDir('vazia'), isTrue);
    await m.delete('src');
    expect(m.tabs, isEmpty);
    expect(Directory('$repo/src').existsSync(), isFalse);
  });

  test(
    'saving while a session is active queues a notice for the agent',
    () async {
      final (:c, :cli) = container();
      await c.read(appSettingsProvider.notifier).load();
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: repo, name: 'r');
      final manager = c.read(sessionManagerProvider.notifier);
      final id = await manager.create(
        NewSessionRequest(
          workspace: ws,
          title: 'Agente',
          prompt: 'Trabalhe.',
          useWorktree: false, // runs in the root = the selected worktree
        ),
      );
      await settle();
      final m = c.read(codeWorktreeModelProvider(repo));
      final tab = ((await m.open('a.txt')) as Opened).tab;
      tab.controller.text = 'editado à mão\n';

      // Turn running: written into the running turn right away (CLI
      // 2.1.302 joins it to the turn), nothing left queued.
      final notified = await m.save(tab, workspaceId: ws.id);
      expect(notified, [id]);
      final notice = SessionManager.userEditNotice('a.txt');
      expect(
        notice,
        'O usuário editou a.txt manualmente; releia antes de alterar.',
      );
      await settle();
      expect(manager.pendingNotices(id), isEmpty);
      final sent = cli.last.writtenJson;
      expect(sent, hasLength(2));
      expect(sent.last['message']['content'], notice);

      // Waiting for an approval: queued until the result.
      cli.last.emit(permissionRequestLine);
      await settle();
      expect(await manager.notifyUserEdit(id, 'c.txt'), isFalse);
      expect(manager.pendingNotices(id), [
        SessionManager.userEditNotice('c.txt'),
      ]);
      final stored = await c.read(durableStateRepoProvider).notices();
      expect(stored[id], [SessionManager.userEditNotice('c.txt')]);
      await manager.approve(id, 'req-1');
      cli.last.emit(resultLine());
      await settle();
      expect(manager.pendingNotices(id), isEmpty);
      expect(await c.read(durableStateRepoProvider).notices(), isEmpty);
      expect(
        cli.last.writtenJson.last['message']['content'],
        SessionManager.userEditNotice('c.txt'),
      );

      // Idle live session: notifyUserEdit sends right away.
      cli.last.emit(resultLine());
      await settle();
      expect(await manager.notifyUserEdit(id, 'b.txt'), isTrue);
      expect(
        cli.last.writtenJson.last['message']['content'],
        SessionManager.userEditNotice('b.txt'),
      );
    },
  );

  test('paused agent: the notice goes with the next message', () async {
    final (:c, :cli) = container();
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    final manager = c.read(sessionManagerProvider.notifier);
    final id = await manager.create(
      NewSessionRequest(
        workspace: ws,
        title: 'Agente',
        prompt: 'Trabalhe.',
        useWorktree: false,
      ),
    );
    await settle();
    await manager.stop(id); // "Pausar agente"
    await settle();
    expect(manager.isAlive(id), isFalse);
    expect(await manager.notifyUserEdit(id, 'a.txt'), isFalse);
    await manager.send(id, 'Continue.');
    await settle();
    final content = cli.last.writtenJson.last['message']['content'] as String;
    expect(content, startsWith(SessionManager.userEditNotice('a.txt')));
    expect(content, endsWith('Continue.'));
  });
}
