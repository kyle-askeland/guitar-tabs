import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tabs/models/song.dart';

void main() {
  test('Song JSON round-trips losslessly', () {
    final song = Song(
      songId: 'abc',
      title: 'Blackbird',
      artist: 'The Beatles',
      tuning: ['D', 'A', 'D', 'G', 'B', 'E'],
      createdAt: '2026-07-08T00:00:00Z',
      updatedAt: '2026-07-09T00:00:00Z',
      sections: [
        Section(name: 'Intro', lines: [
          Line(
            cells: [Cell(col: 0, str: 4, fret: '3')],
            barlines: [8],
            chords: [ChordMark(col: 0, name: 'G'), ChordMark(col: 8, name: 'Am7')],
            lyrics: [LyricMark(col: 0, text: 'Blackbird singing')],
            length: 16,
          ),
        ]),
      ],
    );
    final restored = Song.fromJson(jsonDecode(jsonEncode(song.toJson())));
    expect(jsonEncode(restored.toJson()), jsonEncode(song.toJson()));
  });

  test('fromJson defaults: standard tuning, empty sections', () {
    final song = Song.fromJson({'songId': 'x', 'title': 't'});
    expect(song.tuning, standardTuning);
    expect(song.beatsPerMeasure, 4);
    expect(song.sections, isEmpty);
    expect(song.mine, true);
  });

  test('defaultBarlines matches the historical 4/4 spacing at the default', () {
    expect(defaultBarlines(40, 4), [8, 16, 24, 32]);
  });

  test('defaultBarlines adapts to other measure lengths', () {
    expect(defaultBarlines(40, 3), [6, 12, 18, 24, 30, 36]);
    expect(defaultBarlines(40, 6), [12, 24, 36]);
  });

  test('fromJson defaults for old songs: no chords, no lyrics', () {
    final line = Line.fromJson({'cells': [], 'barlines': [8], 'length': 16});
    expect(line.chords, isEmpty);
    expect(line.lyrics, isEmpty);
  });

  test('a legacy whole-line lyric becomes a mark at column 0', () {
    final line = Line.fromJson({'lyric': 'hello darkness', 'length': 16});
    expect(line.lyricAt(0), 'hello darkness');
  });

  test('setLyric adds, replaces, and clears; lyrics stay sorted by column', () {
    final line = Line(length: 16);
    line.setLyric(8, 'my old friend');
    line.setLyric(0, 'hello darkness');
    expect([for (final l in line.lyrics) l.col], [0, 8]);
    line.setLyric(8, 'again');
    expect(line.lyricAt(8), 'again');
    expect(line.lyrics.length, 2);
    line.setLyric(8, '');
    expect(line.lyricAt(8), isNull);
  });

  test('columnWidths take the widest cell in each column, min 1 (§3)', () {
    final line = Line(length: 4)
      ..setCell(1, 5, '12')
      ..setCell(1, 0, '3')
      ..setCell(2, 4, '5h7');
    expect(line.columnWidths, [1, 2, 3, 1]);
  });

  test('setChord adds, replaces, and clears; chords stay sorted by column', () {
    final line = Line(length: 16);
    line.setChord(8, 'Am7');
    line.setChord(0, 'G');
    expect([for (final c in line.chords) c.name], ['G', 'Am7']);
    line.setChord(8, 'C'); // replace, not duplicate
    expect(line.chordAt(8), 'C');
    expect(line.chords.length, 2);
    line.setChord(8, '');
    expect(line.chordAt(8), isNull);
  });

  test('setCell replaces, clears, and stores frets as strings', () {
    final line = Line(length: 8);
    line.setCell(3, 2, '5');
    line.setCell(3, 2, '5h7'); // replace, not duplicate
    expect(line.cells.length, 1);
    expect(line.cellAt(3, 2)!.fret, '5h7');
    line.setCell(3, 2, '');
    expect(line.cells, isEmpty);
  });

  test('defaultLineLength is 2 measures by default (fits a phone screen)', () {
    expect(defaultLineLength(4), 16); // 2 measures * 4 beats * 2 cols
    expect(defaultLineLength(3), 12);
    expect(defaultLineLength(4, measures: 4), 32); // opt in to the old size
  });

  test('addMeasure appends one measure and closes off the old one', () {
    final line = Line(length: 8, barlines: []);
    line.addMeasure(8);
    expect(line.length, 16);
    expect(line.barlines, [8]);
  });

  test('removeMeasure drops trailing content and no-ops at one measure', () {
    final line = Line(length: 16, barlines: [8])
      ..setCell(10, 0, '3')
      ..setChord(10, 'G')
      ..setLyric(10, 'la');
    expect(line.removeMeasure(8), true);
    expect(line.length, 8);
    expect(line.cells, isEmpty);
    expect(line.chords, isEmpty);
    expect(line.lyrics, isEmpty);
    expect(line.barlines, isEmpty);
    expect(line.removeMeasure(8), false); // already down to one measure
    expect(line.length, 8);
  });

  test('remapColumn keeps a column\'s measure/offset, drops what no longer fits', () {
    // 4/4 (8 cols/measure) -> 3/4 (6 cols/measure): beat 4 (offset 6) of
    // measure 0 has nowhere to go; measure 1's content shifts to start at 6.
    expect(remapColumn(6, 8, 6), isNull);
    expect(remapColumn(4, 8, 6), 4);
    expect(remapColumn(8, 8, 6), 6); // measure 1, offset 0 -> col 6
    expect(remapColumn(10, 8, 6), 8); // measure 1, offset 2 -> col 8
    // Growing never drops anything: 3/4 -> 4/4.
    expect(remapColumn(6, 6, 8), 8); // measure 1, offset 0 -> col 8
  });

  test('remeasureLosses counts only marks that fall outside the new grid', () {
    final line = Line(length: 16, barlines: [8])
      ..setCell(6, 0, '3') // beat 4 of measure 0: lost going to 3/4
      ..setCell(2, 0, '5') // beat 2 of measure 0: survives
      ..setChord(6, 'G'); // also lost
    expect(line.remeasureLosses(4, 3), 2);
    expect(line.remeasureLosses(4, 4), 0); // unchanged grid: nothing lost
    expect(line.remeasureLosses(4, 6), 0); // growing loses nothing
  });

  test('remeasure re-lays cells, chords, lyrics and barlines onto the new grid', () {
    final line = Line(length: 16, barlines: [8])
      ..setCell(0, 0, '3') // measure 0, offset 0
      ..setCell(6, 1, '5') // measure 0, offset 6: dropped by the 3/4 shrink
      ..setCell(10, 2, '7') // measure 1, offset 2 -> shifts to col 8
      ..setChord(8, 'C') // measure 1, offset 0 -> col 6
      ..setLyric(10, 'hey'); // measure 1, offset 2 -> col 8
    line.remeasure(4, 3);
    expect(line.length, 12); // 2 measures * 6 cols
    expect(line.cellAt(0, 0)!.fret, '3');
    expect(line.cellAt(6, 1), isNull);
    expect(line.cellAt(8, 2)!.fret, '7');
    expect(line.chordAt(6), 'C');
    expect(line.lyricAt(8), 'hey');
    expect(line.barlines, [6]);
  });
}
