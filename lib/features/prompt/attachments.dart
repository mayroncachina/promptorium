import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/claude/claude_process.dart' show ImagePart;

/// Files attached to a message of the Prompt screen (picked or dropped).
///
/// - A file **inside the workspace** is just mentioned (`@relative/path`).
/// - An **image** (png, jpg, gif, webp up to [maxImageBytes]) goes in the
///   message as an `image` block, as in the Claude chat.
/// - Any other file is **copied** to `.promptorium/attachments/<date>/` in
///   the workspace (git-ignored) and mentioned, so the agent reads it with
///   the same `@` mechanism as the repository files.

const maxImageBytes = 5 * 1024 * 1024;
const maxAttachments = 10;

const _imageTypes = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
};

/// `image/png` for `foto.PNG`; null when it is not a supported image.
String? imageMediaType(String path) =>
    _imageTypes[p.extension(path).toLowerCase()];

class AttachmentException implements Exception {
  const AttachmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What goes with the message.
class PreparedAttachments {
  const PreparedAttachments({
    this.mentions = const [],
    this.images = const [],
    this.names = const [],
  });

  /// Workspace-relative paths for `@` mentions.
  final List<String> mentions;
  final List<ImagePart> images;

  /// Display names of everything attached.
  final List<String> names;

  /// [text] followed by the mentions and a note about the images.
  String applyTo(String text) {
    final b = StringBuffer(text.trimRight());
    if (mentions.isNotEmpty) {
      b
        ..writeln()
        ..writeln()
        ..write(mentions.map((m) => '@$m').join(' '));
    }
    if (images.isNotEmpty) {
      b
        ..writeln()
        ..writeln()
        ..write(
          images.length == 1
              ? '(imagem anexada: ${images.single.name})'
              : '(imagens anexadas: ${images.map((i) => i.name).join(', ')})',
        );
    }
    return b.toString();
  }
}

/// Reads / copies [paths] for a message in [workspacePath]. Throws
/// [AttachmentException] for a missing file or too many attachments.
Future<PreparedAttachments> prepareAttachments(
  String workspacePath,
  List<String> paths, {
  DateTime? now,
}) async {
  if (paths.isEmpty) return const PreparedAttachments();
  if (paths.length > maxAttachments) {
    throw const AttachmentException(
      'No máximo $maxAttachments anexos por mensagem.',
    );
  }
  final root = p.normalize(workspacePath);
  final mentions = <String>[];
  final images = <ImagePart>[];
  final names = <String>[];
  Directory? batch;
  for (final path in paths) {
    final f = File(path);
    if (!await f.exists()) {
      throw AttachmentException('O arquivo "${p.basename(path)}" não existe.');
    }
    final name = p.basename(path);
    names.add(name);
    final type = imageMediaType(path);
    if (type != null && await f.length() <= maxImageBytes) {
      images.add(
        ImagePart(
          mediaType: type,
          base64: base64Encode(await f.readAsBytes()),
          name: name,
        ),
      );
      continue;
    }
    if (p.isWithin(root, p.normalize(path))) {
      mentions.add(p.relative(path, from: root).replaceAll('\\', '/'));
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
    var target = File('${batch.path}/$name');
    var n = 1;
    while (await target.exists()) {
      target = File(
        '${batch.path}/${p.basenameWithoutExtension(name)}-${n++}${p.extension(name)}',
      );
    }
    await f.copy(target.path);
    mentions.add(p.relative(target.path, from: root).replaceAll('\\', '/'));
  }
  return PreparedAttachments(mentions: mentions, images: images, names: names);
}
