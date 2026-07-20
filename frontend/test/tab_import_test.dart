import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tabs/models/tab_import.dart';

const specExample = '''
e|-------0-------0---|-------0-------0---|
B|-----1-------1-----|-----1-------1-----|
G|---2-------2-------|---0-------0-------|
D|-------------------|-------------------|
A|-3-------3---------|-------------------|
E|-------------------|-2-------2---------|
''';

void main() {
  test('parses the docs/ARCHITECTURE.md example: notes, strings, columns, barline', () {
    final sections = parseTab(specExample);
    expect(sections.length, 1);
    expect(sections.single.name, ''); // unnamed unless the paste had a header
    final line = sections.single.lines.single;
    expect(line.length, 38); // 39 body chars minus the one taken by the bar
    expect(line.barlines, [19]);
    expect(line.cellAt(7, 5)!.fret, '0'); // high e, first open note
    expect(line.cellAt(1, 1)!.fret, '3'); // A string, first fretted note
    expect(line.cellAt(20, 0)!.fret, '2'); // low E, just after the barline
    expect(line.cells.length, 16);
  });

  test('picks up section header, chord row, and lyric', () {
    const text = '''
[Intro]
   G           Am7
e|--3---3---|--0---0---|
B|--0---0---|--1---1---|
G|--0---0---|--2---2---|
D|--0---0---|--2---2---|
A|--2---2---|--0---0---|
E|--3---3---|----------|
Blackbird singing in the dead of night
''';
    final sections = parseTab(text);
    expect(sections.single.name, 'Intro');
    final line = sections.single.lines.single;
    expect(line.lyricAt(0), 'Blackbird singing in the dead of night');
    expect(line.chordAt(1), 'G');
    expect(line.chordAt(12), 'Am7');
    expect(line.cellAt(2, 0)!.fret, '3'); // low E, first note
    expect(line.barlines, [10]);
  });

  test('multi-char tokens stay one cell (12, 5h7, x)', () {
    const text = '''
e|--12----|
B|--5h7---|
G|--------|
D|--------|
A|--------|
E|--x-----|
''';
    final line = parseTab(text).single.lines.single;
    expect(line.cellAt(2, 5)!.fret, '12');
    expect(line.cellAt(2, 4)!.fret, '5h7');
    expect(line.cellAt(2, 0)!.fret, 'x');
    expect(line.barlines, isEmpty);
  });

  test('multiple blocks and headers become multiple sections and lines', () {
    const text = '''
Verse 1:
e|--0--|
B|-----|
G|-----|
D|-----|
A|-----|
E|-----|

e|--3--|
B|-----|
G|-----|
D|-----|
A|-----|
E|-----|

[Chorus]
e|--5--|
B|-----|
G|-----|
D|-----|
A|-----|
E|-----|
''';
    final sections = parseTab(text);
    expect([for (final s in sections) s.name], ['Verse 1', 'Chorus']);
    expect(sections[0].lines.length, 2);
    expect(sections[1].lines.length, 1);
  });

  test('returns empty for text with no tab block', () {
    expect(parseTab('just some lyrics\nand more words'), isEmpty);
  });

  test('chord row with no tab block becomes a chords-only line', () {
    const text = '''
[Chorus]
D G E7 D
    Here comes the sun, doo da doo doo
''';
    final sections = parseTab(text);
    expect(sections.single.name, 'Chorus');
    final line = sections.single.lines.single;
    expect(line.mode, 'chords');
    expect(line.cells, isEmpty);
    expect(line.chordAt(0), 'D');
    expect(line.chordAt(2), 'G');
    expect(line.lyricAt(4), 'Here comes the sun, doo da doo doo');
  });

  test('a chord row followed by another chord row still flushes standalone', () {
    const text = '''
[Verse]
D G
D G Em
''';
    final sections = parseTab(text);
    expect(sections.single.lines.length, 2);
    expect(sections.single.lines[0].chordAt(0), 'D');
    expect(sections.single.lines[1].chordAt(0), 'D');
  });

  test('inline chords on the section header line, tolerating a repeat marker', () {
    const text = '[Intro] D D G A7  [2x]';
    final sections = parseTab(text);
    expect(sections.single.name, 'Intro');
    final line = sections.single.lines.single;
    expect(line.mode, 'chords');
    expect(line.chordAt(0), 'D');
    expect([for (final c in line.chords) c.name], ['D', 'D', 'G', 'A7']);
  });

  test('bracketed header with non-chord trailing text is ignored, not treated as chords', () {
    const text = '[Outro]  [2nd voice canon starting 1 beat later]';
    final sections = parseTab(text);
    expect(sections, isEmpty); // header alone, no lines — nothing to keep
  });
}
