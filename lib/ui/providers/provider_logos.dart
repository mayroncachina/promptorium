import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/svg_path.dart';
import 'provider_logo_paths.dart';

/// Brand colors of the official logos: fixed, outside the theme (SPEC-094
/// R14). Never recolor them.
abstract final class ProviderLogoColors {
  /// Claude symbol, always clay.
  static const claude = Color(0xFFD97757);

  /// OpenAI Blossom, white as supplied in the brand kit.
  static const openAi = Color(0xFFFFFFFF);
}

/// Single switch point (R14 item 5): if OpenAI does not allow the logo,
/// set this to false and [ProviderLogo] draws the book glyph for Codex in
/// the whole app, without touching any screen.
const codexUsesOfficialLogo = true;

/// Providers with a visual identity. ACP agents and others show only the
/// name (R15).
bool hasProviderIdentity(String provider) => switch (provider) {
  'claude' || 'codex' => true,
  _ => false,
};

/// Short brand name shown next to the logo ("Claude" / "Codex").
String providerBrandName(String provider) => switch (provider) {
  'claude' => 'Claude',
  'codex' => 'Codex',
  _ => provider,
};

/// "Codex · gpt-6.2-sol" / "Claude Code · Sonnet" (SPEC-096 R3): who
/// answered and with which model, wherever a run is listed. `inherit` is
/// the provider default.
String providerModelLabel(String provider, String? model) {
  final name = switch (provider) {
    'claude' => 'Claude Code',
    'codex' => 'Codex',
    _ => provider,
  };
  final m = model ?? '';
  if (m.isEmpty || m == 'inherit') return '$name · modelo padrão';
  // Claude aliases read as names ("Sonnet"); Codex ids stay as they are.
  final shown = provider == 'claude' ? m[0].toUpperCase() + m.substring(1) : m;
  return '$name · $shown';
}

/// Identity color of the provider (glyph mark, border, chip). Never state,
/// never the logo. Null when the provider has no token.
Color? providerIdentityColor(String provider) => switch (provider) {
  'claude' => AppColors.providerClaude,
  'codex' => AppColors.providerCodex,
  _ => null,
};

/// Official logo of the provider (R14a), unchanged in shape and color.
/// 16 px by default, 14 px at least.
class ProviderLogo extends StatelessWidget {
  const ProviderLogo(this.provider, {super.key, this.size = 16})
    : assert(size >= minSize, 'logo de provedor tem no mínimo 14 px');

  static const minSize = 14.0;

  final String provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (provider == 'codex' && !codexUsesOfficialLogo) {
      return ProviderGlyph(provider, size: size);
    }
    final logo = switch (provider) {
      'claude' => _claude,
      'codex' => _openAi,
      _ => null,
    };
    if (logo == null) return SizedBox.shrink(key: key);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _SvgLogoPainter(logo)),
    );
  }

  static final _claude = SvgLogo(
    claudeLogoPath,
    const Rect.fromLTWH(0, 0, 24, 24),
    ProviderLogoColors.claude,
  );

  // The Blossom fills about half of the official file; the frame trims
  // only the empty margin (Design → Origem dos SVGs).
  static final _openAi = SvgLogo(
    openAiBlossomPath,
    const Rect.fromLTWH(176, 176, 364, 364),
    ProviderLogoColors.openAi,
  );
}

/// One-path SVG logo: the parsed path, its frame and its fixed color.
class SvgLogo {
  SvgLogo(String data, this.frame, this.color) : path = parseSvgPath(data);

  final Path path;
  final Rect frame;
  final Color color;
}

class _SvgLogoPainter extends CustomPainter {
  _SvgLogoPainter(this.logo);

  final SvgLogo logo;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / logo.frame.width,
      size.height / logo.frame.height,
    );
    canvas
      ..save()
      ..scale(scale)
      ..translate(-logo.frame.left, -logo.frame.top)
      ..drawPath(
        logo.path,
        Paint()
          ..color = logo.color
          ..isAntiAlias = true,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_SvgLogoPainter old) => old.logo != logo;
}

/// Own glyph for small spots (R14b): a 14 px dot in the provider color
/// with an open arc (Claude) or an open book (Codex) in [AppColors.onAmber].
class ProviderGlyph extends StatelessWidget {
  const ProviderGlyph(this.provider, {super.key, this.size = 14});

  final String provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = providerIdentityColor(provider);
    if (color == null) return SizedBox.shrink(key: key);
    return Semantics(
      label: providerBrandName(provider),
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _GlyphPainter(provider, color)),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.provider, this.color);

  final String provider;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, s / 2, Paint()..color = color);
    final ink = Paint()
      ..color = AppColors.onAmber
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, s * 0.12)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (provider case 'claude') {
      // Open arc, opening to the right.
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: s * 0.26),
        math.pi * 0.25,
        math.pi * 1.5,
        false,
        ink,
      );
    } else {
      // Open book: two pages meeting at the spine.
      final w = s * 0.30;
      final h = s * 0.22;
      final top = c.dy - h;
      final bottom = c.dy + h;
      final book = Path()
        ..moveTo(c.dx, top + s * 0.05)
        ..quadraticBezierTo(c.dx - w * 0.5, top - s * 0.03, c.dx - w, top)
        ..lineTo(c.dx - w, bottom - s * 0.03)
        ..quadraticBezierTo(c.dx - w * 0.5, bottom - s * 0.06, c.dx, bottom)
        ..quadraticBezierTo(
          c.dx + w * 0.5,
          bottom - s * 0.06,
          c.dx + w,
          bottom - s * 0.03,
        )
        ..lineTo(c.dx + w, top)
        ..quadraticBezierTo(
          c.dx + w * 0.5,
          top - s * 0.03,
          c.dx,
          top + s * 0.05,
        )
        ..lineTo(c.dx, bottom);
      canvas.drawPath(book, ink);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.provider != provider || old.color != color;
}

/// Brand chip (R14a): official logo next to the name, on a neutral
/// background with the border in the provider color. Never the logo
/// without the name. Providers without identity show only the name.
class ProviderChip extends StatelessWidget {
  ProviderChip(this.provider, {super.key, String? name, this.dense = false})
    : name = name ?? providerBrandName(provider) {
    if (this.name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'o chip sempre mostra o nome');
    }
  }

  final String provider;
  final String name;

  /// Lists: 14 px logo and smaller text.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = providerIdentityColor(provider);
    final text = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: dense ? 11 : 12,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
    );
    if (color == null) return text;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 5 : 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF222732),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProviderLogo(provider, size: dense ? 14 : 16),
          SizedBox(width: dense ? 4 : 5),
          Flexible(child: text),
        ],
      ),
    );
  }
}
