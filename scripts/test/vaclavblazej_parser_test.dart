import 'package:test/test.dart';
import 'package:guitar_tabs_scripts/vaclavblazej_parser.dart';

void main() {
  group('titleArtistFromFilename', () {
    test('splits "Artist - Title.tab"', () {
      final (title, artist) = titleArtistFromFilename('Alt-J - Breezeblocks.tab');
      expect(title, 'Breezeblocks');
      expect(artist, 'Alt-J');
    });

    test('no separator and no extension → title only', () {
      final (title, artist) = titleArtistFromFilename('Bella Ciao');
      expect(title, 'Bella Ciao');
      expect(artist, '');
    });
  });

  group('parseHeader', () {
    test('keeps unrecognized header lines (including capo) as notes', () {
      const raw = 'source: https://example.com\ncapo: 7\nnote: fingerstyle\n\n[Verse]\nhello';
      final h = parseHeader(raw);
      expect(h.notes, contains('source: https://example.com'));
      expect(h.notes, contains('capo: 7'));
      expect(h.notes, contains('note: fingerstyle'));
      expect(h.body, '[Verse]\nhello');
    });

    test('drop D lowers only the low string', () {
      final h = parseHeader('drop D\n\nbody');
      expect(h.tuning, ['D', 'A', 'D', 'G', 'B', 'E']);
    });

    test('no header at all still returns the whole text as body', () {
      final h = parseHeader('just body, no header\nmore body');
      expect(h.body, 'just body, no header\nmore body');
    });

    test('multiple blank-line-separated header paragraphs are both consumed', () {
      // Breezeblocks' actual shape: source/video/note, blank, "drop D",
      // blank, blank, then the real body.
      const raw = 'source: https://example.com\n'
          'video: https://example.com\n'
          'note: something\n'
          '\n'
          'drop D\n'
          '\n'
          '\n'
          '[Verse 1]\nreal content';
      final h = parseHeader(raw);
      expect(h.tuning, ['D', 'A', 'D', 'G', 'B', 'E']);
      expect(h.body, '[Verse 1]\nreal content');
    });
  });

  group('buildSections', () {
    test('clean bracket sections with a real chord row parse via parseTab', () {
      const body = '[Verse]\nAm Am7\nStamattina mi son alzato';
      final sections = buildSections(body);
      expect(sections.single.name, 'Verse');
      final line = sections.single.lines.single;
      expect(line.mode, 'chords');
      expect(line.chordAt(0), 'Am');
    });

    test('a file with no [Section] headers at all still parses (regression)', () {
      // e.g. melodies/Pink Floyd - Is There Anybody Out There.tab
      const body = 'Dm F/C.C Gm Bb\nDm F C Am';
      final sections = buildSections(body);
      expect(sections, isNotEmpty);
      expect(sections.single.name, '');
    });

    test('a trailing bracket annotation on a tab line does not break the block', () {
      const body = '[Intro]\n'
          'e|-----------------|\n'
          'B|-----------------| [8x]\n'
          'G|-----2-------2---|\n'
          'D|-----------------|\n'
          'A|-0-------0-------|\n'
          'E|-----------------|\n';
      final sections = buildSections(body);
      expect(sections.single.name, 'Intro');
      final line = sections.single.lines.single;
      expect(line.mode, 'tab');
      expect(line.cellAt(5, 3)!.fret, '2'); // G string (index 3), column 5
    });

    test('a genuine [Section] header with nothing else on the line is not stripped', () {
      const body = '[Chorus]\nG C\nwords here';
      final sections = buildSections(body);
      expect(sections.single.name, 'Chorus');
    });

    test('non-standard chord shorthand falls back to the permissive parser, nothing dropped', () {
      const body = '[Verse]\n'
          '    F                     Am\n'
          '     She may conta-in  the urge to run away\n'
          '    Dm                            Dm.      D5\'D5\'D5\'D5\'\n'
          '    down with soggy clothes';
      final sections = buildSections(body);
      // One chord+lyric pair per Line (matching the rest of the app's model)
      // — both pairs must survive, not just the first, clean one.
      final lines = sections.single.lines;
      expect(lines.length, 2);
      expect(lines[0].chords.map((c) => c.name), containsAll(['F', 'Am']));
      expect(lines[0].lyrics.map((l) => l.text).join(), contains('urge to run away'));
      expect(lines[1].chords.map((c) => c.name), contains('Dm.'));
      expect(lines[1].lyrics.map((l) => l.text).join(), contains('soggy clothes'));
    });

    test('a stub/duplicate-pointer file (a single line ending in .tab) imports nothing', () {
      final sections = buildSections('The Monkees - I\'m A Believer.tab');
      expect(sections, isEmpty);
    });
  });

  group('dedupKey', () {
    test('case-insensitive on both title and artist', () {
      expect(dedupKey('Wonderwall', 'Oasis'), dedupKey('wonderwall', 'OASIS'));
    });
  });
}
