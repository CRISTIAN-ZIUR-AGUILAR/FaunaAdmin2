import 'package:flutter/material.dart';

/// ================== PALETA (igual a la tuya) ==================
class Brand {
  // Marca / AppBar
  static const green      = Color(0xFF22C55E);
  static const greenDark  = Color(0xFF16A34A);

  // CTA (botón principal)
  static const blue       = Color(0xFF4EA8FF);
  static const blueDark   = Color(0xFF3B82F6);

  // Borde de enfoque (dropdown/inputs)
  static const violet     = Color(0xFF6D28D9);

  // Superficies e inputs
  static const card       = Color(0xFFFFFFFF);
  static const bgLight    = Color(0xFFF6F7F9); // un pelín más suave
  static const inputLight = Color(0xFFEFF1F4); // +contraste con texto

  static const bgDark     = Color(0xFF0B1113);
  static const surfaceDk  = Color(0xFF111417);
  static const inputDark  = Color(0xFF151B20); // +claro que bg, para legibilidad

  // Texto
  static const textMain   = Color(0xFF0F172A);
  static const textMute   = Color(0xFF4B5563); // un poco más visible
  static const textOnDark = Color(0xFFE7EAEC);
}

/// Helpers de mezcla (para hover/press sutiles)
Color _blend(Color a, Color b, double t) {
  return Color.fromARGB(
    (a.alpha + (b.alpha - a.alpha) * t).round(),
    (a.red   + (b.red   - a.red)   * t).round(),
    (a.green + (b.green - a.green) * t).round(),
    (a.blue  + (b.blue  - a.blue)  * t).round(),
  );
}

/// ================== TEXTOS ==================
TextTheme _text(Brightness b) {
  final on  = b == Brightness.dark ? Brand.textOnDark : Brand.textMain;
  final sub = b == Brightness.dark ? const Color(0xFFBCC6CF) : Brand.textMute;

  return TextTheme(
    headlineSmall: TextStyle(fontWeight: FontWeight.w800, color: on, letterSpacing: -.2),
    titleLarge:    TextStyle(fontWeight: FontWeight.w700, color: on),
    titleMedium:   TextStyle(fontWeight: FontWeight.w600, color: on),
    bodyLarge:     TextStyle(fontWeight: FontWeight.w400, color: on, height: 1.25),
    bodyMedium:    TextStyle(fontWeight: FontWeight.w400, color: sub, height: 1.25),
    labelLarge:    TextStyle(fontWeight: FontWeight.w600, color: on),
  );
}

/// ================== ESQUEMAS DE COLOR (M3) ==================
final ColorScheme _light = ColorScheme(
  brightness: Brightness.light,
  primary: Brand.green,     onPrimary: Colors.white,
  primaryContainer: const Color(0xFFD8F7E6), onPrimaryContainer: const Color(0xFF052E16),

  secondary: Brand.blue,    onSecondary: Colors.white,
  secondaryContainer: const Color(0xFFE3F1FF), onSecondaryContainer: const Color(0xFF0A2A4A),

  tertiary: const Color(0xFF1F5130), onTertiary: Colors.white,
  tertiaryContainer: const Color(0xFFCFE9DA), onTertiaryContainer: const Color(0xFF0E2A1C),

  background: Brand.bgLight,  onBackground: Brand.textMain,
  surface: Brand.card,        onSurface: Brand.textMain,
  surfaceVariant: const Color(0xFFEEF1F4), onSurfaceVariant: const Color(0xFF556270),

  error: const Color(0xFFDC2626), onError: Colors.white,
  errorContainer: const Color(0xFFFFE5E5), onErrorContainer: const Color(0xFF7F1D1D),

  outline: const Color(0xFFD6DADE), outlineVariant: const Color(0xFFE9ECF0),
  inverseSurface: const Color(0xFF0B1113), onInverseSurface: Colors.white,
  inversePrimary: Brand.greenDark, shadow: Colors.black, scrim: Colors.black,
);

final ColorScheme _dark = ColorScheme(
  brightness: Brightness.dark,
  primary: Brand.greenDark, onPrimary: Colors.white,
  primaryContainer: const Color(0xFF0E3A22), onPrimaryContainer: const Color(0xFFBAF7CF),

  secondary: Brand.blueDark, onSecondary: Colors.white,
  secondaryContainer: const Color(0xFF0E2A52), onSecondaryContainer: const Color(0xFFDBEAFE),

  tertiary: const Color(0xFF1C3D2A), onTertiary: const Color(0xFFCFE9DA),
  tertiaryContainer: const Color(0xFF102518), onTertiaryContainer: const Color(0xFFBFE0CF),

  background: Brand.bgDark,  onBackground: Brand.textOnDark,
  surface: Brand.surfaceDk,  onSurface: Brand.textOnDark,
  surfaceVariant: const Color(0xFF171D22), onSurfaceVariant: const Color(0xFFA8B2BC),

  error: const Color(0xFFF87171), onError: const Color(0xFF450A0A),
  errorContainer: const Color(0xFF3F1515), onErrorContainer: const Color(0xFFFFDAD6),

  outline: const Color(0xFF2B333A), outlineVariant: Brand.inputDark,
  inverseSurface: const Color(0xFFE7EAEC), onInverseSurface: Brand.bgDark,
  inversePrimary: Brand.green, shadow: Colors.black, scrim: Colors.black,
);

/// ================== THEME ==================
class AppTheme {
  static ThemeData light = _build(_light);
  static ThemeData dark  = _build(_dark);

  static ThemeData _build(ColorScheme cs) {
    final isDark = cs.brightness == Brightness.dark;
    final text = _text(cs.brightness);
    final radius = BorderRadius.circular(18);

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: cs.background,
      textTheme: text,

      // AppBar VERDE (título siempre legible sobre el verde)
      appBarTheme: AppBarTheme(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: text.titleLarge?.copyWith(
          color: cs.onPrimary,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: cs.onPrimary),
      ),

      // Iconos visibles en dark/light
      iconTheme: IconThemeData(color: isDark ? cs.onSurface : cs.onSurfaceVariant),

      // Tarjetas (más suaves en light, más definidas en dark)
      cardTheme: CardTheme(
        color: cs.surface,
        elevation: isDark ? 1.5 : 0,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        surfaceTintColor: isDark ? null : cs.surface, // evita tinte gris en light
      ),

      // Dividers más sutiles
      dividerTheme: DividerThemeData(
        color: cs.outline.withOpacity(isDark ? .25 : .6),
        space: 1,
        thickness: 1,
      ),

      // Inputs: relleno suave, texto con alto contraste
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? Brand.inputDark : Brand.inputLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(color: Brand.violet, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: cs.error.withOpacity(.9)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: cs.error, width: 1.6),
        ),
        hintStyle: text.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant.withOpacity(isDark ? .75 : .9),
        ),
        labelStyle: text.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant.withOpacity(isDark ? .9 : .8),
          fontWeight: FontWeight.w500,
        ),
        helperStyle: text.bodyMedium,
        prefixIconColor: cs.onSurfaceVariant.withOpacity(.9),
        suffixIconColor: cs.onSurfaceVariant.withOpacity(.9),
      ),

      // Dropdown igual a inputs
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: text.bodyLarge?.copyWith(color: cs.onSurface),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: isDark ? Brand.inputDark : Brand.inputLight,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          border: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            borderSide: BorderSide(color: Brand.violet, width: 1.6),
          ),
        ),
      ),

      // BOTÓN PRINCIPAL (azul)
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const MaterialStatePropertyAll(Size.fromHeight(44)),
          shape: const MaterialStatePropertyAll(StadiumBorder()),
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            final base = cs.secondary;
            if (states.contains(MaterialState.disabled)) {
              return base.withOpacity(.45);
            }
            if (states.contains(MaterialState.pressed)) {
              return _blend(base, Colors.black, .08);
            }
            if (states.contains(MaterialState.hovered)) {
              return _blend(base, Colors.white, .06);
            }
            return base;
          }),
          foregroundColor: const MaterialStatePropertyAll(Colors.white),
          textStyle: MaterialStatePropertyAll(text.labelLarge),
          elevation: const MaterialStatePropertyAll(0),
        ),
      ),

      // Botón secundario (verde)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const MaterialStatePropertyAll(Size.fromHeight(44)),
          shape: MaterialStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)),
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            final base = cs.primary;
            if (states.contains(MaterialState.disabled)) return base.withOpacity(.45);
            if (states.contains(MaterialState.pressed)) return _blend(base, Colors.black, .08);
            if (states.contains(MaterialState.hovered)) return _blend(base, Colors.white, .06);
            return base;
          }),
          foregroundColor: const MaterialStatePropertyAll(Colors.white),
          textStyle: MaterialStatePropertyAll(text.labelLarge),
          elevation: const MaterialStatePropertyAll(0.5),
        ),
      ),

      // Link (texto botón)
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: MaterialStatePropertyAll(cs.secondary),
          overlayColor: MaterialStatePropertyAll(cs.secondary.withOpacity(.08)),
          textStyle: MaterialStatePropertyAll(
            text.labelLarge!.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),

      // Navigation bar (si la usas)
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: cs.secondaryContainer.withOpacity(isDark ? .28 : .42),
        backgroundColor: cs.surface,
        labelTextStyle: MaterialStatePropertyAll(text.labelLarge),
        iconTheme: MaterialStatePropertyAll(
          IconThemeData(color: cs.onSurface),
        ),
      ),

      // Snackbars legibles
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFF11181C) : const Color(0xFF0F172A),
        contentTextStyle: text.bodyLarge?.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
