import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'sprint_rules.dart';

/// Sprint chosen on the Quadro of the active workspace (SPEC-042 R2), as
/// stored in `app_settings` (`board.sprint.<id>`); null when nothing was saved.
class BoardSprint extends Notifier<String?> {
  int? _workspaceId;

  @override
  String? build() {
    _workspaceId = ref.watch(activeWorkspaceProvider.select((w) => w?.id));
    final id = _workspaceId;
    if (id == null) return null;
    return ref
        .read(appSettingsProvider.notifier)
        .get(AppSettingKeys.boardSprint(id));
  }

  Future<void> set(SprintFilter filter) async {
    state = filter.stored;
    final id = _workspaceId;
    if (id == null) return;
    await ref
        .read(appSettingsProvider.notifier)
        .set(AppSettingKeys.boardSprint(id), filter.stored);
  }
}

final boardSprintProvider = NotifierProvider<BoardSprint, String?>(
  BoardSprint.new,
);

/// The filter the three views of the Quadro apply.
final boardSprintFilterProvider = Provider<SprintFilter>((ref) {
  final ws = ref.watch(activeWorkspaceProvider);
  if (ws == null) return const SprintFilter.all();
  return resolveSprintFilter(
    ref.watch(boardSprintProvider),
    ref.watch(sprintsProvider(ws.id)).value ?? const [],
  );
});
