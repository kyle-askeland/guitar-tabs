import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tabs/models/song.dart';
import 'package:guitar_tabs/widgets/fretboard_pad.dart';
import 'package:guitar_tabs/widgets/tab_staff.dart';

void main() {
  testWidgets('TabStaff paints chords/lyric/techniques and reports cell taps',
      (tester) async {
    final line = Line(length: 8, barlines: [4])
      ..setCell(0, 0, '3')
      ..setCell(2, 4, '5h7')
      ..setChord(0, 'G')
      ..setLyric(0, 'la la');
    int? tappedCol, tappedStr, tappedChordCol, tappedLyricCol;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TabStaff(
          line: line,
          tuning: standardTuning,
          editable: true,
          cursorCol: 0,
          cursorStr: 0,
          onTapCell: (c, s) {
            tappedCol = c;
            tappedStr = s;
          },
          onTapChord: (c) => tappedChordCol = c,
          onTapLyric: (c) => tappedLyricCol = c,
        ),
      ),
    ));
    final paint = tester.getTopLeft(find
        .descendant(of: find.byType(TabStaff), matching: find.byType(CustomPaint))
        .first);
    // geometry at scale 1: labelW 26, chordH 22, rowH 26, min col width 30
    await tester.tapAt(paint + const Offset(41, 35)); // col 0, top row = high e
    expect(tappedCol, 0);
    expect(tappedStr, 5);
    await tester.tapAt(paint + const Offset(41 + 30, 22 + 6 * 26 - 13 + 26)); // lyric row, col 1
    expect(tappedLyricCol, 1);
    await tester.tapAt(paint + const Offset(41 + 30, 10)); // chord row, col 1
    expect(tappedChordCol, 1);
  });

  testWidgets(
      'chords-mode Line renders no staff; taps only reach chords/lyrics',
      (tester) async {
    final line = Line(length: 8, mode: 'chords')
      ..setCell(0, 0, '3') // cells survive but never render/tap in this mode
      ..setChord(0, 'G')
      ..setLyric(0, 'la la');
    int? tappedCol, tappedStr, tappedChordCol, tappedLyricCol;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TabStaff(
          line: line,
          tuning: standardTuning,
          editable: true,
          onTapCell: (c, s) {
            tappedCol = c;
            tappedStr = s;
          },
          onTapChord: (c) => tappedChordCol = c,
          onTapLyric: (c) => tappedLyricCol = c,
        ),
      ),
    ));
    final paintFinder = find.descendant(
        of: find.byType(TabStaff), matching: find.byType(CustomPaint));
    final paint = tester.getTopLeft(paintFinder.first);

    // No six-string staff: height is just the chord row + lyric row.
    expect(tester.getSize(paintFinder.first).height, 22 + 24);

    await tester.tapAt(paint + const Offset(41, 10)); // chord row, col 0
    expect(tappedChordCol, 0);

    // Below the chord row lands straight on the lyric row — there's no
    // staff area in between to swallow the tap as a cell.
    await tester.tapAt(paint + const Offset(41, 30));
    expect(tappedLyricCol, 0);
    expect(tappedCol, isNull);
    expect(tappedStr, isNull);
  });

  testWidgets('FretboardPad maps taps to (string, fret) across its 4-fret window',
      (tester) async {
    int? str, fret;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: FretboardPad(
            column: const ['', '', '2', '', '', '0'],
            tuning: standardTuning,
            onFret: (s, f) {
              str = s;
              fret = f;
            },
            onSymbol: (_) {},
            onClear: () {},
            onPrev: () {},
            onNext: () {},
          ),
        ),
      ),
    ));
    final board = tester.getTopLeft(find.byKey(const Key('fretboard')));
    // geometry: labelW 24, openW 32, headerH 16, rowH 24
    await tester.tapAt(board + const Offset(24 + 32 + 20, 16 + 12)); // fret 1, high e
    expect(str, 5);
    expect(fret, 1);
    await tester.tapAt(board + const Offset(24 + 16, 16 + 5 * 24 + 12)); // open low E
    expect(str, 0);
    expect(fret, 0);
  });
}
