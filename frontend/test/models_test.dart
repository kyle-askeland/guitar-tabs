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
      capo: 2,
      createdAt: '2026-07-08T00:00:00Z',
      updatedAt: '2026-07-09T00:00:00Z',
      sections: [
        Section(name: 'Intro', lines: [
          Line(cells: [Cell(col: 0, str: 4, fret: '3')], barlines: [8], length: 16),
        ]),
      ],
    );
    final restored = Song.fromJson(jsonDecode(jsonEncode(song.toJson())));
    expect(jsonEncode(restored.toJson()), jsonEncode(song.toJson()));
  });

  test('fromJson defaults: standard tuning, capo 0, empty sections', () {
    final song = Song.fromJson({'songId': 'x', 'title': 't'});
    expect(song.tuning, standardTuning);
    expect(song.capo, 0);
    expect(song.sections, isEmpty);
    expect(song.mine, true);
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
}
