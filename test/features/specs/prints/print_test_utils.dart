import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:promptorium/features/specs/spec_prints.dart';

/// A PNG of [width]×[height] drawn with `dart:ui`.
Future<Uint8List> pngBytes(int width, int height) async {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366CC),
  );
  final image = await rec.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// A print of the draft whose file is [path].
SpecPrint fakePrint(
  String path, {
  String name = 'print-1.png',
  PrintKind? kind = PrintKind.bug,
  String description = '',
  List<String> brands = const [],
}) => SpecPrint(
  path: path,
  name: name,
  width: 1366,
  height: 768,
  kind: kind,
  description: description,
  brands: brands,
);
