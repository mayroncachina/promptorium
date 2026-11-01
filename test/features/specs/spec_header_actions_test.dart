import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/specs/widgets/spec_header.dart';

void _noop() {}

List<String> ids(List<SpecAction> l) => [for (final a in l) a.id];

SpecActionEmphasis emphasisOf(List<SpecAction> l, String id) =>
    l.firstWhere((a) => a.id == id).emphasis;

void main() {
  group('specHeaderActions', () {
    test('R3: draft in the backlog: Refinar com IA, Gerar design, Aprovar '
        '(primary) and the menu, in this order', () {
      final l = specHeaderActions(
        const SpecHeaderState(
          onRefine: _noop,
          onDesign: _noop,
          onApprove: _noop,
          onDelete: _noop,
        ),
      );
      expect(ids(l), ['refine', 'design', 'approve', 'delete']);
      expect(
        [for (final a in l) a.label],
        ['Refinar com IA', 'Gerar design', 'Aprovar', 'Excluir…'],
      );
      expect(
        [for (final a in l) a.emphasis],
        [
          SpecActionEmphasis.secondary,
          SpecActionEmphasis.secondary,
          SpecActionEmphasis.primary,
          SpecActionEmphasis.menu,
        ],
      );
      expect(l.last.destructive, isTrue);
      expect(
        [for (final a in l) a.keyName],
        ['spec-refine', 'spec-design', 'spec-approve', 'spec-delete'],
      );
    });

    test('R4: approved in the backlog: no "Aprovar" and no primary', () {
      final l = specHeaderActions(
        const SpecHeaderState(
          approved: true,
          onRefine: _noop,
          onDesign: _noop,
          onDelete: _noop,
        ),
      );
      expect(ids(l), ['refine', 'design', 'delete']);
      expect(l.where((a) => a.emphasis == SpecActionEmphasis.primary), isEmpty);
    });

    test('R5: locked: only "Clonar para alterar" (primary) and the menu', () {
      final l = specHeaderActions(
        const SpecHeaderState(locked: true, onClone: _noop, onArchive: _noop),
      );
      expect(ids(l), ['clone', 'archive']);
      expect(l.first.label, 'Clonar para alterar');
      expect(l.first.emphasis, SpecActionEmphasis.primary);
      expect(l.first.keyName, 'spec-clone');
      expect(l.last.emphasis, SpecActionEmphasis.menu);
      // Locked without archive/delete: nothing for the menu.
      expect(
        ids(
          specHeaderActions(
            const SpecHeaderState(locked: true, onClone: _noop),
          ),
        ),
        ['clone'],
      );
    });

    test('R6: Protótipo: "Comparar variações" secondary, "Gerar telas da '
        'spec" primary, then the menu', () {
      final l = specHeaderActions(
        const SpecHeaderState(
          prototype: true,
          onCompare: _noop,
          onGenerate: _noop,
          onDelete: _noop,
        ),
      );
      expect(ids(l), ['compare', 'generate', 'delete']);
      expect(emphasisOf(l, 'compare'), SpecActionEmphasis.secondary);
      expect(emphasisOf(l, 'generate'), SpecActionEmphasis.primary);
      expect(l[0].keyName, 'proto-compare');
      expect(l[1].keyName, 'proto-generate');
      expect(l[1].label, 'Gerar telas da spec');
    });

    test('R7, R7a: menu items only when available; labels without "spec"', () {
      expect(
        specHeaderActions(const SpecHeaderState(onRefine: _noop))
            .where((a) => a.emphasis == SpecActionEmphasis.menu),
        isEmpty,
      );
      final archived = specHeaderActions(
        const SpecHeaderState(locked: true, archived: true, onArchive: _noop),
      );
      expect(archived.last.label, 'Desarquivar');
      final archive = specHeaderActions(
        const SpecHeaderState(locked: true, onArchive: _noop),
      );
      expect(archive.last.label, 'Arquivar');
      for (final a in [
        ...specHeaderActions(
          const SpecHeaderState(onArchive: _noop, onDelete: _noop),
        ),
        ...archived,
      ]) {
        if (a.id != 'generate') {
          expect(a.label.toLowerCase(), isNot(contains('spec')), reason: a.id);
        }
      }
    });

    test(
      'R10: every action has a tooltip; an unavailable one explains why',
      () {
        final l = specHeaderActions(
          const SpecHeaderState(unavailableReason: 'Aguarde a ação terminar.'),
        );
        for (final a in l) {
          expect(a.enabled, isFalse);
          expect(a.tooltip, isNotEmpty);
          expect(a.tooltipText, 'Aguarde a ação terminar.');
        }
        final ok = specHeaderActions(const SpecHeaderState(onRefine: _noop));
        expect(ok.first.tooltipText, refineTooltip);
      },
    );
  });

  group('fitActions / layoutSpecActions (R9)', () {
    test('keeps the secondaries that fit, dropping from the last one', () {
      expect(fitActions([130, 115], 300), 2);
      expect(fitActions([130, 115], 245), 2);
      expect(fitActions([130, 115], 244), 1);
      expect(fitActions([130, 115], 129), 0);
      expect(fitActions([], 0), 0);
    });

    final draft = specHeaderActions(
      const SpecHeaderState(onRefine: _noop, onDesign: _noop, onApprove: _noop),
    );
    double width(SpecAction a) => switch (a.id) {
      'refine' => 130,
      'design' => 115,
      _ => 90,
    };

    test('"Gerar design" goes to the menu first, then "Refinar com IA"; the '
        'primary never', () {
      // Everything: 130+8 + 115+8 + 90+8 = 359 (no menu button needed).
      var r = layoutSpecActions(draft, width, 359);
      expect(ids(r.bar), ['refine', 'design', 'approve']);
      expect(r.menu, isEmpty);

      r = layoutSpecActions(draft, width, 330);
      expect(ids(r.bar), ['refine', 'approve']);
      expect(ids(r.menu), ['design']);
      expect(r.menu.single.emphasis, SpecActionEmphasis.menu);

      r = layoutSpecActions(draft, width, 200);
      expect(ids(r.bar), ['approve']);
      expect(ids(r.menu), ['refine', 'design']);

      r = layoutSpecActions(draft, width, 0);
      expect(ids(r.bar), ['approve']);
    });

    test('the moved secondaries come before Arquivar / Excluir', () {
      final l = specHeaderActions(
        const SpecHeaderState(
          onRefine: _noop,
          onDesign: _noop,
          onApprove: _noop,
          onDelete: _noop,
        ),
      );
      final r = layoutSpecActions(l, width, 200);
      expect(ids(r.menu), ['refine', 'design', 'delete']);
    });
  });
}
