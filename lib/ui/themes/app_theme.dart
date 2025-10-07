import 'package:flutter/material.dart';

/// ================== PALETA (según la imagen) ==================
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
  static const bgLight    = Color(0xFFF3F4F6);
  static const inputLight = Color(0xFFE5E7EB);

  static const bgDark     = Color(0xFF0B1113);
  static const surfaceDk  = Color(0xFF111417);
  static const inputDark  = Color(0xFF1F2937);

  // Texto
  static const textMain   = Color(0xFF0F172A);
  static const textMute   = Color(0xFF334155);
  static const textOnDark = Color(0xFFE5E7EB);
}

/// ================== TEXTOS ==================
TextTheme _text(Brightness b) {
  final on = b == Brightness.dark ? Brand.textOnDark : Brand.textMain;
  final sub = b == Brightness.dark ? const Color(0xFFCBD5E1) : Brand.textMute;

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
ColorScheme _light = const ColorScheme(
  brightness: Brightness.light,
  primary: Brand.green,     onPrimary: Colors.white,
  primaryContainer: Color(0xFFD1FADF), onPrimaryContainer: Color(0xFF052E16),

  secondary: Brand.blue,    onSecondary: Colors.white,
  secondaryContainer: Color(0xFFDCEBFF), onSecondaryContainer: Color(0xFF0A2A4A),

  tertiary: Color(0xFF1F5130), onTertiary: Colors.white,
  tertiaryContainer: Color(0xFFCFE9DA), onTertiaryContainer: Color(0xFF0E2A1C),

  background: Brand.bgLight,  onBackground: Brand.textMain,
  surface: Brand.card,        onSurface: Brand.textMain,
  surfaceVariant: Color(0xFFEFF1F3), onSurfaceVariant: Color(0xFF475569),

  error: Color(0xFFEF4444), onError: Colors.white,
  errorContainer: Color(0xFFFFE1E1), onErrorContainer: Color(0xFF7F1D1D),

  outline: Color(0xFFD1D5DB), outlineVariant: Color(0xFFE5E7EB),
  inverseSurface: Color(0xFF0B1113), onInverseSurface: Colors.white,
  inversePrimary: Brand.greenDark, shadow: Colors.black, scrim: Colors.black,
);

ColorScheme _dark = const ColorScheme(
  brightness: Brightness.dark,
  primary: Brand.greenDark, onPrimary: Colors.white,
  primaryContainer: Color(0xFF09351F), onPrimaryContainer: Color(0xFFBAF7CF),

  secondary: Brand.blueDark, onSecondary: Colors.white,
  secondaryContainer: Color(0xFF10264D), onSecondaryContainer: Color(0xFFDBEAFE),

  tertiary: Color(0xFF1C3D2A), onTertiary: Color(0xFFCFE9DA),
  tertiaryContainer: Color(0xFF102518), onTertiaryContainer: Color(0xFFBFE0CF),

  background: Brand.bgDark,  onBackground: Brand.textOnDark,
  surface: Brand.surfaceDk,  onSurface: Brand.textOnDark,
  surfaceVariant: Color(0xFF192025), onSurfaceVariant: Color(0xFF9AA4AE),

  error: Color(0xFFF87171), onError: Color(0xFF450A0A),
  errorContainer: Color(0xFF3F1515), onErrorContainer: Color(0xFFFFDAD6),

  outline: Color(0xFF2A3238), outlineVariant: Brand.inputDark,
  inverseSurface: Color(0xFFE7EAEC), onInverseSurface: Brand.bgDark,
  inversePrimary: Brand.green, shadow: Colors.black, scrim: Colors.black,
);

/// ================== THEME ==================
class AppTheme {
  static ThemeData light = _build(_light);
  static ThemeData dark  = _build(_dark);

  static ThemeData _build(ColorScheme cs) {
    final isDark = cs.brightness == Brightness.dark;
    final radius = BorderRadius.circular(18);

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: cs.background,
      textTheme: _text(cs.brightness),

      // AppBar VERDE (como en la imagen)
      appBarTheme: AppBarTheme(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: _text(cs.brightness).titleLarge,
      ),

      // Tarjetas (login card blanca con sombra suave)
      cardTheme: CardTheme(
        color: cs.surface,
        elevation: 0, // manejamos sombra con BoxDecoration en el widget si se desea
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      // Inputs: gris relleno, borde redondeado, FOCUS MORADO
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
        hintStyle: _text(cs.brightness).bodyMedium,
        labelStyle: _text(cs.brightness).bodyMedium,
        prefixIconColor: cs.onSurfaceVariant,
        suffixIconColor: cs.onSurfaceVariant,
      ),

      // Dropdown idéntico a los inputs
      dropdownMenuTheme: DropdownMenuThemeData(
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

      // BOTÓN PRINCIPAL AZUL en forma "pill"
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const MaterialStatePropertyAll(Size.fromHeight(44)),
          shape: const MaterialStatePropertyAll(StadiumBorder()),
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            final disabled = states.contains(MaterialState.disabled);
            return disabled ? cs.secondary.withOpacity(.5) : cs.secondary;
          }),
          foregroundColor: const MaterialStatePropertyAll(Colors.white),
          textStyle: MaterialStatePropertyAll(_text(cs.brightness).labelLarge),
          elevation: const MaterialStatePropertyAll(0),
        ),
      ),

      // Botón verde (si lo usas para acciones secundarias)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const MaterialStatePropertyAll(Size.fromHeight(44)),
          shape: MaterialStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)),
          backgroundColor: MaterialStatePropertyAll(cs.primary),
          foregroundColor: const MaterialStatePropertyAll(Colors.white),
          textStyle: MaterialStatePropertyAll(_text(cs.brightness).labelLarge),
          elevation: const MaterialStatePropertyAll(0.5),
        ),
      ),

      // Link azul (¿Olvidaste tu contraseña?)
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: MaterialStatePropertyAll(cs.secondary),
          textStyle: MaterialStatePropertyAll(
            _text(cs.brightness).labelLarge!.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: cs.outlineVariant,
        space: 1,
        thickness: 1,
      ),

      // Navegación inferior por si la usas
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: cs.secondaryContainer.withOpacity(isDark ? .32 : .48),
        backgroundColor: cs.surface,
        labelTextStyle: MaterialStatePropertyAll(_text(cs.brightness).labelLarge),
      ),
    );
  }
}
