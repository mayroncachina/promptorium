import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/claude/claude_process.dart' show ImagePart;
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

/// The message of a request with pointed elements (R8): the user's text,
/// then one block per element. With [images], the PNGs go as [ImagePart];
/// without (Codex without the `image` modality), they are written to
/// `.promptorium/attachments/<data>/` in [root] and mentioned with `@`, as
/// the Prompt does with files.
Future<({String text, List<ImagePart> images})> buildPickedMessage(
  String request,
  List<PickedElement> elements, {
  required bool images,
  required String root,
  DateTime? now,
}) async {
  final text = request.trim().isEmpty
      ? (elements.length == 1
            ? 'Veja o elemento apontado no preview.'
            : 'Veja os elementos apontados no preview.')
      : request.trim();
  if (elements.isEmpty) return (text: text, images: const <ImagePart>[]);
  final parts = <ImagePart>[];
  final blocks = <String>[];
  Directory? batch;
  for (final (i, e) in elements.indexed) {
    final pngs = [
      if (e.elementPng case final b?) ('elemento-${i + 1}.png', b),
      if (e.pagePng case final b?) ('pagina-${i + 1}.png', b),
    ];
    final files = <String>[];
    for (final (name, bytes) in pngs) {
      if (images) {
        parts.add(
          ImagePart(
            mediaType: 'image/png',
            base64: base64Encode(bytes),
            name: name,
          ),
        );
        continue;
      }
      if (batch == null) {
        final stamp = (now ?? DateTime.now()).toIso8601String().replaceAll(
          RegExp(r'[:.]'),
          '-',
        );
        batch = Directory('$root/.promptorium/attachments/$stamp');
        await batch.create(recursive: true);
        await File('$root/.promptorium/.gitignore')
            .writeAsString('attachments/\n');
      }
      final f = File('${batch.path}/$name');
      await f.writeAsBytes(bytes);
      files.add(p.relative(f.path, from: root).replaceAll('\\', '/'));
    }
    blocks.add(
      e.toPromptBlock(index: elements.length == 1 ? null : i, files: files),
    );
  }
  final b = StringBuffer(text);
  for (final block in blocks) {
    b
      ..writeln()
      ..writeln()
      ..write(block);
  }
  if (parts.isNotEmpty) {
    b
      ..writeln()
      ..writeln()
      ..write('(prints anexados: ${parts.map((x) => x.name).join(', ')})');
  }
  return (text: b.toString(), images: parts);
}
