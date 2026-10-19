import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The visual vocabulary shared by every built-in Zhuying theme.
///
/// Business widgets only need a palette and a small set of decorative hints;
/// the pages themselves remain shared between themes.
class ZhuyingThemeDefinition {
  const ZhuyingThemeDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.line,
    required this.text,
    required this.muted,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.action,
    required this.onAction,
    required this.error,
    this.brightness = Brightness.dark,
    this.characterAsset,
    this.characterBustAsset,
    this.chibiAsset,
    this.atmosphereAsset,
    this.signatureAsset,
    this.ribbonAsset,
    this.logoAsset = 'assets/branding/xuanlan-logo.jpg',
    this.brandName = '玄览',
    this.displayFontFamily,
    this.signatureFontFamily,
    this.usesDecorations = false,
    this.cornerRadius = 7,
    this.glowStrength = 0.0,
  });

  final String id;
  final String name;
  final String description;
  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color line;
  final Color text;
  final Color muted;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color action;
  final Color onAction;
  final Color error;
  final Brightness brightness;
  final String? characterAsset;
  final String? characterBustAsset;
  final String? chibiAsset;
  final String? atmosphereAsset;
  final String? signatureAsset;
  final String? ribbonAsset;
  final String logoAsset;
  final String brandName;
  final String? displayFontFamily;
  final String? signatureFontFamily;
  final bool usesDecorations;
  final double cornerRadius;
  final double glowStrength;

  bool get isMitsuri => id == 'mitsuri';
  bool get isLight => brightness == Brightness.light;

  ThemeData toThemeData() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
          surface: surface,
        ).copyWith(
          primary: primary,
          onPrimary: _onColor(primary),
          secondary: secondary,
          onSecondary: _onColor(secondary),
          tertiary: accent,
          onTertiary: _onColor(accent),
          surface: surface,
          onSurface: text,
          error: error,
          onError: _onColor(error),
          outline: line,
        );
    final baseText = ThemeData(brightness: brightness).textTheme
        .apply(bodyColor: text, displayColor: text);
    final radius = BorderRadius.circular(cornerRadius);
    final outline = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: line),
    );
    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      textTheme: baseText,
      dividerColor: line,
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface.withValues(alpha: isMitsuri ? 0.82 : 1),
        hintStyle: TextStyle(color: muted),
        border: outline,
        enabledBorder: outline,
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: primary, width: 1.35),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceRaised,
        contentTextStyle: TextStyle(color: text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface.withValues(alpha: isMitsuri ? 0.94 : 1),
        indicatorColor: primary.withValues(alpha: isMitsuri ? 0.2 : 0.14),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? primary : muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: primary.withValues(alpha: 0.18),
        side: BorderSide(color: line),
        labelStyle: TextStyle(color: text, fontSize: 12),
        secondaryLabelStyle: TextStyle(color: primary, fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: line),
        ),
      ),
    );
  }

  static Color _onColor(Color color) =>
      color.computeLuminance() > 0.5 ? const Color(0xFF241B21) : Colors.white;
}

abstract final class ZhuyingThemes {
  static const defaultTheme = ZhuyingThemeDefinition(
    id: 'default',
    name: '影院暗色',
    description: '温暖的影院暗色主题',
    canvas: Color(0xFF111210),
    surface: Color(0xFF1A1B18),
    surfaceRaised: Color(0xFF242521),
    line: Color(0xFF30312C),
    text: Color(0xFFF3F0E8),
    muted: Color(0xFFA6A69D),
    primary: Color(0xFFE9B66E),
    secondary: Color(0xFF9BB7A0),
    accent: Color(0xFFE9B66E),
    action: Color(0xFFE9B66E),
    onAction: Color(0xFF211A10),
    error: Color(0xFFD88570),
  );

  static const mitsuri = ZhuyingThemeDefinition(
    id: 'mitsuri',
    name: '甘露寺蜜璃',
    description: '樱花、蜜桃粉与青柠绿的浪漫主题',
    canvas: Color(0xFF160F18),
    surface: Color(0xFF241522),
    surfaceRaised: Color(0xFF342034),
    line: Color(0xFF633A59),
    text: Color(0xFFFFF2F6),
    muted: Color(0xFFD4B9C8),
    primary: Color(0xFFFF86B4),
    secondary: Color(0xFFC9E978),
    accent: Color(0xFFFFC2D8),
    action: Color(0xFFFF86B4),
    onAction: Colors.white,
    error: Color(0xFFFF9B9B),
    characterAsset: 'assets/themes/mitsuri/character.png',
    characterBustAsset: 'assets/themes/mitsuri/character-hero-cropped.png',
    chibiAsset: 'assets/themes/mitsuri/chibi-transparent.png',
    atmosphereAsset: 'assets/themes/mitsuri/atmosphere-v2.jpg',
    signatureAsset: 'assets/themes/mitsuri/signature.png',
    ribbonAsset: 'assets/themes/mitsuri/ribbon-edge.png',
    logoAsset: 'assets/branding/mitsuri-logo-transparent.png',
    brandName: '我爱看电视',
    displayFontFamily: 'MitsuriDisplay',
    signatureFontFamily: 'MitsuriSignature',
    usesDecorations: true,
    cornerRadius: 9,
    glowStrength: 0.18,
  );

  static const cinemaLight = ZhuyingThemeDefinition(
    id: 'cinema-light',
    name: '影院亮色',
    description: '清透柔和的日间影院主题',
    canvas: Color(0xFFF4F3EF),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF9F8F5),
    line: Color(0xFFE2E0D9),
    text: Color(0xFF272720),
    muted: Color(0xFF77766F),
    primary: Color(0xFFA65300),
    secondary: Color(0xFF587660),
    accent: Color(0xFFB45100),
    action: Color(0xFFF6BC42),
    onAction: Color(0xFF30230D),
    error: Color(0xFFB54E42),
    brightness: Brightness.light,
    cornerRadius: 7,
  );

  static const all = <ZhuyingThemeDefinition>[
    defaultTheme,
    mitsuri,
    cinemaLight,
  ];

  static ZhuyingThemeDefinition byId(String id) =>
      all.firstWhere((theme) => theme.id == id, orElse: () => defaultTheme);
}

/// Backwards-compatible names used by older widgets. New code should prefer
/// [Theme.of] or [ZhuyingTheme.of].
abstract final class ZhuyingColors {
  static ZhuyingThemeDefinition _current = ZhuyingThemes.defaultTheme;

  static void setActive(ZhuyingThemeDefinition definition) {
    _current = definition;
  }

  static Color get canvas => _current.canvas;
  static Color get surface => _current.surface;
  static Color get surfaceRaised => _current.surfaceRaised;
  static Color get line => _current.line;
  static Color get text => _current.text;
  static Color get muted => _current.muted;
  static Color get amber => _current.primary;
  static Color get primary => _current.primary;
  static Color get accent => _current.accent;
  static Color get green => _current.secondary;
  static Color get coral => _current.error;
}

extension ZhuyingThemeContext on BuildContext {
  ZhuyingThemeDefinition get zhuyingTheme =>
      Theme.of(this).extension<ZhuyingThemeExtension>()?.definition ??
      ZhuyingThemes.defaultTheme;
}

class ZhuyingThemeExtension extends ThemeExtension<ZhuyingThemeExtension> {
  const ZhuyingThemeExtension(this.definition);

  final ZhuyingThemeDefinition definition;

  @override
  ZhuyingThemeExtension copyWith({ZhuyingThemeDefinition? definition}) =>
      ZhuyingThemeExtension(definition ?? this.definition);

  @override
  ZhuyingThemeExtension lerp(
    covariant ThemeExtension<ZhuyingThemeExtension>? other,
    double t,
  ) {
    if (other is! ZhuyingThemeExtension) return this;
    return ZhuyingThemeExtension(
      _lerpDefinition(definition, other.definition, t),
    );
  }

  static ZhuyingThemeDefinition _lerpDefinition(
    ZhuyingThemeDefinition a,
    ZhuyingThemeDefinition b,
    double t,
  ) {
    Color lerp(Color first, Color second) =>
        Color.lerp(first, second, t) ?? second;
    return ZhuyingThemeDefinition(
      id: t < 0.5 ? a.id : b.id,
      name: t < 0.5 ? a.name : b.name,
      description: t < 0.5 ? a.description : b.description,
      canvas: lerp(a.canvas, b.canvas),
      surface: lerp(a.surface, b.surface),
      surfaceRaised: lerp(a.surfaceRaised, b.surfaceRaised),
      line: lerp(a.line, b.line),
      text: lerp(a.text, b.text),
      muted: lerp(a.muted, b.muted),
      primary: lerp(a.primary, b.primary),
      secondary: lerp(a.secondary, b.secondary),
      accent: lerp(a.accent, b.accent),
      action: lerp(a.action, b.action),
      onAction: lerp(a.onAction, b.onAction),
      error: lerp(a.error, b.error),
      brightness: t < 0.5 ? a.brightness : b.brightness,
      characterAsset: t < 0.5 ? a.characterAsset : b.characterAsset,
      characterBustAsset: t < 0.5 ? a.characterBustAsset : b.characterBustAsset,
      chibiAsset: t < 0.5 ? a.chibiAsset : b.chibiAsset,
      atmosphereAsset: t < 0.5 ? a.atmosphereAsset : b.atmosphereAsset,
      signatureAsset: t < 0.5 ? a.signatureAsset : b.signatureAsset,
      ribbonAsset: t < 0.5 ? a.ribbonAsset : b.ribbonAsset,
      logoAsset: t < 0.5 ? a.logoAsset : b.logoAsset,
      brandName: t < 0.5 ? a.brandName : b.brandName,
      displayFontFamily: t < 0.5 ? a.displayFontFamily : b.displayFontFamily,
      signatureFontFamily: t < 0.5
          ? a.signatureFontFamily
          : b.signatureFontFamily,
      usesDecorations: t >= 0.5 ? b.usesDecorations : a.usesDecorations,
      cornerRadius: a.cornerRadius + (b.cornerRadius - a.cornerRadius) * t,
      glowStrength: a.glowStrength + (b.glowStrength - a.glowStrength) * t,
    );
  }
}

/// Shared atmospheric layer for themes that provide artwork. It stays behind
/// page content and ignores pointers, so navigation and scrolling keep their
/// original hit targets.
class ZhuyingThemeBackdrop extends StatefulWidget {
  const ZhuyingThemeBackdrop({
    required this.child,
    this.reduceMotion = false,
    this.showCharacter = true,
    super.key,
  });

  final Widget child;
  final bool reduceMotion;
  final bool showCharacter;

  @override
  State<ZhuyingThemeBackdrop> createState() => _ZhuyingThemeBackdropState();
}

class _ZhuyingThemeBackdropState extends State<ZhuyingThemeBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final definition = context.zhuyingTheme;
    final reduceMotion =
        widget.reduceMotion || MediaQuery.disableAnimationsOf(context);
    if (!definition.usesDecorations || definition.characterAsset == null) {
      if (_controller.isAnimating) _controller.stop();
      return widget.child;
    }
    if (reduceMotion) {
      if (_controller.isAnimating) _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (definition.atmosphereAsset != null)
                  Opacity(
                    opacity: 0.24,
                    child: Image.asset(
                      definition.atmosphereAsset!,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _MitsuriAtmospherePainter(
                      progress: reduceMotion ? 0.35 : _controller.value,
                      primary: definition.primary,
                      accent: definition.accent,
                      secondary: definition.secondary,
                      glowStrength: definition.glowStrength,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.showCharacter)
          IgnorePointer(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth < 600
                    ? 188.0
                    : (constraints.maxWidth * 0.34).clamp(220.0, 420.0);
                return Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: 8,
                      bottom: constraints.maxWidth < 600 ? 18 : 26,
                    ),
                    child: Opacity(
                      opacity: constraints.maxWidth < 600 ? 0.1 : 0.13,
                      child: Image.asset(
                        definition.characterAsset!,
                        width: width,
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomRight,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        widget.child,
      ],
    );
  }
}

class _MitsuriAtmospherePainter extends CustomPainter {
  const _MitsuriAtmospherePainter({
    required this.progress,
    required this.primary,
    required this.accent,
    required this.secondary,
    required this.glowStrength,
  });

  final double progress;
  final Color primary;
  final Color accent;
  final Color secondary;
  final double glowStrength;

  @override
  void paint(Canvas canvas, Size size) {
    final glowAlpha = glowStrength.clamp(0.0, 0.3).toDouble();
    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              primary.withValues(alpha: glowAlpha),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.84, size.height * 0.14),
              radius: size.shortestSide * 0.72,
            ),
          );
    canvas.drawRect(Offset.zero & size, glow);

    final phase = progress * 2 * 3.141592653589793;
    final petals = [
      (0.12, 0.16, 0.0, 0.9),
      (0.25, 0.42, 1.3, 0.65),
      (0.72, 0.18, 2.4, 0.74),
      (0.86, 0.55, 4.1, 0.8),
      (0.46, 0.76, 5.2, 0.52),
      (0.16, 0.87, 3.4, 0.58),
      (0.92, 0.84, 1.9, 0.7),
    ];
    for (var index = 0; index < petals.length; index++) {
      final (x, y, seed, opacity) = petals[index];
      final drift = math.sin(phase * (0.3 + index * 0.035) + seed) * 9;
      final fall = math.cos(phase * (0.18 + index * 0.02) + seed) * 7;
      final center = Offset(size.width * x + drift, size.height * y + fall);
      final color = index.isEven ? primary : accent;
      final paint = Paint()..color = color.withValues(alpha: opacity * 0.42);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(seed + phase * 0.12);
      final path = Path()
        ..moveTo(0, -7)
        ..cubicTo(8, -4, 8, 5, 0, 8)
        ..cubicTo(-8, 5, -8, -4, 0, -7)
        ..close();
      canvas.drawPath(path, paint);
      canvas.restore();
    }

    final hearts = [
      (0.78, 0.26, 0.72, 0.8),
      (0.31, 0.63, 0.52, 0.58),
      (0.9, 0.38, 0.42, 0.46),
    ];
    for (final (x, y, scale, opacity) in hearts) {
      final heartPaint = Paint()
        ..color = primary.withValues(alpha: opacity * 0.32);
      final center = Offset(size.width * x, size.height * y);
      final path = Path()
        ..moveTo(center.dx, center.dy + 7 * scale)
        ..cubicTo(
          center.dx - 13 * scale,
          center.dy - 1 * scale,
          center.dx - 8 * scale,
          center.dy - 9 * scale,
          center.dx,
          center.dy - 3 * scale,
        )
        ..cubicTo(
          center.dx + 8 * scale,
          center.dy - 9 * scale,
          center.dx + 13 * scale,
          center.dy - 1 * scale,
          center.dx,
          center.dy + 7 * scale,
        )
        ..close();
      canvas.drawPath(path, heartPaint);
    }

    final linePaint = Paint()
      ..color = secondary.withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final curve = Path()
      ..moveTo(size.width * 0.04, size.height * 0.3)
      ..cubicTo(
        size.width * 0.2,
        size.height * 0.23,
        size.width * 0.23,
        size.height * 0.37,
        size.width * 0.38,
        size.height * 0.31,
      );
    canvas.drawPath(curve, linePaint);
  }

  @override
  bool shouldRepaint(covariant _MitsuriAtmospherePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.primary != primary ||
      oldDelegate.accent != accent ||
      oldDelegate.secondary != secondary ||
      oldDelegate.glowStrength != glowStrength;
}
