import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

@immutable
class MessageColors extends ThemeExtension<MessageColors> {
  final Color userBubble;
  final Color userText;
  final Color assistantBubble;
  final Color assistantText;
  final Color errorBubble;
  final Color errorText;
  final Color errorRetry;

  const MessageColors({
    required this.userBubble,
    required this.userText,
    required this.assistantBubble,
    required this.assistantText,
    required this.errorBubble,
    required this.errorText,
    required this.errorRetry,
  });

  @override
  MessageColors copyWith({
    Color? userBubble,
    Color? userText,
    Color? assistantBubble,
    Color? assistantText,
    Color? errorBubble,
    Color? errorText,
    Color? errorRetry,
  }) {
    return MessageColors(
      userBubble: userBubble ?? this.userBubble,
      userText: userText ?? this.userText,
      assistantBubble: assistantBubble ?? this.assistantBubble,
      assistantText: assistantText ?? this.assistantText,
      errorBubble: errorBubble ?? this.errorBubble,
      errorText: errorText ?? this.errorText,
      errorRetry: errorRetry ?? this.errorRetry,
    );
  }

  @override
  MessageColors lerp(ThemeExtension<MessageColors>? other, double t) {
    if (other is! MessageColors) return this;
    return MessageColors(
      userBubble: Color.lerp(userBubble, other.userBubble, t)!,
      userText: Color.lerp(userText, other.userText, t)!,
      assistantBubble: Color.lerp(assistantBubble, other.assistantBubble, t)!,
      assistantText: Color.lerp(assistantText, other.assistantText, t)!,
      errorBubble: Color.lerp(errorBubble, other.errorBubble, t)!,
      errorText: Color.lerp(errorText, other.errorText, t)!,
      errorRetry: Color.lerp(errorRetry, other.errorRetry, t)!,
    );
  }
}

/// Graphite design tokens (redesign/app.css, [data-style="graphite"]).
@immutable
class DiscoTokens extends ThemeExtension<DiscoTokens> {
  final Color line;
  final Color lineStrong;
  final Color textMuted;
  final Color textFaint;
  final Color accentSoft;
  final Color accentInk;
  final Color good;
  final Color warn;
  final double radius;

  const DiscoTokens({
    required this.line,
    required this.lineStrong,
    required this.textMuted,
    required this.textFaint,
    required this.accentSoft,
    required this.accentInk,
    required this.good,
    required this.warn,
    required this.radius,
  });

  @override
  DiscoTokens copyWith({
    Color? line,
    Color? lineStrong,
    Color? textMuted,
    Color? textFaint,
    Color? accentSoft,
    Color? accentInk,
    Color? good,
    Color? warn,
    double? radius,
  }) {
    return DiscoTokens(
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      accentSoft: accentSoft ?? this.accentSoft,
      accentInk: accentInk ?? this.accentInk,
      good: good ?? this.good,
      warn: warn ?? this.warn,
      radius: radius ?? this.radius,
    );
  }

  @override
  DiscoTokens lerp(ThemeExtension<DiscoTokens>? other, double t) {
    if (other is! DiscoTokens) return this;
    return DiscoTokens(
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      good: Color.lerp(good, other.good, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      radius: radius + (other.radius - radius) * t,
    );
  }
}

class AppTheme {
  AppTheme._();

  // Graphite: minimal neutral dark (redesign/app.css, [data-style="graphite"])
  static const _bg = Color(0xFF0E0F11);
  static const _bgElev = Color(0xFF16181B);
  static const _bgElev2 = Color(0xFF1D2024);
  static const _line = Color(0xFF24272C);
  static const _lineStrong = Color(0xFF343941);
  static const _text = Color(0xFFE7EAEE);
  static const _textMuted = Color(0xFF9AA1AA);
  static const _textFaint = Color(0xFF646A72);
  static const _accent = Color(0xFF8FB5DC);
  static const _accentInk = Color(0xFF0A111A);
  static const _accentSoft = Color(0xFF1A2530);
  static const _good = Color(0xFF7FC79A);
  static const _warn = Color(0xFFD9B36A);
  static const _error = Color(0xFFE58383);

  // Syntax accents for code blocks
  static const synKey = Color(0xFFA9C4E6);
  static const synStr = Color(0xFF94C9A6);
  static const synCom = _textFaint;
  static const synNum = Color(0xFFD9B36A);

  static const radius = 14.0;

  /// Weights bundled under assets/google_fonts/. With runtime fetching off,
  /// any other weight would silently fall back to the system font — add its
  /// file there (named `<Family>-<Weight>.ttf`) before using it.
  static final _bundledDisplayWeights = {
    FontWeight.w400,
    FontWeight.w500,
    FontWeight.w600,
    FontWeight.w700,
    FontWeight.w800,
  };
  static final _bundledMonoWeights = {FontWeight.w400};

  static bool _fontsConfigured = false;

  /// Serves both families from the app bundle only — never from Google's
  /// servers — and registers their OFL licences. Call once before runApp.
  static void useBundledFonts() {
    GoogleFonts.config.allowRuntimeFetching = false;
    if (_fontsConfigured) return;
    _fontsConfigured = true;
    LicenseRegistry.addLicense(() async* {
      for (final (family, file) in [
        ('Hanken Grotesk', 'HankenGrotesk'),
        ('JetBrains Mono', 'JetBrainsMono'),
      ]) {
        final text =
            await rootBundle.loadString('assets/google_fonts/$file-OFL.txt');
        yield LicenseEntryWithLineBreaks([family], text);
      }
    });
  }

  /// Hanken Grotesk — display face for titles and headings.
  static TextStyle display({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    assert(_bundledDisplayWeights.contains(fontWeight ?? FontWeight.w400),
        'Hanken Grotesk $fontWeight is not bundled in assets/google_fonts/');
    return GoogleFonts.hankenGrotesk(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// JetBrains Mono — metadata, model names, code.
  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
  }) {
    assert(
        _bundledMonoWeights.contains(fontWeight ?? FontWeight.w400) &&
            fontStyle != FontStyle.italic,
        'JetBrains Mono $fontWeight $fontStyle is not bundled in '
        'assets/google_fonts/');
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontStyle: fontStyle,
    );
  }

  /// Hanken Grotesk applied to every slot of [base]. google_fonts 9 builds
  /// its `hankenGroteskTextTheme()` on `package:material_ui`, whose
  /// `TextTheme` is a different type from the one `ThemeData` takes, so this
  /// does what that helper does internally, slot by slot.
  static TextTheme _hankenGroteskTextTheme(TextTheme base) => TextTheme(
        displayLarge: GoogleFonts.hankenGrotesk(textStyle: base.displayLarge),
        displayMedium: GoogleFonts.hankenGrotesk(textStyle: base.displayMedium),
        displaySmall: GoogleFonts.hankenGrotesk(textStyle: base.displaySmall),
        headlineLarge: GoogleFonts.hankenGrotesk(textStyle: base.headlineLarge),
        headlineMedium:
            GoogleFonts.hankenGrotesk(textStyle: base.headlineMedium),
        headlineSmall: GoogleFonts.hankenGrotesk(textStyle: base.headlineSmall),
        titleLarge: GoogleFonts.hankenGrotesk(textStyle: base.titleLarge),
        titleMedium: GoogleFonts.hankenGrotesk(textStyle: base.titleMedium),
        titleSmall: GoogleFonts.hankenGrotesk(textStyle: base.titleSmall),
        bodyLarge: GoogleFonts.hankenGrotesk(textStyle: base.bodyLarge),
        bodyMedium: GoogleFonts.hankenGrotesk(textStyle: base.bodyMedium),
        bodySmall: GoogleFonts.hankenGrotesk(textStyle: base.bodySmall),
        labelLarge: GoogleFonts.hankenGrotesk(textStyle: base.labelLarge),
        labelMedium: GoogleFonts.hankenGrotesk(textStyle: base.labelMedium),
        labelSmall: GoogleFonts.hankenGrotesk(textStyle: base.labelSmall),
      );

  static ThemeData get dark {
    final baseText = _hankenGroteskTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    ).apply(bodyColor: _text, displayColor: _text);

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accent,
        brightness: Brightness.dark,
        surface: _bg,
        surfaceContainerLowest: _bg,
        surfaceContainerLow: _bgElev,
        surfaceContainer: _bgElev,
        surfaceContainerHigh: _bgElev2,
        surfaceContainerHighest: _accentSoft,
        primary: _accent,
        onPrimary: _accentInk,
        primaryContainer: _accentSoft,
        onPrimaryContainer: _text,
        secondaryContainer: _accentSoft,
        onSecondaryContainer: _accent,
        onSurface: _text,
        onSurfaceVariant: _textMuted,
        outline: _lineStrong,
        outlineVariant: _line,
        error: _error,
      ),

      textTheme: baseText.copyWith(
        headlineSmall: display(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: _text,
        ),
        titleLarge: display(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: _text,
        ),
        titleMedium: display(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: _text,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(height: 1.55),
        bodyMedium: baseText.bodyMedium?.copyWith(height: 1.5),
        bodySmall: baseText.bodySmall?.copyWith(
          color: _textMuted,
          fontSize: 13,
        ),
      ),

      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _bg,
        foregroundColor: _text,
        centerTitle: false,
        shape: const Border(bottom: BorderSide(color: _line)),
        titleTextStyle: display(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: _text,
        ),
        iconTheme: const IconThemeData(color: _textMuted, size: 22),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: _bgElev,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: _line, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _bgElev,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _accent),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: _textFaint),
        labelStyle: const TextStyle(color: _textMuted),
        prefixIconColor: _textFaint,
        suffixIconColor: _textFaint,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: _accentInk,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          // Component text styles replace the inherited one outright, so
          // each must carry the family or it falls back to the system font.
          textStyle: display(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: _accentInk,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: display(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _accent),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 0,
        hoverElevation: 0,
        focusElevation: 0,
        highlightElevation: 0,
        backgroundColor: _accent,
        foregroundColor: _accentInk,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: _textMuted),
      ),

      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        iconColor: _textMuted,
        subtitleTextStyle: display(color: _textMuted, fontSize: 13),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _accent;
          return _textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _accent.withValues(alpha: 0.35);
          }
          return _line;
        }),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        side: const BorderSide(color: _line),
        shape: const StadiumBorder(),
        labelStyle: display(color: _textMuted, fontSize: 12.5),
        iconTheme: const IconThemeData(color: _textMuted, size: 15),
        selectedColor: _accentSoft,
        checkmarkColor: _accent,
      ),

      tabBarTheme: const TabBarThemeData(
        labelColor: _accent,
        unselectedLabelColor: _textMuted,
        indicatorColor: _accent,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: _line,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _bgElev2,
        contentTextStyle: mono(fontSize: 12.5, color: _text),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _line),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: _line,
        thickness: 1,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: _accent,
        linearTrackColor: _accent.withValues(alpha: 0.15),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: _bgElev2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _line),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: _bgElev,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: _line),
        ),
        titleTextStyle: display(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: _text,
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _bgElev,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      drawerTheme: const DrawerThemeData(
        backgroundColor: _bgElev,
        surfaceTintColor: Colors.transparent,
        shape: Border(right: BorderSide(color: _line)),
      ),

      extensions: const [
        MessageColors(
          userBubble: _accentSoft,
          userText: Color(0xFFE7EDF4),
          assistantBubble: _bgElev,
          assistantText: _text,
          errorBubble: Color(0xFF33201F),
          errorText: Color(0xFFE8A0A0),
          errorRetry: _error,
        ),
        DiscoTokens(
          line: _line,
          lineStrong: _lineStrong,
          textMuted: _textMuted,
          textFaint: _textFaint,
          accentSoft: _accentSoft,
          accentInk: _accentInk,
          good: _good,
          warn: _warn,
          radius: radius,
        ),
      ],
    );
  }
}
