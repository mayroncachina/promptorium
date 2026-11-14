import 'dart:convert';

import 'package:flutter/foundation.dart';

/// An element of the preview page captured by "Apontar" (SPEC-051 R7): it
/// goes to the session's composer as an attachment (R8).
@immutable
class PickedElement {
  const PickedElement({
    required this.selector,
    required this.html,
    required this.url,
    this.styles = const {},
    this.width = 0,
    this.height = 0,
    this.elementPng,
    this.pagePng,
  });

  final String selector;

  /// `outerHTML`, up to 4 KB.
  final String html;
  final String url;
  final Map<String, String> styles;
  final double width, height;

  /// The element with a margin, and the visible page with it marked.
  final Uint8List? elementPng, pagePng;

  int get imageCount =>
      (elementPng == null ? 0 : 1) + (pagePng == null ? 0 : 1);

  /// Reads the binding's payload (the picker's JSON) without the PNGs.
  static PickedElement? fromPayload(String payload) {
    Object? j;
    try {
      j = jsonDecode(payload);
    } catch (_) {
      return null;
    }
    if (j is! Map || j['cancel'] == true) return null;
    final box = j['box'] is Map ? j['box'] as Map : const {};
    double n(Object? v) => v is num ? v.toDouble() : 0;
    return PickedElement(
      selector: '${j['selector'] ?? ''}',
      html: '${j['html'] ?? ''}',
      url: '${j['url'] ?? ''}',
      styles: {
        if (j['styles'] is Map)
          for (final MapEntry(:key, :value) in (j['styles'] as Map).entries)
            '$key': '$value',
      },
      width: n(box['width']),
      height: n(box['height']),
    );
  }

  PickedElement withImages({Uint8List? element, Uint8List? page}) =>
      PickedElement(
        selector: selector,
        html: html,
        url: url,
        styles: styles,
        width: width,
        height: height,
        elementPng: element ?? elementPng,
        pagePng: page ?? pagePng,
      );

  /// `127.0.0.1:4003/login` (no scheme).
  String get shortUrl => url.replaceFirst(RegExp(r'^https?://'), '');

  /// One line of the main styles (the card in the composer).
  String get styleLine => [
    for (final k in const [
      'background-color',
      'color',
      'opacity',
      'cursor',
      'font-size',
    ])
      if (styles[k] case final v?)
        '${k == 'background-color' ? 'background' : k}: $v',
  ].join(' · ');

  /// The text block sent with the request (R8).
  String toPromptBlock({int? index, List<String> files = const []}) {
    final b = StringBuffer()
      ..writeln(
        'Elemento apontado${index == null ? '' : ' ${index + 1}'} no preview:',
      )
      ..writeln('- seletor: `$selector`')
      ..writeln('- URL: $url')
      ..writeln('- tamanho: ${width.round()} × ${height.round()}');
    if (files.isNotEmpty) {
      b.writeln('- prints: ${files.map((f) => '@$f').join(' ')}');
    }
    if (styles.isNotEmpty) {
      b.writeln('- estilos:');
      for (final MapEntry(:key, :value) in styles.entries) {
        b.writeln('  - $key: $value');
      }
    }
    b
      ..writeln('- HTML:')
      ..writeln('```html')
      ..writeln(html)
      ..write('```');
    return b.toString();
  }
}
