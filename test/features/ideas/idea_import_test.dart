import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/ideas/idea_import.dart';

/// A `pdfinfo` / `pdftotext` stand-in: [pages] is what each page prints.
class FakePoppler {
  FakePoppler(
    this.pages, {
    this.missing = false,
    this.password = false,
    this.noInfo = false,
  });

  final List<String> pages;
  final bool missing;
  final bool password;
  final bool noInfo;
  final calls = <List<String>>[];

  Future<ProcessResult> call(String exe, List<String> args) async {
    calls.add([exe, ...args]);
    if (missing || (noInfo && exe == 'pdfinfo')) {
      throw ProcessException(exe, args, 'No such file or directory', 2);
    }
    if (password) {
      return ProcessResult(1, 1, '', 'Command Line Error: Incorrect password');
    }
    if (exe == 'pdfinfo') {
      return ProcessResult(
        1,
        0,
        'Title: x\nPages:          ${pages.length}\n',
        '',
      );
    }
    final f = args.indexOf('-f');
    if (f < 0) return ProcessResult(1, 0, pages.map((p) => '$p\f').join(), '');
    final i = int.parse(args[f + 1]);
    return ProcessResult(1, 0, '${pages[i - 1]}\f', '');
  }
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('idea-import-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File write(String name, Object content) {
    final f = File('${tmp.path}/$name');
    content is String
        ? f.writeAsStringSync(content)
        : f.writeAsBytesSync(content as List<int>);
    return f;
  }

  IdeaImport reader([FakePoppler? fake]) =>
      IdeaImport((fake ?? FakePoppler(const [])).call);

  group('TXT e Markdown', () {
    test('TXT is read as UTF-8 with normalized breaks and spaces', () async {
      final f = write(
        'ideia.txt',
        '\uFEFF  \r\nLembrete de consulta   \r\n\r\n\r\n\r\npor WhatsApp\t\r\n\n',
      );
      final r = await reader().read(f.path);
      expect(r.kind, ImportKind.text);
      expect(r.text, 'Lembrete de consulta\n\npor WhatsApp');
      expect(r.pages, isNull);
      expect(r.chars, r.text.length);
      expect(r.warnings, isEmpty);
      expect(r.name, 'ideia.txt');
    });

    test('Markdown goes in as it is', () async {
      const md =
          '## Público\nDonos de escolas pequenas.\n\n- cadastro de turmas\n- matrícula';
      final f = write('proposta.markdown', md);
      final r = await reader().read(f.path);
      expect(r.kind, ImportKind.markdown);
      expect(r.text, md);
      expect(ImportKind.of('a.MD'), ImportKind.markdown);
    });

    test('TXT outside UTF-8 is read as Latin-1 with a warning', () async {
      final f = write('latin.txt', [
        ...latin1.encode('Ação do paciente'),
        0x81, // control range: becomes "?"
      ]);
      final r = await reader().read(f.path);
      expect(r.text, 'Ação do paciente?');
      expect(r.warnings.single, isA<EncodingWarning>());
      expect(
        r.warnings.single.title,
        'Alguns caracteres não foram reconhecidos.',
      );
    });
  });

  group('PDF', () {
    test('reads page by page, reporting progress', () async {
      final fake = FakePoppler([
        'Primeira página.',
        'Segunda página.',
        'Terceira.',
      ]);
      final f = write('b.pdf', 'x');
      final progress = <(int, int)>[];
      final r = await reader(fake)
          .read(f.path, onProgress: (i, n) => progress.add((i, n)));
      expect(r.kind, ImportKind.pdf);
      expect(r.pages, 3);
      expect(progress, [(1, 3), (2, 3), (3, 3)]);
      expect(r.text, 'Primeira página.\n\nSegunda página.\n\nTerceira.');
      expect(fake.calls[1], [
        'pdftotext',
        '-layout',
        '-f',
        '1',
        '-l',
        '1',
        f.path,
        '-',
      ]);
    });

    test('joins broken lines and keeps titles and lists apart', () async {
      final fake = FakePoppler([
        '   Briefing · Lembretes\n'
            '   Hoje 18% dos pacientes faltam sem avisar. A clínica quer mandar\n'
            '   um lembrete por WhatsApp 24 h antes, com botões Confirmar e\n'
            '   Remarcar. Quem remarcar escolhe um novo horário livre na agenda.\n'
            '\n'
            '   Requisitos levantados com a recepção:\n'
            '   • o lembrete sai às 9 h do dia anterior;\n'
            '   • a recepção vê quem confirmou e quem não res-\n'
            '     pondeu.\n',
      ]);
      final r = await reader(fake).read(write('b.pdf', 'x').path);
      expect(
        r.text,
        'Briefing · Lembretes\n'
        'Hoje 18% dos pacientes faltam sem avisar. A clínica quer mandar um '
        'lembrete por WhatsApp 24 h antes, com botões Confirmar e Remarcar. '
        'Quem remarcar escolhe um novo horário livre na agenda.\n'
        '\n'
        'Requisitos levantados com a recepção:\n'
        '• o lembrete sai às 9 h do dia anterior;\n'
        '• a recepção vê quem confirmou e quem não respondeu.',
      );
    });

    test('a full-width line ending a sentence goes on', () async {
      final fake = FakePoppler([
        'O lembrete sai um dia antes da consulta marcada.\n'
            'A recepção acompanha as respostas.\n'
            'Outro parágrafo começa aqui.\n',
      ]);
      final r = await reader(fake).read(write('b.pdf', 'x').path);
      expect(
        r.text,
        'O lembrete sai um dia antes da consulta marcada. A recepção '
        'acompanha as respostas.\nOutro parágrafo começa aqui.',
      );
    });

    test('removes headers and footers repeated on every page', () async {
      final fake = FakePoppler([
        'Clínica Sorriso — briefing\n\nPrimeira parte do texto.\n\n\nPágina 1 de 2\n',
        'Clínica Sorriso — briefing\n\nSegunda parte do texto.\n\n\nPágina 2 de 2\n',
      ]);
      final r = await reader(fake).read(write('b.pdf', 'x').path);
      expect(r.text, 'Primeira parte do texto.\n\nSegunda parte do texto.');
    });

    test('a sentence that goes on to the next page is joined', () async {
      final fake = FakePoppler([
        'O lembrete sai um dia\n',
        'antes da consulta.\n',
      ]);
      final r = await reader(fake).read(write('b.pdf', 'x').path);
      expect(r.text, 'O lembrete sai um dia antes da consulta.');
    });

    test('without pdfinfo, reads the whole PDF split by form feeds', () async {
      final fake = FakePoppler(['Um.', 'Dois.'], noInfo: true);
      final r = await reader(fake).read(write('b.pdf', 'x').path);
      expect(r.pages, 2);
      expect(r.text, 'Um.\n\nDois.');
      expect(fake.calls.last, [
        'pdftotext',
        '-layout',
        write('b.pdf', 'x').path,
        '-',
      ]);
    });

    test('cancelling stops between pages', () async {
      final fake = FakePoppler(List.filled(8, 'Texto.'));
      final cancel = ImportCancel();
      final f = write('b.pdf', 'x');
      await expectLater(
        reader(fake).read(
          f.path,
          cancel: cancel,
          onProgress: (i, _) {
            if (i == 2) cancel.cancel();
          },
        ),
        throwsA(isA<ImportCancelled>()),
      );
      expect(fake.calls.where((c) => c.first == 'pdftotext'), hasLength(2));
    });

    test('a PDF without text (scanned) is a problem', () async {
      final fake = FakePoppler(['\n\n', '  \n']);
      final e = await _problem(reader(fake), write('s.pdf', 'x').path);
      expect(e, isA<NoTextProblem>());
      expect(e.title, 'Este PDF não tem texto para ler.');
    });

    test('a PDF with a password is a problem', () async {
      final e = await _problem(
        reader(FakePoppler(['x'], password: true)),
        write('p.pdf', 'x').path,
      );
      expect(e, isA<PasswordProblem>());
      expect(e.title, 'O PDF tem senha.');
    });

    test('pdftotext missing asks to install poppler-utils', () async {
      final e = await _problem(
        reader(FakePoppler(['x'], missing: true)),
        write('p.pdf', 'x').path,
      );
      expect(e, isA<NoPdftotextProblem>());
      expect(e.title, 'Para ler PDF, instale o pacote poppler-utils.');
      expect(e.command, 'sudo apt install poppler-utils');
    });
  });

  group('limites', () {
    test(
      'cuts over 40.000 at the end of the last paragraph that fits',
      () async {
        final para = '${'a' * 9998}.';
        final text = List.filled(5, para).join('\n\n'); // 50.003 chars
        final r = await reader().read(write('longo.md', text).path);
        expect(r.text, List.filled(3, para).join('\n\n'));
        expect(r.text.length, lessThanOrEqualTo(ideaMaxChars));
        final w = r.truncated!;
        expect(w.total, text.length);
        expect(w.overflow, List.filled(2, para).join('\n\n'));
        expect(
          w.title,
          'O arquivo tem 50.003 caracteres; o campo aceita 40.000.',
        );
        expect(r.fullText, text);
      },
    );

    test('fit cuts again for the room left in the field', () {
      final r = ImportedText(
        path: '/x/a.txt',
        kind: ImportKind.text,
        text: 'Um.\n\nDois.',
        fullText: 'Um.\n\nDois.',
      ).fit(7);
      expect(r.text, 'Um.');
      expect(r.truncated!.overflow, 'Dois.');
      expect(r.fit(100).truncated, isNull);
    });

    test('a paragraph longer than the limit falls back to a sentence', () {
      expect(cutAtParagraph('Um dois. Três quatro cinco', 15), (
        'Um dois.',
        'Três quatro cinco',
      ));
    });

    test('a file over 20 MB is not read', () async {
      final f = File('${tmp.path}/grande.txt');
      final raf = f.openSync(mode: FileMode.write)
        ..truncateSync(ideaMaxBytes + 4 * 1024 * 1024 + 300 * 1024);
      raf.closeSync();
      final e = await _problem(reader(), f.path);
      expect(e, isA<TooBigProblem>());
      expect(e.title, 'O arquivo tem 24,3 MB; o limite é 20 MB.');
    });

    test('formats not accepted are a problem', () async {
      final e = await _problem(reader(), write('briefing.docx', 'x').path);
      expect(e, isA<UnsupportedProblem>());
      expect(e.title, 'Ainda não dá para importar .docx.');
      expect(e.detail, 'Salve como PDF, Markdown ou TXT.');
      final png = await _problem(reader(), write('a.PNG', 'x').path);
      expect(png.title, 'Ainda não dá para importar .png.');
    });

    test('a missing file is unreadable', () async {
      final e = await _problem(reader(), '${tmp.path}/sumiu.txt');
      expect(e, isA<UnreadableProblem>());
    });
  });

  group('poppler de verdade', () {
    final real = IdeaImport(Process.run);
    final skip = File('/usr/bin/pdftotext').existsSync()
        ? null
        : 'poppler-utils não instalado';
    const dir = 'test/fixtures/ideas';

    test('reads a PDF with text, without the repeated header', () async {
      final r = await real.read('$dir/briefing.pdf');
      expect(r.pages, 2);
      expect(r.text, isNot(contains('Cabecalho')));
      expect(r.text, isNot(contains('Pagina')));
      expect(
        r.text,
        'Hoje muitos pacientes faltam sem avisar e a clinica quer mandar um '
        'lembrete por WhatsApp.\n\nSegunda pagina com texto.',
      );
    }, skip: skip);

    test('a PDF with a password and one without text', () async {
      expect(await _problem(real, '$dir/senha.pdf'), isA<PasswordProblem>());
      expect(await _problem(real, '$dir/escaneado.pdf'), isA<NoTextProblem>());
    }, skip: skip);
  });
}

Future<ImportProblem> _problem(IdeaImport r, String path) async {
  try {
    await r.read(path);
  } on ImportProblem catch (e) {
    return e;
  }
  fail('expected an ImportProblem');
}
