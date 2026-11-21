import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../update/update_check.dart' show appVersionProvider;

import '../codex/codex_provider.dart';
import '../codex/codex_cli.dart';
import '../codex/codex_probe.dart';
import '../process/process_runner.dart';
import 'agent_registry.dart';
import 'provider_preferences.dart';

enum ProviderStatus { ready, missing, loginRequired, incompatible, unknown }

class ProviderAvailability {
  const ProviderAvailability(
    this.status,
    this.message, {
    this.authVerified = true,
    this.version,
    this.subscriptionType,
    this.warning,
    this.sandboxWarning,
  });
  final ProviderStatus status;
  final String message;
  final bool authVerified;

  /// `x.y.z` of `--version`, when it answered.
  final String? version;

  /// `subscriptionType` of `claude auth status --json` (`pro`, `max`), null
  /// with an API key or an older CLI (SPEC-072 R8, P6).
  final String? subscriptionType;

  /// Works, with a caveat: "versão mais nova que a testada (0.170)" (R10).
  final String? warning;

  /// Codex sandbox unavailable on this machine (R7a, decisão 15): only
  /// YOLO in a worktree works. Null = the sandbox runs (or not checked).
  final String? sandboxWarning;

  bool get sandboxAvailable => sandboxWarning == null;

  /// Whether the CLI runs on a subscription plan (quota, not dollars).
  bool get subscription => subscriptionType != null;
  bool get available => status == ProviderStatus.ready;
  String get label => switch (status) {
    ProviderStatus.ready =>
      authVerified ? 'conectado' : 'disponível · login verificado ao iniciar',
    ProviderStatus.missing => 'não encontrado',
    ProviderStatus.loginRequired => 'login pendente',
    ProviderStatus.incompatible => 'incompatível',
    ProviderStatus.unknown => 'não verificado',
  };
}

/// Only version/help/auth-status commands: never starts a conversation or login.
///
/// Codex (SPEC-094 R10, R7a): below [codexMinVersion] it is incompatible;
/// above the tested version it works with a warning; [missingMethods] names
/// App Server methods the installed version lacks (incompatible); and
/// [sandbox] says whether its sandbox runs on this machine (no quota).
Future<ProviderAvailability> inspectProvider(
  AgentProvider provider,
  ProcessRunner run, {
  Future<List<String>> Function(String executable, String version)?
  missingMethods,
  Future<String?> Function(String executable)? sandbox,
}) async {
  const missing = ProviderAvailability(
    ProviderStatus.missing,
    'CLI não encontrado. Instale o provedor e confira o PATH em Configurações → Provedores.',
  );
  if (!provider.enabled) {
    return const ProviderAvailability(
      ProviderStatus.incompatible,
      'Integração ainda indisponível. Confira Configurações → Provedores.',
    );
  }
  try {
    Future<ProcessResult> probe(String executable, List<String> args) =>
        run(executable, args);
    if (provider is AcpProvider) {
      if (provider.command.isEmpty) return missing;
      final v = await probe(provider.command.first, ['--version']);
      if (v.exitCode != 0) {
        return const ProviderAvailability(
          ProviderStatus.incompatible,
          'O comando ACP não respondeu à verificação de versão. Confira a configuração.',
        );
      }
      return const ProviderAvailability(
        ProviderStatus.ready,
        'Executável ACP disponível. A autenticação e o protocolo serão verificados pelo agente ao iniciar; nenhum login foi realizado.',
        authVerified: false,
      );
    }
    final exe = switch (provider) {
      ClaudeCodeProvider p => p.executable,
      CodexProvider p => p.executable,
      _ => throw const ProcessException('unknown', []),
    };
    final version = await probe(exe, ['--version']);
    if (version.exitCode != 0) return missing;
    final semver = RegExp(r'\d+\.\d+\.\d+').firstMatch('${version.stdout}');
    String? plan;
    if (semver == null) {
      return const ProviderAvailability(
        ProviderStatus.incompatible,
        'Versão do CLI não reconhecida. Atualize o provedor.',
      );
    }
    if (provider.id == 'codex') {
      final v = semver.group(0)!;
      if (compareVersions(v, codexMinVersion) < 0) {
        return ProviderAvailability(
          ProviderStatus.incompatible,
          'Versão instalada $v, mínimo ${codexMinVersion.substring(0, 5)}. '
          'Atualize o Codex CLI (`codex update`).',
          version: v,
        );
      }
      final help = await probe(exe, ['app-server', '--help']);
      if (help.exitCode != 0) {
        return const ProviderAvailability(
          ProviderStatus.incompatible,
          'Este Codex não suporta App Server. Atualize o CLI.',
        );
      }
      final missing = missingMethods == null
          ? const <String>[]
          : await missingMethods(exe, v);
      if (missing.isNotEmpty) {
        return ProviderAvailability(
          ProviderStatus.incompatible,
          'O Codex $v não tem ${missing.length == 1 ? 'o método' : 'os métodos'} '
          '${missing.join(', ')} do App Server usado${missing.length == 1 ? '' : 's'} '
          'pelo app. Atualize o Codex CLI (`codex update`).',
          version: v,
        );
      }
      final auth = await probe(exe, ['login', 'status']);
      if (auth.exitCode != 0) {
        return ProviderAvailability(
          ProviderStatus.loginRequired,
          'Execute codex login no terminal e depois verifique novamente.',
          version: v,
        );
      }
      return ProviderAvailability(
        ProviderStatus.ready,
        'CLI instalado, autenticado e compatível.',
        version: v,
        warning: codexNewerThanTested(v)
            ? 'versão mais nova que a testada ($codexTestedVersion)'
            : null,
        sandboxWarning: sandbox == null ? null : await sandbox(exe),
      );
    } else {
      final help = await probe(exe, ['--help']);
      if (help.exitCode != 0 ||
          !'${help.stdout}'.contains('--input-format') ||
          !'${help.stdout}'.contains('--output-format')) {
        return const ProviderAvailability(
          ProviderStatus.incompatible,
          'Este Claude não oferece o protocolo de streaming necessário. Atualize o CLI.',
        );
      }
      final auth = await probe(exe, ['auth', 'status', '--json']);
      Object? data;
      try {
        data = jsonDecode('${auth.stdout}');
      } catch (_) {}
      if (data is! Map || data['loggedIn'] is! bool) {
        return const ProviderAvailability(
          ProviderStatus.incompatible,
          'O CLI não oferece diagnóstico de autenticação compatível. Atualize o Claude.',
        );
      }
      if (auth.exitCode != 0 || data['loggedIn'] != true) {
        return ProviderAvailability(
          ProviderStatus.loginRequired,
          'Execute claude auth login no terminal e depois verifique novamente.',
          version: semver.group(0),
        );
      }
      final sub = data['subscriptionType'];
      if (sub is String && sub.trim().isNotEmpty) plan = sub.trim();
    }
    return ProviderAvailability(
      ProviderStatus.ready,
      'CLI instalado, autenticado e compatível.',
      version: semver.group(0),
      subscriptionType: plan,
    );
  } on ProcessException {
    return missing;
  } catch (_) {
    return const ProviderAvailability(
      ProviderStatus.unknown,
      'Não foi possível verificar o CLI. Confira a instalação e tente novamente.',
    );
  }
}

final providerAvailabilityProvider =
    FutureProvider.family<ProviderAvailability, String>((ref, id) async {
      final all = ref.watch(agentProvidersProvider);
      final provider = all.where((p) => p.id == id).firstOrNull;
      if (provider == null) {
        return const ProviderAvailability(
          ProviderStatus.incompatible,
          'Provedor salvo não está registrado. Escolha outro provedor explicitamente.',
        );
      }
      // Claude resolved during startup; Codex has its own candidate discovery.
      if (id == 'codex' && provider.enabled) {
        try {
          if (await ref.watch(codexCliInfoProvider.future) == null) {
            return const ProviderAvailability(
              ProviderStatus.missing,
              'Codex CLI não encontrado. Instale o CLI e confira o PATH.',
            );
          }
        } catch (_) {
          return const ProviderAvailability(
            ProviderStatus.missing,
            'Codex CLI não encontrado. Instale o CLI e confira o PATH.',
          );
        }
      }
      final runner = ref.watch(processRunnerProvider);
      var disposed = false;
      final timers = <Timer>[];
      final pending = <Completer<ProcessResult>>[];
      ref.onDispose(() {
        disposed = true;
        for (final timer in timers) {
          timer.cancel();
        }
        for (final call in pending) {
          if (!call.isCompleted) {
            call.complete(ProcessResult(0, -1, '', 'cancelled'));
          }
        }
      });
      Future<ProcessResult> probe(String executable, List<String> args) {
        if (disposed) {
          return Future.value(ProcessResult(0, -1, '', 'cancelled'));
        }
        final call = Completer<ProcessResult>();
        pending.add(call);
        final timer = Timer(const Duration(seconds: 8), () {
          if (!call.isCompleted) {
            call.completeError(TimeoutException('CLI indisponível'));
          }
        });
        timers.add(timer);
        runner(executable, args).then(
          (result) {
            timer.cancel();
            if (!call.isCompleted) call.complete(result);
          },
          onError: (Object e, StackTrace st) {
            timer.cancel();
            if (!call.isCompleted) call.completeError(e, st);
          },
        );
        return call.future;
      }

      if (id != 'codex') return inspectProvider(provider, probe);
      final settings = ref.read(appSettingsProvider.notifier);
      final starter = ref.read(codexProcessStarterProvider);
      // Tests inject the runner; the App Server is only started for real
      // with the real runner, or with an injected starter.
      final underTest = Platform.environment['FLUTTER_TEST'] == 'true';
      final realRunner = identical(runner, defaultProcessRunner);
      final canHandshake = starter != null || (realRunner && !underTest);
      return inspectProvider(
        provider,
        probe,
        // P3: the schema is generated once per version and kept.
        missingMethods: (exe, version) async {
          final key = 'codex.methods.$version';
          if (realRunner && underTest) return const [];
          final saved = settings.get(key);
          if (saved != null) {
            return [for (final m in jsonDecode(saved) as List) '$m'];
          }
          try {
            final missing = await codexMissingMethods(exe, probe);
            await settings.set(key, jsonEncode(missing));
            return missing;
          } catch (e) {
            // Could not check: never block on the check itself.
            debugPrint('codex: conferência de métodos falhou: $e');
            return const [];
          }
        },
        // R7a + R8: one handshake, no thread and no turn — sandbox and
        // model catalog (cached with the version, P2).
        sandbox: (exe) async {
          if (!canHandshake || disposed) return null;
          try {
            final h = await codexHandshake(
              executable: exe,
              starter: starter,
              workingDirectory: Directory.systemTemp.path,
              clientVersion: ref.read(appVersionProvider).value ?? '0.0.0',
            );
            if (h.models.isNotEmpty) {
              final info = await ref.read(codexCliInfoProvider.future);
              await settings.set(
                codexModelsCacheKey,
                CodexModelsCache(
                  version: info?.version,
                  readAt: DateTime.now(),
                  models: h.models,
                ).encode(),
              );
            }
            return h.sandboxWarning;
          } catch (e) {
            debugPrint('codex: handshake falhou: $e');
            return null;
          }
        },
      );
    });
