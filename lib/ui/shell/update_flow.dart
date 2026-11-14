import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_shutdown.dart';
import '../../core/update/installer.dart';
import '../../core/update/update_check.dart';
import '../../data/providers.dart';
import '../../features/sessions/session_manager.dart';

/// What the update card of Sobre shows (SPEC-038 R7), one state at a time.
sealed class UpdateFlowState {
  const UpdateFlowState();
}

/// No query on record to say anything from (D7).
final class UpdateNeverChecked extends UpdateFlowState {
  const UpdateNeverChecked();
}

final class UpdateUpToDate extends UpdateFlowState {
  const UpdateUpToDate(this.checkedAt);

  final DateTime checkedAt;
}

final class UpdateChecking extends UpdateFlowState {
  const UpdateChecking();
}

final class UpdateNoResponse extends UpdateFlowState {
  const UpdateNoResponse();
}

final class UpdateAvailable extends UpdateFlowState {
  const UpdateAvailable(this.update);

  final AvailableUpdate update;
}

/// "Atualizar agora" with sessions running: restarting ends them (R8).
final class UpdateConfirmSessions extends UpdateFlowState {
  const UpdateConfirmSessions(this.update, this.sessions);

  final AvailableUpdate update;
  final int sessions;
}

final class UpdateDownloading extends UpdateFlowState {
  const UpdateDownloading(this.update, [this.progress]);

  final AvailableUpdate update;

  /// Null until the first event.
  final DownloadProgress? progress;
}

final class UpdateInstalling extends UpdateFlowState {
  const UpdateInstalling(this.update);

  final AvailableUpdate update;
}

/// Installed: the launcher of the new copy started and the app is closing
/// (SPEC-070 R1–R3).
final class UpdateRestarting extends UpdateFlowState {
  const UpdateRestarting(this.update);

  final AvailableUpdate update;
}

/// Installed, but the launcher didn't start: the app stays open, with
/// "Reiniciar agora" (SPEC-070 R4).
final class UpdateInstalledNotRestarted extends UpdateFlowState {
  const UpdateInstalledNotRestarted(this.update);

  final AvailableUpdate update;
}

final class UpdateFailed extends UpdateFlowState {
  const UpdateFailed(this.update, this.reason);

  final AvailableUpdate update;
  final String reason;
}

/// The package the update will download, for its size on the card.
final updatePackageProvider = FutureProvider.autoDispose<ReleaseAsset?>((
  ref,
) async {
  final update = ref.watch(updateCheckerProvider);
  if (update == null) return null;
  final installer = ref.read(updateInstallerProvider);
  return pickAsset(update.assets, preferDeb: await installer.prefersDeb());
});

/// The whole update inside the card of Sobre: query, download, installation.
/// It lives while the screen is open, so a failure doesn't outlive it, and it
/// is out of the widget because closing the screen depends on it (R9).
class UpdateFlow extends Notifier<UpdateFlowState> {
  StreamSubscription<DownloadProgress>? _download;

  @override
  UpdateFlowState build() {
    ref.listen(updateCheckerProvider, (_, _) => _settle());
    ref.listen(lastCheckProvider, (_, _) => _settle());
    ref.onDispose(() => unawaited(_download?.cancel()));
    return _resting();
  }

  /// The state with nothing happening. An update already found wins over a
  /// query that failed (R10).
  UpdateFlowState _resting() {
    final update = ref.read(updateCheckerProvider);
    if (update != null) return UpdateAvailable(update);
    final last = ref.read(lastCheckProvider);
    return switch (last?.outcome) {
      UpdateCheckOutcome.upToDate => UpdateUpToDate(last!.at),
      UpdateCheckOutcome.failed => const UpdateNoResponse(),
      // `found` with no update in memory: the app restarted since then.
      UpdateCheckOutcome.found || null => const UpdateNeverChecked(),
    };
  }

  /// A query that finished elsewhere changes the card only when it is idle.
  void _settle() {
    if (state
        case UpdateNeverChecked() ||
            UpdateUpToDate() ||
            UpdateNoResponse() ||
            UpdateAvailable()) {
      state = _resting();
    }
  }

  /// "Verificar agora" and "Tentar de novo" of a query.
  Future<void> check() async {
    state = const UpdateChecking();
    try {
      await ref.read(updateCheckerProvider.notifier).check(force: true);
    } catch (e) {
      debugPrint('atualização: $e');
    }
    if (ref.mounted) state = _resting();
  }

  /// "Atualizar agora": this click is the confirmation (D2), except when it
  /// would end running sessions, and only [confirmed] goes past those.
  void update({bool confirmed = false}) {
    final update = switch (state) {
      UpdateAvailable(:final update) ||
      UpdateConfirmSessions(:final update) ||
      UpdateFailed(:final update) => update,
      _ => null,
    };
    if (update == null) return;
    final sessions = ref
        .read(sessionManagerProvider)
        .live
        .values
        .where((s) => s.alive)
        .length;
    if (sessions > 0 && !confirmed) {
      state = UpdateConfirmSessions(update, sessions);
    } else {
      unawaited(_start(update));
    }
  }

  /// "Agora não".
  void dismissConfirmation() {
    if (state is UpdateConfirmSessions) state = _resting();
  }

  /// "Cancelar": doesn't wait for the stream, which ends (and deletes the
  /// partial file) at its next chunk.
  void cancelDownload() {
    if (state is! UpdateDownloading) return;
    unawaited(_download?.cancel());
    _download = null;
    state = _resting();
  }

  Future<void> _start(AvailableUpdate update) async {
    final starting = UpdateDownloading(update);
    state = starting;
    final installer = ref.read(updateInstallerProvider);
    try {
      final asset = pickAsset(
        update.assets,
        preferDeb: await installer.prefersDeb(),
      );
      // Cancelled (or closed) while looking for the package.
      if (!ref.mounted || !identical(state, starting)) return;
      if (asset == null) {
        throw const FileSystemException(
          'Nenhum pacote compatível com o Linux.',
        );
      }
      _download = installer
          .download(asset, releaseAssets: update.assets)
          .listen(
            (p) {
              final file = p.file;
              if (file == null) {
                state = UpdateDownloading(update, p);
              } else {
                unawaited(_install(update, file));
              }
            },
            onError: (Object e) => _fail(update, e),
            onDone: () {
              if (state is UpdateDownloading) {
                _fail(update, 'download sem arquivo');
              }
            },
            cancelOnError: true,
          );
    } catch (e) {
      if (ref.mounted) _fail(update, e);
    }
  }

  /// The package installed by this flow, for "Reiniciar agora".
  File? _installed;

  Future<void> _install(AvailableUpdate update, File file) async {
    state = UpdateInstalling(update);
    try {
      await ref
          .read(updateInstallerProvider)
          .installAndRestart(
            file,
            version: update.version,
            shutdown: ref.read(appShutdownProvider),
            markInstalled: () => _markInstalled(update),
            onInstalled: () {
              _installed = file;
              if (ref.mounted) state = UpdateRestarting(update);
            },
          );
    } on RelaunchFailed {
      if (ref.mounted) state = UpdateInstalledNotRestarted(update);
    } catch (e) {
      if (ref.mounted) _fail(update, e);
    }
  }

  /// "Reiniciar agora": tries the launcher again (SPEC-070 R4).
  Future<void> restartNow() async {
    final current = state;
    final file = _installed;
    if (current is! UpdateInstalledNotRestarted || file == null) return;
    final update = current.update;
    state = UpdateRestarting(update);
    final installer = ref.read(updateInstallerProvider);
    try {
      await installer.restart(
        executable: installer.relaunchExecutable(file),
        version: update.version,
        shutdown: ref.read(appShutdownProvider),
        markInstalled: () => _markInstalled(update),
      );
    } on RelaunchFailed {
      if (ref.mounted) state = UpdateInstalledNotRestarted(update);
    }
  }

  /// The next start says "Atualizado para a `<versão>`" (SPEC-070 R6).
  Future<void> _markInstalled(AvailableUpdate update) => ref
      .read(appSettingsProvider.notifier)
      .set(AppSettingKeys.justInstalled, update.version);

  void _fail(AvailableUpdate update, Object error) {
    debugPrint('atualização: $error');
    _download = null;
    final installing = state is UpdateInstalling;
    state = UpdateFailed(update, switch (error) {
      FileSystemException(:final message) when message.isNotEmpty => message,
      _ when installing =>
        'A instalação não terminou. Sua versão continua a mesma.',
      _ => 'O download parou no meio. Sua versão continua a mesma.',
    });
  }
}

final updateFlowProvider =
    NotifierProvider.autoDispose<UpdateFlow, UpdateFlowState>(UpdateFlow.new);
