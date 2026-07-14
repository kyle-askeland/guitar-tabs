/// Renders the palette comparison images in `images/`.
///
///     cd frontend && flutter test tool/palette_shots.dart --update-goldens
///
/// It lives in `tool/` rather than `test/` on purpose: `flutter test` with no
/// arguments only walks `test/`, so this never runs as part of `make test`.
/// Only the shipped palette (Sage & Oak, see storage/app_theme.dart) exists in
/// the app; the alternates are declared here so the app carries no dead colour.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tabs/models/song.dart';
import 'package:guitar_tabs/storage/app_theme.dart';
import 'package:guitar_tabs/widgets/tab_staff.dart';

/// One candidate: an accent colour plus the wood it sits on, per mode.
class Palette {
  final String name, blurb;
  final Color light, lightContainer, dark, darkContainer;
  final WoodTone lightWood, darkWood;

  const Palette(this.name, this.blurb,
      {required this.light,
      required this.lightContainer,
      required this.dark,
      required this.darkContainer,
      required this.lightWood,
      required this.darkWood});
}

const _oak = WoodTone(
  base: Color(0xFFC4A279),
  grain: Color(0xFF7A5730),
  seam: Color(0xFF5E4426),
);
const _coffee = WoodTone(
  base: Color(0xFF221B18),
  grain: Color(0xFF6B5443),
  seam: Color(0xFF0C0908),
);
const _walnut = WoodTone(
  base: Color(0xFF2A2320),
  grain: Color(0xFF7A6250),
  seam: Color(0xFF0F0B0A),
);
const _ebony = WoodTone(
  base: Color(0xFF1E1917),
  grain: Color(0xFF5A4739),
  seam: Color(0xFF080606),
);

const palettes = [
  Palette('01-sage-and-oak', 'SHIPPED — sage green on tan oak / roasted coffee',
      light: Color(0xFF4F6B4A),
      lightContainer: Color(0xFFD2E3CA),
      dark: Color(0xFF9CBB90),
      darkContainer: Color(0xFF35502F),
      lightWood: _oak,
      darkWood: _coffee),
  Palette('02-brass-and-parchment', 'brass on parchment / dark walnut',
      light: Color(0xFFA9762C),
      lightContainer: Color(0xFFF0DCB4),
      dark: Color(0xFFE0A94A),
      darkContainer: Color(0xFF57411C),
      lightWood: _oak,
      darkWood: _walnut),
  Palette('03-verdigris-and-cream', 'aged copper on cream / espresso',
      light: Color(0xFF1F6F6B),
      lightContainer: Color(0xFFC5E4E1),
      dark: Color(0xFF62BEB4),
      darkContainer: Color(0xFF20514D),
      lightWood: _oak,
      darkWood: _ebony),
  Palette('04-oxblood-and-bone', 'cherry burst on bone / warm black-brown',
      light: Color(0xFF8C2F2A),
      lightContainer: Color(0xFFF3D3CF),
      dark: Color(0xFFD9736A),
      darkContainer: Color(0xFF63302B),
      lightWood: _oak,
      darkWood: _ebony),
];

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    loader.addFont(File(path).readAsBytes().then((b) => b.buffer.asByteData()));
  }
  await loader.load();
}

/// Procedural stand-in for a candidate wood tone. `WoodBackground` now tiles
/// a photographed texture, but that photo only exists for the shipped Sage &
/// Oak palette — the alternates here have no asset, so approximate them with
/// a flat base, a few grain streaks, and a seam-coloured vignette.
class _SwatchWoodPainter extends CustomPainter {
  final WoodTone tone;
  const _SwatchWoodPainter(this.tone);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = tone.base);
    final grain = Paint()
      ..color = tone.grain.withValues(alpha: .35)
      ..strokeWidth = 1.5;
    for (double y = 6; y < size.height; y += 14) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 4), grain);
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.15, -.35),
          radius: 1.1,
          colors: [Colors.transparent, tone.seam.withValues(alpha: .35)],
          stops: const [.45, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _SwatchWoodPainter old) => old.tone != tone;
}

/// A tab line with enough going on to judge a palette by: chord names, a
/// selected cell, a hammer-on, a lyric.
Line _demoLine() => Line(length: 12, barlines: [6])
  ..setCell(0, 0, '3')
  ..setCell(0, 1, '2')
  ..setCell(0, 5, '3')
  ..setCell(2, 4, '1')
  ..setCell(4, 3, '5h7')
  ..setCell(7, 5, '0')
  ..setCell(9, 2, '12')
  ..setChord(0, 'G')
  ..setChord(6, 'Am7')
  ..setLyric(0, 'blackbird')
  ..setLyric(6, 'singing');

Widget _panel(Palette p, bool dark) {
  final base = dark ? _darkNeutrals : _lightNeutrals;
  final scheme = base.copyWith(
    primary: dark ? p.dark : p.light,
    primaryContainer: dark ? p.darkContainer : p.lightContainer,
    onPrimary: dark ? const Color(0xFF1E1A17) : Colors.white,
  );
  final theme = themeFrom(scheme);
  return Theme(
    data: theme,
    child: SizedBox(
      width: 460,
      height: 560,
      // WoodBackground now tiles a real photo for the shipped palette only;
      // approximate the other candidates' wood procedurally instead.
      child: CustomPaint(
        painter: _SwatchWoodPainter(dark ? p.darkWood : p.lightWood),
        isComplex: true,
        child: Builder(
          builder: (_) => Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(dark ? 'Dark' : 'Light',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      )),
                  const SizedBox(height: 10),
                  Card(
                    color: scheme.surface,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('Practice the intro slowly.'),
                    ),
                  ),
                  Card(
                    color: scheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: TabStaff(
                        line: _demoLine(),
                        tuning: standardTuning,
                        editable: true,
                        cursorCol: 4,
                        cursorStr: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, children: [
                    for (final c in ['G', 'Am7', 'C', 'D'])
                      ChoiceChip(
                          label: Text(c), selected: c == 'Am7', onSelected: (_) {}),
                  ]),
                  const Spacer(),
                  SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.save, size: 24),
                      label: const Text('Save changes',
                          style:
                              TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Warm neutral ramps, shared by every candidate so only the accent (and the
/// dark wood) differ between images.
const _lightNeutrals = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF4F6B4A),
  onPrimary: Colors.white,
  secondary: Color(0xFF7A5A38),
  onSecondary: Colors.white,
  error: Color(0xFFA13B32),
  onError: Colors.white,
  surface: Color(0xFFFFFFFF),
  onSurface: Color(0xFF2E2620),
  surfaceContainerHighest: Color(0xFFE8E2D6),
  onSurfaceVariant: Color(0xFF5A554C),
  outline: Color(0xFF8C877C),
  outlineVariant: Color(0xFFD6D0C3),
);

const _darkNeutrals = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF9CBB90),
  onPrimary: Color(0xFF1C3520),
  secondary: Color(0xFFD9BE96),
  onSecondary: Color(0xFF3B2A16),
  error: Color(0xFFFFB4A8),
  onError: Color(0xFF561E17),
  surface: Color(0xFF312924),
  onSurface: Color(0xFFEDE3D4),
  surfaceContainerHighest: Color(0xFF4A403A),
  onSurfaceVariant: Color(0xFFCBBFAF),
  outline: Color(0xFF948779),
  outlineVariant: Color(0xFF4A4038),
);

void main() {
  setUpAll(() async {
    // Real fonts, so the images show text rather than test-harness boxes.
    const supp = '/System/Library/Fonts/Supplemental';
    await _loadFont('Roboto', ['$supp/Arial.ttf']);
    await _loadFont('monospace', ['$supp/Courier New.ttf']);
  });

  for (final p in palettes) {
    testWidgets(p.name, (tester) async {
      tester.view
        ..physicalSize = const Size(920 * 2, 620 * 2)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ColoredBox(
          color: const Color(0xFF15120F),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('${p.name.substring(3)} — ${p.blurb}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [_panel(p, false), _panel(p, true)],
            ),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../images/${p.name}.png'),
      );
    });
  }
}
