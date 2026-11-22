import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/review/auto_reviewer.dart';
import 'package:promptorium/features/review/reviewer_findings.dart';

const _diff =
    '''diff --git a/lib/pagamento/checkout.dart b/lib/pagamento/checkout.dart
index 1111111..2222222 100644
--- a/lib/pagamento/checkout.dart
+++ b/lib/pagamento/checkout.dart
@@ -40,4 +40,6 @@ class Checkout {
   Future cobrar(Pedido p) async {
-    return null;
+    final r = await _stripe.charge(p.total);
+    return Pagamento.aprovado(r.id);
   }
 }
diff --git a/a/notas.md b/a/notas.md
new file mode 100644
--- /dev/null
+++ b/a/notas.md
@@ -0,0 +1 @@
+nota
''';

const _wt = '/home/x/.promptorium/wt/spec-031';

List<ReviewerComment> _norm(List<ReviewerComment> c, {Set<String>? reqs}) =>
    normalizeReviewerComments(
      c,
      diff: _diff,
      worktree: _wt,
      requirements: reqs ?? {'R1', 'R2'},
    );

/// SPEC-102 R8: each rule of the normalizer, the same for both providers.
void main() {
  test('caminho absoluto, ./ e a/ b/ viram relativos à raiz do worktree', () {
    final out = _norm(const [
      ReviewerComment(
        text: 'abs',
        path: '$_wt/lib/pagamento/checkout.dart',
        line: 42,
      ),
      ReviewerComment(text: 'ponto', path: './lib/pagamento/checkout.dart'),
      ReviewerComment(text: 'b', path: 'b/lib/pagamento/checkout.dart'),
      // Absolute path of another checkout of the same repository.
      ReviewerComment(
        text: 'outro',
        path: '/home/x/repo/lib/pagamento/checkout.dart',
        line: 43,
      ),
      // A real folder `a/` is kept.
      ReviewerComment(text: 'pasta a', path: 'a/notas.md', line: 1),
    ]);
    expect(out.map((c) => c.path), [
      'lib/pagamento/checkout.dart',
      'lib/pagamento/checkout.dart',
      'lib/pagamento/checkout.dart',
      'lib/pagamento/checkout.dart',
      'a/notas.md',
    ]);
    expect(out.first.line, 42);
  });

  test('arquivo fora do diff vira comentário geral com o caminho no texto', () {
    final out = _norm(const [
      ReviewerComment(
        text: 'ainda é importado',
        path: 'lib/pagamento/legado.dart',
        line: 7,
      ),
    ]);
    expect(out.single.path, isNull);
    expect(out.single.line, isNull);
    expect(out.single.text, 'lib/pagamento/legado.dart:7 — ainda é importado');
  });

  test('linha fora do trecho vira comentário do arquivo (linha 0)', () {
    final out = _norm(const [
      ReviewerComment(
        text: 'longe',
        path: 'lib/pagamento/checkout.dart',
        line: 120,
      ),
      ReviewerComment(
        text: 'dentro',
        path: 'lib/pagamento/checkout.dart',
        line: 41,
      ),
    ]);
    expect(out.map((c) => c.line), [0, 41]);
  });

  test('severidade inválida vira media; requisito inexistente fica vazio', () {
    final out = _norm(const [
      ReviewerComment(
        text: 'a',
        path: 'lib/pagamento/checkout.dart',
        severity: 'critical',
        requirement: 'R9',
      ),
      ReviewerComment(
        text: 'b',
        path: 'lib/pagamento/checkout.dart',
        severity: 'ALTA',
        requirement: 'r2',
      ),
    ]);
    expect(out.map((c) => c.severity), ['media', 'alta']);
    expect(out.map((c) => c.requirement), [null, 'R2']);
    // PR without spec: no requirement at all.
    expect(
      normalizeReviewerComments(
        const [ReviewerComment(text: 'x', requirement: 'R1')],
        diff: _diff,
        worktree: _wt,
      ).single.requirement,
      isNull,
    );
  });

  test('duplicatas da rodada (arquivo, linha e texto) entram uma vez', () {
    final out = _norm(const [
      ReviewerComment(text: 'igual', path: 'lib/pagamento/checkout.dart'),
      ReviewerComment(
        text: 'igual',
        path: './lib/pagamento/checkout.dart',
        line: 0,
      ),
      ReviewerComment(
        text: 'igual',
        path: 'lib/pagamento/checkout.dart',
        line: 42,
      ),
      ReviewerComment(text: 'geral'),
      ReviewerComment(text: 'geral'),
    ]);
    expect(out.map((c) => (c.path, c.line, c.text)), [
      ('lib/pagamento/checkout.dart', null, 'igual'),
      ('lib/pagamento/checkout.dart', 42, 'igual'),
      (null, null, 'geral'),
    ]);
  });

  test('o veredito normalizado mantém aprovação, resumo e critérios', () {
    final v = ReviewerVerdict.parse({
      'veredito': 'corrigir',
      'resumo': 'falta',
      'criterios': [
        {'indice': 1, 'atendido': true},
      ],
      'comentarios': [
        {
          'arquivo': '$_wt/lib/pagamento/checkout.dart',
          'linha': 42,
          'texto': 'trate o erro',
          'severidade': 'alta',
          'requisito': 'R2',
        },
      ],
    })!.normalized(diff: _diff, worktree: _wt, requirements: {'R2'});
    expect(v.approve, isFalse);
    expect(v.summary, 'falta');
    expect(v.met, {0});
    expect(v.comments.single.location, 'lib/pagamento/checkout.dart:42');
  });
}
