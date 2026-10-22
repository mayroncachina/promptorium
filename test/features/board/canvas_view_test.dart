import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/board/widgets/canvas_view_controller.dart';
import 'package:promptorium/features/board/spec_references.dart';

void main() {
  test('zoom starts at 100%, clamps, resets and centers selection', () {
    final view = CanvasViewController()..viewport = const Size(1000, 700);
    addTearDown(view.dispose);
    expect(view.scale, 1);
    for (var i = 0; i < 20; i++) {
      view.zoomIn();
    }
    expect(view.scale, 1.5);
    for (var i = 0; i < 20; i++) {
      view.zoomOut();
    }
    expect(view.scale, .5);
    view.reset();
    expect(view.scale, 1);
    const rect = Rect.fromLTWH(300, 500, 250, 116);
    view.fitSelection(rect);
    expect(view.scale, 1.3);
    expect(
      view.toScene(const Offset(500, 350)).dx,
      closeTo(rect.center.dx, .001),
    );
    expect(
      view.toScene(const Offset(500, 350)).dy,
      closeTo(rect.center.dy, .001),
    );
  });
  test('only executed Skill tools count, not available init skills', () {
    expect(
      loadedSkills({
        'type': 'system',
        'skills': ['available'],
      }),
      isEmpty,
    );
    expect(
      loadedSkills({
        'message': {
          'content': [
            {
              'type': 'tool_use',
              'name': 'Skill',
              'input': {'skill': 'used'},
            },
            {
              'type': 'tool_use',
              'name': 'Read',
              'input': {'skill': 'wrong'},
            },
            {
              'type': 'tool_use',
              'name': 'Skill',
              'input': {'skill': 'used'},
            },
          ],
        },
      }),
      {'used'},
    );
  });
}
