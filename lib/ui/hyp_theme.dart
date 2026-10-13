import 'package:flutter/material.dart';

/// A single, reusable visual language for Windows and Android.
/// No screenshots, third-party illustrations or fabricated cover art.
abstract final class HypColors {
  static const background = Color(0xFF0B1024);
  static const surface = Color(0xFF151A36);
  static const raised = Color(0xFF1D2345);
  static const field = Color(0xFF14192F);
  static const border = Color(0xFF3F4278);
  static const primary = Color(0xFF8A70FF);
  static const lightPurple = Color(0xFFC38DFF);
  static const text = Color(0xFFF8F6FF);
  static const muted = Color(0xFFB5B7D9);
  static const dim = Color(0xFF858AAC);
  static const success = Color(0xFF8EDBC6);
}

abstract final class HypTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: HypColors.primary,
      onPrimary: Colors.white,
      secondary: HypColors.lightPurple,
      onSecondary: HypColors.background,
      surface: HypColors.surface,
      onSurface: HypColors.text,
      error: Color(0xFFFF8FA3),
    );
    final rounded = OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: HypColors.border),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: HypColors.background,
      canvasColor: HypColors.background,
      fontFamily: null,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 29, fontWeight: FontWeight.w800, color: HypColors.text),
        headlineMedium: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: HypColors.text),
        titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: HypColors.text),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: HypColors.text),
        bodyMedium: TextStyle(fontSize: 13, height: 1.4, color: HypColors.text),
        bodySmall: TextStyle(fontSize: 12, height: 1.35, color: HypColors.muted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: HypColors.field,
        hintStyle: const TextStyle(color: HypColors.dim, fontSize: 13),
        labelStyle: const TextStyle(color: HypColors.muted, fontSize: 13),
        helperStyle: const TextStyle(color: HypColors.muted, fontSize: 11),
        border: rounded,
        enabledBorder: rounded,
        focusedBorder: rounded.copyWith(
          borderSide: const BorderSide(color: HypColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
      dividerColor: HypColors.border.withValues(alpha: 0.55),
      iconTheme: const IconThemeData(color: HypColors.muted),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: HypColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: HypColors.text,
          side: const BorderSide(color: HypColors.border),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: HypColors.raised,
        contentTextStyle: const TextStyle(color: HypColors.text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Background panel shared by hero, search, work cards and settings.
class HypPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final BorderRadiusGeometry? radius;
  final Color? borderColor;
  final bool glow;

  const HypPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.radius,
    this.borderColor,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? HypColors.surface,
        borderRadius: radius ?? BorderRadius.circular(17),
        border: Border.all(color: borderColor ?? HypColors.border.withValues(alpha: 0.65)),
        boxShadow: glow
            ? [
                BoxShadow(
                  blurRadius: 25,
                  spreadRadius: 0,
                  color: HypColors.primary.withValues(alpha: 0.13),
                ),
              ]
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class HypSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const HypSectionTitle({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: HypColors.lightPurple, size: 25),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 3),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton.icon(
              onPressed: onAction,
              label: Text(actionLabel!),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.chevron_right, size: 19),
            ),
        ],
      );
}

class HypEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const HypEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => HypPanel(
        color: HypColors.surface.withValues(alpha: 0.72),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: HypColors.lightPurple, size: 38),
                const SizedBox(height: 10),
                Text(title, textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(message, textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 15),
                  OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
                ],
              ],
            ),
          ),
        ),
      );
}
