import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repos/debt_links_repo.dart';
import '../specs/spec_service.dart';
import '../vibe/vibe_service.dart';
import 'debt_item.dart';
import 'debt_table.dart';

/// "Pagar" (SPEC-112 R15): the selected open debts become one VIBE or one
/// spec, and each one is "em pagamento" until the merge strikes it or the
/// discard gives it back.

enum DebtPayMode { vibe, spec }

/// VIBE for up to 2 debts, spec from 3 (R15): only the suggestion, the
/// person chooses.
DebtPayMode suggestedPayMode(int count) =>
    count <= 2 ? DebtPayMode.vibe : DebtPayMode.spec;

/// `DT-05`, `DT-05 e DT-06`, `DT-03, DT-05 e DT-06`.
String debtCodesText(List<String> codes) => codes.length <= 1
    ? codes.join()
    : '${codes.sublist(0, codes.length - 1).join(', ')} e ${codes.last}';

/// The text of a cell without the Markdown marks.
String _plain(String v) => v
    .replaceAll(RegExp(r'\*\*|~~|`'), '')
    .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1)!)
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// `DT-05 · Pagamento simulado (PagarView.vue): ligar o gateway`.
String debtPaymentLine(DebtItem d) {
  final where = d.whereRefs.join(', ');
  final todo = d.toResolve.trim();
  final b = StringBuffer('${d.code} · ${_plain(d.title)}');
  if (where.isNotEmpty) b.write(' ($where)');
  if (todo.isNotEmpty && todo != debtDash) b.write(': ${_plain(todo)}');
  final s = b.toString();
  return s.endsWith('.') ? s : '$s.';
}

/// The prompt of the VIBE (R15, mock 5).
String vibePaymentPrompt(List<DebtItem> items, {required String file}) {
  final codes = [for (final d in items) d.code];
  return [
    'Pague ${codes.length == 1 ? 'o débito' : 'os débitos'} '
        '${debtCodesText(codes)} de $file.',
    for (final d in items) debtPaymentLine(d),
    'No fim, diga quais pagou e o que ficou de fora.',
  ].join('\n');
}

/// `Pagar débitos: DT-03, DT-05`.
String paymentSpecTitle(List<DebtItem> items) =>
    'Pagar ${items.length == 1 ? 'débito' : 'débitos'}: '
    '${items.map((d) => d.code).join(', ')}';

/// The Objetivo of the spec: the debts, one per line.
String paymentSpecObjective(List<DebtItem> items, {required String file}) => [
  'Pagar ${items.length == 1 ? 'o débito' : 'os débitos'} '
      '${debtCodesText([for (final d in items) d.code])} de `$file`. No '
      'merge, o app risca as linhas com "**resolvido** pela spec".',
  '',
  for (final d in items)
    '- ${d.code} · **${_plain(d.title)}**'
        '${d.reason.trim().isEmpty ? '' : ': ${_plain(d.reason)}'}'
        '${d.whereRefs.isEmpty ? '' : ' (${d.whereRefs.map((w) => '`$w`').join(', ')})'}',
].join('\n');

/// One requirement per debt.
String paymentRequirement(DebtItem d) {
  final todo = d.toResolve.trim();
  final where = d.whereRefs.join(', ');
  return 'Pagar o ${d.code} (${_plain(d.title)})'
      '${todo.isEmpty || todo == debtDash ? '' : ': ${_plain(todo)}'}'
      '${where.isEmpty ? '' : ' — em `$where`'}.';
}

/// The Markdown of the spec "Pagar débitos: …" (R15).
String paymentSpecMarkdown({
  required String code,
  required List<DebtItem> items,
  required String file,
}) => newSpecMarkdown(
  code: code,
  title: paymentSpecTitle(items),
  objective: paymentSpecObjective(items, file: file),
  requirements: [for (final d in items) paymentRequirement(d)],
);

/// Creates the VIBE of [prompt] in [ws]; returns the spec row.
typedef StartPaymentVibe = Future<Spec> Function(Workspace ws, String prompt);

/// Creates the spec titled [title] with the text [render] builds.
typedef CreatePaymentSpec = Future<Spec> Function(
  Workspace ws,
  String title,
  String Function(String code) render,
);

class DebtPayment {
  DebtPayment({
    required this.links,
    required this.startVibe,
    required this.createSpec,
  });

  final DebtLinksRepo links;
  final StartPaymentVibe startVibe;
  final CreatePaymentSpec createSpec;

  /// "Criar VIBE" / "Criar spec" (R15): creates the task and links each of
  /// [items] to it (`paymentSpecId`), so they show "em pagamento".
  Future<Spec> pay(
    Workspace ws,
    List<DebtItem> items,
    DebtPayMode mode, {
    required String file,
  }) async {
    final open = [
      for (final d in items)
        if (!d.paid) d,
    ];
    if (open.isEmpty) throw StateError('Nenhum débito aberto para pagar.');
    final spec = switch (mode) {
      DebtPayMode.vibe => await startVibe(
        ws,
        vibePaymentPrompt(open, file: file),
      ),
      DebtPayMode.spec => await createSpec(
        ws,
        paymentSpecTitle(open),
        (code) => paymentSpecMarkdown(code: code, items: open, file: file),
      ),
    };
    for (final d in open) {
      final id = await links.ensure(ws.path, DebtKind.debt.dbName, d.code);
      await links.update(id, DebtLinksCompanion(paymentSpecId: Value(spec.id)));
    }
    return spec;
  }

  /// The spec or the VIBE was discarded (R15, P7).
  Future<void> release(int specId) => links.releaseSpec(specId);
}

final debtPaymentProvider = Provider(
  (ref) => DebtPayment(
    links: ref.watch(debtLinksRepoProvider),
    startVibe: (ws, prompt) async =>
        (await ref.read(vibeServiceProvider).start(ws, prompt)).spec,
    createSpec: (ws, title, render) =>
        ref.read(specServiceProvider).create(ws, title: title, render: render),
  ),
);
