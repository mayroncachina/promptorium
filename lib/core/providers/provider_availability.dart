import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../codex/codex_provider.dart';
import '../codex/codex_cli.dart';
import '../process/process_runner.dart';
import 'agent_registry.dart';

enum ProviderStatus { ready, missing, loginRequired, incompatible, unknown }

class ProviderAvailability {
  const ProviderAvailability(
    this.status,
    this.message, {
    this.authVerified = true,
  });
  final ProviderStatus status;
  final String message;
  final bool authVerified;
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
Future<ProviderAvailability> inspectProvider(
  AgentProvider provider,
  ProcessRunner run,
) async {
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
    if (!RegExp(r'\d+\.\d+\.\d+').hasMatch('${version.stdout}')) {
      return const ProviderAvailability(
        ProviderStatus.incompatible,
        'Versão do CLI não reconhecida. Atualize o provedor.',
      );
    }
    if (provider.id == 'codex') {
      final help = await probe(exe, ['app-server', '--help']);
      if (help.exitCode != 0) {
        return const ProviderAvailability(
          ProviderStatus.incompatible,
          'Este Codex não suporta App Server. Atualize o CLI.',
        );
      }
      final auth = await probe(exe, ['login', 'status']);
      if (auth.exitCode != 0) {
        return const ProviderAvailability(
          ProviderStatus.loginRequired,
          'Execute codex login no terminal e depois verifique novamente.',
        );
      }
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
        return const ProviderAvailability(
          ProviderStatus.loginRequired,
          'Execute claude auth login no terminal e depois verifique novamente.',
        );
      }
    }
    return const ProviderAvailability(
      ProviderStatus.ready,
      'CLI instalado, autenticado e compatível.',
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
      if (id == 'codex') {
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

      return inspectProvider(provider, probe);
    });
