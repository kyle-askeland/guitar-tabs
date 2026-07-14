/// Previews the real WoodBackground widget (not just the raw painter) at a
/// phone size and a wider size, to check the photo-tile scale reads
/// consistently. Renders to `images/wood-photo-preview.png`.
///
///     cd frontend && flutter test tool/wood_photo_preview.dart --update-goldens
///
/// Lives in `tool/` (not `test/`) so it never runs as part of `make test`.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tabs/widgets/wood_background.dart';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    loader.addFont(File(path).readAsBytes().then((b) => b.buffer.asByteData()));
  }
  await loader.load();
}

Widget _demoContent() => const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 40),
          Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text('Practice the intro slowly.'),
            ),
          ),
        ],
      ),
    );

void main() {
  setUpAll(() async {
    const supp = '/System/Library/Fonts/Supplemental';
    await _loadFont('Roboto', ['$supp/Arial.ttf']);
  });

  testWidgets('wood photo preview', (tester) async {
    const phone = Size(390, 844);
    const wide = Size(900, 700);
    const pad = 24.0;
    final rowHeight = phone.height > wide.height ? phone.height : wide.height;
    final total = Size(
      phone.width + wide.width + pad * 3,
      rowHeight * 2 + pad * 3,
    );

    tester.view
      ..physicalSize = Size(total.width * 2, total.height * 2)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);

    Widget row(bool dark) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: phone.width,
              height: phone.height,
              child: WoodBackground(dark: dark, child: _demoContent()),
            ),
            const SizedBox(width: pad),
            SizedBox(
              width: wide.width,
              height: wide.height,
              child: WoodBackground(dark: dark, child: _demoContent()),
            ),
          ],
        );

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: const Color(0xFF15120F),
        child: Padding(
          padding: const EdgeInsets.all(pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [row(false), const SizedBox(height: pad), row(true)],
          ),
        ),
      ),
    ));
    // Asset image loads via a real ImageStreamListener callback, which needs
    // a real event-loop turn rather than the fake-async pump.
    await tester.runAsync(() async {
      await tester.pump();
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../images/wood-photo-preview.png'),
    );
  });
}
