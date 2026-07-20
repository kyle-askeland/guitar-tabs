import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light or dark, nothing else to choose. Both are wood — light is tan oak,
/// dark is roasted-coffee brown (not black) — with sage green as the one
/// accent, the colour that reads most naturally against timber.
///
/// The surface ramp is defined by hand rather than derived from a seed:
/// `ColorScheme.fromSeed` pulls chroma out of the seed hue, and any brown or
/// green seed drags the neutrals pink or minty. These are warm greys mixed
/// toward the wood instead.
///
/// The choice persists via shared_preferences (localStorage on web) and is
/// loaded before runApp so the first frame is already the right one.
final darkModeNotifier = ValueNotifier<bool>(false);

Future<void> loadTheme() async {
  final prefs = await SharedPreferences.getInstance();
  darkModeNotifier.value = prefs.getBool('darkMode') ?? false;
}

Future<void> setDarkMode(bool dark) async {
  darkModeNotifier.value = dark;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('darkMode', dark);
}

/// The three colours the wood painter needs: the plank body, the grain drawn
/// on it, and the seams between planks.
class WoodTone {
  final Color base, grain, seam;
  const WoodTone({required this.base, required this.grain, required this.seam});
}

/// Tan oak. Grain is darker than the plank, as in real light timber.
const lightWood = WoodTone(
  base: Color(0xFFC4A279),
  grain: Color(0xFF7A5730),
  seam: Color(0xFF5E4426),
);

/// Roasted coffee. Grain is *lighter* than the plank — on dark stained wood
/// the figure catches the light rather than swallowing it.
const darkWood = WoodTone(
  base: Color(0xFF221B18),
  grain: Color(0xFF6B5443),
  seam: Color(0xFF0C0908),
);

const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF4F6B4A), // sage
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFD2E3CA),
  onPrimaryContainer: Color(0xFF0C2010),
  secondary: Color(0xFF7A5A38), // walnut, for the rare second accent
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFEBDCC6),
  onSecondaryContainer: Color(0xFF2A1B0B),
  error: Color(0xFFA13B32),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD5),
  onErrorContainer: Color(0xFF410300),
  surface: Color(0xFFFFFFFF), // cards, staves, dialogs, app bar — flat white
  onSurface: Color(0xFF2E2620),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFAF8F5),
  surfaceContainer: Color(0xFFF5F2EC),
  surfaceContainerHigh: Color(0xFFEFEAE1),
  surfaceContainerHighest: Color(0xFFE8E2D6),
  onSurfaceVariant: Color(0xFF5A554C),
  outline: Color(0xFF8C877C),
  outlineVariant: Color(0xFFD6D0C3),
  inverseSurface: Color(0xFF332D26),
  onInverseSurface: Color(0xFFFAF8F5),
  inversePrimary: Color(0xFF9CBB90),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

const _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF9CBB90), // sage, lifted for dark surfaces
  onPrimary: Color(0xFF1C3520),
  primaryContainer: Color(0xFF35502F),
  onPrimaryContainer: Color(0xFFB8D7AC),
  secondary: Color(0xFFD9BE96),
  onSecondary: Color(0xFF3B2A16),
  secondaryContainer: Color(0xFF53402A),
  onSecondaryContainer: Color(0xFFF3E1C6),
  error: Color(0xFFFFB4A8),
  onError: Color(0xFF561E17),
  errorContainer: Color(0xFF73342A),
  onErrorContainer: Color(0xFFFFDAD5),
  surface: Color(0xFF312924),
  onSurface: Color(0xFFEDE3D4),
  surfaceContainerLowest: Color(0xFF1A1512),
  surfaceContainerLow: Color(0xFF29221E),
  surfaceContainer: Color(0xFF342C27),
  surfaceContainerHigh: Color(0xFF3F3630),
  surfaceContainerHighest: Color(0xFF4A403A),
  onSurfaceVariant: Color(0xFFCBBFAF),
  outline: Color(0xFF948779),
  outlineVariant: Color(0xFF4A4038),
  inverseSurface: Color(0xFFEDE3D4),
  onInverseSurface: Color(0xFF332D26),
  inversePrimary: Color(0xFF4F6B4A),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

/// Scaffolds are transparent so the wood shows through; content that has to
/// stay legible (tab staves, cards, app bar) sits on `colorScheme.surface`.
ThemeData themeFor(bool dark) => themeFrom(dark ? _darkScheme : _lightScheme);

/// Split from [themeFor] so alternate palettes can be rendered without the
/// app having to carry them (see `tool/palette_shots.dart`).
ThemeData themeFrom(ColorScheme scheme) => ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface, // opaque — must match cards/dialogs exactly
        surfaceTintColor: Colors.transparent,
      ),
      // Dialog and PopupMenu default to surfaceContainerHigh/surfaceContainer
      // rather than `surface` — a different (and, on this hand-tuned ramp,
      // slightly warmer) token than the one cards and the app bar use. Pin
      // them to `surface` so every opaque panel in the app is the same color.
      // (`surfaceTintColor` also defaults to `primary`, tinting elevated
      // surfaces sage-green by elevation; disabled everywhere for the same
      // reason.)
      cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
