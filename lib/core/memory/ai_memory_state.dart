import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'ai_memory_cli.dart';

/// State of the ai-memory integration (SPEC-098 R1).
enum AiMemoryStatus {
  notInstalled('não encontrado'),
  serverDown('servidor parado'),
  outdated('versão antiga'),
  connected('conectado');

  const AiMemoryStatus(this.label);
  final String label;
}

/// `app_settings` key of a server address that is not the default (the
/// person's `AI_MEMORY_SERVER_URL` wins over it).
const aiMemoryServerUrlKey = 'aiMemory.serverUrl';

/// What the detection found (R1). Cached until "Verificar de novo" or the
/// next app start (R14).
@immutable
class AiMemoryDetection {
  const AiMemoryDetection({
    required this.status,
    this.executable,
    this.version,
    this.serverUrl = aiMemoryDefaultServer,
  });

  static const notInstalled = AiMemoryDetection(
    status: AiMemoryStatus.notInstalled,
  );

  final AiMemoryStatus status;
  final String? executable;
  final String? version;
  final String serverUrl;

  bool get installed => status != AiMemoryStatus.notInstalled;

  /// The server answered `/healthz` (the panel can read).
  bool get serverUp =>
      status == AiMemoryStatus.connected || status == AiMemoryStatus.outdated;

  /// `127.0.0.1:49374`.
  String get serverHost {
    final u = Uri.tryParse(serverUrl);
    if (u == null || u.host.isEmpty) return serverUrl;
    return u.hasPort ? '${u.host}:${u.port}' : u.host;
  }

  /// `ai-memory 3.5.1`.
  String get title => version == null ? 'ai-memory' : 'ai-memory $version';

  /// What to do in a bad state, to copy (R1). Null when connected.
  String? get fixCommand => switch (status) {
    AiMemoryStatus.notInstalled => aiMemoryInstallCommand,
    AiMemoryStatus.serverDown => aiMemoryStartCommand,
    AiMemoryStatus.outdated => aiMemoryUpgradeCommand,
    AiMemoryStatus.connected => null,
  };

  /// One sentence for each state (mock 4).
  String get message => switch (status) {
    AiMemoryStatus.notInstalled =>
      'Memória entre agentes e entre sessões, num wiki local. Opcional: sem '
          'ele nada muda no app.',
    AiMemoryStatus.serverDown =>
      'O binário existe, mas $serverUrl/healthz não respondeu. O app não '
          'inicia o serviço.',
    AiMemoryStatus.outdated =>
      'Mínima: $aiMemoryMinVersion. Ligar continua possível; "Continuar no '
          'Codex" pelo terminal fica indisponível.',
    AiMemoryStatus.connected =>
      'Conectado. As leituras passam pela CLI do ai-memory, que se autentica '
          'sozinha.',
  };
}

/// The app's environment (PATH, HOME, AI_MEMORY_SERVER_URL). Tests point it
/// at a fake binary and an isolated HOME.
final aiMemoryEnvironmentProvider = Provider<Map<String, String>>(
  (ref) => Platform.environment,
);

final aiMemoryRunnerProvider = Provider<AiMemoryRunner>(
  (ref) => defaultAiMemoryRunner,
);

final aiMemoryHttpProbeProvider = Provider<AiMemoryHttpProbe>(
  (ref) => defaultAiMemoryHttpProbe,
);

/// Path of the binary, from the disk only (no process): what the run
/// environments use (R6), cheap enough to await before each run.
final aiMemoryExecutableProvider = FutureProvider<String?>((ref) async {
  return findAiMemory(ref.watch(aiMemoryEnvironmentProvider));
});

/// The server address: `AI_MEMORY_SERVER_URL`, else the saved one, else
/// the default.
String aiMemoryServerUrl(Map<String, String> env, String? saved) {
  String clean(String s) => s.trim().replaceAll(RegExp(r'/+$'), '');
  final fromEnv = env['AI_MEMORY_SERVER_URL'];
  if (fromEnv != null && fromEnv.trim().isNotEmpty) return clean(fromEnv);
  if (saved != null && saved.trim().isNotEmpty) return clean(saved);
  return aiMemoryDefaultServer;
}

/// R1: finds the binary, runs only `--version` and asks `GET /healthz`.
/// Never installs, upgrades nor starts anything.
Future<AiMemoryDetection> detectAiMemory({
  required String? executable,
  required AiMemoryCli Function(String executable) cli,
  required AiMemoryHttpProbe probe,
  required String serverUrl,
}) async {
  if (executable == null) return AiMemoryDetection.notInstalled;
  final version = await cli(executable).version();
  if (version == null) {
    // The file exists but does not answer: as good as missing.
    return AiMemoryDetection.notInstalled;
  }
  final health = Uri.tryParse('$serverUrl/healthz');
  final code = health == null ? null : await probe(health, aiMemoryCallTimeout);
  final up = code != null && code >= 200 && code < 300;
  final status = !up
      ? AiMemoryStatus.serverDown
      : compareSemver(version, aiMemoryMinVersion) < 0
      ? AiMemoryStatus.outdated
      : AiMemoryStatus.connected;
  return AiMemoryDetection(
    status: status,
    executable: executable,
    version: version,
    serverUrl: serverUrl,
  );
}

/// The CLI of the detected binary (null without it).
final aiMemoryCliProvider = FutureProvider<AiMemoryCli?>((ref) async {
  final exe = await ref.watch(aiMemoryExecutableProvider.future);
  if (exe == null) return null;
  return AiMemoryCli(executable: exe, run: ref.watch(aiMemoryRunnerProvider));
});

/// The detection, cached until [recheckAiMemory] (R14).
final aiMemoryDetectionProvider = FutureProvider<AiMemoryDetection>((
  ref,
) async {
  final exe = await ref.watch(aiMemoryExecutableProvider.future);
  final run = ref.watch(aiMemoryRunnerProvider);
  final saved = ref
      .read(appSettingsProvider.notifier)
      .get(aiMemoryServerUrlKey);
  return detectAiMemory(
    executable: exe,
    cli: (e) => AiMemoryCli(executable: e, run: run),
    probe: ref.watch(aiMemoryHttpProbeProvider),
    serverUrl: aiMemoryServerUrl(ref.watch(aiMemoryEnvironmentProvider), saved),
  );
});

/// "Verificar de novo": forgets the cached detection.
void recheckAiMemory(WidgetRef ref) {
  ref.invalidate(aiMemoryExecutableProvider);
  ref.invalidate(aiMemoryDetectionProvider);
}
