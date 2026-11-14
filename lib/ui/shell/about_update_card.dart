import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/update/installer.dart';
import '../../core/update/update_check.dart';
import '../../features/sessions/widgets/session_style.dart';
import '../../features/specs/widgets/spec_action_banner.dart'
    show ActionSpinner;
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'update_flow.dart';

/// Same height in every state: the news below never move (SPEC-038 R7).
const updateCardHeight = 112.0;

String _two(int v) => v.toString().padLeft(2, '0');

/// `05/11/2026`.
String formatDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

String _formatChecked(DateTime at, DateTime now) {
  final time = '${_two(at.hour)}:${_two(at.minute)}';
  final day = DateTime(at.year, at.month, at.day);
  final days = DateTime(now.year, now.month, now.day).difference(day).inDays;
  return switch (days) {
    0 => 'Verificado hoje às $time',
    1 => 'Verificado ontem às $time',
    _ => 'Verificado em ${formatDate(at)} às $time',
  };
}

int _mb(int bytes) => (bytes / 1000000).round();

/// What a state looks like; the actions come apart from it.
typedef _Look = ({
  Widget icon,
  String title,
  String detail,
  Color background,
  Color border,
});

const _hint = 'Baixa, instala e reinicia o app.';

/// The card of Sobre: one state of [updateFlowProvider], with icon and text.
/// [actionFocus] goes to the main action of the state, if it has one.
class UpdateCard extends ConsumerWidget {
  const UpdateCard({
    super.key,
    required this.actionFocus,
    required this.cardFocus,
  });

  final FocusNode actionFocus;

  /// Holds the focus when the state has no action to hold it.
  final FocusNode cardFocus;

  _Look _look(UpdateFlowState state, int? packageSize) {
    Widget icon(IconData data, Color color) =>
        Icon(data, size: 18, color: color);
    final spinner = Builder(
      builder: (context) => AppMotion.animate(context)
          ? const ActionSpinner(size: 18)
          : icon(Icons.hourglass_top, AppColors.amber),
    );
    _Look plain(Widget icon, String title, String detail) => (
      icon: icon,
      title: title,
      detail: detail,
      background: AppColors.surfaceRaised,
      border: AppColors.border,
    );
    _Look highlighted(Widget icon, String title, String detail) => (
      icon: icon,
      title: title,
      detail: detail,
      background: SessionColors.approvalBg,
      border: SessionColors.approvalBorder,
    );
    final download = icon(Icons.file_download_outlined, AppColors.amber);
    return switch (state) {
      UpdateNeverChecked() => plain(
        icon(Icons.help_outline, AppColors.textSecondary),
        'Ainda não verificado',
        'Consulte o GitHub para ver se há versão nova.',
      ),
      UpdateUpToDate(:final checkedAt) => plain(
        icon(Icons.check, CanvasColors.done),
        'Você está na versão mais recente',
        _formatChecked(checkedAt, DateTime.now()),
      ),
      UpdateChecking() => plain(
        spinner,
        'Verificando…',
        'Consultando as versões publicadas',
      ),
      UpdateNoResponse() => plain(
        icon(Icons.wifi_off, AppColors.amber),
        'Não foi possível verificar atualizações',
        'O GitHub não respondeu. Veja sua conexão e tente de novo.',
      ),
      UpdateAvailable(:final update) => highlighted(
        download,
        'Versão ${update.version} disponível',
        _availableDetail(update, packageSize),
      ),
      UpdateConfirmSessions(:final update, :final sessions) => highlighted(
        icon(Icons.warning_amber, AppColors.amber),
        sessions == 1
            ? '1 sessão em execução será encerrada'
            : '$sessions sessões em execução serão encerradas',
        'O app reinicia para instalar a ${update.version}.',
      ),
      UpdateDownloading(:final update, :final progress) => highlighted(
        download,
        'Baixando a ${update.version}',
        _progressDetail(progress),
      ),
      UpdateInstalling() => highlighted(
        spinner,
        'Instalando e reiniciando…',
        'O sistema pode pedir sua senha.',
      ),
      UpdateRestarting(:final update) => highlighted(
        spinner,
        'Reiniciando na ${update.version}…',
        'O app fecha e abre sozinho na versão nova.',
      ),
      UpdateInstalledNotRestarted(:final update) => highlighted(
        icon(Icons.check, CanvasColors.done),
        'A ${update.version} foi instalada',
        'Feche e abra o app para usar',
      ),
      UpdateFailed(:final reason) => (
        icon: icon(Icons.close, AppColors.red),
        title: 'Não foi possível atualizar',
        detail: reason,
        background: AppColors.surfaceRaised,
        border: SessionColors.stopBorder,
      ),
    };
  }

  static String _availableDetail(AvailableUpdate update, int? size) {
    final published = update.publishedAt?.toLocal();
    final facts = [
      if (published != null) 'Publicada em ${formatDate(published)}',
      if (size != null) '${_mb(size)} MB',
    ].join(' · ');
    return facts.isEmpty ? _hint : '$facts. $_hint';
  }

  static String _progressDetail(DownloadProgress? p) {
    if (p == null) return 'Iniciando…';
    final fraction = p.fraction;
    if (fraction == null) return '${_mb(p.received)} MB baixados';
    return '${(fraction * 100).round()}% · '
        '${_mb(p.received)} de ${_mb(p.total!)} MB';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateFlowProvider);
    final flow = ref.read(updateFlowProvider.notifier);
    final size = ref.watch(updatePackageProvider).value?.size;
    final look = _look(state, size);

    Widget secondary(
      String key,
      String label,
      VoidCallback? onTap, {
      FocusNode? focus,
    }) => SmallButton(
      key: ValueKey(key),
      label: label,
      onTap: onTap,
      focusNode: focus,
      height: 32,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      background: AppColors.surfaceRaised,
      border: SessionColors.selectedBorder,
    );
    Widget primary(String key, String label, VoidCallback onTap) => AmberButton(
      key: ValueKey(key),
      label: label,
      onTap: onTap,
      focusNode: actionFocus,
      height: 32,
      fontSize: 13,
    );

    final side = switch (state) {
      UpdateNeverChecked() || UpdateUpToDate() => secondary(
        'about-check-now',
        'Verificar agora',
        flow.check,
        focus: actionFocus,
      ),
      // Disabled, so it can't hold the focus.
      UpdateChecking() => secondary('about-check-now', 'Verificando…', null),
      UpdateNoResponse() => secondary(
        'about-check-retry',
        'Tentar de novo',
        flow.check,
        focus: actionFocus,
      ),
      UpdateAvailable() => primary(
        'about-update-now',
        'Atualizar agora',
        flow.update,
      ),
      UpdateDownloading() => secondary(
        'about-download-cancel',
        'Cancelar',
        flow.cancelDownload,
        focus: actionFocus,
      ),
      UpdateInstalledNotRestarted() => primary(
        'about-restart-now',
        'Reiniciar agora',
        flow.restartNow,
      ),
      UpdateConfirmSessions() ||
      UpdateInstalling() ||
      UpdateRestarting() ||
      UpdateFailed() => null,
    };
    final below = switch (state) {
      UpdateConfirmSessions() => UpdateActionRow([
        secondary('about-update-later', 'Agora não', flow.dismissConfirmation),
        primary(
          'about-update-anyway',
          'Atualizar mesmo assim',
          () => flow.update(confirmed: true),
        ),
      ]),
      UpdateFailed(:final update) => UpdateActionRow([
        secondary(
          'about-open-release',
          'Abrir página da release',
          () => ref.read(updateInstallerProvider).openReleasePage(update.url),
        ),
        primary('about-update-retry', 'Tentar de novo', flow.update),
      ]),
      UpdateDownloading(:final progress) => _Bar(progress),
      _ => null,
    };
    // Announces the state, not each percent of the download (R11).
    final announced = state is UpdateDownloading
        ? look.title
        : '${look.title}. ${look.detail}';
    final oneLine = below != null;

    return Focus(
      focusNode: cardFocus,
      child: Container(
        key: const ValueKey('about-update-card'),
        height: updateCardHeight,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: look.background,
          border: Border.all(color: look.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                look.icon,
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    key: const ValueKey('about-update-status'),
                    container: true,
                    liveRegion: true,
                    label: announced,
                    child: ExcludeSemantics(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            look.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                          Tooltip(
                            // A long reason is cut only on the card.
                            message: state is UpdateFailed ? look.detail : '',
                            child: Text(
                              look.detail,
                              key: state is UpdateFailed
                                  ? const ValueKey('about-download-error')
                                  : null,
                              maxLines: oneLine ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (side != null) ...[const SizedBox(width: 10), side],
              ],
            ),
            if (below != null) ...[const SizedBox(height: 10), below],
          ],
        ),
      ),
    );
  }
}

/// With two actions they go below the text, the main one last (R7).
class UpdateActionRow extends StatelessWidget {
  const UpdateActionRow(this.actions, {super.key});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerRight,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, a) in actions.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          a,
        ],
      ],
    ),
  );
}

class _Bar extends StatelessWidget {
  const _Bar(this.progress);

  final DownloadProgress? progress;

  @override
  Widget build(BuildContext context) {
    final fraction = progress?.fraction;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        key: const ValueKey('about-download-progress'),
        minHeight: 6,
        // Without a total the bar moves by itself, if motion is on.
        value: fraction ?? (AppMotion.animate(context) ? null : 0),
        color: AppColors.amber,
        backgroundColor: AppColors.border,
        semanticsLabel: 'Progresso do download',
        semanticsValue: fraction == null
            ? null
            : '${(fraction * 100).round()}%',
      ),
    );
  }
}
