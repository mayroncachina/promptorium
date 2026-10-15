import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/sessions/widgets/composer.dart';

void main() {
  test('"Anexar spec" inserts and removes @specs mentions', () {
    var r = insertMention('', 0, 'specs/SPEC-002-sessoes.md');
    expect(r.text, '@specs/SPEC-002-sessoes.md ');
    expect(r.cursor, r.text.length);

    r = insertMention('Implemente isso', 15, 'specs/SPEC-001-a.md');
    expect(r.text, 'Implemente isso @specs/SPEC-001-a.md ');

    r = insertMention('Veja  e corrija', 5, 'specs/SPEC-003.md');
    expect(r.text, 'Veja @specs/SPEC-003.md e corrija');

    const text =
        'Use @specs/SPEC-001-a.md e @lib/x.dart\n@specs/SPEC-002.md ok';
    expect(attachedSpecs(text), ['specs/SPEC-001-a.md', 'specs/SPEC-002.md']);
    expect(
      removeMention(text, 'specs/SPEC-001-a.md'),
      'Use e @lib/x.dart\n@specs/SPEC-002.md ok',
    );
    expect(
      removeMention(text, 'specs/SPEC-002.md'),
      'Use @specs/SPEC-001-a.md e @lib/x.dart\n ok',
    );
  });
}
