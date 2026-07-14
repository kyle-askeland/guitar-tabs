/// Chord shapes, so picking a chord can stamp its notes into the tab column
/// underneath it. Two sources of shapes: [_openShapes] holds the standard
/// open-position voicings (the picker's default whenever one exists), and
/// [_shapes] holds the movable ("barre") voicing with its root on the low E
/// string, expressed as frets above a base fret — used as a fallback, or
/// when the base fret is slid up the neck away from the open position.
library;

const chordRoots = ['A', 'A#', 'B', 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#'];
const chordQualities = ['', 'm', '7', 'm7', 'maj7', 'sus2', 'sus4', 'dim'];

/// Offsets from the base fret per string, index 0 = low E. `null` = not played.
const _shapes = <String, List<int?>>{
  '': [0, 2, 2, 1, 0, 0],
  'm': [0, 2, 2, 0, 0, 0],
  '7': [0, 2, 0, 1, 0, 0],
  'm7': [0, 2, 0, 0, 0, 0],
  'maj7': [0, 2, 1, 1, 0, 0],
  'sus2': [0, 2, 4, 4, 0, 0],
  'sus4': [0, 2, 2, 2, 0, 0],
  'dim': [0, 1, 2, 0, null, null],
};

/// True open-position voicings (absolute frets, not offsets from a base),
/// keyed by `root + quality`. These are the standard shapes taught in
/// virtually every guitar method book/chord chart — the same "source of
/// truth" the movable shapes above are drawn from. Only combinations with a
/// clean, commonly-taught open voicing are listed here; anything else falls
/// back to the movable barre shape via [chordFrets].
const _openShapes = <String, List<int?>>{
  'E': [0, 2, 2, 1, 0, 0],
  'Em': [0, 2, 2, 0, 0, 0],
  'E7': [0, 2, 0, 1, 0, 0],
  'Em7': [0, 2, 0, 0, 0, 0],
  'Emaj7': [0, 2, 1, 1, 0, 0],
  'Esus4': [0, 2, 2, 2, 0, 0],
  'A': [null, 0, 2, 2, 2, 0],
  'Am': [null, 0, 2, 2, 1, 0],
  'A7': [null, 0, 2, 0, 2, 0],
  'Am7': [null, 0, 2, 0, 1, 0],
  'Amaj7': [null, 0, 2, 1, 2, 0],
  'Asus2': [null, 0, 2, 2, 0, 0],
  'Asus4': [null, 0, 2, 2, 3, 0],
  'D': [null, null, 0, 2, 3, 2],
  'Dm': [null, null, 0, 2, 3, 1],
  'D7': [null, null, 0, 2, 1, 2],
  'Dm7': [null, null, 0, 2, 1, 1],
  'Dmaj7': [null, null, 0, 2, 2, 2],
  'Dsus2': [null, null, 0, 2, 3, 0],
  'Dsus4': [null, null, 0, 2, 3, 3],
  'G': [3, 2, 0, 0, 0, 3],
  'G7': [3, 2, 0, 0, 0, 1],
  'Gmaj7': [3, 2, 0, 0, 0, 2],
  'C': [null, 3, 2, 0, 1, 0],
  'C7': [null, 3, 2, 3, 1, 0],
  'Cmaj7': [null, 3, 2, 0, 0, 0],
  'B7': [null, 2, 1, 2, 0, 2],
};

/// Sharp names by semitone above C; `_semitones` is its inverse.
const _names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
const _semitones = {
  'C': 0, 'C#': 1, 'D': 2, 'D#': 3, 'E': 4, 'F': 5,
  'F#': 6, 'G': 7, 'G#': 8, 'A': 9, 'A#': 10, 'B': 11,
};

/// The lowest base fret that puts [root] under the shape's root finger.
/// E is the open position (0), so F is 1, G is 3, A is 5…
int baseFretFor(String root) => ((_semitones[root] ?? 4) - 4 + 12) % 12;

/// Frets for `root + quality` at [base], index 0 = low E, `null` = not played.
/// Returns null for a quality with no shape (imported names like `D/F#`).
List<int?>? chordFrets(String quality, int base) {
  final shape = _shapes[quality];
  if (shape == null) return null;
  return [for (final offset in shape) offset == null ? null : base + offset];
}

/// The true open-position voicing for `root + quality`, if one is taught in
/// standard chord charts. Null means "no clean open shape — use the movable
/// barre shape instead" (see [chordFrets] / [defaultBaseFor]).
List<int?>? openShapeFor(String root, String quality) => _openShapes['$root$quality'];

/// The base fret the chord picker should default to: `null` means "use the
/// open-position shape", otherwise the lowest barre-shape fret as before.
int? defaultBaseFor(String root, String quality) =>
    openShapeFor(root, quality) != null ? null : baseFretFor(root);

/// Resolves the frets to show/stamp for `root + quality` at [base]. `base ==
/// null` selects the open-position shape; otherwise the movable barre shape
/// at that fret (same as [chordFrets]).
List<int?> resolveFrets(String root, String quality, int? base) =>
    base == null ? openShapeFor(root, quality)! : chordFrets(quality, base)!;

/// Splits a chord name into (root, quality), e.g. `Am7` → `('A', 'm7')`.
/// Returns null when the name isn't a shape this library knows how to build.
(String, String)? splitChord(String name) {
  final root = name.length > 1 && (name[1] == '#' || name[1] == 'b')
      ? name.substring(0, 2)
      : (name.isEmpty ? '' : name.substring(0, 1));
  // Flats normalize to the sharp spelling the picker uses (Bb → A#).
  final normalized = root.length == 2 && root[1] == 'b'
      ? _names[((_semitones[root[0]] ?? 0) + 11) % 12]
      : root;
  if (!chordRoots.contains(normalized)) return null;
  final quality = name.substring(root.length);
  if (!_shapes.containsKey(quality)) return null;
  return (normalized, quality);
}
