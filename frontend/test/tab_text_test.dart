import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tabs/models/song.dart';
import 'package:guitar_tabs/models/tab_text.dart';

void main() {
  test('empty line renders labels, dashes, and enclosing pipes', () {
    final line = Line(length: 8, barlines: []);
    final rows = renderLine(line, standardTuning);
    expect(rows, [
      'e|--------|',
      'B|--------|',
      'G|--------|',
      'D|--------|',
      'A|--------|',
      'E|--------|',
    ]);
  });

  test('string labels come from the tuning (drop D), high e lowercased', () {
    final rows = renderLine(Line(length: 4, barlines: []), ['D', 'A', 'D', 'G', 'B', 'E']);
    expect([for (final r in rows) r[0]], ['e', 'B', 'G', 'D', 'A', 'D']);
  });

  test('frets land on the right string/column; 0 = open; str 0 is low E', () {
    final line = Line(length: 8, barlines: [4])
      ..setCell(1, 5, '0')
      ..setCell(2, 0, '3');
    expect(renderLine(line, standardTuning), [
      'e|-0--|----|',
      'B|----|----|',
      'G|----|----|',
      'D|----|----|',
      'A|----|----|',
      'E|--3-|----|',
    ]);
  });

  test('multi-char cells pad sibling strings with dashes (§3 alignment rule)', () {
    final line = Line(length: 4, barlines: [])
      ..setCell(1, 5, '12')
      ..setCell(1, 0, '3')
      ..setCell(2, 4, '5h7');
    final rows = renderLine(line, standardTuning);
    expect(rows[0], 'e|-12----|'); // 12 sets column 1 width to 2
    expect(rows[1], 'B|---5h7-|');
    expect(rows[5], 'E|-3-----|'); // 3 padded to width 2
    expect({for (final r in rows) r.length}.length, 1, reason: 'all rows equal length');
  });

  test('renderSong includes header, sections, and capo', () {
    final song = Song(songId: 'x', title: 'Blackbird', artist: 'The Beatles', capo: 2)
      ..sections.add(Section(name: 'Intro', lines: [Line(length: 4, barlines: [])]));
    final text = renderSong(song);
    expect(text, startsWith('Blackbird\nThe Beatles\nCapo 2\n\n[Intro]\n'));
    expect(text, contains('e|----|'));
    expect(text, contains('E|----|'));
  });
}
