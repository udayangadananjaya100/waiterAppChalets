import 'package:flutter/material.dart';

class Palette {
  static const forest = Color(0xFF193E35);
  static const green = Color(0xFF2C6B54);
  static const paper = Color(0xFFF8F7F3);
  static const ink = Color(0xFF20352F);
  static const muted = Color(0xFF758078);
  static const line = Color(0xFFE3E6DD);
  static const mint = Color(0xFFE8F0E7);
  static const amber = Color(0xFF9C591F);
  static const peach = Color(0xFFFBEDDA);
  static const red = Color(0xFFB14339);
}

ThemeData serviceTheme() {
  final scheme = ColorScheme.fromSeed(
      seedColor: Palette.forest,
      primary: Palette.forest,
      surface: Palette.paper,
      error: Palette.red);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Manrope',
    scaffoldBackgroundColor: Palette.paper,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
          fontFamily: 'Lora', fontSize: 34, height: 1.2, color: Palette.ink),
      headlineMedium: TextStyle(
          fontFamily: 'Lora', fontSize: 29, height: 1.25, color: Palette.ink),
      headlineSmall:
          TextStyle(fontFamily: 'Lora', fontSize: 23, color: Palette.ink),
      titleLarge: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w700, color: Palette.ink),
      titleMedium: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w700, color: Palette.ink),
      bodyLarge: TextStyle(fontSize: 15, height: 1.6, color: Palette.ink),
      bodyMedium: TextStyle(fontSize: 13, height: 1.5, color: Palette.ink),
      bodySmall: TextStyle(fontSize: 12, height: 1.5, color: Palette.muted),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
        backgroundColor: Palette.paper,
        foregroundColor: Palette.ink,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0),
    inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Palette.line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Palette.line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Palette.green, width: 1.5)),
        hintStyle: const TextStyle(color: Palette.muted, fontSize: 13)),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            minimumSize: const Size(48, 54),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w700,
                fontSize: 14))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 50),
            side: const BorderSide(color: Palette.line),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)))),
    cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Palette.line))),
    dividerTheme:
        const DividerThemeData(color: Palette.line, thickness: 1, space: 1),
    bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Palette.paper,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)))),
    snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Palette.forest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: Palette.mint,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w500,
            color: Palette.ink))),
  );
}

class BrandMark extends StatelessWidget {
  final bool light;
  final double size;
  const BrandMark({super.key, this.light = false, this.size = 42});
  @override
  Widget build(BuildContext context) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: light ? Colors.white.withValues(alpha: .12) : Palette.mint,
          borderRadius: BorderRadius.circular(size * .3)),
      child: Icon(Icons.landscape_outlined,
          color: light ? const Color(0xFFD5DFC8) : Palette.forest,
          size: size * .67));
}

class StatusTag extends StatelessWidget {
  final String label;
  final Color color, background;
  final IconData? icon;
  const StatusTag(this.label,
      {super.key,
      this.color = Palette.green,
      this.background = Palette.mint,
      this.icon});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: background, borderRadius: BorderRadius.circular(7)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4)
        ],
        Flexible(
            child: Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: color)))
      ]));
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, description;
  final Widget? action;
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      required this.description,
      this.action});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Palette.mint),
            child: Icon(icon, size: 32, color: Palette.green)),
        const SizedBox(height: 18),
        Text(title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Palette.muted, height: 1.6)),
        if (action != null) ...[const SizedBox(height: 20), action!]
      ]));
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirm(BuildContext context,
        {required String title,
        required String message,
        required String action}) async =>
    await showDialog<bool>(
        context: context,
        builder: (context) =>
            AlertDialog(title: Text(title), content: Text(message), actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Go back')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(action))
            ])) ??
    false;

class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionTitle(this.title, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        if (trailing != null) trailing!
      ]);
}

IconData dishIcon(String category) {
  final c = category.toLowerCase();
  if (RegExp('drink|beverage|juice|tea|coffee').hasMatch(c)) {
    return Icons.local_cafe_outlined;
  }
  if (RegExp('dessert|sweet').hasMatch(c)) return Icons.cake_outlined;
  if (RegExp('starter|salad|soup').hasMatch(c)) return Icons.eco_outlined;
  return Icons.ramen_dining_outlined;
}
