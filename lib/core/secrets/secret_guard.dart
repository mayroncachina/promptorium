import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../features/project/project_config.dart';
import '../claude/managed_hooks.dart' show secretsEnabledSettingKey;
import '../git/git_service.dart';
import 'gitleaks.dart';
import 'secret_diff.dart';
import 'secret_rules.dart';
import 'secret_scanner.dart';

/// What is checked (SPEC-085 R1, R5).
enum SecretCheckKind { commit, push }

/// Who commits (R14): each has its switch.
enum SecretOrigin {
  /// The agent (hook, or the end of the turn without it).
  agent,

  /// The app's own commits and pushes (Criar PR, arquivos restantes, VIBE,
  /// Corrigir CI).
  app,

  /// "Commitar" of the Código screen.
  manual,
}

/// `app_settings` keys of the Vigia de segredos (R13, R14).
abstract final class SecretSettingKeys {
  static const enabled = secretsEnabledSettingKey;
  static const app = 'secrets.app';
  static const manual = 'secrets.manual';

  /// '1' = also run gitleaks when installed (default off).
  static const gitleaks = 'secrets.gitleaks';

  /// Local salt of the fingerprints (created on first use).
  static const salt = 'secrets.salt';
}

/// The switches of Configurações › Vigia de segredos.
@immutable
class SecretPrefs {
  const SecretPrefs({
    this.enabled = true,
    this.app = true,
    this.manual = true,
    this.gitleaks = false,
    this.disabled = const {},
  });

  factory SecretPrefs.of(Map<String, String> s) => SecretPrefs(
    enabled: s[SecretSettingKeys.enabled] != '0',
    app: s[SecretSettingKeys.app] != '0',
    manual: s[SecretSettingKeys.manual] != '0',
    gitleaks: s[SecretSettingKeys.gitleaks] == '1',
    disabled: {
      for (final g in SecretRuleGroup.values)
        if (s[g.settingKey] == '0') g,
    },
  );

  final bool enabled, app, manual, gitleaks;
  final Set<SecretRuleGroup> disabled;

  bool covers(SecretOrigin o) =>
      enabled &&
      switch (o) {
        SecretOrigin.agent => true,
        SecretOrigin.app => app,
        SecretOrigin.manual => manual,
      };
}

/// A commit or push of the app / Código stopped by findings (R5, R6): the
/// UI opens the window of findings.
class SecretsFound implements Exception {
  const SecretsFound({
    required this.findings,
    required this.kind,
    required this.worktree,
    required this.workspaceId,
    this.partial = false,
  });

  final List<SecretFinding> findings;
  final SecretCheckKind kind;
  final String worktree;
  final int workspaceId;
  final bool partial;

  @override
  String toString() =>
      'O Vigia de segredos parou o ${kind == SecretCheckKind.push ? 'push' : 'commit'}: '
      '${findings.length} ${findings.length == 1 ? 'achado' : 'achados'}.';
}

/// Checks the app's and the Código's commits and pushes, and gives the
/// hook its rules (SPEC-085 R1, R5, R6, R13).
class SecretGuard {
  SecretGuard(this._ref);

  final Ref _ref;
  Future<String?>? _gitleaks;

  SecretPrefs get prefs => SecretPrefs.of(_ref.read(appSettingsProvider));

  /// The local salt; created (and saved) the first time.
  Future<String> salt() async {
    final settings = _ref.read(appSettingsProvider.notifier);
    final cur = settings.get(SecretSettingKeys.salt);
    if (cur != null && cur.isNotEmpty) return cur;
    final r = Random.secure();
    final s = [
      for (var i = 0; i < 24; i++)
        r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    await settings.set(SecretSettingKeys.salt, s);
    return s;
  }

  /// `gitleaks version` once; null when absent.
  Future<String?> installedGitleaks() => _gitleaks ??= versionProbe();

  /// How [installedGitleaks] asks (tests replace it).
  @visibleForTesting
  Future<String?> Function() versionProbe = gitleaksVersion;

  Future<bool> _useGitleaks() async =>
      prefs.gitleaks && gitleaksSupported(await installedGitleaks());

  Future<List<SecretWaiverRef>> _waivers(int workspaceId) async {
    try {
      return await _ref.read(secretWaiversRepoProvider).refs(workspaceId);
    } catch (e) {
      debugPrint('justificativas do vigia não lidas — $e');
      return const [];
    }
  }

  /// `secrets.json` of a session in [root] (the worktree: its
  /// `.promptorium/config.yml` has `segredos.ignorar`).
  Future<Map<String, Object?>> hookJson({
    required int workspaceId,
    required String root,
  }) async {
    final p = prefs;
    return {
      ...secretRulesJson(
        disabled: p.disabled,
        ignoredGlobs: ProjectConfig.loadSync(root).secretIgnore,
        waivers: await _waivers(workspaceId),
        salt: await salt(),
      ),
      'ligado': p.enabled,
      'tempo': 10,
      if (await _useGitleaks()) 'gitleaks': 'gitleaks',
    };
  }

  /// The findings of what a commit / push of [worktree] would send.
  Future<SecretScan> scan(
    String worktree,
    SecretCheckKind kind, {
    required int workspaceId,
  }) async {
    final git = _ref.read(gitServiceFactoryProvider)(worktree);
    final diff = kind == SecretCheckKind.commit
        ? await commitDiff(git)
        : await pushDiff(git);
    final s = await salt();
    final res = scanSecrets(
      diff,
      disabled: prefs.disabled,
      ignored: ProjectConfig.loadSync(worktree).secretIgnore,
      waivers: await _waivers(workspaceId),
      salt: s,
    );
    if (res.waived.isNotEmpty) {
      try {
        await _ref.read(secretWaiversRepoProvider).touch(res.waived);
      } catch (_) {}
    }
    if (!await _useGitleaks()) return res;
    final extra = await runGitleaks(worktree, changedPaths(diff), salt: s);
    final waivers = await _waivers(workspaceId);
    return SecretScan(
      findings: [
        ...res.findings,
        for (final f in extra)
          if (!waivers.any((w) => w.matches(f.ruleId, f.path, f.fingerprint)))
            f,
      ],
      waived: res.waived,
      partial: res.partial,
    );
  }

  /// Throws [SecretsFound] when a commit / push of [worktree] by [origin]
  /// would send a secret; nothing when the vigia does not cover [origin]
  /// or git fails (the commit itself will report it).
  Future<void> check(
    String worktree,
    SecretCheckKind kind, {
    required int workspaceId,
    required SecretOrigin origin,
  }) async {
    if (!prefs.covers(origin)) return;
    final SecretScan res;
    try {
      res = await scan(worktree, kind, workspaceId: workspaceId);
    } on GitException catch (e) {
      debugPrint('vigia de segredos: git falhou em $worktree — $e');
      return;
    }
    if (res.clean) return;
    throw SecretsFound(
      findings: res.findings,
      kind: kind,
      worktree: worktree,
      workspaceId: workspaceId,
      partial: res.partial,
    );
  }
}

final secretGuardProvider = Provider<SecretGuard>(SecretGuard.new);
