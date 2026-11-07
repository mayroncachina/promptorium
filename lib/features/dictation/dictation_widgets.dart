import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_dialog.dart';
import '../../ui/widgets/app_toast.dart';
import '../sessions/widgets/session_style.dart';
import '../settings/settings_sections.dart';
import 'dictation_controller.dart';
import 'voice_model.dart';

const dictationHint = 'Ditar por voz (Ctrl+Shift+M)';

int _mb(int bytes) => (bytes / 1000000).round();

String _two(int n) => n.toString().padLeft(2, '0');

/// What a click on the microphone does (SPEC-040 R2, R3, R10).
Future<void> dictationAction(
  BuildContext context,
  WidgetRef ref,
  String targetId,
) async {
  final models = ref.read(voiceModelsProvider.notifier);
  final state = ref.read(voiceModelsProvider);
  if (state.running ||
      state.phase == ModelPhase.failed ||
      models.active == null) {
    if (!state.running && models.active == null && models.hasPartial) {
      unawaited(models.start()); // R10: continues where it stopped
    }
    await showVoiceModelDialog(context, ref, talkTo: targetId);
    return;
  }
  await ref.read(dictationProvider.notifier).start(targetId);
}

/// The dialog of the model, which follows the download (R2). [talkTo] offers
/// "Falar agora" at the end; without it (Configurações) only "Fechar".
Future<void> showVoiceModelDialog(
  BuildContext context,
  WidgetRef ref, {
  String? talkTo,
}) async {
  final models = ref.read(voiceModelsProvider.notifier);
  final dictation = ref.read(dictationProvider.notifier);
  models.toForeground();
  final talk = await showAppDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (_) => _ModelDialog(canTalk: talkTo != null),
  );
  // Esc and "Continuar em segundo plano" leave the download running (R2).
  final after = ref.read(voiceModelsProvider);
  if (after.running) {
    models.toBackground();
  } else if (after.phase == ModelPhase.ready) {
    models.acknowledge();
  } else if (after.phase == ModelPhase.failed) {
    models.cancel();
  }
  if (talk == true && talkTo != null) await dictation.start(talkTo);
}

class _ModelDialog extends ConsumerWidget {
  const _ModelDialog({required this.canTalk});

  final bool canTalk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(voiceModelsProvider);
    final models = ref.read(voiceModelsProvider.notifier);
    void close([bool talk = false]) => Navigator.of(context).pop(talk);
    final model = s.target ?? models.choice;
    final (String title, Widget body, List<Widget> actions) = switch (s.phase) {
      ModelPhase.downloading => (
        'Baixando o modelo de voz',
        _Progress(state: s),
        [
          SmallButton(
            key: const ValueKey('voice-cancel'),
            label: 'Cancelar',
            height: 36,
            onTap: () {
              models.cancel();
              close();
            },
          ),
          AmberButton(
            key: const ValueKey('voice-background'),
            label: 'Continuar em segundo plano',
            height: 36,
            onTap: close,
          ),
        ],
      ),
      ModelPhase.verifying => (
        'Conferindo o arquivo',
        const _Text('Falta pouco. O modelo foi baixado.'),
        [
          SmallButton(
            key: const ValueKey('voice-cancel'),
            label: 'Cancelar',
            height: 36,
            onTap: () {
              models.cancel();
              close();
            },
          ),
          AmberButton(
            key: const ValueKey('voice-background'),
            label: 'Continuar em segundo plano',
            height: 36,
            onTap: close,
          ),
        ],
      ),
      ModelPhase.ready => (
        'Modelo pronto',
        const _Text('O ditado por voz já funciona, mesmo sem internet.'),
        [
          if (canTalk)
            SmallButton(
              key: const ValueKey('voice-close'),
              label: 'Fechar',
              height: 36,
              onTap: close,
            ),
          if (canTalk)
            AmberButton(
              key: const ValueKey('voice-talk'),
              label: 'Falar agora',
              height: 36,
              onTap: () => close(true),
            )
          else
            AmberButton(
              key: const ValueKey('voice-close'),
              label: 'Fechar',
              height: 36,
              onTap: close,
            ),
        ],
      ),
      ModelPhase.failed => (
        'Não foi possível baixar o modelo',
        const _Text(
          'Verifique a conexão e tente de novo. O download continua de onde '
          'parou.',
        ),
        [
          SmallButton(
            key: const ValueKey('voice-close'),
            label: 'Fechar',
            height: 36,
            onTap: close,
          ),
          AmberButton(
            key: const ValueKey('voice-retry'),
            label: 'Tentar de novo',
            height: 36,
            onTap: () => unawaited(models.start()),
          ),
        ],
      ),
      ModelPhase.idle => (
        'Ativar o ditado por voz',
        _Text(
          'O ditado precisa de um modelo de voz de ${model.size}, baixado uma '
          'vez. A transcrição roda neste computador, e o áudio não sai da '
          'máquina.',
        ),
        [
          SmallButton(
            key: const ValueKey('voice-not-now'),
            label: 'Agora não',
            height: 36,
            onTap: close,
          ),
          AmberButton(
            key: const ValueKey('voice-download'),
            label: 'Baixar modelo',
            height: 36,
            onTap: () => unawaited(models.start()),
          ),
        ],
      ),
    };
    return AlertDialog(
      key: const ValueKey('voice-dialog'),
      backgroundColor: AppColors.panel,
      title: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(width: 400, child: body),
      actionsOverflowButtonSpacing: 8,
      actions: [
        for (final a in actions)
          IntrinsicWidth(
            child: FocusTraversalOrder(
              order: const NumericFocusOrder(0),
              child: a,
            ),
          ),
      ],
    );
  }
}

class _Text extends StatelessWidget {
  const _Text(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      height: 1.45,
      color: AppColors.textSecondary,
    ),
  );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.state});

  final VoiceModelsState state;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          key: const ValueKey('voice-progress'),
          value: state.percent / 100,
          minHeight: 6,
          color: AppColors.amber,
          backgroundColor: AppColors.border,
        ),
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_mb(state.received)} MB de ${_mb(state.total)} MB',
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            '${state.percent}%',
            key: const ValueKey('voice-percent'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ],
  );
}

/// Keeps a field registered while it is on screen and swaps [child], its row
/// of actions, for the recording while there is one (R3, R4). A recording
/// ends with the field.
class DictationActions extends ConsumerStatefulWidget {
  const DictationActions({
    super.key,
    required this.target,
    required this.child,
  });

  final DictationTarget target;
  final Widget child;

  @override
  ConsumerState<DictationActions> createState() => _DictationActionsState();
}

class _DictationActionsState extends ConsumerState<DictationActions> {
  late final DictationController _dictation;

  @override
  void initState() {
    super.initState();
    _dictation = ref.read(dictationProvider.notifier)..register(widget.target);
  }

  @override
  void didUpdateWidget(DictationActions old) {
    super.didUpdateWidget(old);
    if (!identical(old.target, widget.target)) {
      _dictation
        ..unregister(old.target)
        ..register(widget.target);
    }
  }

  @override
  void dispose() {
    _dictation.unregister(widget.target);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(dictationProvider);
    if (!s.activeIn(widget.target.id)) return widget.child;
    final d = ref.read(dictationProvider.notifier);
    if (s.phase == DictationPhase.transcribing) {
      return Row(
        key: const ValueKey('dictation-transcribing'),
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.amber,
            ),
          ),
          const SizedBox(width: 8),
          const Text('Transcrevendo…', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 12),
          SmallButton(
            key: const ValueKey('dictation-cancel'),
            label: 'Cancelar',
            onTap: () => unawaited(d.cancel()),
          ),
        ],
      );
    }
    final seconds = s.elapsed.inSeconds;
    return Row(
      key: const ValueKey('dictation-recording'),
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: AppColors.red,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'Gravando',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 10),
        Text(
          '${_two(seconds ~/ 60)}:${_two(seconds % 60)}',
          key: const ValueKey('dictation-time'),
          style: const TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(child: _LevelBars(level: s.level)),
        const Spacer(),
        SmallButton(
          key: const ValueKey('dictation-cancel'),
          label: 'Cancelar',
          onTap: () => unawaited(d.cancel()),
        ),
        const SizedBox(width: 8),
        AmberButton(
          key: const ValueKey('dictation-stop'),
          label: 'Parar e transcrever',
          onTap: () => unawaited(d.stop()),
        ),
      ],
    );
  }
}

/// Level of the audio. R3: with reduced motion, one steady bar.
class _LevelBars extends StatefulWidget {
  const _LevelBars({required this.level});

  final double level;

  @override
  State<_LevelBars> createState() => _LevelBarsState();
}

class _LevelBarsState extends State<_LevelBars> {
  static const _count = 12;
  final _history = List<double>.filled(_count, 0, growable: true);

  @override
  void didUpdateWidget(_LevelBars old) {
    super.didUpdateWidget(old);
    _history
      ..removeAt(0)
      ..add(widget.level);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final bars = still ? [widget.level] : _history;
    return ExcludeSemantics(
      child: SizedBox(
        height: 18,
        child: Row(
          key: const ValueKey('dictation-level'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final b in bars)
              Container(
                width: still ? 48 * b.clamp(.05, 1) : 3,
                height: still ? 6 : 3 + 15 * b.clamp(0, 1),
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The microphone, left of "Enviar" (R1). Hidden where the package has no
/// `whisper-cli` (R8).
class DictationButton extends ConsumerWidget {
  const DictationButton({super.key, required this.target, this.size = 30});

  final DictationTarget target;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(dictationAvailableProvider)) return const SizedBox.shrink();
    final models = ref.watch(voiceModelsProvider);
    final blocked = ref.watch(dictationProvider.select((s) => s.blocked));
    final failed = models.notice == ModelNotice.failed;
    final tip = blocked
        ? 'Há uma gravação guardada. Tente de novo ou descarte.'
        : models.running
        ? 'Baixando o modelo · ${models.percent}%'
        : dictationHint;
    return Tooltip(
      message: tip,
      child: Semantics(
        button: true,
        enabled: !blocked,
        label: tip,
        child: Material(
          color: AppColors.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(
              color: failed ? SessionColors.stopBorder : AppColors.border,
            ),
          ),
          child: InkWell(
            key: ValueKey('dictation-button-${target.id}'),
            borderRadius: BorderRadius.circular(6),
            focusColor: AppColors.amber.withValues(alpha: .25),
            onTap: blocked
                ? null
                : () => unawaited(dictationAction(context, ref, target.id)),
            child: SizedBox(
              width: models.running ? null : size,
              height: size,
              child: models.running
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              value: models.percent / 100,
                              strokeWidth: 2,
                              color: AppColors.amber,
                              backgroundColor: AppColors.border,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${models.percent}%',
                            key: const ValueKey('dictation-button-percent'),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Icon(
                      failed ? Icons.error_outline : Icons.mic_none,
                      size: 16,
                      color: failed
                          ? AppColors.red
                          : blocked
                          ? AppColors.textDisabled
                          : AppColors.textSecondary,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What happened to the dictation of a field (R5, R6), above the field.
class DictationNotices extends ConsumerWidget {
  const DictationNotices({super.key, required this.target});

  final DictationTarget target;

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final discard = await showAppDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('dictation-discard-dialog'),
        backgroundColor: AppColors.panel,
        title: const Text(
          'Descartar a gravação?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        content: const SizedBox(
          width: 380,
          child: _Text(
            'A gravação guardada será apagada. Isso não pode ser desfeito.',
          ),
        ),
        actions: [
          OutlinedButton(
            key: const ValueKey('dictation-discard-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.red,
              side: const BorderSide(color: SessionColors.stopBorder),
            ),
            child: const Text('Descartar'),
          ),
          FilledButton(
            key: const ValueKey('dictation-discard-keep'),
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.amber,
              foregroundColor: AppColors.onAmber,
            ),
            child: const Text(
              'Manter gravação',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (discard == true) {
      await ref.read(dictationProvider.notifier).discardAudio();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(dictationProvider);
    final d = ref.read(dictationProvider.notifier);
    if (s.insertedIn == target.id) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text(
          'Texto inserido. Revise e envie.',
          key: ValueKey('dictation-inserted'),
          style: TextStyle(fontSize: 12, color: AppColors.teal),
        ),
      );
    }
    if (s.issue == null || s.targetId != target.id) {
      return const SizedBox.shrink();
    }
    final retry = SmallButton(
      key: const ValueKey('dictation-retry'),
      label: 'Tentar de novo',
      onTap: () => unawaited(d.retry()),
    );
    final close = SmallButton(
      key: const ValueKey('dictation-dismiss'),
      label: 'Fechar',
      onTap: d.dismissIssue,
    );
    final (
      String title,
      String text,
      List<Widget> actions,
    ) = switch (s.issue!) {
      DictationIssue.noMicrophone => (
        'Nenhum microfone encontrado',
        'Conecte um microfone ou escolha outro nas Configurações.',
        [
          close,
          SmallButton(
            key: const ValueKey('dictation-settings'),
            label: 'Abrir Configurações',
            onTap: () {
              d.dismissIssue();
              ref
                  .read(selectedSettingsSectionProvider.notifier)
                  .select(SettingsSection.dictation);
              unawaited(
                ref
                    .read(navigationProvider.notifier)
                    .request(AppSection.settings),
              );
            },
          ),
          retry,
        ],
      ),
      DictationIssue.noSpeech => (
        'Nenhuma fala detectada',
        'Fale mais perto do microfone e tente de novo.',
        [close, retry],
      ),
      DictationIssue.transcribeFailed => (
        'Não foi possível transcrever',
        'A gravação continua guardada até você tentar de novo ou descartar.',
        [
          SmallButton(
            key: const ValueKey('dictation-discard'),
            label: 'Descartar áudio',
            onTap: () => unawaited(_discard(context, ref)),
          ),
          retry,
        ],
      ),
    };
    return Container(
      key: const ValueKey('dictation-issue'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border.all(color: SessionColors.stopBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.error_outline,
                  size: 15,
                  color: AppColors.red,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      text,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final a in actions) IntrinsicWidth(child: a)],
          ),
        ],
      ),
    );
  }
}

/// Notices, microphone and recording of a small field (R1): the answers of
/// the questions and the idea of "Nova spec".
class DictationBar extends ConsumerWidget {
  const DictationBar({super.key, required this.target});

  final DictationTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(dictationAvailableProvider)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          DictationNotices(target: target),
          DictationActions(
            target: target,
            child: Align(
              alignment: Alignment.centerRight,
              child: DictationButton(target: target),
            ),
          ),
        ],
      ),
    );
  }
}

/// A field that locks while its audio becomes text (R4).
class DictationLock extends ConsumerWidget {
  const DictationLock({super.key, required this.id, required this.builder});

  final String id;
  final Widget Function(bool locked) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) => builder(
    ref.watch(
      dictationProvider.select(
        (s) => s.phase == DictationPhase.transcribing && s.targetId == id,
      ),
    ),
  );
}

/// Whether "Enviar" of [id] waits after inserted text (R5).
bool sendHeld(WidgetRef ref, String id) =>
    ref.watch(dictationProvider.select((s) => s.sendHeldIn == id));

/// `Ctrl+Shift+M` and `Esc` wherever the focus is (R3), the toasts of the
/// dictation and the notices of a download in the background (R10).
class DictationHost extends ConsumerStatefulWidget {
  const DictationHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DictationHost> createState() => _DictationHostState();
}

class _DictationHostState extends ConsumerState<DictationHost> {
  /// R10: the end of a download leaves by itself.
  static const noticeTime = Duration(seconds: 6);
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _noticeTimer?.cancel();
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final s = ref.read(dictationProvider);
    final d = ref.read(dictationProvider.notifier);
    final keys = HardwareKeyboard.instance;
    if (e.logicalKey == LogicalKeyboardKey.escape &&
        s.phase != DictationPhase.idle) {
      unawaited(d.cancel());
      return true;
    }
    if (e.logicalKey == LogicalKeyboardKey.keyM &&
        keys.isControlPressed &&
        keys.isShiftPressed) {
      if (!ref.read(dictationAvailableProvider)) return false;
      if (s.phase == DictationPhase.recording) {
        unawaited(d.stop());
      } else if (s.phase == DictationPhase.idle && !s.blocked) {
        final target = d.focused;
        if (target != null) {
          unawaited(dictationAction(context, ref, target.id));
        }
      }
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(dictationProvider.select((s) => s.message), (_, message) {
      if (message == null) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showAppToast(SnackBar(content: Text(message)));
      ref.read(dictationProvider.notifier).toastShown();
    });
    ref.listen(voiceModelsProvider.select((s) => s.notice), (_, notice) {
      _noticeTimer?.cancel();
      if (notice == ModelNotice.ready) {
        _noticeTimer = Timer(
          noticeTime,
          ref.read(voiceModelsProvider.notifier).dismissNotice,
        );
      }
    });
    final notice = ref.watch(voiceModelsProvider.select((s) => s.notice));
    final models = ref.read(voiceModelsProvider.notifier);
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (notice != null)
          Positioned(
            top: 56,
            right: 16,
            child: Material(
              key: const ValueKey('voice-notice'),
              color: AppColors.surfaceRaised,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: notice == ModelNotice.failed
                      ? SessionColors.stopBorder
                      : AppColors.border,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      notice == ModelNotice.ready
                          ? 'Modelo pronto. Clique no microfone para falar.'
                          : 'Não foi possível baixar o modelo',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 12),
                    if (notice == ModelNotice.failed) ...[
                      SmallButton(
                        key: const ValueKey('voice-notice-details'),
                        label: 'Ver detalhes',
                        onTap: () =>
                            unawaited(showVoiceModelDialog(context, ref)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    SmallButton(
                      key: const ValueKey('voice-notice-close'),
                      label: 'Fechar',
                      onTap: models.dismissNotice,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// "Ditado por voz" of Configurações (R7).
class DictationSettingsCard extends ConsumerWidget {
  const DictationSettingsCard({super.key});

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final remove = await showAppDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('voice-remove-dialog'),
        backgroundColor: AppColors.panel,
        title: const Text(
          'Remover o modelo de voz?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        content: const SizedBox(
          width: 380,
          child: _Text(
            'O ditado para de funcionar até você baixar o modelo de novo.',
          ),
        ),
        actions: [
          OutlinedButton(
            key: const ValueKey('voice-remove-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.red,
              side: const BorderSide(color: SessionColors.stopBorder),
            ),
            child: const Text('Remover'),
          ),
          FilledButton(
            key: const ValueKey('voice-remove-keep'),
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.amber,
              foregroundColor: AppColors.onAmber,
            ),
            child: const Text(
              'Manter modelo',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (remove != true) return;
    await ref.read(voiceModelsProvider.notifier).remove();
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showAppToast(const SnackBar(content: Text('Modelo removido.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(dictationAvailableProvider)) {
      return const _Text(
        'O ditado por voz vem nos pacotes .deb e .tar.gz para Linux. Esta '
        'instalação não tem o whisper-cli.',
      );
    }
    final s = ref.watch(voiceModelsProvider);
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final models = ref.read(voiceModelsProvider.notifier);
    final choice = models.choice;
    final inUse = models.active;
    final mics = ref.watch(micDevicesProvider).value ?? const [];
    final language =
        VoiceLanguage.values
            .asNameMap()[settings[AppSettingKeys.voiceLanguage]] ??
        VoiceLanguage.portuguese;
    final device = settings[AppSettingKeys.voiceDevice];
    final status = s.running
        ? 'Baixando · ${s.percent}%'
        : s.installed.contains(choice)
        ? 'Instalado · ${choice.size}'
        : inUse != null
        ? 'Não instalado · em uso até baixar: ${inUse.label}'
        : 'Não instalado';
    const label = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Modelo de voz', style: label),
        Text(
          status,
          key: const ValueKey('voice-status'),
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        RadioGroup<VoiceModel>(
          groupValue: choice,
          onChanged: (m) {
            if (m != null && !s.running) unawaited(models.choose(m));
          },
          child: Column(
            children: [
              for (final m in VoiceModel.values)
                RadioListTile<VoiceModel>(
                  key: ValueKey('voice-model-${m.name}'),
                  value: m,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.amber,
                  title: Text(m.label, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    m.detail,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text('Idioma', style: label),
        const SizedBox(height: 6),
        DropdownButton<VoiceLanguage>(
          key: const ValueKey('voice-language'),
          value: language,
          isExpanded: true,
          items: [
            for (final l in VoiceLanguage.values)
              DropdownMenuItem(value: l, child: Text(l.label)),
          ],
          onChanged: (l) {
            if (l != null) {
              unawaited(notifier.set(AppSettingKeys.voiceLanguage, l.name));
            }
          },
        ),
        const SizedBox(height: 12),
        const Text('Microfone', style: label),
        const SizedBox(height: 6),
        DropdownButton<String>(
          key: const ValueKey('voice-mic'),
          value: mics.any((m) => m.id == device) ? device : '',
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: '', child: Text('Padrão do sistema')),
            for (final m in mics)
              DropdownMenuItem(value: m.id, child: Text(m.label)),
          ],
          onChanged: (v) {
            if (v == null) return;
            unawaited(
              v.isEmpty
                  ? notifier.remove(AppSettingKeys.voiceDevice)
                  : notifier.set(AppSettingKeys.voiceDevice, v),
            );
          },
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: s.running
              ? SmallButton(
                  key: const ValueKey('voice-see-progress'),
                  label: 'Ver progresso',
                  onTap: () => unawaited(showVoiceModelDialog(context, ref)),
                )
              : !s.installed.contains(choice)
              ? AmberButton(
                  key: const ValueKey('voice-settings-download'),
                  label: 'Baixar modelo',
                  onTap: () {
                    unawaited(models.start());
                    unawaited(showVoiceModelDialog(context, ref));
                  },
                )
              : SmallButton(
                  key: const ValueKey('voice-remove'),
                  label: 'Remover modelo',
                  color: AppColors.red,
                  border: SessionColors.stopBorder,
                  onTap: () => unawaited(_remove(context, ref)),
                ),
        ),
      ],
    );
  }
}
