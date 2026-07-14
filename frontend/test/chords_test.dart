import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tabs/models/chords.dart';

void main() {
  test('base 0 gives the open E shapes', () {
    expect(chordFrets('', 0), [0, 2, 2, 1, 0, 0]); // E
    expect(chordFrets('m', 0), [0, 2, 2, 0, 0, 0]); // Em
    expect(chordFrets('7', 0), [0, 2, 0, 1, 0, 0]); // E7
  });

  test('the same shape slides up the neck: G major is E major at fret 3', () {
    expect(baseFretFor('G'), 3);
    expect(chordFrets('', baseFretFor('G')), [3, 5, 5, 4, 3, 3]);
    expect(baseFretFor('E'), 0);
    expect(baseFretFor('F'), 1);
    expect(baseFretFor('A'), 5);
  });

  test('unplayed strings come back as null', () {
    expect(chordFrets('dim', 0), [0, 1, 2, 0, null, null]);
  });

  test('splitChord names the root and quality, normalizing flats', () {
    expect(splitChord('Am7'), ('A', 'm7'));
    expect(splitChord('E'), ('E', ''));
    expect(splitChord('F#m'), ('F#', 'm'));
    expect(splitChord('Bb'), ('A#', ''));
  });

  test('splitChord declines names with no shape (imported slash chords)', () {
    expect(splitChord('D/F#'), isNull);
    expect(splitChord('Cadd9'), isNull);
    expect(chordFrets('add9', 0), isNull);
  });

  test('roots with a standard open voicing default to it, not the barre shape', () {
    expect(defaultBaseFor('G', ''), isNull);
    expect(openShapeFor('G', ''), [3, 2, 0, 0, 0, 3]);
    expect(resolveFrets('G', '', defaultBaseFor('G', '')), [3, 2, 0, 0, 0, 3]);

    expect(defaultBaseFor('C', ''), isNull);
    expect(openShapeFor('C', ''), [null, 3, 2, 0, 1, 0]);

    expect(defaultBaseFor('A', 'm'), isNull);
    expect(openShapeFor('A', 'm'), [null, 0, 2, 2, 1, 0]);
  });

  test('roots/qualities with no open voicing fall back to the movable barre shape', () {
    expect(openShapeFor('B', ''), isNull); // no open B major
    expect(defaultBaseFor('B', ''), baseFretFor('B'));
    expect(resolveFrets('B', '', defaultBaseFor('B', '')),
        chordFrets('', baseFretFor('B')));

    expect(openShapeFor('E', 'dim'), isNull);
    expect(defaultBaseFor('E', 'dim'), 0);
  });
}
