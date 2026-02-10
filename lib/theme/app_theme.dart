import 'package:flutter/material.dart';

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

class AppTheme {
  AppTheme._();

  // Custom color palette
  static const _surface = Color(0xFF0D0F11);
  static const _surfaceContainerLow = Color(0xFF141719);
  static const _surfaceContainer = Color(0xFF1A1D21);
  static const _surfaceContainerHigh = Color(0xFF1F2328);
  static const _surfaceContainerHighest = Color(0xFF262A30);
  static const _primary = Color(0xFF7EB0CC);
  static const _primaryContainer = Color(0xFF2A4A5C);
  static const _onSurface = Color(0xFFD8DEE4);
  static const _onSurfaceMuted = Color(0xFF8B929A);
  static const _outline = Color(0xFF3A3F47);
  static const _outlineVariant = Color(0xFF2A2E34);

  static final dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _surface,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6E8CA0),
      brightness: Brightness.dark,
      surface: _surface,
      surfaceContainerLow: _surfaceContainerLow,
      surfaceContainer: _surfaceContainer,
      surfaceContainerHigh: _surfaceContainerHigh,
      surfaceContainerHighest: _surfaceContainerHighest,
      primary: _primary,
      primaryContainer: _primaryContainer,
      onSurface: _onSurface,
      outline: _outline,
      outlineVariant: _outlineVariant,
    ),

    // AppBar — flat, dark
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: _surfaceContainerLow,
      foregroundColor: _onSurface,
      centerTitle: false,
    ),

    // Card — flat with subtle border
    cardTheme: CardThemeData(
      elevation: 0,
      color: _surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _outlineVariant, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),

    // Input — filled, no border, rounded
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: _onSurfaceMuted),
      labelStyle: const TextStyle(color: _onSurfaceMuted),
      prefixIconColor: _onSurfaceMuted,
    ),

    // Elevated button — primary fill, flat
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _primary,
        foregroundColor: _surface,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),

    // FAB — rounded square
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 0,
      hoverElevation: 0,
      focusElevation: 0,
      highlightElevation: 0,
      backgroundColor: _primary,
      foregroundColor: _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),

    // Icon button — muted
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: _onSurfaceMuted,
      ),
    ),

    // ListTile — rounded, muted secondary text
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      iconColor: _onSurfaceMuted,
      subtitleTextStyle: const TextStyle(color: _onSurfaceMuted, fontSize: 13),
    ),

    // Switch — primary thumb
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return _primary;
        return _onSurfaceMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return _primary.withValues(alpha: 0.35);
        }
        return _outlineVariant;
      }),
    ),

    // Snackbar — floating, rounded, dark
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: _surfaceContainerHighest,
      contentTextStyle: const TextStyle(color: _onSurface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),

    // Divider
    dividerTheme: const DividerThemeData(
      color: _outlineVariant,
      thickness: 1,
    ),

    // Progress indicator
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: _primary,
      linearTrackColor: _primary.withValues(alpha: 0.15),
    ),

    // Popup menu
    popupMenuTheme: PopupMenuThemeData(
      color: _surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),

    // Text theme — improved readability
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        fontWeight: FontWeight.bold,
        letterSpacing: -0.5,
        color: _onSurface,
      ),
      bodyLarge: TextStyle(
        height: 1.5,
        color: _onSurface,
      ),
      bodyMedium: TextStyle(
        height: 1.45,
        color: _onSurface,
      ),
      bodySmall: TextStyle(
        color: _onSurfaceMuted,
        fontSize: 13,
      ),
    ),

    extensions: const [
      MessageColors(
        userBubble: _primaryContainer,
        userText: Color(0xFFE8EDF0),
        assistantBubble: _surfaceContainer,
        assistantText: Color(0xFFD0D4DA),
        errorBubble: Color(0xFF3D2020),
        errorText: Color(0xFFE8A0A0),
        errorRetry: Color(0xFFE57373),
      ),
    ],
  );
}
