import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dev/picked_element.dart';

/// Elements pointed in the preview and not sent yet, per session (SPEC-051
/// R8): several can be pointed before sending.
class PickedElements extends Notifier<List<PickedElement>> {
  PickedElements(this.sessionId);

  final String sessionId;

  @override
  List<PickedElement> build() => const [];

  void add(PickedElement e) => state = [...state, e];

  void removeAt(int i) => state = [...state]..removeAt(i);

  void clear() => state = const [];
}

final pickedElementsProvider =
    NotifierProvider.family<PickedElements, List<PickedElement>, String>(
      PickedElements.new,
    );
