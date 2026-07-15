import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_tabs/models/chords.dart';

void main() {
  test('base 0 gives the open E-shape templates', () {
    expect(chordFrets('E', '', 0), [0, 2, 2, 1, 0, 0]); // E
    expect(chordFrets('E', 'm', 0), [0, 2, 2, 0, 0, 0]); // Em
    expect(chordFrets('E', '7', 0), [0, 2, 0, 1, 0, 0]); // E7
  });

  test('the same shape slides up the neck: G major is E major at fret 3', () {
    expect(defaultMovableShape('G', ''), ('E', 3));
    expect(chordFrets('E', '', 3), [3, 5, 5, 4, 3, 3]);
  });

  test('unplayed strings come back as null', () {
    expect(chordFrets('E', 'dim', 0), [0, 1, 2, 0, null, null]);
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
    expect(chordFrets('E', 'add9', 0), isNull);
  });

  test('roots with a standard open voicing default to it, not a barre shape', () {
    expect(defaultShapeFor('G', ''), ('', null));
    expect(openShapeFor('G', ''), [3, 2, 0, 0, 0, 3]);
    final (gFamily, gBase) = defaultShapeFor('G', '');
    expect(resolveFrets('G', '', gFamily, gBase), [3, 2, 0, 0, 0, 3]);

    expect(defaultShapeFor('C', ''), ('', null));
    expect(openShapeFor('C', ''), [null, 3, 2, 0, 1, 0]);

    expect(defaultShapeFor('A', 'm'), ('', null));
    expect(openShapeFor('A', 'm'), [null, 0, 2, 2, 1, 0]);
  });

  test(
      'roots/qualities with no open voicing fall back to whichever movable '
      'shape (E or A) reaches the root at the lower fret', () {
    expect(openShapeFor('B', ''), isNull); // no open B major
    // A-shape barre at fret 2 (x24442) beats the E-shape barre at fret 7.
    expect(defaultMovableShape('B', ''), ('A', 2));
    expect(defaultShapeFor('B', ''), ('A', 2));
    expect(resolveFrets('B', '', 'A', 2), chordFrets('A', '', 2));

    // C#m: A-shape (Am-shape) barre at fret 4 beats the E-shape at fret 9.
    expect(defaultMovableShape('C#', 'm'), ('A', 4));

    // dim has no A-shape template, so it always falls back to the E-shape.
    expect(openShapeFor('E', 'dim'), isNull);
    expect(defaultShapeFor('E', 'dim'), ('E', 0));
  });
}
