/// Parses pasted ASCII tab (the format used across the internet) into the
/// data model. Recognizes, per docs/ARCHITECTURE.md's notation standard:
/// - blocks of 6 consecutive tab lines (`e|---3---|`) → one [Line]
/// - `[Intro]` / `Verse:` style headers → section boundaries, including
///   chords written inline on the header line itself (`[Intro] D D G A7`)
/// - a chord-name row right above a block (`  G     Am7`) → [ChordMark]s
/// - a plain-text row right after a block → [LyricMark]s, anchored to the
///   column each run of words sits over
/// - a chord row with no tab block following (just its own lyric row, or
///   nothing) → a chords/lyrics-only [Line] (`mode: 'chords'`, no cells),
///   same column anchoring, just without a block to anchor against
/// - repeat markers (`[2x]`, `(2x)`, `x2`) mixed in with chords are ignored
///   rather than breaking chord-row recognition
library;

import 'song.dart';

const _tokenChars = '0123456789hpbrtxX/\\~()<>';

/// Sections parsed from pasted text; empty if no tab block was found.
List<Section> parseTab(String text) {
  final src = text.split('\n');
  final sections = <Section>[];
  String? pendingChords; // raw line, kept for character positions

  void addLine(Line line) {
    if (sections.isEmpty) sections.add(Section(name: '', lines: []));
    sections.last.lines.add(line);
  }

  /// A chord row that never found a tab block to anchor to (and isn't about
  /// to be paired with the lyric row right after it) still becomes a
  /// chords-only line rather than being silently dropped.
  void flushPendingChords([String? lyricRow]) {
    if (pendingChords == null) return;
    addLine(_parseChordsOnly(pendingChords!, lyricRow));
    pendingChords = null;
  }

  var i = 0;
  while (i < src.length) {
    final trimmed = src[i].trim();
    if (trimmed.isEmpty) {
      flushPendingChords();
      i++;
      continue;
    }
    if (_isTabLine(src[i]) &&
        i + 5 < src.length &&
        [for (var k = 1; k < 6; k++) src[i + k]].every(_isTabLine)) {
      final block = src.sublist(i, i + 6);
      i += 6;
      // A plain text line immediately after the block holds its lyrics.
      String? lyricRow;
      if (i < src.length) {
        final after = src[i].trim();
        if (after.isNotEmpty &&
            !_isTabLine(src[i]) &&
            _sectionHeader(after) == null &&
            !_isChordRow(after)) {
          lyricRow = src[i];
          i++;
        }
      }
      addLine(_parseBlock(block, pendingChords, lyricRow));
      pendingChords = null;
      continue;
    }
    final header = _sectionHeader(trimmed);
    if (header != null) {
      flushPendingChords();
      sections.add(Section(name: header.$1, lines: []));
      pendingChords = header.$2;
      i++;
      continue;
    }
    if (_isChordRow(trimmed)) {
      flushPendingChords(); // an earlier pending row never got a lyric/block
      pendingChords = src[i];
      i++;
      continue;
    }
    if (pendingChords != null) {
      flushPendingChords(src[i]); // this plain line is its lyric row
      i++;
      continue;
    }
    i++;
  }
  flushPendingChords();
  return [
    for (final s in sections)
      if (s.lines.isNotEmpty) s
  ];
}

/// Maps the raw character offsets a chord row / lyric row's tokens start at
/// onto compact, sequential columns — one per token instead of one per
/// source character. A prose line is mostly whitespace, so anchoring columns
/// to character position (the old behavior) left a chords-only line dozens
/// of columns wide, nearly all of it empty padding between the few that
/// actually held a chord or a word. Collapsing to "one column per token"
/// keeps every chord over the same word it started above (both rows are
/// mapped through the same offset→column table) while cutting the line down
/// to only as many columns as it has content — the difference between a
/// line that needs no horizontal scrolling on a phone and one that needs a
/// lot of it.
Map<int, int> _tokenColumns(String? chordRow, String? lyricRow) {
  final offsets = <int>{};
  if (chordRow != null) {
    for (final m in RegExp(r'\S+').allMatches(chordRow)) {
      if (!_isRepeatMarker(m.group(0)!)) offsets.add(m.start);
    }
  }
  if (lyricRow != null) {
    for (final m in RegExp(r'\S+(?: \S+)*').allMatches(lyricRow)) {
      offsets.add(m.start);
    }
  }
  final sorted = offsets.toList()..sort();
  return {for (var i = 0; i < sorted.length; i++) sorted[i]: i};
}

/// Anchors a chord row (and optional lyric row) to columns — one per token
/// (see [_tokenColumns]) rather than one per raw character, since there's no
/// tab block here to anchor against. `mode: 'chords'` means no six-string
/// staff renders under it (`tab_staff.dart`), so there's no blank-strings
/// problem to solve.
Line _parseChordsOnly(String chordRow, String? lyricRow) {
  final colOf = _tokenColumns(chordRow, lyricRow);
  final line = Line(
      barlines: const [], length: colOf.isNotEmpty ? colOf.length : 1, mode: 'chords');
  for (final m in RegExp(r'\S+').allMatches(chordRow)) {
    if (_isRepeatMarker(m.group(0)!)) continue;
    final col = colOf[m.start]!;
    if (line.chordAt(col) == null) line.setChord(col, m.group(0)!);
  }
  if (lyricRow != null) {
    for (final m in RegExp(r'\S+(?: \S+)*').allMatches(lyricRow)) {
      final col = colOf[m.start]!;
      if (line.lyricAt(col) == null) line.setLyric(col, m.group(0)!);
    }
  }
  return line;
}

String _stripClosingPipe(String body) =>
    body.endsWith('|') ? body.substring(0, body.length - 1) : body;

/// A tab line: an optional short string label, a `|`, then only tab
/// characters (dashes, frets, techniques, bars).
bool _isTabLine(String raw) {
  final l = raw.trim();
  final pipe = l.indexOf('|');
  if (pipe < 0 || pipe > 3) return false;
  final body = l.substring(pipe + 1);
  if (body.isEmpty || !body.contains('-')) return false;
  return !body.contains(RegExp(r'[^-0-9hpbrtxX/\\~()<>|. ]'));
}

final _chordToken =
    RegExp(r'^[A-G][#b]?(m|maj|min|dim|aug|M)?\d*(sus\d?|add\d+)?(/[A-G][#b]?)?$');

/// A bracketed or bare repeat/loop marker mixed in with chords (`[2x]`,
/// `(2x)`, `x2`) — noise around the chords, not a chord itself.
bool _isRepeatMarker(String token) =>
    RegExp(r'^[\[(]?\d+x[\])]?$', caseSensitive: false).hasMatch(token);

bool _isChordRow(String trimmed) {
  final tokens =
      trimmed.split(RegExp(r'\s+')).where((t) => !_isRepeatMarker(t)).toList();
  return tokens.isNotEmpty && tokens.every(_chordToken.hasMatch);
}

/// A `[Section]` header — bracketed (optionally with inline chords and/or a
/// repeat marker trailing on the same line, e.g. `[Intro] D D G A7 [2x]`) or
/// a bare word like `Verse 2:`. The second element of the result is the
/// untouched inline-chords remainder (so character columns still line up
/// for `_parseChordsOnly`), or null if there's no remainder or it doesn't
/// look like chords.
(String, String?)? _sectionHeader(String trimmed) {
  final bracketed = RegExp(r'^\[([^\]]+)\](.*)$').firstMatch(trimmed);
  if (bracketed != null) {
    final name = bracketed.group(1)!.trim();
    final rest = bracketed.group(2)!.replaceFirst(RegExp(r':$'), '').trim();
    if (rest.isEmpty) return (name, null);
    return (name, _isChordRow(rest) ? rest : null);
  }
  final word = RegExp(
    r'^(intro|verse|chorus|bridge|solo|outro|pre-?chorus|interlude|riff)\b\s*\d*\s*:?$',
    caseSensitive: false,
  );
  if (word.hasMatch(trimmed)) return (trimmed.replaceAll(':', '').trim(), null);
  return null;
}

/// rows[0] = high e (str 5) … rows[5] = low E (str 0), standard tab order.
Line _parseBlock(List<String> rows, String? chordRow, String? lyricRow) {
  final labelLen = rows[0].indexOf('|') + 1;
  // The trailing pipe is the line's closing edge (the renderer always draws
  // one), not a column — strip it before mapping positions.
  final bodies = [
    for (final r in rows)
      _stripClosingPipe(r.trimRight().substring(r.trimRight().indexOf('|') + 1))
  ];
  var maxLen = 0;
  for (final b in bodies) {
    if (b.length > maxLen) maxLen = b.length;
  }

  // Bar characters occupy a column in ASCII but are metadata in the model:
  // map char positions to logical columns, skipping bars.
  final barChars = <int>{};
  for (final b in bodies) {
    for (var p = 0; p < b.length; p++) {
      if (b[p] == '|') barChars.add(p);
    }
  }
  final colOf = List<int>.filled(maxLen, 0);
  var col = 0;
  for (var p = 0; p < maxLen; p++) {
    colOf[p] = col;
    if (!barChars.contains(p)) col++;
  }

  final line = Line(
    barlines: {for (final p in barChars) colOf[p]}.toList()..sort(),
    length: col > 0 ? col : 1,
  );

  for (var row = 0; row < 6; row++) {
    final str = 5 - row;
    final b = bodies[row];
    var p = 0;
    while (p < b.length) {
      if (_tokenChars.contains(b[p])) {
        var q = p + 1;
        while (q < b.length && _tokenChars.contains(b[q])) {
          q++;
        }
        line.setCell(colOf[p], str, b.substring(p, q));
        p = q;
      } else {
        p++;
      }
    }
  }

  /// Character position in an annotation row → the column it sits over.
  int columnAt(int start) {
    final p = start - labelLen;
    return p < 0 ? 0 : (p < maxLen ? colOf[p] : line.length - 1);
  }

  if (chordRow != null) {
    for (final m in RegExp(r'\S+').allMatches(chordRow)) {
      final col = columnAt(m.start);
      if (line.chordAt(col) == null) line.setChord(col, m.group(0)!);
    }
  }

  if (lyricRow != null) {
    // Single spaces hold a phrase together; two or more start a new run,
    // which is how spaced-out syllables get anchored to their own columns.
    for (final m in RegExp(r'\S+(?: \S+)*').allMatches(lyricRow)) {
      final col = columnAt(m.start);
      if (line.lyricAt(col) == null) line.setLyric(col, m.group(0)!);
    }
  }
  return line;
}
