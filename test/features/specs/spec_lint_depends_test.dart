import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/specs/spec_file.dart';
import 'package:promptorium/features/specs/spec_lint.dart';

String spec(String head) =>
    '---\nid: SPEC-002\nstatus: aprovada\n$head---\n\n# Pedidos\n\n'
    '## Requisitos\n\n- R1 · Quando pedir, o sistema deve guardar\n\n'
    '## Critérios de aceite\n\n- [ ] Guarda [R1] verificar: true\n';

List<SpecWarning> of(SpecWarningKind k, String text, {Set<String>? codes}) => [
  for (final w in lintSpec(text, knownCodes: codes))
    if (w.kind == k) w,
];

/// SPEC-063 t2: dependency and frontmatter warnings.
void main() {
  const codes = {'SPEC-001', 'SPEC-002', 'SPEC-003'};

  test('R3: a dependency on a spec outside the workspace, on its line', () {
    final w = of(
      SpecWarningKind.unknownDependency,
      spec('depende-de: [SPEC-001, SPEC-009]\n'),
      codes: codes,
    );
    expect(w, hasLength(1));
    expect(w.single.line, 4);
    expect(
      w.single.message,
      'depende-de cita SPEC-009, que não existe neste workspace: a spec não '
      'vai esperar por ela',
    );
    final two = of(
      SpecWarningKind.unknownDependency,
      spec('depende: [SPEC-008, SPEC-009]\n'),
      codes: codes,
    );
    expect(
      two.single.message,
      contains('SPEC-008 e SPEC-009, que não existem'),
    );
    // Without the codes of the workspace there is nothing to compare.
    expect(
      of(SpecWarningKind.unknownDependency, spec('depende-de: [SPEC-009]\n')),
      isEmpty,
    );
  });

  test('R3: the spec itself', () {
    final w = of(
      SpecWarningKind.selfDependency,
      spec('depende-de: [SPEC-002]\n'),
      codes: codes,
    );
    expect(w.single.message, 'depende-de cita a própria spec (SPEC-002)');
    // Not counted as unknown too.
    expect(
      of(
        SpecWarningKind.unknownDependency,
        spec('depende-de: [SPEC-002]\n'),
        codes: {'SPEC-001'},
      ),
      isEmpty,
    );
  });

  test('R4: an unknown key, with "Trocar para depende-de"; known keys and '
      'variations are quiet', () {
    final w = of(
      SpecWarningKind.unknownFrontmatterKey,
      spec('requer: SPEC-003\n'),
      codes: codes,
    );
    expect(w.single.line, 4);
    expect(w.single.key, 'requer');
    expect(w.single.fixLabel, 'Trocar para depende-de');
    expect(
      w.single.message,
      contains('Chave desconhecida no cabeçalho: requer'),
    );
    expect(
      of(
        SpecWarningKind.unknownFrontmatterKey,
        spec(
          'depende-de: [SPEC-001]\nfase: mvp\ndesign: dispensado\n'
          'issue: 12\nplano: automatico\ndepende: [SPEC-003]\n',
        ),
        codes: codes,
      ),
      isEmpty,
    );
  });

  test('R4: withDependsOnFrom turns the key into depende-de', () {
    final out = SpecDocument.parse(
      spec('depende-de: [SPEC-001]\nrequer: SPEC-003\n'),
    ).withDependsOnFrom('requer');
    expect(out, spec('depende-de: [SPEC-001, SPEC-003]\n'));
    final alone = SpecDocument.parse(spec('requer: SPEC-003\n'))
        .withDependsOnFrom('requer');
    expect(alone, spec('depende-de: [SPEC-003]\n'));
  });
}
