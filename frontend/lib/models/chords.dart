/// Chord shapes, so picking a chord can stamp its notes into the tab column
/// underneath it. Two kinds of shape:
///
/// - [_openShapes]: standard open-position voicings (the picker's default
///   whenever one exists) — the actual finger positions taught in every
///   guitar method book, one entry per root+quality that has a clean one.
/// - Movable ("barre") shapes: real guitarists only rely on two shapes as
///   full six-string barre chords that work at any fret — the E-shape and
///   the A-shape. (The C/G/D open shapes already use all four fretting
///   fingers, leaving none spare to barre with — they're only played open.)
///   Both are just the matching `E*`/`A*` entries in [_openShapes] reused as
///   slide-anywhere templates: an "E-shape barre chord" is literally the
///   open E chord slid up the neck. [_movableExtras] covers the one quality
///   (`dim`) with no taught open equivalent to borrow from. When a chord has
///   no true open shape, the picker defaults to whichever of the two movable
///   families reaches the root at the lower, more comfortable fret — see
///   [defaultMovableShape].
library;

const chordRoots = ['A', 'A#', 'B', 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#'];
const chordQualities = ['', 'm', '7', 'm7', 'maj7', 'sus2', 'sus4', 'dim'];

/// True open-position voicings (absolute frets, not offsets from a base),
/// keyed by `root + quality`. These are the standard shapes taught in
/// virtually every guitar method book/chord chart. Only combinations with a
/// clean, commonly-taught open voicing are listed here; anything else falls
/// back to a movable barre shape (see [defaultMovableShape]). The `E*` and
/// `A*` entries do double duty as the movable-shape templates below.
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

/// Movable-shape templates with no taught open-chord equivalent to borrow
/// from [_openShapes]. Just `Edim` today — diminished chords aren't taught
/// as "open chords," but the shape (root on the low E string) is standard.
const _movableExtras = <String, List<int?>>{
  'Edim': [0, 1, 2, 0, null, null],
};

/// The two string-families used as movable ("barre") shapes in practice.
const _movableFamilies = ['E', 'A'];

/// Sharp names by semitone above C; `_semitones` is its inverse.
const _names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
const _semitones = {
  'C': 0, 'C#': 1, 'D': 2, 'D#': 3, 'E': 4, 'F': 5,
  'F#': 6, 'G': 7, 'G#': 8, 'A': 9, 'A#': 10, 'B': 11,
};

/// The movable-shape template for `family + quality` ('E' or 'A'), if one
/// is taught. Reuses [_openShapes] (an "E-shape barre chord" is the open E
/// chord slid up the neck), falling back to [_movableExtras].
List<int?>? _movableTemplate(String family, String quality) =>
    _openShapes['$family$quality'] ?? _movableExtras['$family$quality'];

/// (family, base fret) of the movable barre shape the picker should default
/// to for `root+quality` — whichever of the E-shape or A-shape reaches
/// [root] at the lower, more comfortable fret. Null only if neither family
/// teaches [quality] (doesn't happen for any quality in [chordQualities]
/// today — every one is taught by at least the E-shape or the A-shape).
(String, int)? defaultMovableShape(String root, String quality) {
  String? bestFamily;
  int? bestBase;
  for (final family in _movableFamilies) {
    if (_movableTemplate(family, quality) == null) continue;
    final base = (_semitones[root]! - _semitones[family]! + 12) % 12;
    if (bestBase == null || base < bestBase) {
      bestBase = base;
      bestFamily = family;
    }
  }
  return bestFamily == null ? null : (bestFamily, bestBase!);
}

/// Frets for the movable `family`-shape barre chord in `quality` at [base],
/// index 0 = low E, `null` = not played. Null for a quality neither movable
/// family teaches (imported names like `D/F#`).
List<int?>? chordFrets(String family, String quality, int base) {
  final shape = _movableTemplate(family, quality);
  if (shape == null) return null;
  return [for (final offset in shape) offset == null ? null : base + offset];
}

/// The true open-position voicing for `root + quality`, if one is taught in
/// standard chord charts. Null means "no clean open shape — use a movable
/// barre shape instead" (see [defaultMovableShape]).
List<int?>? openShapeFor(String root, String quality) => _openShapes['$root$quality'];

/// (family, base) the chord picker should default to: base `null` means
/// "show the open-position shape" (family is meaningless then); otherwise
/// the movable barre shape from [defaultMovableShape].
(String, int?) defaultShapeFor(String root, String quality) =>
    openShapeFor(root, quality) != null
        ? ('', null)
        : defaultMovableShape(root, quality)!;

/// Resolves the frets to show/stamp for `root + quality`. `base == null`
/// selects the open-position shape; otherwise the movable `family`-shape
/// barre chord at that fret (same as [chordFrets]).
List<int?> resolveFrets(String root, String quality, String family, int? base) =>
    base == null ? openShapeFor(root, quality)! : chordFrets(family, quality, base)!;

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
  if (!chordQualities.contains(quality)) return null;
  return (normalized, quality);
}
